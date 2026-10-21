#!/usr/bin/env bash
# P1_instancias.sh – Security Groups base y las 4 instancias nuevas de Fase 3, más encender y detener (Persona 1).
# Ejecutar en AWS CloudShell (us-east-1). No guarda ni pide credenciales.
#
#   bash P1_instancias.sh crear                   crea (o reutiliza) los Security Groups zenite-servidores y zenite-visitantes
#                                                 y las instancias zp-ntp-01, zp-ldap-01, zp-intranet-01 y zp-visitantes-01
#   bash P1_instancias.sh encender [nombre ...]   enciende las zp-* indicadas (por defecto, todas las de la VPC) y espera a que arranquen
#   bash P1_instancias.sh detener  [nombre ...]   detiene las zp-* indicadas (por defecto, todas las que estén encendidas)
#   bash P1_instancias.sh --validar               solo lee: comprueba las 4 instancias nuevas y sus Security Groups
#   TIPO=t3.small bash P1_instancias.sh crear     usa otro tipo de instancia x86_64 (por defecto t3.micro)
#   SI=1 bash P1_instancias.sh crear              omite la pregunta de confirmación
#
# Sin IPv4 pública ni llave SSH: se administran por EC2 Instance Connect Endpoint (usuario ec2-user; en zp-ldap-01, que
# usa Ubuntu 24.04, el usuario es ubuntu). Los Security Groups nuevos nacen solo con TCP/22 desde zenite-eice; las
# demás reglas las agrega la Persona 5. Idempotente. Salida en ~/fase3-config/: instancias-fase3-validacion.txt, instancias-fase3.json
set -euo pipefail

ENV_FILE="$(cd "$(dirname "$0")" && pwd)/../../.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

REGION="us-east-1"
VPC_NAME="vpc-zenite-fase2"
SG_EICE="zenite-eice"
TIPO="${TIPO:-t3.micro}"
OUT_DIR="$HOME/fase3-config"
MODO="${1:-}"
[[ $# -gt 0 ]] && shift
NOMBRES_ARG=("$@")

uso() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
case "$MODO" in crear|encender|detener|--validar) ;; *) uso ;; esac

# nombre | IP privada | subred | Security Group | Role | sistema operativo
PLAN=(
  "zp-ntp-01|10.20.0.68|subnet-zenite-servidores|zenite-servidores|NTP|al2023"
  "zp-ldap-01|10.20.0.69|subnet-zenite-servidores|zenite-servidores|LDAP|ubuntu"
  "zp-intranet-01|10.20.0.71|subnet-zenite-servidores|zenite-servidores|Intranet|al2023"
  "zp-visitantes-01|10.20.0.36|subnet-zenite-visitantes|zenite-visitantes|Visitantes|al2023"
)
SGS=(
  "zenite-servidores|Reglas de Fase 3 para la red Servidores"
  "zenite-visitantes|Reglas de Fase 3 para la red Visitantes"
)
NOMBRES_PLAN=$(printf '%s,' "${PLAN[@]%%|*}"); NOMBRES_PLAN="${NOMBRES_PLAN%,}"
VIVAS="pending,running,stopping,stopped"
TAGS="{Key=Project,Value=ZenitePrestige},{Key=Phase,Value=Fase3},{Key=Environment,Value=Prototype},{Key=Owner,Value=Grupo30}"

awsr() { aws --region "$REGION" --output json "$@"; }
mkdir -p "$OUT_DIR"

IDS=$(awsr ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" | jq -r '.Vpcs[].VpcId')
read -ra ARR <<<"$IDS"
if (( ${#ARR[@]} != 1 )); then echo "ERROR: se esperaba 1 VPC llamada $VPC_NAME y hay ${#ARR[@]}." >&2; exit 1; fi
VPC_ID="${ARR[0]}"

subnet_id() { awsr ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$1" | jq -r '.Subnets[0].SubnetId // empty'; }
sg_id() { awsr ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=$1" | jq -r '.SecurityGroups[0].GroupId // empty'; }
instancias() {  # nombres separados por coma -> "InstanceId estado IP SubnetId Nombre" por instancia no terminada
  awsr ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$1" "Name=instance-state-name,Values=$VIVAS" \
    | jq -r '.Reservations[].Instances[] | [.InstanceId, .State.Name, (.PrivateIpAddress // "-"), .SubnetId, (.Tags // [] | map(select(.Key=="Name").Value) | first // "-")] | @tsv'
}
todas_zp() {  # todas las zp-* del proyecto en la VPC
  awsr ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Project,Values=ZenitePrestige" "Name=instance-state-name,Values=$VIVAS" \
    | jq -r '.Reservations[].Instances[] | [.InstanceId, .State.Name, (.PrivateIpAddress // "-"), (.Tags // [] | map(select(.Key=="Name").Value) | first // "-")] | @tsv' \
    | awk -F'\t' '$4 ~ /^zp-/' | sort -k4
}
ami_mas_reciente() {  # propietario, patrón de nombre -> "ami-id nombre"
  awsr ec2 describe-images --owners "$1" --filters "Name=name,Values=$2" "Name=state,Values=available" \
    | jq -r '.Images | sort_by(.CreationDate) | last | "\(.ImageId) \(.Name)"'
}
confirmar() {
  [[ "${SI:-}" == "1" ]] && return 0
  local r; read -r -p "Escribe 'si' para continuar: " r
  [[ "$r" == "si" ]] || { echo "Cancelado. No se modificó nada."; exit 1; }
}
AMI_AL=""; AMI_UB=""

# ---------- Comprobaciones previas de crear (solo lectura) ----------
preflight() {
  local err=0 e name ip subnet sg role so sid lineas iid iest iip isub eni dueno eice_id eice_est arch ft
  read -r eice_id eice_est < <(awsr ec2 describe-instance-connect-endpoints --filters "Name=vpc-id,Values=$VPC_ID" \
    | jq -r '.InstanceConnectEndpoints[0] | "\(.InstanceConnectEndpointId // "-") \(.State // "no-existe")"') || true
  if [[ "${eice_est:-}" == "create-complete" ]]; then echo "EICE: $eice_id · disponible"
  else echo "ERROR: la VPC no tiene un EC2 Instance Connect Endpoint disponible (estado: ${eice_est:-no existe})." >&2; err=1; fi
  [[ -n "$(sg_id "$SG_EICE")" ]] || { echo "ERROR: no existe el Security Group $SG_EICE." >&2; err=1; }

  read -r arch ft < <(awsr ec2 describe-instance-types --instance-types "$TIPO" \
    | jq -r '.InstanceTypes[0] | "\((.ProcessorInfo.SupportedArchitectures | index("x86_64")) != null) \(.FreeTierEligible)"') || true
  if [[ "${arch:-}" != "true" ]]; then echo "ERROR: el tipo $TIPO no existe en $REGION o no es x86_64 (las AMI elegidas son x86_64)." >&2; err=1
  else
    echo "Tipo: $TIPO · x86_64 · Free Tier: ${ft:-?}"
    [[ "${ft:-}" == "true" ]] || echo "AVISO: $TIPO no aparece como Free Tier en esta cuenta (la cuenta no tiene créditos: se cobra completo)." >&2
  fi
  AMI_AL=$(ami_mas_reciente amazon "al2023-ami-2023.*-x86_64")
  AMI_UB=$(ami_mas_reciente 099720109477 "ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*")
  [[ "$AMI_AL" == ami-* ]] && echo "AMI Amazon Linux 2023: $AMI_AL" || { echo "ERROR: no se encontró la AMI de Amazon Linux 2023." >&2; err=1; }
  [[ "$AMI_UB" == ami-* ]] && echo "AMI Ubuntu 24.04:      $AMI_UB" || { echo "ERROR: no se encontró la AMI de Ubuntu 24.04." >&2; err=1; }

  for e in "${PLAN[@]}"; do
    IFS='|' read -r name ip subnet sg role so <<<"$e"
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
    echo "  $name -> $ip · $subnet (${sid:--}) · $sg · $so"
  done
  return "$err"
}

# ---------- crear ----------
crear() {
  local e name ip subnet sg role so sid gid iid iest ud ami s desc eice todas=() extra=()
  [[ "$TIPO" == t* ]] && extra=(--credit-specification CpuCredits=standard)
  eice=$(sg_id "$SG_EICE")

  for s in "${SGS[@]}"; do
    IFS='|' read -r name desc <<<"$s"
    if [[ -z "$(sg_id "$name")" ]]; then
      echo "Creando Security Group $name ..."
      gid=$(awsr ec2 create-security-group --group-name "$name" --description "$desc" --vpc-id "$VPC_ID" \
            --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$name},$TAGS]" | jq -r '.GroupId')
      awsr ec2 authorize-security-group-ingress --group-id "$gid" \
        --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,UserIdGroupPairs=[{GroupId=$eice,Description=SSH desde $SG_EICE}]" >/dev/null
    else
      echo "Ya existe el Security Group $name; no se modifican sus reglas."
    fi
  done

  for e in "${PLAN[@]}"; do
    IFS='|' read -r name ip subnet sg role so <<<"$e"
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
    sid=$(subnet_id "$subnet"); gid=$(sg_id "$sg")
    ami=$([[ "$so" == ubuntu ]] && awk '{print $1}' <<<"$AMI_UB" || awk '{print $1}' <<<"$AMI_AL")
    ud="#!/bin/bash
hostnamectl set-hostname $name
echo 'preserve_hostname: true' > /etc/cloud/cloud.cfg.d/99-zenite-hostname.cfg"
    echo "Creando $name ($ip en $subnet, $so) ..."
    iid=$(awsr ec2 run-instances --image-id "$ami" --instance-type "$TIPO" --count 1 \
      --network-interfaces "[{\"DeviceIndex\":0,\"SubnetId\":\"$sid\",\"PrivateIpAddress\":\"$ip\",\"Groups\":[\"$gid\"],\"AssociatePublicIpAddress\":false,\"DeleteOnTermination\":true}]" \
      --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
      "${extra[@]}" --user-data "$ud" \
      --tag-specifications \
        "ResourceType=instance,Tags=[{Key=Name,Value=$name},{Key=Role,Value=$role},$TAGS]" \
        "ResourceType=volume,Tags=[{Key=Name,Value=$name-root},{Key=Role,Value=$role},$TAGS]" \
      | jq -r '.Instances[0].InstanceId')
    echo "  $name -> $iid"
    todas+=("$iid")
  done

  echo "Esperando estado running ..."
  awsr ec2 wait instance-running --instance-ids "${todas[@]}"
  echo "Esperando status checks 2/2 (suele tardar de 3 a 5 minutos) ..."
  awsr ec2 wait instance-status-ok --instance-ids "${todas[@]}" \
    || echo "AVISO: los status checks aún no están en 2/2; vuelve a correr --validar en unos minutos."
}

# ---------- encender / detener ----------
seleccion() {  # estados permitidos, nombres... -> "InstanceId nombre" por línea
  local estados="$1"; shift
  local lista; lista=$(todas_zp)
  if (( $# > 0 )); then
    local n
    for n in "$@"; do
      awk -F'\t' -v n="$n" '$4==n{f=1} END{exit !f}' <<<"$lista" || { echo "ERROR: no existe la instancia $n en la VPC." >&2; return 1; }
    done
  fi
  while IFS=$'\t' read -r iid est ip nm; do
    [[ -z "$iid" ]] && continue
    if (( $# > 0 )); then
      local ok=0 n; for n in "$@"; do [[ "$n" == "$nm" ]] && ok=1; done; (( ok )) || continue
    fi
    case ",$estados," in *",$est,"*) echo "$iid $nm";; esac
  done <<<"$lista"
}
encender() {
  local sel ids=() linea
  sel=$(seleccion "stopped" "${NOMBRES_ARG[@]+"${NOMBRES_ARG[@]}"}") || exit 1
  if [[ -z "$sel" ]]; then echo "No hay instancias detenidas que encender."; return 0; fi
  while read -r linea; do ids+=("${linea%% *}"); echo "Encendiendo ${linea#* } (${linea%% *}) ..."; done <<<"$sel"
  awsr ec2 start-instances --instance-ids "${ids[@]}" >/dev/null
  awsr ec2 wait instance-running --instance-ids "${ids[@]}"
  echo "En ejecución. Los status checks tardan unos 3 a 5 minutos en llegar a 2/2 antes de poder conectarte por EICE."
}
detener() {
  local sel ids=() linea
  sel=$(seleccion "pending,running" "${NOMBRES_ARG[@]+"${NOMBRES_ARG[@]}"}") || exit 1
  if [[ -z "$sel" ]]; then echo "No hay instancias encendidas que detener."; return 0; fi
  while read -r linea; do ids+=("${linea%% *}"); echo "Deteniendo ${linea#* } (${linea%% *}) ..."; done <<<"$sel"
  awsr ec2 stop-instances --instance-ids "${ids[@]}" >/dev/null
  awsr ec2 wait instance-stopped --instance-ids "${ids[@]}"
  echo "Detenidas."
}
resumen() {
  echo "Estado de las instancias zp-* de la VPC:"
  todas_zp | awk -F'\t' '{printf "  %-18s %-10s %-14s %s\n", $4, $2, $3, $1}'
  echo "Encendidas ahora: $(todas_zp | awk -F'\t' '$2=="running"||$2=="pending"' | wc -l | tr -d ' ')"
}

# ---------- Validación ----------
validar() {
  local fallas=0
  check() {  # descripción, esperado, real
    if [[ "$2" == "$3" ]]; then printf "  [OK]    %-44s %s\n" "$1" "$3"
    else printf "  [FALLA] %-44s esperado=%s real=%s\n" "$1" "$2" "$3"; fallas=1; fi
  }
  ssh22() {  # GroupId, GroupId del par -> sí/no (TCP/22 de entrada desde ese grupo)
    jq -r --arg g "$1" --arg p "$2" '.SecurityGroups[] | select(.GroupId==$g) | .IpPermissions
      | if any(.[]; (.IpProtocol=="-1" or (.IpProtocol=="tcp" and .FromPort<=22 and .ToPort>=22)) and any(.UserIdGroupPairs[]?; .GroupId==$p)) then "sí" else "no" end' <<<"$SGJ"
  }
  local IJ SGJ eice_sg
  IJ=$(awsr ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$NOMBRES_PLAN" "Name=instance-state-name,Values=$VIVAS")
  SGJ=$(awsr ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID")
  printf '%s\n' "$IJ" > "$OUT_DIR/instancias-fase3.json"
  eice_sg=$(jq -r --arg n "$SG_EICE" '.SecurityGroups[] | select(.GroupName==$n) | .GroupId' <<<"$SGJ")

  echo "Validación de las instancias nuevas de Fase 3 · $VPC_NAME · $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "  VPC ID: $VPC_ID · región: $REGION"
  check "Instancias del plan (no terminadas)" "${#PLAN[@]}" "$(jq '[.Reservations[].Instances[]] | length' <<<"$IJ")"

  local s name desc gid e ip subnet sg role so i iid st stt
  for s in "${SGS[@]}"; do
    IFS='|' read -r name desc <<<"$s"
    gid=$(jq -r --arg n "$name" '.SecurityGroups[] | select(.GroupName==$n) | .GroupId' <<<"$SGJ")
    echo "  -- Security Group $name (${gid:-no existe})"
    check "Existe" "sí" "$([[ -n "$gid" ]] && echo sí || echo no)"
    [[ -n "$gid" ]] && check "TCP/22 de entrada desde $SG_EICE" "sí" "$(ssh22 "$gid" "$eice_sg")"
    [[ -n "$gid" ]] && echo "    entrada actual: $(jq -r --arg g "$gid" '.SecurityGroups[] | select(.GroupId==$g) | [.IpPermissions[] | "\(if .IpProtocol=="-1" then "todo" else "\(.IpProtocol):\(.FromPort // "-")" end)"] | join(", ")' <<<"$SGJ") (la Persona 5 puede ampliarla)"
  done

  for e in "${PLAN[@]}"; do
    IFS='|' read -r name ip subnet sg role so <<<"$e"
    i=$(jq -c --arg n "$name" '[.Reservations[].Instances[] | select(any(.Tags[]?; .Key=="Name" and .Value==$n))] | first // empty' <<<"$IJ")
    if [[ -z "$i" ]]; then echo "  -- $name ($ip)"; check "Existe" "sí" "no"; continue; fi
    iid=$(jq -r '.InstanceId' <<<"$i")
    tagv() { jq -r --arg k "$1" '.Tags[]? | select(.Key==$k) | .Value' <<<"$i"; }
    echo "  -- $name · $iid · $(jq -r '.InstanceType' <<<"$i") · $(jq -r '.ImageId' <<<"$i") · $so"
    stt=$(jq -r '.State.Name' <<<"$i")
    if [[ "$stt" == running ]]; then
      st=$(awsr ec2 describe-instance-status --instance-ids "$iid" | jq -r '.InstanceStatuses[0] | "\(.SystemStatus.Status)/\(.InstanceStatus.Status)"')
      check "Estado y status checks" "running ok/ok" "running $st"
    else
      echo "  [INFO]  estado: $stt (detenida: se omiten los status checks)"
    fi
    check "Subred ($subnet)" "$(subnet_id "$subnet")" "$(jq -r '.SubnetId' <<<"$i")"
    check "IP privada" "$ip" "$(jq -r '.PrivateIpAddress' <<<"$i")"
    check "IPv4 pública" "ninguna" "$(jq -r '.PublicIpAddress // "ninguna"' <<<"$i")"
    check "Security Group" "$sg" "$(jq -r '[.NetworkInterfaces[].Groups[].GroupName] | unique | join(",")' <<<"$i")"
    check "IMDSv2 obligatorio" "required" "$(jq -r '.MetadataOptions.HttpTokens' <<<"$i")"
    check "Tags Name/Project/Phase/Role" "$name/ZenitePrestige/Fase3/$role" "$(tagv Name)/$(tagv Project)/$(tagv Phase)/$(tagv Role)"
  done

  echo "  -- Resumen"
  echo "  $(todas_zp | awk -F'\t' '$2=="running"||$2=="pending"' | wc -l | tr -d ' ') instancia(s) zp-* encendida(s) en la VPC (≈ US\$0.0104 por hora cada una)."
  if (( fallas == 0 )); then echo "RESULTADO: todo correcto."; else echo "RESULTADO: hay fallas; corrígelas antes de continuar."; fi
  return "$fallas"
}

case "$MODO" in
  crear)
    echo "Plan: Security Groups ${SGS[*]%%|*} (solo TCP/22 desde $SG_EICE) y ${#PLAN[@]} instancias $TIPO sin IP pública en $VPC_NAME."
    echo "      Costo: ≈ US\$0.0104 por hora cada instancia encendida + discos de 8 GiB (≈ US\$0.64 al mes cada uno)."
    preflight || { echo "No se modificó nada." >&2; exit 1; }
    confirmar
    crear
    echo
    set +e; validar | tee "$OUT_DIR/instancias-fase3-validacion.txt"; RC=${PIPESTATUS[0]}; set -e
    echo
    echo "Conexión: instancia > Connect > EC2 Instance Connect > Connect using EC2 Instance Connect Endpoint (usuario ec2-user; ubuntu en zp-ldap-01)."
    echo "Al terminar: bash P1_instancias.sh detener  y  bash P1_gateways.sh destruir"
    ;;
  encender) encender; echo; resumen ;;
  detener)  detener;  echo; resumen ;;
  --validar)
    set +e; validar | tee "$OUT_DIR/instancias-fase3-validacion.txt"; RC=${PIPESTATUS[0]}; set -e
    ;;
esac
exit "${RC:-0}"
