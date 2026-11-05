#!/usr/bin/env bash
# P1_dmz_infra.sh – Base pública de la fase final: rutas de la DMZ y la VPN, Elastic IP, Security Groups base e instancias
# zp-web-01, zp-vpn-01 y zp-monitor-01 (Fase final · Persona 1).
# Ejecutar en AWS CloudShell (us-east-1). No guarda ni pide credenciales.
#
#   bash P1_dmz_infra.sh crear              crea (o reutiliza) rutas, Security Groups, instancias y Elastic IP; valida
#   bash P1_dmz_infra.sh --validar          solo lee: comprueba que todo esté como se espera (instancias encendidas o no)
#   bash P1_dmz_infra.sh --validar-apagado  solo lee: cierre de sesión (sin NAT, sin instancias encendidas, solo nuestras Elastic IP)
#   bash P1_dmz_infra.sh liberar-eip        desasocia y libera las Elastic IP de web y VPN (el DNS dejará de apuntar a la web)
#   bash P1_dmz_infra.sh --revertir         deshace las rutas y los Security Groups (exige que no existan las instancias ni las Elastic IP)
#   TIPO=t3.micro TIPO_MONITOR=t3.small DISCO_MONITOR=16 bash P1_dmz_infra.sh crear    cambia tipos y disco (valores por defecto)
#   SI=1 bash P1_dmz_infra.sh crear         omite la pregunta de confirmación
#
# Qué hace crear: rt-zenite-dmz recibe 0.0.0.0/0 -> igw-zenite-fase3; se crea rt-zenite-vpn con la misma ruta y se le pasa
# subnet-zenite-vpn (hoy usa rt-zenite-interna, que sale por el NAT y no puede recibir tráfico de Internet). Se crean los
# Security Groups zenite-dmz y zenite-vpn solo con TCP/22 desde zenite-eice (la Persona 3 agrega 80/443/1194 y el resto).
# Instancias Ubuntu 24.04 sin llave SSH y con IMDSv2: zp-web-01 (10.20.0.116) y zp-vpn-01 (10.20.0.132), cada una con su
# Elastic IP, y zp-monitor-01 (10.20.0.103, subred TI, sin IP pública). Se administran por EC2 Instance Connect Endpoint
# (usuario ubuntu). No abre nada a 0.0.0.0/0. Idempotente: si falla a medias, se vuelve a correr sin duplicar recursos.
# Salida en ~/final-config/: dmz-infra-validacion.txt, final-sesiones.log y los JSON.
set -euo pipefail

ENV_FILE="$(cd "$(dirname "$0")" && pwd)/../../.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

REGION="us-east-1"
VPC_NAME="vpc-zenite-fase2"
IGW_NAME="igw-zenite-fase3"
SG_EICE="zenite-eice"
RT_INTERNA="rt-zenite-interna"
RT_DMZ="rt-zenite-dmz"
RT_VPN="rt-zenite-vpn"
SUBNET_VPN="subnet-zenite-vpn"
TIPO="${TIPO:-t3.micro}"
TIPO_MONITOR="${TIPO_MONITOR:-t3.small}"
DISCO_MONITOR="${DISCO_MONITOR:-16}"
OUT_DIR="$HOME/final-config"
MODO="${1:-}"

uso() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
case "$MODO" in crear|--validar|--validar-apagado|liberar-eip|--revertir) ;; *) uso ;; esac

# nombre | IP privada | subred | Security Group | Role | Elastic IP ("-" si no lleva) | tipo (std o monitor)
PLAN=(
  "zp-web-01|10.20.0.116|subnet-zenite-dmz|zenite-dmz|Web|eip-zenite-web|std"
  "zp-vpn-01|10.20.0.132|subnet-zenite-vpn|zenite-vpn|VPN|eip-zenite-vpn|std"
  "zp-monitor-01|10.20.0.103|subnet-zenite-ti|zenite-ti|Monitor|-|monitor"
)
# Security Groups nuevos: nombre | descripción (solo ASCII: AWS no admite tildes) | entradas 0.0.0.0/0 autorizadas (decisión D10)
SGS=(
  "zenite-dmz|Reglas de la fase final para la DMZ (web publica)|tcp:80-80,tcp:443-443"
  "zenite-vpn|Reglas de la fase final para la VPN|udp:1194-1194"
)
EIPS=("eip-zenite-web" "eip-zenite-vpn")
NOMBRES_PLAN=$(printf '%s,' "${PLAN[@]%%|*}"); NOMBRES_PLAN="${NOMBRES_PLAN%,}"
VIVAS="pending,running,stopping,stopped"
TAGS="{Key=Project,Value=ZenitePrestige},{Key=Phase,Value=Final},{Key=Environment,Value=Prototype},{Key=Owner,Value=Grupo30}"

awsr() { aws --region "$REGION" --output json "$@"; }
mkdir -p "$OUT_DIR"
QUIEN=$(aws sts get-caller-identity --output json | jq -r '.Arn | if endswith(":root") then "root" else (split("/") | last) end')
registrar() { echo "$(date '+%Y-%m-%d %H:%M:%S %Z') · $*" >> "$OUT_DIR/final-sesiones.log"; }

# ---------- Búsquedas (todas por nombre, nunca por ID copiado a mano) ----------
IDS=$(awsr ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" | jq -r '.Vpcs[].VpcId')
read -ra ARR <<<"$IDS"
if (( ${#ARR[@]} != 1 )); then echo "ERROR: se esperaba 1 VPC llamada $VPC_NAME y hay ${#ARR[@]}." >&2; exit 1; fi
VPC_ID="${ARR[0]}"

subnet_id() { awsr ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$1" | jq -r '.Subnets[0].SubnetId // empty'; }
sg_id() { awsr ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=$1" | jq -r '.SecurityGroups[0].GroupId // empty'; }
rt_id() { awsr ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$1" | jq -r '.RouteTables[0].RouteTableId // empty'; }
igw_id() {  # IGW de nombre igw-zenite-fase3 adjunto a la VPC
  awsr ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$IGW_NAME" \
    | jq -r '.InternetGateways[0].InternetGatewayId // empty'
}
ruta_default() {  # route table id -> "destino estado" de 0.0.0.0/0 (vacío si no existe)
  awsr ec2 describe-route-tables --route-table-ids "$1" \
    | jq -r '.RouteTables[0].Routes[] | select(.DestinationCidrBlock=="0.0.0.0/0") | "\(.GatewayId // .NatGatewayId // "otro") \(.State)"'
}
asociacion_subred() {  # subred id -> "AssociationId RouteTableId" de la route table a la que está asociada (vacío si ninguna)
  awsr ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.subnet-id,Values=$1" \
    | jq -r --arg s "$1" '.RouteTables[0] // empty | "\(.Associations[] | select(.SubnetId==$s) | .RouteTableAssociationId) \(.RouteTableId)"'
}
eip_json() { awsr ec2 describe-addresses --filters "Name=tag:Name,Values=$1" | jq -c '.Addresses[0] // empty'; }
instancias() {  # nombres separados por coma -> "InstanceId estado IP SubnetId Nombre" por instancia no terminada
  awsr ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$1" "Name=instance-state-name,Values=$VIVAS" \
    | jq -r '.Reservations[].Instances[] | [.InstanceId, .State.Name, (.PrivateIpAddress // "-"), .SubnetId, (.Tags // [] | map(select(.Key=="Name").Value) | first // "-")] | @tsv'
}
todas_zp() {  # todas las zp-* del proyecto en la VPC: "InstanceId estado IP nombre IP_pública"
  awsr ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Project,Values=ZenitePrestige" "Name=instance-state-name,Values=$VIVAS" \
    | jq -r '.Reservations[].Instances[] | [.InstanceId, .State.Name, (.PrivateIpAddress // "-"), (.Tags // [] | map(select(.Key=="Name").Value) | first // "-"), (.PublicIpAddress // "-")] | @tsv' \
    | awk -F'\t' '$4 ~ /^zp-/' | sort -k4
}
nat_vivos() {  # NAT Gateways de la VPC pending/available/deleting: cantidad
  awsr ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=pending,available,deleting" | jq '.NatGateways | length'
}
ami_ubuntu() {  # -> "ami-id nombre"
  awsr ec2 describe-images --owners 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*" "Name=state,Values=available" \
    | jq -r '.Images | sort_by(.CreationDate) | last | "\(.ImageId) \(.Name)"'
}
tipo_de() { [[ "$1" == monitor ]] && echo "$TIPO_MONITOR" || echo "$TIPO"; }
tagspec() {  # tipo de recurso, nombre, [tiempo] -> valor para --tag-specifications
  local ex=""
  [[ "${3:-}" == "tiempo" ]] && ex=",{Key=Creador,Value=$QUIEN},{Key=Inicio,Value=$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},$TAGS$ex]"
}
confirmar() {
  [[ "${SI:-}" == "1" ]] && return 0
  local r; read -r -p "Escribe 'si' para continuar: " r
  [[ "$r" == "si" ]] || { echo "Cancelado. No se modificó nada."; exit 1; }
}
AMI_UB=""; ROOT_DEV=""; VACIO="{}"

# ---------- Comprobaciones previas de crear (solo lectura) ----------
preflight_crear() {
  local err=0 e name ip subnet sg role eip tp sid lineas iid iest iip isub eni dueno eice_id eice_est arch t d igw rtD rtV a j
  read -r eice_id eice_est < <(awsr ec2 describe-instance-connect-endpoints --filters "Name=vpc-id,Values=$VPC_ID" \
    | jq -r '.InstanceConnectEndpoints[0] | "\(.InstanceConnectEndpointId // "-") \(.State // "no-existe")"') || true
  if [[ "${eice_est:-}" == "create-complete" ]]; then echo "EICE: $eice_id · disponible"
  else echo "ERROR: la VPC no tiene un EC2 Instance Connect Endpoint disponible (estado: ${eice_est:-no existe})." >&2; err=1; fi
  for d in "$SG_EICE" zenite-ti; do
    [[ -n "$(sg_id "$d")" ]] || { echo "ERROR: no existe el Security Group $d." >&2; err=1; }
  done

  igw=$(igw_id)
  if [[ -z "$igw" ]]; then echo "ERROR: no hay un Internet Gateway $IGW_NAME adjunto a la VPC (corre antes P1_gateways.sh crear)." >&2; err=1
  else echo "Internet Gateway: $IGW_NAME ($igw)"; fi

  rtD=$(rt_id "$RT_DMZ"); rtV=$(rt_id "$RT_VPN")
  [[ -n "$rtD" ]] || { echo "ERROR: no existe la route table $RT_DMZ." >&2; err=1; }
  [[ -n "$(rt_id "$RT_INTERNA")" ]] || { echo "ERROR: no existe la route table $RT_INTERNA." >&2; err=1; }
  if [[ -n "$rtD" ]]; then
    d=$(ruta_default "$rtD")
    if [[ -n "$d" && "${d%% *}" != "$igw" ]]; then echo "ERROR: $RT_DMZ ya tiene una ruta 0.0.0.0/0 distinta de nuestro IGW ($d). No se modifica." >&2; err=1; fi
  fi
  if [[ -n "$rtV" ]]; then
    d=$(ruta_default "$rtV")
    if [[ -n "$d" && "${d%% *}" != "$igw" ]]; then echo "ERROR: $RT_VPN ya tiene una ruta 0.0.0.0/0 distinta de nuestro IGW ($d). No se modifica." >&2; err=1; fi
  fi
  sid=$(subnet_id "$SUBNET_VPN")
  [[ -n "$sid" ]] || { echo "ERROR: no existe la subred $SUBNET_VPN." >&2; err=1; }
  if [[ -n "$sid" ]]; then
    a=$(asociacion_subred "$sid")
    if [[ -z "$a" ]]; then echo "ERROR: $SUBNET_VPN no tiene asociación explícita a una route table; revísalo en la consola." >&2; err=1
    else
      j=$(awsr ec2 describe-route-tables --route-table-ids "${a#* }" | jq -r '.RouteTables[0].Tags // [] | map(select(.Key=="Name").Value) | first // "-"')
      if [[ "$j" != "$RT_INTERNA" && "$j" != "$RT_VPN" ]]; then echo "ERROR: $SUBNET_VPN está asociada a '$j' (se esperaba $RT_INTERNA o $RT_VPN)." >&2; err=1
      else echo "$SUBNET_VPN usa hoy: $j"; fi
    fi
  fi

  AMI_UB=$(ami_ubuntu)
  if [[ "$AMI_UB" == ami-* ]]; then
    echo "AMI Ubuntu 24.04: $AMI_UB"
    ROOT_DEV=$(awsr ec2 describe-images --image-ids "${AMI_UB%% *}" | jq -r '.Images[0].RootDeviceName // empty')
    [[ -n "$ROOT_DEV" ]] || { echo "ERROR: no se pudo leer el dispositivo raíz de la AMI." >&2; err=1; }
  else echo "ERROR: no se encontró la AMI de Ubuntu 24.04." >&2; err=1; fi

  for t in "$TIPO" "$TIPO_MONITOR"; do
    arch=$(awsr ec2 describe-instance-types --instance-types "$t" \
      | jq -r '.InstanceTypes[0] | ((.ProcessorInfo.SupportedArchitectures | index("x86_64")) != null)') || arch=""
    [[ "$arch" == "true" ]] && echo "Tipo $t · x86_64" || { echo "ERROR: el tipo $t no existe en $REGION o no es x86_64." >&2; err=1; }
  done

  for e in "${PLAN[@]}"; do
    IFS='|' read -r name ip subnet sg role eip tp <<<"$e"
    sid=$(subnet_id "$subnet")
    [[ -n "$sid" ]] || { echo "ERROR: no existe la subred $subnet." >&2; err=1; }
    lineas=$(instancias "$name")
    if (( $(grep -c . <<<"$lineas") > 1 )); then
      echo "ERROR: hay más de una instancia llamada $name. Termina las sobrantes desde la consola." >&2; err=1
    elif [[ -n "$lineas" ]]; then
      read -r iid iest iip isub _ <<<"$lineas"
      if [[ "$iip" != "$ip" || "$isub" != "$sid" ]]; then
        echo "ERROR: $name ($iid) ya existe con IP $iip en $isub; el plan es $ip en $subnet. Termínala desde la consola." >&2; err=1
      fi
    else
      read -r eni dueno < <(awsr ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" "Name=addresses.private-ip-address,Values=$ip" \
        | jq -r '.NetworkInterfaces[0] // empty | "\(.NetworkInterfaceId) \(.Attachment.InstanceId // "ninguna")"') || true
      if [[ -n "${eni:-}" ]]; then echo "ERROR: la IP $ip ya la usa $eni (instancia: $dueno). Libérala antes de crear $name." >&2; err=1; fi
    fi
    echo "  $name -> $ip · $subnet · $sg · $(tipo_de "$tp") · Elastic IP: $eip"
  done

  for e in "${EIPS[@]}"; do
    j=$(eip_json "$e")
    if [[ -n "$j" ]]; then
      echo "  Elastic IP $e ya existe: $(jq -r '.PublicIp' <<<"$j") (asociada a: $(jq -r '.InstanceId // "nadie"' <<<"$j"))"
    fi
  done
  return "$err"
}

# ---------- crear ----------
crear() {
  local igw rtD rtV sid a e name ip subnet sg role eip tp gid eice ud iid iest tp_t j alloc pub todas=() extra=() bdm
  igw=$(igw_id); eice=$(sg_id "$SG_EICE")

  # 1. Rutas
  rtD=$(rt_id "$RT_DMZ")
  if [[ -z "$(ruta_default "$rtD")" ]]; then
    echo "Ruta 0.0.0.0/0 -> $igw en $RT_DMZ ..."
    awsr ec2 create-route --route-table-id "$rtD" --destination-cidr-block 0.0.0.0/0 --gateway-id "$igw" >/dev/null
    registrar "Ruta 0.0.0.0/0 -> IGW creada en $RT_DMZ"
  else echo "$RT_DMZ ya tiene 0.0.0.0/0 -> IGW."; fi

  rtV=$(rt_id "$RT_VPN")
  if [[ -z "$rtV" ]]; then
    echo "Creando la route table $RT_VPN ..."
    rtV=$(awsr ec2 create-route-table --vpc-id "$VPC_ID" --tag-specifications "$(tagspec route-table "$RT_VPN")" | jq -r '.RouteTable.RouteTableId')
    registrar "Route table $RT_VPN creada $rtV"
  else echo "Ya existe $RT_VPN ($rtV); se reutiliza."; fi
  if [[ -z "$(ruta_default "$rtV")" ]]; then
    echo "Ruta 0.0.0.0/0 -> $igw en $RT_VPN ..."
    awsr ec2 create-route --route-table-id "$rtV" --destination-cidr-block 0.0.0.0/0 --gateway-id "$igw" >/dev/null
  fi
  sid=$(subnet_id "$SUBNET_VPN"); a=$(asociacion_subred "$sid")
  if [[ "${a#* }" != "$rtV" ]]; then
    echo "Asociando $SUBNET_VPN a $RT_VPN (deja de usar $RT_INTERNA) ..."
    awsr ec2 replace-route-table-association --association-id "${a%% *}" --route-table-id "$rtV" >/dev/null
    registrar "$SUBNET_VPN pasó de $RT_INTERNA a $RT_VPN"
  else echo "$SUBNET_VPN ya está asociada a $RT_VPN."; fi

  # 2. Security Groups base
  local s desc ok
  for s in "${SGS[@]}"; do
    IFS='|' read -r name desc ok <<<"$s"
    if [[ -z "$(sg_id "$name")" ]]; then
      echo "Creando Security Group $name ..."
      gid=$(awsr ec2 create-security-group --group-name "$name" --description "$desc" --vpc-id "$VPC_ID" \
            --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$name},$TAGS]" | jq -r '.GroupId')
      awsr ec2 authorize-security-group-ingress --group-id "$gid" \
        --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,UserIdGroupPairs=[{GroupId=$eice,Description=SSH desde $SG_EICE}]" >/dev/null
      registrar "Security Group $name creado $gid"
    else echo "Ya existe el Security Group $name; no se modifican sus reglas."; fi
  done

  # 3. Instancias
  extra=(--credit-specification CpuCredits=standard)
  for e in "${PLAN[@]}"; do
    IFS='|' read -r name ip subnet sg role eip tp <<<"$e"
    read -r iid iest _ <<<"$(instancias "$name")" || true
    if [[ -n "${iid:-}" ]]; then
      case "$iest" in
        stopping) echo "$name ($iid) se está deteniendo; se espera y se enciende ..."
                  awsr ec2 wait instance-stopped --instance-ids "$iid"
                  awsr ec2 start-instances --instance-ids "$iid" >/dev/null ;;
        stopped)  echo "Encendiendo $name ($iid) ..."; awsr ec2 start-instances --instance-ids "$iid" >/dev/null ;;
        *)        echo "Ya existe $name ($iid, $iest); se reutiliza." ;;
      esac
      todas+=("$iid"); continue
    fi
    sid=$(subnet_id "$subnet"); gid=$(sg_id "$sg"); tp_t=$(tipo_de "$tp")
    bdm=()
    [[ "$tp" == monitor ]] && bdm=(--block-device-mappings "[{\"DeviceName\":\"$ROOT_DEV\",\"Ebs\":{\"VolumeSize\":$DISCO_MONITOR,\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]")
    ud="#!/bin/bash
hostnamectl set-hostname $name
echo 'preserve_hostname: true' > /etc/cloud/cloud.cfg.d/99-zenite-hostname.cfg"
    echo "Creando $name ($ip en $subnet, $tp_t) ..."
    iid=$(awsr ec2 run-instances --image-id "${AMI_UB%% *}" --instance-type "$tp_t" --count 1 \
      --network-interfaces "[{\"DeviceIndex\":0,\"SubnetId\":\"$sid\",\"PrivateIpAddress\":\"$ip\",\"Groups\":[\"$gid\"],\"AssociatePublicIpAddress\":false,\"DeleteOnTermination\":true}]" \
      --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
      "${extra[@]}" ${bdm[@]+"${bdm[@]}"} --user-data "$ud" \
      --tag-specifications \
        "ResourceType=instance,Tags=[{Key=Name,Value=$name},{Key=Role,Value=$role},$TAGS]" \
        "ResourceType=volume,Tags=[{Key=Name,Value=$name-root},{Key=Role,Value=$role},$TAGS]" \
      | jq -r '.Instances[0].InstanceId')
    echo "  $name -> $iid"
    registrar "Instancia $name creada $iid"
    todas+=("$iid")
  done

  echo "Esperando estado running ..."
  awsr ec2 wait instance-running --instance-ids "${todas[@]}"

  # 4. Elastic IP: reservar (si no existe) y asociar a la instancia
  for e in "${PLAN[@]}"; do
    IFS='|' read -r name ip subnet sg role eip tp <<<"$e"
    [[ "$eip" == "-" ]] && continue
    iid=$(instancias "$name" | awk -F'\t' '{print $1}')
    j=$(eip_json "$eip")
    if [[ -z "$j" ]]; then
      echo "Reservando Elastic IP $eip ..."
      j=$(awsr ec2 allocate-address --domain vpc --tag-specifications "$(tagspec elastic-ip "$eip" tiempo)" | jq -c '.')
      registrar "Elastic IP reservada $eip $(jq -r '.AllocationId' <<<"$j") $(jq -r '.PublicIp' <<<"$j")"
      j=$(eip_json "$eip")
    else echo "Ya existe la Elastic IP $eip ($(jq -r '.PublicIp' <<<"$j")); se reutiliza."; fi
    alloc=$(jq -r '.AllocationId' <<<"$j")
    if [[ "$(jq -r '.InstanceId // empty' <<<"$j")" == "$iid" ]]; then
      echo "$eip ya está asociada a $name."
    else
      echo "Asociando $eip a $name ($iid) ..."
      awsr ec2 associate-address --allocation-id "$alloc" --instance-id "$iid" >/dev/null
      registrar "Elastic IP $eip asociada a $name"
    fi
    pub=$(jq -r '.PublicIp' <<<"$(eip_json "$eip")")
    echo "  $name -> IP pública $pub"
  done

  echo "Esperando status checks 2/2 (suele tardar de 3 a 5 minutos) ..."
  awsr ec2 wait instance-status-ok --instance-ids "${todas[@]}" \
    || echo "AVISO: los status checks aún no están en 2/2; vuelve a correr --validar en unos minutos."
  echo "RECORDATORIO: las Elastic IP cobran por hora (≈ US\$0.005) aunque la instancia esté detenida. Para apagar: P1_instancias.sh detener."
}

# ---------- Validación ----------
validar() {  # encendido | apagado
  local modo="$1" fallas=0
  check() {  # descripción, esperado, real
    if [[ "$2" == "$3" ]]; then printf "  [OK]    %-52s %s\n" "$1" "$3"
    else printf "  [FALLA] %-52s esperado=%s real=%s\n" "$1" "$2" "$3"; fallas=1; fi
  }
  local IJ SGJ ADJ eice_sg igw rtD rtV rtN d sid a e name ip subnet sg role eip tp i iid st stt pub s desc ok gid n x sobran
  igw=$(igw_id); rtD=$(rt_id "$RT_DMZ"); rtV=$(rt_id "$RT_VPN"); rtN=$(rt_id "$RT_INTERNA")
  SGJ=$(awsr ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID")
  ADJ=$(awsr ec2 describe-addresses)
  eice_sg=$(jq -r --arg n "$SG_EICE" '.SecurityGroups[] | select(.GroupName==$n) | .GroupId' <<<"$SGJ")
  printf '%s\n' "$ADJ" > "$OUT_DIR/addresses.json"
  awsr ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" > "$OUT_DIR/route-tables.json"

  echo "Validación de la base pública ($modo) · $VPC_NAME · $VPC_ID · $(date '+%Y-%m-%d %H:%M:%S %Z')"

  if [[ "$modo" == "apagado" ]]; then
    check "NAT Gateway vivo (pending/available/deleting)" "0" "$(nat_vivos)"
    d=$(ruta_default "$rtN")
    check "$RT_INTERNA sin ruta por defecto" "ninguna" "${d:-ninguna}"
    check "Instancias zp-* encendidas" "0" "$(todas_zp | awk -F'\t' '$2=="running"||$2=="pending"' | wc -l | tr -d ' ')"
    sobran=$(jq -r --argjson ok "$(printf '%s\n' "${EIPS[@]}" | jq -R . | jq -s .)" \
      '[.Addresses[] | (.Tags // [] | map(select(.Key=="Name").Value) | first // "sin-nombre") as $n | select(($ok | index($n)) == null) | "\($n)=\(.PublicIp)"] | join(",")' <<<"$ADJ")
    check "Elastic IP ajenas al plan (NAT u otras)" "ninguna" "${sobran:-ninguna}"
    n=$(jq '.Addresses | length' <<<"$ADJ")
    echo "  [INFO]  Elastic IP reservadas en la cuenta: $n (cada una ≈ US\$0.12 por día, también con la instancia detenida)"
    if (( fallas == 0 )); then echo "RESULTADO: todo correcto."; else echo "RESULTADO: hay fallas; revísalas antes de cerrar la sesión."; fi
    return "$fallas"
  fi

  IJ=$(awsr ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$NOMBRES_PLAN" "Name=instance-state-name,Values=$VIVAS")
  printf '%s\n' "$IJ" > "$OUT_DIR/instancias-final.json"
  printf '%s\n' "$SGJ" > "$OUT_DIR/security-groups.json"

  echo "  -- Rutas"
  check "Internet Gateway $IGW_NAME adjunto" "sí" "$([[ -n "$igw" ]] && echo sí || echo no)"
  d=$([[ -n "$rtD" ]] && ruta_default "$rtD" || true)
  check "$RT_DMZ: 0.0.0.0/0 -> IGW (activa)" "$igw active" "${d:-ninguna}"
  check "Existe $RT_VPN" "sí" "$([[ -n "$rtV" ]] && echo sí || echo no)"
  if [[ -n "$rtV" ]]; then
    d=$(ruta_default "$rtV"); check "$RT_VPN: 0.0.0.0/0 -> IGW (activa)" "$igw active" "${d:-ninguna}"
    sid=$(subnet_id "$SUBNET_VPN"); a=$(asociacion_subred "$sid")
    check "$SUBNET_VPN asociada a $RT_VPN" "$rtV" "${a#* }"
  fi

  for s in "${SGS[@]}"; do
    IFS='|' read -r name desc ok <<<"$s"
    gid=$(jq -r --arg n "$name" '.SecurityGroups[] | select(.GroupName==$n) | .GroupId' <<<"$SGJ")
    echo "  -- Security Group $name (${gid:-no existe})"
    check "Existe" "sí" "$([[ -n "$gid" ]] && echo sí || echo no)"
    [[ -z "$gid" ]] && continue
    check "TCP/22 de entrada desde $SG_EICE" "sí" "$(jq -r --arg g "$gid" --arg p "$eice_sg" '.SecurityGroups[] | select(.GroupId==$g) | .IpPermissions
        | if any(.[]; (.IpProtocol=="-1" or (.IpProtocol=="tcp" and .FromPort<=22 and .ToPort>=22)) and any(.UserIdGroupPairs[]?; .GroupId==$p)) then "sí" else "no" end' <<<"$SGJ")"
    x=$(jq -r --arg g "$gid" --arg ok "$ok" \
      '($ok | split(",")) as $permitidas | [.SecurityGroups[] | select(.GroupId==$g) | .IpPermissions[] | select(any(.IpRanges[]?; .CidrIp=="0.0.0.0/0")) | "\(.IpProtocol):\(.FromPort // "-")-\(.ToPort // "-")"] | map(select(. as $e | ($permitidas | index($e)) == null)) | join(",")' <<<"$SGJ")
    check "Entradas 0.0.0.0/0 fuera de las excepciones D10" "ninguna" "${x:-ninguna}"
    echo "    [INFO] entrada actual: $(jq -r --arg g "$gid" '.SecurityGroups[] | select(.GroupId==$g) | [.IpPermissions[] | "\(if .IpProtocol=="-1" then "todo" else "\(.IpProtocol):\(.FromPort // "-")" end)"] | join(", ")' <<<"$SGJ") (la Persona 3 completa las reglas)"
  done

  for e in "${PLAN[@]}"; do
    IFS='|' read -r name ip subnet sg role eip tp <<<"$e"
    i=$(jq -c --arg n "$name" '[.Reservations[].Instances[] | select(any(.Tags[]?; .Key=="Name" and .Value==$n))] | first // empty' <<<"$IJ")
    if [[ -z "$i" ]]; then echo "  -- $name ($ip)"; check "Existe" "sí" "no"; continue; fi
    iid=$(jq -r '.InstanceId' <<<"$i")
    tagv() { jq -r --arg k "$1" '.Tags[]? | select(.Key==$k) | .Value' <<<"$i"; }
    echo "  -- $name · $iid · $(jq -r '.InstanceType' <<<"$i") · $(jq -r '.ImageId' <<<"$i") · ubuntu"
    stt=$(jq -r '.State.Name' <<<"$i")
    if [[ "$stt" == running ]]; then
      st=$(awsr ec2 describe-instance-status --instance-ids "$iid" | jq -r '.InstanceStatuses[0] | "\(.SystemStatus.Status)/\(.InstanceStatus.Status)"')
      check "Estado y status checks" "running ok/ok" "running $st"
    else echo "  [INFO]  estado: $stt (detenida: se omiten los status checks)"; fi
    check "Subred ($subnet)" "$(subnet_id "$subnet")" "$(jq -r '.SubnetId' <<<"$i")"
    check "IP privada" "$ip" "$(jq -r '.PrivateIpAddress' <<<"$i")"
    check "Tipo de instancia" "$(tipo_de "$tp")" "$(jq -r '.InstanceType' <<<"$i")"
    check "Security Group" "$sg" "$(jq -r '[.NetworkInterfaces[].Groups[].GroupName] | unique | join(",")' <<<"$i")"
    check "IMDSv2 obligatorio" "required" "$(jq -r '.MetadataOptions.HttpTokens' <<<"$i")"
    check "Tags Name/Project/Phase/Role" "$name/ZenitePrestige/Final/$role" "$(tagv Name)/$(tagv Project)/$(tagv Phase)/$(tagv Role)"
    if [[ "$eip" != "-" ]]; then
      d=$(jq -c --arg n "$eip" '[.Addresses[] | select(any(.Tags[]?; .Key=="Name" and .Value==$n))] | first // empty' <<<"$ADJ")
      check "Elastic IP $eip asociada a $name" "$iid" "$(jq -r '.InstanceId // "ninguna"' <<<"${d:-$VACIO}")"
      pub=$(jq -r '.PublicIp // empty' <<<"${d:-$VACIO}")
      echo "    [INFO] IP pública: ${pub:--}"
      if [[ "$stt" == running && -n "$pub" && "${SIN_PRUEBA_RED:-}" != "1" ]]; then
        if timeout 5 bash -c "exec 3<>/dev/tcp/$pub/22" 2>/dev/null; then x="abierto"; else x="cerrado"; fi
        check "TCP/22 de $pub desde CloudShell (DMZ-04)" "cerrado" "$x"
      fi
    else
      check "Sin IPv4 pública" "ninguna" "$(jq -r '.PublicIpAddress // "ninguna"' <<<"$i")"
    fi
  done

  echo "  -- Barrido de IP públicas (DMZ-03)"
  x=$(todas_zp | awk -F'\t' '$5!="-" {print $4}' | grep -v -x -e zp-web-01 -e zp-vpn-01 | paste -sd, - || true)
  check "zp-* con IP pública distintas de web y VPN" "ninguna" "${x:-ninguna}"
  n=$(jq '.Addresses | length' <<<"$ADJ")
  echo "  [INFO]  Elastic IP en la cuenta: $n · instancias zp-* encendidas: $(todas_zp | awk -F'\t' '$2=="running"||$2=="pending"' | wc -l | tr -d ' ')"
  if (( fallas == 0 )); then echo "RESULTADO: todo correcto."; else echo "RESULTADO: hay fallas; corrígelas antes de continuar."; fi
  return "$fallas"
}

# ---------- liberar Elastic IP ----------
liberar_eip() {
  local e j alloc assoc i
  for e in "${EIPS[@]}"; do
    j=$(eip_json "$e")
    if [[ -z "$j" ]]; then echo "No existe la Elastic IP $e."; continue; fi
    alloc=$(jq -r '.AllocationId' <<<"$j"); assoc=$(jq -r '.AssociationId // empty' <<<"$j")
    if [[ -n "$assoc" ]]; then echo "Desasociando $e ($(jq -r '.PublicIp' <<<"$j")) ..."; awsr ec2 disassociate-address --association-id "$assoc" >/dev/null; fi
    echo "Liberando $e ($alloc) ..."
    for i in 1 2 3 4 5 6; do
      if awsr ec2 release-address --allocation-id "$alloc" >/dev/null 2>"$OUT_DIR/.release.err"; then
        registrar "Elastic IP liberada $e $alloc"; rm -f "$OUT_DIR/.release.err"; break
      fi
      (( i == 6 )) && { echo "ERROR: no se pudo liberar $alloc: $(cat "$OUT_DIR/.release.err")" >&2; exit 1; }
      sleep 5
    done
  done
  echo "Listo. Si vuelves a crear las Elastic IP tendrán otra dirección: hay que actualizar el registro A del dominio."
}

# ---------- revertir ----------
revertir() {
  local rtD rtV rtN igw sid a d e s name resto
  rtD=$(rt_id "$RT_DMZ"); rtV=$(rt_id "$RT_VPN"); rtN=$(rt_id "$RT_INTERNA"); igw=$(igw_id)

  resto=$(instancias "$NOMBRES_PLAN" | awk -F'\t' '{printf "%s(%s) ", $5, $2}')
  if [[ -n "$resto" ]]; then
    echo "ERROR: aún existen instancias del plan: $resto" >&2
    echo "Este script no las borra. Termínalas desde la consola (EC2 > Instances > Terminate) y vuelve a correr --revertir." >&2; exit 1
  fi
  for e in "${EIPS[@]}"; do
    if [[ -n "$(eip_json "$e")" ]]; then echo "ERROR: existe la Elastic IP $e; corre antes: bash P1_dmz_infra.sh liberar-eip" >&2; exit 1; fi
  done

  sid=$(subnet_id "$SUBNET_VPN"); a=$(asociacion_subred "$sid")
  if [[ -n "$a" && "${a#* }" != "$rtN" ]]; then
    echo "Devolviendo $SUBNET_VPN a $RT_INTERNA ..."
    awsr ec2 replace-route-table-association --association-id "${a%% *}" --route-table-id "$rtN" >/dev/null
  fi
  if [[ -n "$rtV" ]]; then
    echo "Eliminando la route table $RT_VPN ..."
    awsr ec2 delete-route-table --route-table-id "$rtV" >/dev/null
    registrar "Route table $RT_VPN eliminada"
  fi
  if [[ -n "$rtD" ]]; then
    d=$(ruta_default "$rtD")
    if [[ -n "$d" && "${d%% *}" == "$igw" ]]; then
      echo "Quitando 0.0.0.0/0 de $RT_DMZ ..."
      awsr ec2 delete-route --route-table-id "$rtD" --destination-cidr-block 0.0.0.0/0 >/dev/null
    elif [[ -n "$d" ]]; then echo "AVISO: $RT_DMZ tiene 0.0.0.0/0 -> ${d%% *}, que no es nuestro IGW; no se toca." >&2; fi
  fi
  for s in "${SGS[@]}"; do
    name="${s%%|*}"
    if [[ -n "$(sg_id "$name")" ]]; then
      echo "Eliminando el Security Group $name ..."
      awsr ec2 delete-security-group --group-id "$(sg_id "$name")" >/dev/null
      registrar "Security Group $name eliminado"
    fi
  done
  echo "Listo. Estado de Fase 3 restaurado (el Internet Gateway se conserva)."
}

case "$MODO" in
  crear)
    echo "Plan: $RT_DMZ y $RT_VPN con 0.0.0.0/0 -> $IGW_NAME; $SUBNET_VPN pasa a $RT_VPN; Security Groups ${SGS[*]%%|*} (solo TCP/22 desde $SG_EICE);"
    echo "      instancias ${NOMBRES_PLAN//,/, } (Ubuntu 24.04, $TIPO y $TIPO_MONITOR con disco de ${DISCO_MONITOR} GiB para el monitor); Elastic IP ${EIPS[*]}."
    echo "      Costo: ≈ US\$0.0104 por hora cada t3.micro, ≈ US\$0.0208 la t3.small, ≈ US\$0.005 por hora cada Elastic IP (también con la instancia detenida)."
    preflight_crear || { echo "No se modificó nada." >&2; exit 1; }
    confirmar
    crear
    echo
    set +e; validar encendido | tee "$OUT_DIR/dmz-infra-validacion.txt"; RC=${PIPESTATUS[0]}; set -e
    echo
    echo "Conexión: instancia > Connect > EC2 Instance Connect > Connect using EC2 Instance Connect Endpoint (usuario ubuntu)."
    ;;
  --validar)
    set +e; validar encendido | tee "$OUT_DIR/dmz-infra-validacion.txt"; RC=${PIPESTATUS[0]}; set -e ;;
  --validar-apagado)
    set +e; validar apagado | tee "$OUT_DIR/dmz-infra-validacion.txt"; RC=${PIPESTATUS[0]}; set -e ;;
  liberar-eip)
    echo "Plan: desasociar y liberar ${EIPS[*]}. El dominio dejará de llegar a la web y la próxima Elastic IP será distinta."
    confirmar
    liberar_eip ;;
  --revertir)
    echo "Plan: devolver $SUBNET_VPN a $RT_INTERNA, borrar $RT_VPN, quitar 0.0.0.0/0 de $RT_DMZ y borrar los Security Groups ${SGS[*]%%|*}."
    confirmar
    revertir ;;
esac
echo
echo "Archivos en $OUT_DIR: dmz-infra-validacion.txt, final-sesiones.log, addresses.json, route-tables.json, security-groups.json, instancias-final.json."
exit "${RC:-0}"
