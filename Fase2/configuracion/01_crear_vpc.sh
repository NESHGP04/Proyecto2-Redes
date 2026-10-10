#!/usr/bin/env bash
# 01_crear_vpc.sh – Crea (si no existe) y valida vpc-zenite-fase2 en us-east-1 (MD_1).
# Ejecutar en AWS CloudShell. No guarda ni pide credenciales.
#
#   bash 01_crear_vpc.sh             crea (o reutiliza) la VPC y la valida
#   bash 01_crear_vpc.sh --validar   solo valida; no modifica nada
#
# Es idempotente: si la VPC ya existe con el nombre y el CIDR correctos, la reutiliza.
# Salida en ~/fase2-config/: vpc.json y vpc-validacion.txt
set -euo pipefail

REGION="us-east-1"
VPC_NAME="vpc-zenite-fase2"
VPC_CIDR="10.20.0.0/24"
OUT_DIR="$HOME/fase2-config"
MODO="crear"
[[ "${1:-}" == "--validar" ]] && MODO="validar"

awsr() { aws --region "$REGION" "$@"; }
mkdir -p "$OUT_DIR"

IDS=$(awsr ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" \
  --query "Vpcs[].VpcId" --output text)
read -ra ARR <<<"$IDS"
N=${#ARR[@]}

if [[ "$MODO" == "crear" ]]; then
  if (( N > 1 )); then
    echo "ERROR: hay $N VPC con el nombre $VPC_NAME (${ARR[*]}). Elimina las duplicadas desde la consola y vuelve a correr el script." >&2
    exit 1
  fi

  if (( N == 0 )); then
    OTRA=$(awsr ec2 describe-vpcs --filters "Name=cidr,Values=$VPC_CIDR" \
      --query "Vpcs[].VpcId" --output text)
    if [[ -n "$OTRA" ]]; then
      echo "ERROR: ya existe $OTRA con $VPC_CIDR pero sin el nombre $VPC_NAME. Revísala en la consola; no se crea otra VPC." >&2
      exit 1
    fi
    echo "Creando $VPC_NAME ($VPC_CIDR) en $REGION ..."
    VPC_ID=$(awsr ec2 create-vpc \
      --cidr-block "$VPC_CIDR" \
      --instance-tenancy default \
      --query "Vpc.VpcId" --output text)
    awsr ec2 wait vpc-available --vpc-ids "$VPC_ID"
  else
    VPC_ID="${ARR[0]}"
    CIDR_ACTUAL=$(awsr ec2 describe-vpcs --vpc-ids "$VPC_ID" --query "Vpcs[0].CidrBlock" --output text)
    if [[ "$CIDR_ACTUAL" != "$VPC_CIDR" ]]; then
      echo "ERROR: $VPC_ID se llama $VPC_NAME pero su CIDR es $CIDR_ACTUAL (debe ser $VPC_CIDR). No se modifica." >&2
      exit 1
    fi
    echo "Ya existe $VPC_ID con el CIDR correcto; se reutiliza."
  fi

  awsr ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}'
  awsr ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'
  awsr ec2 create-tags --resources "$VPC_ID" --tags \
    "Key=Name,Value=$VPC_NAME" \
    "Key=Project,Value=ZenitePrestige" \
    "Key=Phase,Value=Fase2" \
    "Key=Environment,Value=Prototype" \
    "Key=Owner,Value=Grupo30"
else
  if (( N != 1 )); then
    echo "ERROR: se esperaba 1 VPC llamada $VPC_NAME y hay $N." >&2
    exit 1
  fi
  VPC_ID="${ARR[0]}"
fi

validar() {
  local fallas=0 J
  J=$(awsr ec2 describe-vpcs --vpc-ids "$VPC_ID" --output json)
  printf '%s\n' "$J" > "$OUT_DIR/vpc.json"

  check() {  # descripción, esperado, real
    if [[ "$2" == "$3" ]]; then
      printf "  [OK]    %-30s %s\n" "$1" "$3"
    else
      printf "  [FALLA] %-30s esperado=%s real=%s\n" "$1" "$2" "$3"
      fallas=1
    fi
  }
  tag() { jq -r --arg k "$1" '.Vpcs[0].Tags[]? | select(.Key==$k) | .Value' <<<"$J"; }

  local dns_s dns_h n_cidr
  dns_s=$(awsr ec2 describe-vpc-attribute --vpc-id "$VPC_ID" --attribute enableDnsSupport \
    --query "EnableDnsSupport.Value" --output text)
  dns_h=$(awsr ec2 describe-vpc-attribute --vpc-id "$VPC_ID" --attribute enableDnsHostnames \
    --query "EnableDnsHostnames.Value" --output text)
  n_cidr=$(awsr ec2 describe-vpcs --filters "Name=cidr,Values=$VPC_CIDR" \
    --query "length(Vpcs)" --output text)

  echo "Validación de $VPC_NAME · $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "  VPC ID: $VPC_ID · región: $REGION"
  check "Estado"                      "available"        "$(jq -r '.Vpcs[0].State' <<<"$J")"
  check "CIDR"                        "$VPC_CIDR"        "$(jq -r '.Vpcs[0].CidrBlock' <<<"$J")"
  check "VPC con ese CIDR (total)"    "1"                "$n_cidr"
  check "Bloques IPv6"                "0"                "$(jq -r '(.Vpcs[0].Ipv6CidrBlockAssociationSet // []) | length' <<<"$J")"
  check "Tenancy"                     "default"          "$(jq -r '.Vpcs[0].InstanceTenancy' <<<"$J")"
  check "DNS resolution"              "True"             "$dns_s"
  check "DNS hostnames"               "True"             "$dns_h"
  check "Tag Name"                    "$VPC_NAME"        "$(tag Name)"
  check "Tag Project"                 "ZenitePrestige"   "$(tag Project)"
  check "Tag Phase"                   "Fase2"            "$(tag Phase)"
  check "Tag Environment"             "Prototype"        "$(tag Environment)"
  check "Tag Owner"                   "Grupo30"          "$(tag Owner)"

  local inst nat eip vpn
  inst=$(awsr ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" \
    "Name=instance-state-name,Values=pending,running" --query "length(Reservations[].Instances[])" --output text)
  nat=$(awsr ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" \
    "Name=state,Values=pending,available" --query "length(NatGateways)" --output text)
  eip=$(awsr ec2 describe-addresses --query "length(Addresses)" --output text)
  vpn=$(awsr ec2 describe-vpn-connections --filters "Name=state,Values=pending,available" \
    --query "length(VpnConnections)" --output text)
  echo "  Control de costos (esta parte debe estar en 0): EC2=$inst NAT=$nat ElasticIP=$eip VPN-S2S=$vpn"
  if [[ "$inst$nat$eip$vpn" != "0000" ]]; then
    echo "  AVISO: hay recursos con costo. No son parte de este paso; revísalos."
  fi

  if (( fallas == 0 )); then
    echo "RESULTADO: todo correcto."
  else
    echo "RESULTADO: hay fallas; corrígelas antes de continuar."
  fi
  return "$fallas"
}

set +e
validar | tee "$OUT_DIR/vpc-validacion.txt"
RC=${PIPESTATUS[0]}
set -e

echo
echo "Archivos: $OUT_DIR/vpc.json y $OUT_DIR/vpc-validacion.txt (descárgalos a Fase2/configuracion/)."
echo "Falta la captura E01 en la consola: VPC > Your VPCs (nombre, VPC ID, CIDR, región, estado Available)."
exit "$RC"
