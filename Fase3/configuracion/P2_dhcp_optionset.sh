#!/usr/bin/env bash
# P2_dhcp_optionset.sh - Fase 3, Persona 2
# Crea (si no existe) y asocia a la VPC el DHCP Option Set de Zenite Prestige.
# Uso:  bash P2_dhcp_optionset.sh --validar   (solo lectura)
#       bash P2_dhcp_optionset.sh crear       (pide confirmacion (si) antes de cambiar AWS)
set -euo pipefail

REGION="us-east-1"
VPC_NAME="vpc-zenite-fase2"
OPT_NAME="dopt-zenite-fase3"
DOMINIO="zenite.internal"          
DNS="AmazonProvidedDNS"
NTP="10.20.0.68"
OUT_DIR="$HOME/fase3-config"
MODO="${1:---validar}"

export AWS_DEFAULT_REGION="$REGION"
mkdir -p "$OUT_DIR"
ERRORES=0
ok()    { echo "[OK] $*"; }
falla() { echo "[FALLA] $*"; ERRORES=$((ERRORES+1)); }

# valor de una opcion del Option Set ($1 = id, $2 = clave)
valor() {
  aws ec2 describe-dhcp-options --dhcp-options-ids "$1" \
    --query "DhcpOptions[0].DhcpConfigurations[?Key=='$2'].Values[].Value" --output text
}

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" \
  --query "Vpcs[0].VpcId" --output text)
if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
  falla "No se encontro la VPC $VPC_NAME en $REGION"; exit 1
fi
ok "VPC $VPC_NAME = $VPC_ID ($REGION)"

ASOCIADO=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --query "Vpcs[0].DhcpOptionsId" --output text)
OPT_ID=$(aws ec2 describe-dhcp-options --filters "Name=tag:Name,Values=$OPT_NAME" \
  --query "DhcpOptions[0].DhcpOptionsId" --output text)
[[ "$OPT_ID" == "None" ]] && OPT_ID=""

verificar() {
  [[ "$(valor "$OPT_ID" domain-name)" == "$DOMINIO" ]] && ok "domain-name = $DOMINIO" || falla "domain-name no coincide con $DOMINIO"
  [[ "$(valor "$OPT_ID" domain-name-servers)" == "$DNS" ]] && ok "domain-name-servers = $DNS" || falla "domain-name-servers no coincide con $DNS"
  [[ "$(valor "$OPT_ID" ntp-servers)" == "$NTP" ]] && ok "ntp-servers = $NTP" || falla "ntp-servers no coincide con $NTP"
  [[ "$ASOCIADO" == "$OPT_ID" ]] && ok "Asociado a la VPC" || falla "El Option Set no esta asociado a la VPC (actual: $ASOCIADO)"
}

if [[ "$MODO" == "--validar" ]]; then
  if [[ -z "$OPT_ID" ]]; then falla "No existe el Option Set $OPT_NAME"; else ok "Option Set $OPT_NAME = $OPT_ID"; verificar; fi
  [[ $ERRORES -eq 0 ]] && echo "Validacion completa sin fallos." || echo "Validacion con $ERRORES fallo(s)."
  exit $ERRORES
fi

[[ "$MODO" == "crear" ]] || { echo "Modo desconocido: $MODO"; exit 1; }

echo "Se va a cambiar la configuracion DHCP de TODA la VPC $VPC_ID."
echo "  dominio: $DOMINIO | DNS: $DNS | NTP: $NTP"
echo "  Option Set actualmente asociado: $ASOCIADO"
read -r -p "Escribe si para continuar: " R
[[ "${R,,}" == "si" ]] || { echo "Cancelado, no se cambio nada."; exit 0; }

if [[ -n "$OPT_ID" ]]; then
  ok "Ya existe $OPT_NAME = $OPT_ID; no se vuelve a crear"
  # un Option Set no se puede editar: si difiere, se aborta sin cambios
  [[ "$(valor "$OPT_ID" domain-name)" == "$DOMINIO" && "$(valor "$OPT_ID" ntp-servers)" == "$NTP" ]] \
    || { falla "El Option Set existente difiere de lo esperado. No se modifico nada; hay que crear otro con otro nombre."; exit 1; }
else
  OPT_ID=$(aws ec2 create-dhcp-options \
    --dhcp-configurations "Key=domain-name,Values=$DOMINIO" "Key=domain-name-servers,Values=$DNS" "Key=ntp-servers,Values=$NTP" \
    --tag-specifications "ResourceType=dhcp-options,Tags=[{Key=Name,Value=$OPT_NAME},{Key=Project,Value=ZenitePrestige},{Key=Phase,Value=Fase3},{Key=Environment,Value=Prototype},{Key=Owner,Value=Grupo30}]" \
    --query "DhcpOptions.DhcpOptionsId" --output text)
  ok "Creado $OPT_NAME = $OPT_ID"
fi

if [[ "$ASOCIADO" != "$OPT_ID" ]]; then
  echo "$ASOCIADO" > "$OUT_DIR/dhcp-optionset-anterior.txt"   # para poder revertir
  aws ec2 associate-dhcp-options --dhcp-options-id "$OPT_ID" --vpc-id "$VPC_ID"
  ok "Asociado a $VPC_ID (anterior guardado en $OUT_DIR/dhcp-optionset-anterior.txt)"
  ASOCIADO="$OPT_ID"
fi

verificar
aws ec2 describe-dhcp-options --dhcp-options-ids "$OPT_ID" > "$OUT_DIR/dhcp-options.json"
ok "Salida guardada en $OUT_DIR/dhcp-options.json"
exit $ERRORES
