#!/usr/bin/env bash
# P5_acls.sh - Fase 3, Persona 5
# Network ACL de Visitantes y de TI (seccion 3 de P5_reglas_seguridad.md). Las ACL no guardan estado: cada regla de ida
# lleva su regla de retorno, y TCP/22 desde la subred del EICE (10.20.0.144/28) se permite ANTES de cualquier denegacion.
# Uso:  bash P5_acls.sh --validar [visitantes|ti|todo]   (solo lectura; modo por defecto, objeto por defecto: todo)
#       bash P5_acls.sh aplicar visitantes|ti            (UNA a la vez; muestra el plan y pide confirmacion (si))
#       bash P5_acls.sh --revertir [visitantes|ti|todo]  (vuelve a la ACL predeterminada y borra la ACL; pide (si))
# Despues de cada "aplicar" hay que comprobar la entrada por EICE a esa instancia; si falla, --revertir.
set -euo pipefail

REGION="us-east-1"
VPC_NAME="vpc-zenite-fase2"
OUT_DIR="$HOME/fase3-config"
MODO="${1:---validar}"
OBJ="${2:-}"

export AWS_DEFAULT_REGION="$REGION"
export AWS_PAGER=""
mkdir -p "$OUT_DIR"
ERRORES=0
ok()    { echo "[OK] $*"; }
falla() { echo "[FALLA] $*"; ERRORES=$((ERRORES+1)); }

EICE="10.20.0.144/28"; TI="10.20.0.96/28"; VPC="10.20.0.0/24"; ANY="0.0.0.0/0"

# "direccion|regla|protocolo|desde|hasta|origen o destino|accion"   (icmp: desde=tipo, hasta=codigo; all: "-")
ACL_VISITANTES=(
  "in|100|tcp|22|22|$EICE|allow"
  "in|110|tcp|22|22|$TI|allow"
  "in|120|icmp|-1|-1|$TI|allow"
  "in|200|all|-|-|$VPC|deny"
  "in|300|tcp|1024|65535|$ANY|allow"
  "in|310|udp|1024|65535|$ANY|allow"
  "out|100|tcp|1024|65535|$EICE|allow"
  "out|110|tcp|1024|65535|$TI|allow"
  "out|120|icmp|-1|-1|$TI|allow"
  "out|200|all|-|-|$VPC|deny"
  "out|300|tcp|80|80|$ANY|allow"
  "out|310|tcp|443|443|$ANY|allow"
  "out|320|tcp|53|53|$ANY|allow"
  "out|330|udp|53|53|$ANY|allow"
)
ACL_TI=(
  "in|100|tcp|22|22|$EICE|allow"
  "in|110|tcp|1024|65535|$VPC|allow"
  "in|120|udp|1024|65535|$VPC|allow"
  "in|130|icmp|0|-1|$VPC|allow"
  "out|100|all|-|-|$VPC|allow"
)

case "$MODO" in
  --validar) OBJ="${OBJ:-todo}" ;;
  --revertir) OBJ="${OBJ:-todo}" ;;
  aplicar) [[ "$OBJ" == "visitantes" || "$OBJ" == "ti" ]] || { echo "aplicar necesita un objeto: visitantes o ti (una ACL a la vez)"; exit 1; } ;;
  *) echo "Modo desconocido: $MODO (usa --validar, aplicar o --revertir)"; exit 1 ;;
esac
[[ "$OBJ" =~ ^(visitantes|ti|todo)$ ]] || { echo "Objeto desconocido: $OBJ (visitantes, ti o todo)"; exit 1; }
if [[ "$OBJ" == "todo" ]]; then LISTA=(visitantes ti); else LISTA=("$OBJ"); fi

VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[0].VpcId" --output text)
if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then falla "No se encontro la VPC $VPC_NAME en $REGION"; exit 1; fi
ok "VPC $VPC_NAME = $VPC_ID ($REGION)"

DEFAULT_ACL=$(aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" "Name=default,Values=true" \
  --query "NetworkAcls[0].NetworkAclId" --output text)
[[ -n "$DEFAULT_ACL" && "$DEFAULT_ACL" != "None" ]] || { falla "No se encontro la ACL predeterminada"; exit 1; }
ok "ACL predeterminada = $DEFAULT_ACL"

subnet_id() { aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=subnet-zenite-$1" --query "Subnets[0].SubnetId" --output text; }
acl_id()    { local I; I=$(aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=acl-zenite-$1" --query "NetworkAcls[0].NetworkAclId" --output text); [[ "$I" == "None" ]] && I=""; echo "$I"; }
acl_de_subred() { aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$1" --query "NetworkAcls[0].NetworkAclId" --output text; }
asoc_de_subred() { aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$1" --query "NetworkAcls[0].Associations[?SubnetId=='$1'].NetworkAclAssociationId | [0]" --output text; }
proto_num() { case "$1" in tcp) echo 6;; udp) echo 17;; icmp) echo 1;; all) echo -1;; esac; }

# cuantas entradas coinciden exactamente con la regla $2 de la ACL $1
existe_entrada() {  # acl dir num proto desde hasta cidr accion
  local ACL="$1" DIR="$2" NUM="$3" PR PN F="$5" T="$6" CIDR="$7" ACC="$8" EG="false" Q
  [[ "$DIR" == "out" ]] && EG="true"
  PN=$(proto_num "$4")
  Q="Entries[?RuleNumber==\`$NUM\` && Egress==\`$EG\` && Protocol=='$PN' && CidrBlock=='$CIDR' && RuleAction=='$ACC'"
  case "$4" in
    tcp|udp) Q="$Q && PortRange.From==\`$F\` && PortRange.To==\`$T\`" ;;
    icmp)    Q="$Q && IcmpTypeCode.Type==\`$F\` && IcmpTypeCode.Code==\`$T\`" ;;
  esac
  aws ec2 describe-network-acls --network-acl-ids "$ACL" --query "length(NetworkAcls[0].${Q}])" --output text
}

crear_entrada() {  # acl dir num proto desde hasta cidr accion
  local ACL="$1" DIR="$2" NUM="$3" PR="$4" F="$5" T="$6" CIDR="$7" ACC="$8"
  local ARGS=(--network-acl-id "$ACL" --rule-number "$NUM" --protocol "$(proto_num "$PR")" --rule-action "$ACC" --cidr-block "$CIDR")
  [[ "$DIR" == "in" ]] && ARGS+=(--ingress) || ARGS+=(--egress)
  case "$PR" in
    tcp|udp) ARGS+=(--port-range "From=$F,To=$T") ;;
    icmp)    ARGS+=(--icmp-type-code "Type=$F,Code=$T") ;;
  esac
  aws ec2 create-network-acl-entry "${ARGS[@]}"
}

validar_una() {  # visitantes | ti
  local N="$1" ACL SUB L DIR NUM PR F T CIDR ACC
  local REG; [[ "$N" == "visitantes" ]] && REG=("${ACL_VISITANTES[@]}") || REG=("${ACL_TI[@]}")
  SUB=$(subnet_id "$N")
  [[ -n "$SUB" && "$SUB" != "None" ]] || { falla "No existe subnet-zenite-$N"; return; }
  ACL=$(acl_id "$N")
  if [[ -z "$ACL" ]]; then falla "$N: no existe acl-zenite-$N"; return; fi
  ok "$N: existe acl-zenite-$N = $ACL"
  for L in "${REG[@]}"; do
    IFS='|' read -r DIR NUM PR F T CIDR ACC <<< "$L"
    [[ "$(existe_entrada "$ACL" "$DIR" "$NUM" "$PR" "$F" "$T" "$CIDR" "$ACC")" -ge 1 ]] \
      && ok "$N $DIR $NUM $PR $F-$T $CIDR $ACC" || falla "$N falta $DIR $NUM $PR $F-$T $CIDR $ACC"
  done
  local ACT; ACT=$(acl_de_subred "$SUB")
  [[ "$ACT" == "$ACL" ]] && ok "$N: subnet-zenite-$N ($SUB) esta asociada a $ACL" || falla "$N: subnet-zenite-$N usa $ACT, no $ACL"
}

validar() {
  local N
  for N in "${LISTA[@]}"; do validar_una "$N"; done
  # el resto de subredes sigue en la ACL predeterminada
  local OTROS=0 S ID
  for S in ventas servidores vpn dmz infra; do
    ID=$(subnet_id "$S"); [[ -n "$ID" && "$ID" != "None" ]] || continue
    [[ "$(acl_de_subred "$ID")" == "$DEFAULT_ACL" ]] || { falla "subnet-zenite-$S no esta en la ACL predeterminada"; OTROS=1; }
  done
  [[ $OTROS -eq 0 ]] && ok "Ventas, Servidores, VPN, DMZ e Infra siguen en la ACL predeterminada (decision D2)"
}

guardar_estado() {  # $1 = sufijo
  aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" > "$OUT_DIR/p5-acl-estado-$1.json"
  ok "Estado guardado en $OUT_DIR/p5-acl-estado-$1.json"
}

if [[ "$MODO" == "--validar" ]]; then
  validar
  [[ $ERRORES -eq 0 ]] && echo "Validacion completa sin fallos." || echo "Validacion con $ERRORES fallo(s)."
  exit $ERRORES
fi

if [[ "$MODO" == "aplicar" ]]; then
  N="$OBJ"
  SUB=$(subnet_id "$N"); [[ -n "$SUB" && "$SUB" != "None" ]] || { falla "No existe subnet-zenite-$N"; exit 1; }
  [[ "$N" == "visitantes" ]] && REG=("${ACL_VISITANTES[@]}") || REG=("${ACL_TI[@]}")
  ACL=$(acl_id "$N")
  ACTUAL=$(acl_de_subred "$SUB")
  echo "Plan para acl-zenite-$N -> subnet-zenite-$N ($SUB):"
  [[ -z "$ACL" ]] && echo "  - crear acl-zenite-$N" || echo "  - ya existe acl-zenite-$N ($ACL); solo se agregan las reglas que falten"
  echo "  - ${#REG[@]} reglas (entrada y salida, con retorno; TCP/22 desde $EICE antes de cualquier denegacion)"
  echo "  - asociarla a la subred (hoy usa $ACTUAL) SOLO cuando esten todas las reglas"
  if [[ "$N" == "ti" ]]; then
    echo "  ATENCION: TI queda SIN Internet. nmap debe estar instalado ya en zp-ti-01 (con el NAT encendido)."
    read -r -p "Ya instalaste nmap en zp-ti-01? Escribe si: " R
    [[ "${R,,}" == "si" ]] || { echo "Cancelado: instala nmap primero."; exit 0; }
  fi
  echo "Rollback listo: bash P5_acls.sh --revertir $N"
  read -r -p "Escribe si para continuar: " R
  [[ "${R,,}" == "si" ]] || { echo "Cancelado, no se cambio nada."; exit 0; }
  guardar_estado "antes-$N"
  if [[ -z "$ACL" ]]; then
    ACL=$(aws ec2 create-network-acl --vpc-id "$VPC_ID" --query "NetworkAcl.NetworkAclId" --output text \
      --tag-specifications "ResourceType=network-acl,Tags=[{Key=Name,Value=acl-zenite-$N},{Key=Project,Value=ZenitePrestige},{Key=Phase,Value=Fase3},{Key=Environment,Value=Prototype},{Key=Owner,Value=Grupo30}]")
    ok "ACL creada: acl-zenite-$N = $ACL (todavia sin asociar)"
  fi
  for L in "${REG[@]}"; do
    IFS='|' read -r DIR NUM PR F T CIDR ACC <<< "$L"
    if [[ "$(existe_entrada "$ACL" "$DIR" "$NUM" "$PR" "$F" "$T" "$CIDR" "$ACC")" -ge 1 ]]; then
      ok "ya existe $DIR $NUM"
    elif crear_entrada "$ACL" "$DIR" "$NUM" "$PR" "$F" "$T" "$CIDR" "$ACC"; then
      ok "agregada $DIR $NUM $PR $F-$T $CIDR $ACC"
    else
      falla "no se pudo agregar $DIR $NUM"
    fi
  done
  if [[ $ERRORES -ne 0 ]]; then
    echo "Hubo fallos al crear reglas: NO se asocia la ACL. Revisar y repetir (es idempotente)."; exit 1
  fi
  if [[ "$ACTUAL" != "$ACL" ]]; then
    ASOC=$(asoc_de_subred "$SUB")
    aws ec2 replace-network-acl-association --association-id "$ASOC" --network-acl-id "$ACL" >/dev/null \
      && ok "subnet-zenite-$N asociada a $ACL" || { falla "no se pudo asociar"; exit 1; }
  fi
  guardar_estado "despues-$N"
  LISTA=("$N"); validar
  [[ $ERRORES -eq 0 ]] && echo "RESULTADO: todo correcto. AHORA comprueba la entrada por EICE a la instancia de $N; si falla: bash P5_acls.sh --revertir $N" \
                       || echo "RESULTADO: $ERRORES fallo(s). Si EICE se corta: bash P5_acls.sh --revertir $N"
  exit $ERRORES
fi

if [[ "$MODO" == "--revertir" ]]; then
  echo "Se va a volver a la ACL predeterminada y BORRAR: ${LISTA[*]}"
  read -r -p "Escribe si para continuar: " R
  [[ "${R,,}" == "si" ]] || { echo "Cancelado, no se cambio nada."; exit 0; }
  guardar_estado "antes-revertir"
  for N in "${LISTA[@]}"; do
    SUB=$(subnet_id "$N"); ACL=$(acl_id "$N")
    if [[ -n "$SUB" && "$SUB" != "None" && "$(acl_de_subred "$SUB")" != "$DEFAULT_ACL" ]]; then
      ASOC=$(asoc_de_subred "$SUB")
      aws ec2 replace-network-acl-association --association-id "$ASOC" --network-acl-id "$DEFAULT_ACL" >/dev/null \
        && ok "subnet-zenite-$N de vuelta en la ACL predeterminada" || falla "no se pudo reasociar subnet-zenite-$N"
    else
      ok "subnet-zenite-$N ya esta en la ACL predeterminada"
    fi
    if [[ -n "$ACL" ]]; then
      aws ec2 delete-network-acl --network-acl-id "$ACL" >/dev/null && ok "acl-zenite-$N ($ACL) eliminada" || falla "no se pudo eliminar $ACL"
    else
      ok "acl-zenite-$N ya no existe"
    fi
  done
  [[ $ERRORES -eq 0 ]] && echo "Reversion completa." || echo "Reversion con $ERRORES fallo(s)."
  exit $ERRORES
fi
