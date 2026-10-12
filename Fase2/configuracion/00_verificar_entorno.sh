#!/usr/bin/env bash
# 00_verificar_entorno.sh – Solo lectura: no crea ni modifica nada en AWS.
# Ejecutar en AWS CloudShell antes de crear la VPC (MD_1).
set -uo pipefail

ENV_FILE="$(cd "$(dirname "$0")" && pwd)/../../.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

REGION="us-east-1"
awsr() { aws --region "$REGION" "$@"; }

echo "== Región =="
echo "Este script consulta SIEMPRE $REGION (US East, N. Virginia)."
echo "Región activa de la sesión: ${AWS_REGION:-${AWS_DEFAULT_REGION:-no definida}}"
echo "Confirma en la consola (esquina superior derecha) que también dice N. Virginia."

echo
echo "== Cuenta (no copiar estos datos al repositorio) =="
awsr sts get-caller-identity --query "[Account,Arn]" --output text

echo
echo "== VPC existentes en $REGION =="
awsr ec2 describe-vpcs \
  --query "Vpcs[].[VpcId,CidrBlock,IsDefault,Tags[?Key=='Name']|[0].Value]" \
  --output table

echo
echo "== Recursos que generan costo (deben estar en 0 en esta parte) =="
INST=$(awsr ec2 describe-instances \
  --filters "Name=instance-state-name,Values=pending,running" \
  --query "length(Reservations[].Instances[])" --output text)
NAT=$(awsr ec2 describe-nat-gateways \
  --filter "Name=state,Values=pending,available" \
  --query "length(NatGateways)" --output text)
EIP=$(awsr ec2 describe-addresses --query "length(Addresses)" --output text)
VPN=$(awsr ec2 describe-vpn-connections \
  --filters "Name=state,Values=pending,available" \
  --query "length(VpnConnections)" --output text)

printf "  Instancias EC2 activas ........ %s\n" "$INST"
printf "  NAT Gateway activos ........... %s\n" "$NAT"
printf "  Elastic IP .................... %s\n" "$EIP"
printf "  VPN Site-to-Site activas ...... %s\n" "$VPN"

if [[ "$INST" != "0" || "$NAT" != "0" || "$EIP" != "0" || "$VPN" != "0" ]]; then
  echo "AVISO: hay recursos con costo en la cuenta/región. Si no son del grupo, no los toques; si son tuyos y no se usan, deténlos."
fi

echo
echo "Recordatorio: revisa AWS Billing (créditos y gasto acumulado) antes de continuar."
