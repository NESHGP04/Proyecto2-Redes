#!/usr/bin/env bash
# P3_eice.sh - Fase final, Persona 3
# Entra a una instancia zp-* por EC2 Instance Connect Endpoint desde CloudShell: ejecuta un comando, abre una sesion o copia archivos.
# Uso:  bash P3_eice.sh <zp-nombre>                                  sesion interactiva
#       bash P3_eice.sh <zp-nombre> '<comando>'                       ejecuta el comando (la salida empieza con uname -n y la hora UTC)
#       bash P3_eice.sh <zp-nombre> --copiar <archivo o carpeta...>   copia al home del usuario de la instancia
#       bash P3_eice.sh <zp-nombre> --traer <ruta remota> <destino>    copia un archivo de la instancia a CloudShell
# La llave SSH es temporal y vive solo en CloudShell (~/.ssh/zenite-eice): AWS la acepta 60 s despues de send-ssh-public-key.
set -euo pipefail

export AWS_DEFAULT_REGION="us-east-1"
export AWS_PAGER=""
VPC_NAME="vpc-zenite-fase2"
KEY="$HOME/.ssh/zenite-eice"
NOMBRE="${1:-}"
[[ $# -gt 0 ]] && shift
case "$NOMBRE" in
  zp-ldap-01|zp-web-01|zp-vpn-01|zp-monitor-01) USUARIO=ubuntu ;;   # Ubuntu 24.04
  zp-?*)                                       USUARIO=ec2-user ;; # Amazon Linux 2023
  *) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
esac

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[0].VpcId" --output text)
IID=$(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$NOMBRE" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" --output text)
[[ "$IID" =~ ^i-[0-9a-f]+$ ]] || { echo "[FALLA] $NOMBRE no esta encendida (o hay mas de una): '$IID'" >&2; exit 1; }

mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
[[ -f "$KEY" ]] || ssh-keygen -q -t ed25519 -N '' -C zenite-eice-cloudshell -f "$KEY"
aws ec2-instance-connect send-ssh-public-key --instance-id "$IID" --instance-os-user "$USUARIO" \
  --ssh-public-key "file://$KEY.pub" >/dev/null
OPC=(-i "$KEY" -o "ProxyCommand=aws ec2-instance-connect open-tunnel --instance-id $IID" -o IdentitiesOnly=yes
     -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$HOME/.ssh/zenite-known-hosts" -o ConnectTimeout=30)

case "${1:-}" in
  "")       exec ssh "${OPC[@]}" "$USUARIO@$IID" ;;
  --copiar) shift; exec scp -r "${OPC[@]}" "$@" "$USUARIO@$IID:" ;;
  --traer)  exec scp "${OPC[@]}" "$USUARIO@$IID:$2" "$3" ;;
  *)        T=(); [[ -t 0 ]] && T=(-t)
            exec ssh "${T[@]}" "${OPC[@]}" "$USUARIO@$IID" "echo \"== \$(uname -n) · \$(date -u '+%Y-%m-%d %H:%M:%S') UTC\"; $*" ;;
esac
