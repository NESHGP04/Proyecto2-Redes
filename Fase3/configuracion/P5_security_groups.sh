#!/usr/bin/env bash
# P5_security_groups.sh - Fase 3, Persona 5
# Completa las reglas de ENTRADA de los Security Groups (S-04 a S-08 de P5_reglas_seguridad.md).
# Solo agrega permisos por Security Group de origen; no toca las reglas de P1, P2 ni P3.
# Uso:  bash P5_security_groups.sh --validar    (solo lectura; es el modo por defecto)
#       bash P5_security_groups.sh aplicar      (muestra el plan y pide confirmacion (si))
#       bash P5_security_groups.sh --revertir   (quita SOLO las reglas S-04 a S-08; pide (si))
set -euo pipefail

REGION="us-east-1"
VPC_NAME="vpc-zenite-fase2"
OUT_DIR="$HOME/fase3-config"
MODO="${1:---validar}"

export AWS_DEFAULT_REGION="$REGION"
export AWS_PAGER=""
mkdir -p "$OUT_DIR"
ERRORES=0
ok()    { echo "[OK] $*"; }
falla() { echo "[FALLA] $*"; ERRORES=$((ERRORES+1)); }

# --- Reglas nuevas: "destino|origen|protocolo|desde|hasta|id|descripcion" (nombres de SG, no IDs) ---
REGLAS=(
  "zenite-servidores|zenite-ventas|tcp|80|80|S-04|HTTP Intranet desde Ventas (P5)"
  "zenite-servidores|zenite-ti|tcp|80|80|S-04|HTTP Intranet desde TI (P5)"
  "zenite-servidores|zenite-servidores|tcp|80|80|S-04|HTTP Intranet desde Servidores (P5)"
  "zenite-servidores|zenite-ti|tcp|22|22|S-05|SSH desde TI (P5)"
  "zenite-servidores|zenite-ti|icmp|-1|-1|S-06|ICMP desde TI (P5)"
  "zenite-ventas|zenite-ti|tcp|22|22|S-07|SSH desde TI (P5)"
  "zenite-visitantes|zenite-ti|tcp|22|22|S-08|SSH desde TI (P5)"
  "zenite-visitantes|zenite-ti|icmp|-1|-1|S-08|ICMP desde TI (P5)"
)

# Reglas de otras personas que NO se tocan, pero que se comprueban (si desaparecen, algo se rompio)
BASE=(
  "zenite-servidores|zenite-eice|tcp|22|22|SSH desde EICE (P1)"
  "zenite-servidores|zenite-ventas|udp|123|123|NTP desde Ventas (P2/P5)"
  "zenite-servidores|zenite-ti|udp|123|123|NTP desde TI (P2/P5)"
  "zenite-servidores|zenite-servidores|udp|123|123|NTP desde Servidores (P2/P5)"
  "zenite-servidores|zenite-ventas|tcp|389|389|LDAP desde Ventas (P3)"
  "zenite-servidores|zenite-ti|tcp|389|389|LDAP desde TI (P3)"
  "zenite-servidores|zenite-ventas|tcp|636|636|LDAPS desde Ventas (P3)"
  "zenite-servidores|zenite-ti|tcp|636|636|LDAPS desde TI (P3)"
  "zenite-ventas|zenite-eice|tcp|22|22|SSH desde EICE (P1)"
  "zenite-ti|zenite-eice|tcp|22|22|SSH desde EICE (P1)"
  "zenite-visitantes|zenite-eice|tcp|22|22|SSH desde EICE (P1)"
)

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" \
  --query "Vpcs[0].VpcId" --output text)
if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
  falla "No se encontro la VPC $VPC_NAME en $REGION"; exit 1
fi
ok "VPC $VPC_NAME = $VPC_ID ($REGION)"

# ID de un Security Group por nombre (se detiene si no existe)
declare -A SG
for N in zenite-servidores zenite-ventas zenite-ti zenite-visitantes zenite-eice; do
  ID=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=$N" \
    --query "SecurityGroups[0].GroupId" --output text)
  if [[ -z "$ID" || "$ID" == "None" ]]; then falla "No existe el Security Group $N"; exit 1; fi
  SG[$N]="$ID"
done
ok "Security Groups encontrados: servidores=${SG[zenite-servidores]} ventas=${SG[zenite-ventas]} ti=${SG[zenite-ti]} visitantes=${SG[zenite-visitantes]} eice=${SG[zenite-eice]}"

# cuantas reglas de ENTRADA hay en $1 (nombre destino) desde el SG $2 (nombre origen), proto $3, puertos $4-$5
contar() {
  aws ec2 describe-security-group-rules --filters "Name=group-id,Values=${SG[$1]}" \
    --query "length(SecurityGroupRules[?IsEgress==\`false\` && IpProtocol=='$3' && FromPort==\`$4\` && ToPort==\`$5\` && ReferencedGroupInfo.GroupId=='${SG[$2]}'])" \
    --output text
}

# ids de esas reglas (para --revertir)
ids_regla() {
  aws ec2 describe-security-group-rules --filters "Name=group-id,Values=${SG[$1]}" \
    --query "SecurityGroupRules[?IsEgress==\`false\` && IpProtocol=='$3' && FromPort==\`$4\` && ToPort==\`$5\` && ReferencedGroupInfo.GroupId=='${SG[$2]}'].SecurityGroupRuleId" \
    --output text
}

validar() {
  local L DEST ORI PROTO F T ID DESC N
  for L in "${REGLAS[@]}"; do
    IFS='|' read -r DEST ORI PROTO F T ID DESC <<< "$L"
    N=$(contar "$DEST" "$ORI" "$PROTO" "$F" "$T")
    [[ "$N" -ge 1 ]] && ok "$ID $DEST <- $ORI $PROTO $F-$T" || falla "$ID falta: $DEST <- $ORI $PROTO $F-$T"
  done
  for L in "${BASE[@]}"; do
    IFS='|' read -r DEST ORI PROTO F T DESC <<< "$L"
    N=$(contar "$DEST" "$ORI" "$PROTO" "$F" "$T")
    [[ "$N" -ge 1 ]] && ok "se conserva: $DESC" || falla "FALTA regla de otra persona: $DESC ($DEST <- $ORI $PROTO $F-$T)"
  done
  # HARD-04: ninguna entrada desde 0.0.0.0/0 en los grupos de la VPC
  local PUB
  PUB=$(aws ec2 describe-security-group-rules \
    --filters "Name=group-id,Values=$(IFS=,; echo "${SG[*]}")" \
    --query "length(SecurityGroupRules[?IsEgress==\`false\` && CidrIpv4=='0.0.0.0/0'])" --output text)
  [[ "$PUB" == "0" ]] && ok "HARD-04: ninguna regla de entrada desde 0.0.0.0/0" || falla "HARD-04: hay $PUB regla(s) de entrada desde 0.0.0.0/0"
  # Visitantes no debe aparecer como origen en ningun grupo
  local VIS
  VIS=$(aws ec2 describe-security-group-rules \
    --filters "Name=group-id,Values=${SG[zenite-servidores]},${SG[zenite-ventas]},${SG[zenite-ti]}" \
    --query "length(SecurityGroupRules[?IsEgress==\`false\` && ReferencedGroupInfo.GroupId=='${SG[zenite-visitantes]}'])" --output text)
  [[ "$VIS" == "0" ]] && ok "Visitantes no es origen en Servidores, Ventas ni TI" || falla "Visitantes aparece como origen en $VIS regla(s)"
}

if [[ "$MODO" == "--validar" ]]; then
  validar
  [[ $ERRORES -eq 0 ]] && echo "Validacion completa sin fallos." || echo "Validacion con $ERRORES fallo(s)."
  exit $ERRORES
fi

# antes de cualquier cambio: guardar el estado actual de las reglas
guardar_estado() {  # $1 = sufijo del archivo
  aws ec2 describe-security-group-rules \
    --filters "Name=group-id,Values=$(IFS=,; echo "${SG[*]}")" > "$OUT_DIR/p5-sg-reglas-$1.json"
  ok "Estado guardado en $OUT_DIR/p5-sg-reglas-$1.json"
}

if [[ "$MODO" == "aplicar" ]]; then
  PLAN=()
  for L in "${REGLAS[@]}"; do
    IFS='|' read -r DEST ORI PROTO F T ID DESC <<< "$L"
    [[ "$(contar "$DEST" "$ORI" "$PROTO" "$F" "$T")" -ge 1 ]] || PLAN+=("$L")
  done
  if [[ ${#PLAN[@]} -eq 0 ]]; then ok "Todas las reglas ya existen; no hay nada que aplicar"; validar; exit $ERRORES; fi
  echo "Se van a AGREGAR ${#PLAN[@]} regla(s) de entrada (solo permisos, por Security Group de origen):"
  for L in "${PLAN[@]}"; do
    IFS='|' read -r DEST ORI PROTO F T ID DESC <<< "$L"
    echo "  $ID  $DEST <- $ORI  $PROTO $F-$T"
  done
  read -r -p "Escribe si para continuar: " R
  [[ "${R,,}" == "si" ]] || { echo "Cancelado, no se cambio nada."; exit 0; }
  guardar_estado antes
  for L in "${PLAN[@]}"; do
    IFS='|' read -r DEST ORI PROTO F T ID DESC <<< "$L"
    if aws ec2 authorize-security-group-ingress --group-id "${SG[$DEST]}" \
      --ip-permissions "IpProtocol=$PROTO,FromPort=$F,ToPort=$T,UserIdGroupPairs=[{GroupId=${SG[$ORI]},Description=$DESC}]" >/dev/null; then
      ok "$ID agregada: $DEST <- $ORI $PROTO $F-$T"
    else
      falla "$ID no se pudo agregar: $DEST <- $ORI $PROTO $F-$T"
    fi
  done
  guardar_estado despues
  validar
  [[ $ERRORES -eq 0 ]] && echo "RESULTADO: todo correcto." || echo "RESULTADO: $ERRORES fallo(s); revisar antes de continuar."
  exit $ERRORES
fi

if [[ "$MODO" == "--revertir" ]]; then
  echo "Se van a QUITAR solo las reglas S-04 a S-08 (las de P1, P2 y P3 no se tocan)."
  echo "Efecto: la Intranet deja de ser accesible por TCP 80 y TI pierde SSH/ICMP hacia Servidores, Ventas y Visitantes."
  read -r -p "Escribe si para continuar: " R
  [[ "${R,,}" == "si" ]] || { echo "Cancelado, no se cambio nada."; exit 0; }
  guardar_estado antes_revertir
  for L in "${REGLAS[@]}"; do
    IFS='|' read -r DEST ORI PROTO F T ID DESC <<< "$L"
    RID=$(ids_regla "$DEST" "$ORI" "$PROTO" "$F" "$T")
    if [[ -z "$RID" || "$RID" == "None" ]]; then ok "$ID ya no existe: $DEST <- $ORI $PROTO $F-$T"; continue; fi
    aws ec2 revoke-security-group-ingress --group-id "${SG[$DEST]}" --security-group-rule-ids $RID >/dev/null \
      && ok "$ID quitada ($RID)" || falla "$ID no se pudo quitar ($RID)"
  done
  [[ $ERRORES -eq 0 ]] && echo "Reversion completa." || echo "Reversion con $ERRORES fallo(s)."
  exit $ERRORES
fi

echo "Modo desconocido: $MODO (usa --validar, aplicar o --revertir)"; exit 1
