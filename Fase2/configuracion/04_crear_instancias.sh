#!/usr/bin/env bash
# 04_crear_instancias.sh – Lanza y valida las 3 instancias de prueba privadas de Fase 2 (MD_4).
# Ejecutar en AWS CloudShell (us-east-1). No guarda ni pide credenciales.
#
#   bash 04_crear_instancias.sh                  crea (o reutiliza) zp-ventas-01, zp-ventas-02 y zp-ti-01 y valida
#   bash 04_crear_instancias.sh --validar        solo valida; no modifica nada
#   TIPO=t4g.micro bash 04_crear_instancias.sh   usa otro tipo de instancia (por defecto t3.micro)
#
# Requiere MD_2 (subredes) y MD_3 (Security Groups zenite-ventas / zenite-ti / zenite-eice y el EC2 Instance Connect
# Endpoint de la VPC). Es idempotente: reutiliza las instancias que ya existan con el mismo Name (si están detenidas,
# las enciende). Se detiene sin crear nada si falta algo o si una IP del plan está ocupada por otro recurso.
# Las instancias no tienen IPv4 pública ni llave SSH: se administran por EC2 Instance Connect Endpoint.
# Salida en ~/fase2-config/: instances.json e instancias-validacion.txt
set -euo pipefail

ENV_FILE="$(cd "$(dirname "$0")" && pwd)/../../.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

REGION="us-east-1"
VPC_NAME="vpc-zenite-fase2"
VPC_CIDR="10.20.0.0/24"
SG_EICE="zenite-eice"
TIPO="${TIPO:-t3.micro}"
OUT_DIR="$HOME/fase2-config"
MODO="crear"
[[ "${1:-}" == "--validar" ]] && MODO="validar"

# nombre | IP privada | subred | Security Group (group-name) | Role
PLAN=(
  "zp-ventas-01|10.20.0.10|subnet-zenite-ventas|zenite-ventas|Ventas"
  "zp-ventas-02|10.20.0.11|subnet-zenite-ventas|zenite-ventas|Ventas"
  "zp-ti-01|10.20.0.102|subnet-zenite-ti|zenite-ti|TI"
)
NOMBRES="zp-ventas-01,zp-ventas-02,zp-ti-01"
VIVAS="pending,running,stopping,stopped"
TAGS="{Key=Project,Value=ZenitePrestige},{Key=Phase,Value=Fase2},{Key=Environment,Value=Prototype},{Key=Owner,Value=Grupo30}"

awsr() { aws --region "$REGION" "$@"; }
mkdir -p "$OUT_DIR"

IDS=$(awsr ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[].VpcId" --output text)
read -ra ARR <<<"$IDS"
if (( ${#ARR[@]} != 1 )); then
  echo "ERROR: se esperaba 1 VPC llamada $VPC_NAME y hay ${#ARR[@]}. Ejecuta primero 01_crear_vpc.sh." >&2
  exit 1
fi
VPC_ID="${ARR[0]}"
echo "VPC: $VPC_NAME · $VPC_ID"

subnet_id() {  # nombre -> SubnetId (vacío si no existe)
  awsr ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$1" \
    --query "Subnets[0].SubnetId" --output text | sed 's/^None$//'
}
sg_id() {  # group-name -> GroupId (vacío si no existe; el nombre es único dentro de la VPC)
  awsr ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=$1" \
    --query "SecurityGroups[0].GroupId" --output text | sed 's/^None$//'
}
instancias() {  # nombre -> una línea "InstanceId estado IP SubnetId" por instancia no terminada
  awsr ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$1" \
    "Name=instance-state-name,Values=$VIVAS" \
    --query "Reservations[].Instances[].[InstanceId,State.Name,PrivateIpAddress,SubnetId]" --output text
}

# ---------- Comprobaciones previas (no modifican nada) ----------
preflight() {
  local err=0 e name ip subnet sg role sid gid lineas iid iest iip isub eni dueno eice_id eice_est eice_sub free arm

  read -r eice_id eice_est eice_sub < <(awsr ec2 describe-instance-connect-endpoints --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "InstanceConnectEndpoints[0].[InstanceConnectEndpointId,State,SubnetId]" --output text) || true
  if [[ "${eice_est:-}" == "create-complete" ]]; then
    echo "EICE: $eice_id · subred $eice_sub · disponible"
  else
    echo "ERROR: la VPC no tiene un EC2 Instance Connect Endpoint disponible (estado: ${eice_est:-no existe}). Revisa MD_3." >&2; err=1
  fi
  [[ -n "$(sg_id "$SG_EICE")" ]] || { echo "ERROR: no existe el Security Group $SG_EICE en la VPC (MD_3)." >&2; err=1; }

  read -r free arm < <(awsr ec2 describe-instance-types --instance-types "$TIPO" \
    --query "InstanceTypes[0].[FreeTierEligible,contains(ProcessorInfo.SupportedArchitectures,'arm64')]" --output text 2>/dev/null) || true
  if [[ -z "${free:-}" ]]; then
    echo "ERROR: el tipo de instancia $TIPO no existe en $REGION." >&2; err=1
  else
    ARCH="x86_64"; [[ "$arm" == "True" ]] && ARCH="arm64"
    echo "Tipo: $TIPO · $ARCH · Free Tier: $free"
    [[ "$free" == "True" ]] || echo "AVISO: $TIPO no aparece como Free Tier en esta cuenta; revisa créditos y costo antes de seguir." >&2
    # Amazon Linux 2023 estándar (la variante minimal no trae ec2-instance-connect).
    read -r AMI_ID AMI_NOM < <(awsr ec2 describe-images --owners amazon \
      --filters "Name=name,Values=al2023-ami-2023.*-$ARCH" "Name=state,Values=available" \
      --query "sort_by(Images,&CreationDate)[-1].[ImageId,Name]" --output text) || true
    if [[ "${AMI_ID:-}" == ami-* ]]; then
      echo "AMI: $AMI_ID ($AMI_NOM)"
    else
      echo "ERROR: no se encontró la AMI de Amazon Linux 2023 para $ARCH." >&2; err=1
    fi
  fi

  for e in "${PLAN[@]}"; do
    IFS='|' read -r name ip subnet sg role <<<"$e"
    sid=$(subnet_id "$subnet")
    gid=$(sg_id "$sg")
    [[ -n "$sid" ]] || { echo "ERROR: no existe la subred $subnet en la VPC (MD_2)." >&2; err=1; }
    [[ -n "$gid" ]] || { echo "ERROR: no existe el Security Group $sg en la VPC (MD_3)." >&2; err=1; }

    lineas=$(instancias "$name")
    if (( $(grep -c . <<<"$lineas") > 1 )); then
      echo "ERROR: hay más de una instancia llamada $name. Termina las sobrantes desde la consola." >&2; err=1
    elif [[ -n "$lineas" ]]; then
      read -r iid iest iip isub <<<"$lineas"
      if [[ "$iip" != "$ip" || "$isub" != "$sid" ]]; then
        echo "ERROR: $name ($iid) ya existe con IP $iip en $isub; el plan es $ip en $subnet. Termínala desde la consola." >&2; err=1
      fi
    else
      read -r eni dueno < <(awsr ec2 describe-network-interfaces \
        --filters "Name=vpc-id,Values=$VPC_ID" "Name=addresses.private-ip-address,Values=$ip" \
        --query "NetworkInterfaces[0].[NetworkInterfaceId,Attachment.InstanceId || 'ninguna']" --output text) || true
      if [[ -n "${eni:-}" && "$eni" != "None" ]]; then
        echo "ERROR: la IP $ip ya la usa $eni (instancia: $dueno). Libérala antes de crear $name." >&2; err=1
      fi
    fi
    echo "  $name -> $ip · $subnet (${sid:--}) · $sg (${gid:--})"
  done
  return "$err"
}

# ---------- Creación ----------
crear() {
  local e name ip subnet sg role sid gid iid iest ud todas=() extra=()
  # T3/T4g en modo "standard": sin cargos extra por créditos de CPU ("unlimited" es el valor por defecto).
  [[ "$TIPO" == t* ]] && extra=(--credit-specification CpuCredits=standard)

  for e in "${PLAN[@]}"; do
    IFS='|' read -r name ip subnet sg role <<<"$e"
    read -r iid iest _ <<<"$(instancias "$name")" || true
    if [[ -n "${iid:-}" ]]; then
      case "$iest" in
        stopping) echo "$name ($iid) se está deteniendo; se espera y se enciende ..."
                  awsr ec2 wait instance-stopped --instance-ids "$iid"
                  awsr ec2 start-instances --instance-ids "$iid" >/dev/null ;;
        stopped)  echo "Encendiendo $name ($iid) ..."
                  awsr ec2 start-instances --instance-ids "$iid" >/dev/null ;;
        *)        echo "Ya existe $name ($iid, $iest); se reutiliza." ;;
      esac
      todas+=("$iid")
      continue
    fi

    sid=$(subnet_id "$subnet")
    gid=$(sg_id "$sg")
    # preserve_hostname evita que cloud-init regrese el nombre a ip-10-20-0-x tras un Stop/Start.
    ud="#!/bin/bash
hostnamectl set-hostname $name
echo 'preserve_hostname: true' > /etc/cloud/cloud.cfg.d/99-zenite-hostname.cfg"
    echo "Creando $name ($ip en $subnet) ..."
    iid=$(awsr ec2 run-instances --image-id "$AMI_ID" --instance-type "$TIPO" --count 1 \
      --network-interfaces "[{\"DeviceIndex\":0,\"SubnetId\":\"$sid\",\"PrivateIpAddress\":\"$ip\",\"Groups\":[\"$gid\"],\"AssociatePublicIpAddress\":false,\"DeleteOnTermination\":true}]" \
      --metadata-options "HttpTokens=required,HttpEndpoint=enabled" \
      "${extra[@]}" \
      --user-data "$ud" \
      --tag-specifications \
        "ResourceType=instance,Tags=[{Key=Name,Value=$name},{Key=Role,Value=$role},$TAGS]" \
        "ResourceType=volume,Tags=[{Key=Name,Value=$name-root},{Key=Role,Value=$role},$TAGS]" \
      --query "Instances[0].InstanceId" --output text)
    echo "  $name -> $iid"
    todas+=("$iid")
  done

  echo "Esperando estado running ..."
  awsr ec2 wait instance-running --instance-ids "${todas[@]}"
  echo "Esperando status checks 2/2 (suele tardar de 3 a 5 minutos) ..."
  awsr ec2 wait instance-status-ok --instance-ids "${todas[@]}" \
    || echo "AVISO: los status checks aún no están en 2/2; la validación mostrará cuáles faltan. Vuelve a correr con --validar en unos minutos."
}

# ---------- Validación ----------
validar() {
  local fallas=0
  check() {  # descripción, esperado, real
    if [[ "$2" == "$3" ]]; then
      printf "  [OK]    %-44s %s\n" "$1" "$3"
    else
      printf "  [FALLA] %-44s esperado=%s real=%s\n" "$1" "$2" "$3"
      fallas=1
    fi
  }
  ssh22() {  # GroupId, GroupId del par, ingress|egress -> sí/no (TCP/22 entre ambos grupos)
    jq -r --arg g "$1" --arg p "$2" --arg d "$3" --arg vpc "$VPC_CIDR" '
      .SecurityGroups[] | select(.GroupId==$g)
      | (if $d=="ingress" then .IpPermissions else .IpPermissionsEgress end)
      | if any(.[]; (.IpProtocol=="-1" or (.IpProtocol=="tcp" and .FromPort<=22 and .ToPort>=22))
                    and (any(.UserIdGroupPairs[]?; .GroupId==$p)
                         or ($d=="egress" and any(.IpRanges[]?; .CidrIp=="0.0.0.0/0" or .CidrIp==$vpc))))
        then "sí" else "no" end' <<<"$SGJ"
  }

  local IJ SGJ EJ eice_sg
  IJ=$(awsr ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$NOMBRES" \
    "Name=instance-state-name,Values=$VIVAS" --output json)
  SGJ=$(awsr ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --output json)
  EJ=$(awsr ec2 describe-instance-connect-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --output json)
  printf '%s\n' "$IJ" > "$OUT_DIR/instances.json"
  eice_sg=$(jq -r --arg n "$SG_EICE" '.SecurityGroups[] | select(.GroupName==$n) | .GroupId' <<<"$SGJ")

  echo "Validación de las instancias de prueba de $VPC_NAME · $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "  VPC ID: $VPC_ID · región: $REGION"
  check "Instancias del plan (no terminadas)" "${#PLAN[@]}" "$(jq '[.Reservations[].Instances[]] | length' <<<"$IJ")"

  local e name ip subnet sg role i iid gid st
  for e in "${PLAN[@]}"; do
    IFS='|' read -r name ip subnet sg role <<<"$e"
    i=$(jq -c --arg n "$name" '[.Reservations[].Instances[] | select(any(.Tags[]?; .Key=="Name" and .Value==$n))] | first // empty' <<<"$IJ")
    if [[ -z "$i" ]]; then
      echo "  -- $name ($ip)"
      check "Existe" "sí" "no"; continue
    fi
    iid=$(jq -r '.InstanceId' <<<"$i")
    gid=$(jq -r --arg n "$sg" '.SecurityGroups[] | select(.GroupName==$n) | .GroupId' <<<"$SGJ")
    tagv() { jq -r --arg k "$1" '.Tags[]? | select(.Key==$k) | .Value' <<<"$i"; }
    st=$(awsr ec2 describe-instance-status --instance-ids "$iid" \
      --query "InstanceStatuses[0].[SystemStatus.Status,InstanceStatus.Status]" --output text | tr '\t' '/')
    echo "  -- $name · $iid · $(jq -r '.InstanceType' <<<"$i") · $(jq -r '.ImageId' <<<"$i")"
    check "Estado" "running" "$(jq -r '.State.Name' <<<"$i")"
    check "Status checks (sistema/instancia)" "ok/ok" "$st"
    check "Subred ($subnet)" "$(subnet_id "$subnet")" "$(jq -r '.SubnetId' <<<"$i")"
    check "IP privada" "$ip" "$(jq -r '.PrivateIpAddress' <<<"$i")"
    check "IPv4 pública" "ninguna" "$(jq -r '.PublicIpAddress // "ninguna"' <<<"$i")"
    check "Security Group" "$sg" "$(jq -r '[.NetworkInterfaces[].Groups[].GroupName] | unique | join(",")' <<<"$i")"
    check "TCP/22 desde $SG_EICE" "sí" "$(ssh22 "$gid" "$eice_sg" ingress)"
    check "IMDSv2 obligatorio" "required" "$(jq -r '.MetadataOptions.HttpTokens' <<<"$i")"
    check "Tags Name/Project/Phase/Role" "$name/ZenitePrestige/Fase2/$role" "$(tagv Name)/$(tagv Project)/$(tagv Phase)/$(tagv Role)"
  done

  echo "  -- EC2 Instance Connect Endpoint"
  check "EICE en la VPC" "create-complete" "$(jq -r '.InstanceConnectEndpoints[0].State // "no existe"' <<<"$EJ")"
  echo "    $(jq -r '.InstanceConnectEndpoints[0] // empty | "\(.InstanceConnectEndpointId) · \(.SubnetId) · \(.Tags // [] | map(select(.Key=="Name").Value) | first // "sin Name")"' <<<"$EJ")"
  for sg in zenite-ventas zenite-ti; do
    gid=$(jq -r --arg n "$sg" '.SecurityGroups[] | select(.GroupName==$n) | .GroupId' <<<"$SGJ")
    check "$SG_EICE permite salida TCP/22 a $sg" "sí" "$(ssh22 "$eice_sg" "$gid" egress)"
  done

  local igw nat eip inst
  igw=$(awsr ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query "length(InternetGateways)" --output text)
  nat=$(awsr ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" \
    "Name=state,Values=pending,available" --query "length(NatGateways)" --output text)
  eip=$(awsr ec2 describe-addresses --query "length(Addresses)" --output text)
  inst=$(awsr ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=pending,running" \
    --query "length(Reservations[].Instances[])" --output text)
  echo "  -- Control de costos"
  check "Internet Gateway / NAT Gateway / Elastic IP" "0/0/0" "$igw/$nat/$eip"
  check "Instancias encendidas en la VPC" "${#PLAN[@]}" "$inst"

  if (( fallas == 0 )); then echo "RESULTADO: todo correcto."; else echo "RESULTADO: hay fallas; corrígelas antes de continuar."; fi
  return "$fallas"
}

if [[ "$MODO" == "crear" ]]; then
  preflight || { echo "No se modificó nada." >&2; exit 1; }
  crear
  echo
fi

set +e
validar | tee "$OUT_DIR/instancias-validacion.txt"
RC=${PIPESTATUS[0]}
set -e

echo
echo "Archivos en $OUT_DIR: instances.json e instancias-validacion.txt (cópialos a Fase2/configuracion/)."
echo "Captura E07: EC2 > Instances con Name, Instance ID, State, Private IPv4, Subnet ID y Public IPv4 (vacía)."
echo "Conexión: instancia > Connect > EC2 Instance Connect > Connect using EC2 Instance Connect Endpoint, usuario ec2-user."
echo "O desde CloudShell: aws ec2-instance-connect ssh --instance-id <id> --os-user ec2-user --connection-type eice"
echo "Al terminar la sesión, si no siguen las pruebas de MD_5, detén las instancias (Instance state > Stop)."
exit "$RC"
