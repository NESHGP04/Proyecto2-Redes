#!/usr/bin/env bash
# P3_firewall_final.sh - Fase final, Persona 3 (VPN y firewall final)
# Reglas del firewall de la fase final: Security Groups de la DMZ, la VPN y el monitoreo, y Network ACL de la DMZ y la VPN.
# Las UNICAS entradas desde 0.0.0.0/0 son las de la decision D10: TCP 80 y 443 en zenite-dmz y UDP 1194 en zenite-vpn.
# Uso:  bash P3_firewall_final.sh --validar [paso|todo]   (solo lectura; modo por defecto, paso por defecto: todo)
#       bash P3_firewall_final.sh aplicar <paso>          (UN paso a la vez; muestra el plan y pide confirmacion (si))
#       bash P3_firewall_final.sh --revertir <paso>       (quita solo lo de ese paso; pide confirmacion (si))
# Pasos: base       TCP 80/443 en zenite-dmz (ya las abrio P2: se reconocen, no se duplican), UDP 1194 en zenite-vpn y SSH desde TI
#        vpn        Intranet (TCP 80) de zenite-servidores desde zenite-vpn
#        monitoreo  SNMP (UDP 161) desde zenite-ti hacia todos los grupos, ICMP desde TI en DMZ y VPN, y SNMP en acl-zenite-visitantes
#        acl-dmz    acl-zenite-dmz asociada a subnet-zenite-dmz
#        acl-vpn    acl-zenite-vpn asociada a subnet-zenite-vpn
# Despues de cada "aplicar" de una ACL hay que comprobar la entrada por EICE a la instancia de esa subred; si falla: --revertir.
# Ejecutar en AWS CloudShell (us-east-1). Salida y estados en ~/final-config/.
set -euo pipefail

REGION="us-east-1"
VPC_NAME="vpc-zenite-fase2"
OUT_DIR="$HOME/final-config"
MODO="${1:---validar}"
PASO="${2:-}"

export AWS_DEFAULT_REGION="$REGION"
export AWS_PAGER=""
mkdir -p "$OUT_DIR"
exec > >(tee -a "$OUT_DIR/P3_firewall_final.log") 2>&1
echo "== P3_firewall_final.sh $MODO ${PASO} · $(date -u '+%Y-%m-%d %H:%M:%S') UTC"
ERRORES=0
ok()    { echo "[OK] $*"; }
falla() { echo "[FALLA] $*"; ERRORES=$((ERRORES+1)); }
info()  { echo "[INFO] $*"; }

PASOS="base vpn monitoreo acl-dmz acl-vpn"
case "$MODO" in
  --validar) PASO="${PASO:-todo}" ;;
  aplicar|--revertir) [[ -n "$PASO" && "$PASO" != "todo" ]] || { echo "$MODO necesita un paso: $PASOS (uno a la vez)"; exit 1; } ;;
  *) echo "Modo desconocido: $MODO (usa --validar, aplicar o --revertir)"; exit 1 ;;
esac
[[ " $PASOS todo " == *" $PASO "* ]] || { echo "Paso desconocido: $PASO ($PASOS o todo)"; exit 1; }
if [[ "$PASO" == "todo" ]]; then LISTA=($PASOS); else LISTA=("$PASO"); fi

# --- Security Groups: "paso|destino|origen|protocolo|desde|hasta|id|descripcion" (origen = nombre de SG o CIDR) ---
REGLAS=(
  "base|zenite-dmz|0.0.0.0/0|tcp|80|80|F-01|HTTP redireccion y Lets Encrypt (D10)"
  "base|zenite-dmz|0.0.0.0/0|tcp|443|443|F-02|HTTPS portal publico (D10)"
  "base|zenite-dmz|zenite-ti|tcp|22|22|F-03|SSH desde TI (P3)"
  "base|zenite-vpn|0.0.0.0/0|udp|1194|1194|F-04|OpenVPN (D10)"
  "base|zenite-vpn|zenite-ti|tcp|22|22|F-05|SSH desde TI (P3)"
  "vpn|zenite-servidores|zenite-vpn|tcp|80|80|F-06|Intranet desde la VPN (P3)"
  "monitoreo|zenite-dmz|zenite-ti|udp|161|161|F-07|SNMP desde TI (P3)"
  "monitoreo|zenite-vpn|zenite-ti|udp|161|161|F-07|SNMP desde TI (P3)"
  "monitoreo|zenite-servidores|zenite-ti|udp|161|161|F-07|SNMP desde TI (P3)"
  "monitoreo|zenite-ventas|zenite-ti|udp|161|161|F-07|SNMP desde TI (P3)"
  "monitoreo|zenite-visitantes|zenite-ti|udp|161|161|F-07|SNMP desde TI (P3)"
  "monitoreo|zenite-ti|zenite-ti|udp|161|161|F-07|SNMP desde TI (P3)"
  "monitoreo|zenite-dmz|zenite-ti|icmp|-1|-1|F-08|ICMP desde TI (P3)"
  "monitoreo|zenite-vpn|zenite-ti|icmp|-1|-1|F-08|ICMP desde TI (P3)"
)
# Reglas de P1 que NO se tocan, pero que se comprueban
BASE_P1=(
  "zenite-dmz|zenite-eice|tcp|22|22|SSH desde EICE (P1)"
  "zenite-vpn|zenite-eice|tcp|22|22|SSH desde EICE (P1)"
)
# Unicas entradas desde Internet permitidas (D10): "grupo protocolo desde hasta"
D10=$'zenite-dmz tcp 443 443\nzenite-dmz tcp 80 80\nzenite-vpn udp 1194 1194'
PUBLICAS_OK="zp-web-01 zp-vpn-01"

# --- Network ACL: "direccion|regla|protocolo|desde|hasta|origen o destino|accion" (icmp: desde=tipo, hasta=codigo; all: "-") ---
EICE="10.20.0.144/28"; TI="10.20.0.96/28"; VPC="10.20.0.0/24"; SRV="10.20.0.64/27"; ANY="0.0.0.0/0"
ACL_DMZ=(
  "in|100|tcp|22|22|$EICE|allow"
  "in|110|tcp|22|22|$TI|allow"
  "in|120|udp|161|161|$TI|allow"
  "in|130|icmp|-1|-1|$TI|allow"
  "in|200|all|-|-|$VPC|deny"
  "in|300|tcp|80|80|$ANY|allow"
  "in|310|tcp|443|443|$ANY|allow"
  "in|320|tcp|1024|65535|$ANY|allow"
  "in|330|udp|1024|65535|$ANY|allow"
  "out|100|tcp|1024|65535|$EICE|allow"
  "out|110|tcp|1024|65535|$TI|allow"
  "out|120|udp|1024|65535|$TI|allow"
  "out|130|icmp|-1|-1|$TI|allow"
  "out|200|all|-|-|$VPC|deny"
  "out|300|tcp|80|80|$ANY|allow"
  "out|310|tcp|443|443|$ANY|allow"
  "out|320|tcp|1024|65535|$ANY|allow"
  "out|330|udp|53|53|$ANY|allow"
  "out|340|tcp|53|53|$ANY|allow"
  "out|350|udp|123|123|$ANY|allow"
)
ACL_VPN=(
  "in|100|tcp|22|22|$EICE|allow"
  "in|110|tcp|22|22|$TI|allow"
  "in|120|udp|161|161|$TI|allow"
  "in|130|icmp|-1|-1|$TI|allow"
  "in|140|tcp|1024|65535|$SRV|allow"
  "in|200|all|-|-|$VPC|deny"
  "in|300|udp|1194|1194|$ANY|allow"
  "in|310|tcp|1024|65535|$ANY|allow"
  "in|320|udp|1024|65535|$ANY|allow"
  "out|100|tcp|1024|65535|$EICE|allow"
  "out|110|tcp|1024|65535|$TI|allow"
  "out|120|udp|1024|65535|$TI|allow"
  "out|130|icmp|-1|-1|$TI|allow"
  "out|140|tcp|80|80|$SRV|allow"
  "out|200|all|-|-|$VPC|deny"
  "out|300|udp|1024|65535|$ANY|allow"
  "out|310|tcp|80|80|$ANY|allow"
  "out|320|tcp|443|443|$ANY|allow"
  "out|330|udp|53|53|$ANY|allow"
  "out|340|tcp|53|53|$ANY|allow"
  "out|350|udp|123|123|$ANY|allow"
)
# SNMP en la ACL de Visitantes de Fase 3 (paso monitoreo): reglas 130, libres y antes de la denegacion 200
ACL_VIS_SNMP=(
  "in|130|udp|161|161|$TI|allow"
  "out|130|udp|1024|65535|$TI|allow"
)

# ---------- busquedas por nombre ----------
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[0].VpcId" --output text)
if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then falla "No se encontro la VPC $VPC_NAME en $REGION"; exit 1; fi
ok "VPC $VPC_NAME = $VPC_ID ($REGION)"

declare -A SG
for N in zenite-dmz zenite-vpn zenite-servidores zenite-ventas zenite-ti zenite-visitantes zenite-eice; do
  ID=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=$N" \
    --query "SecurityGroups[0].GroupId" --output text)
  if [[ -z "$ID" || "$ID" == "None" ]]; then falla "No existe el Security Group $N"; exit 1; fi
  SG[$N]="$ID"
done
ok "Security Groups: dmz=${SG[zenite-dmz]} vpn=${SG[zenite-vpn]} servidores=${SG[zenite-servidores]} ti=${SG[zenite-ti]} eice=${SG[zenite-eice]}"

DEFAULT_ACL=$(aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" "Name=default,Values=true" \
  --query "NetworkAcls[0].NetworkAclId" --output text)
[[ -n "$DEFAULT_ACL" && "$DEFAULT_ACL" != "None" ]] || { falla "No se encontro la ACL predeterminada"; exit 1; }

# filtro JMESPath de una regla de ENTRADA de SG: destino, origen, protocolo, desde, hasta
filtro_sg() {
  local O
  if [[ "$2" == */* ]]; then O="CidrIpv4=='$2'"; else O="ReferencedGroupInfo.GroupId=='${SG[$2]}'"; fi
  echo "SecurityGroupRules[?IsEgress==\`false\` && IpProtocol=='$3' && FromPort==\`$4\` && ToPort==\`$5\` && $O]"
}
contar()    { aws ec2 describe-security-group-rules --filters "Name=group-id,Values=${SG[$1]}" --query "length($(filtro_sg "$@"))" --output text; }
ids_regla() { aws ec2 describe-security-group-rules --filters "Name=group-id,Values=${SG[$1]}" --query "$(filtro_sg "$@").SecurityGroupRuleId" --output text; }

# ---------- Network ACL (funciones de P5_acls.sh) ----------
subnet_id() { aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=subnet-zenite-$1" --query "Subnets[0].SubnetId" --output text; }
acl_id()    { local I; I=$(aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=acl-zenite-$1" --query "NetworkAcls[0].NetworkAclId" --output text); [[ "$I" == "None" ]] && I=""; echo "$I"; }
acl_de_subred()  { aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$1" --query "NetworkAcls[0].NetworkAclId" --output text; }
asoc_de_subred() { aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$1" --query "NetworkAcls[0].Associations[?SubnetId=='$1'].NetworkAclAssociationId | [0]" --output text; }
proto_num() { case "$1" in tcp) echo 6;; udp) echo 17;; icmp) echo 1;; all) echo -1;; esac; }

existe_entrada() {  # acl dir num proto desde hasta cidr accion
  local ACL="$1" DIR="$2" NUM="$3" PN F="$5" T="$6" CIDR="$7" ACC="$8" EG="false" Q
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
reglas_acl() {  # dmz|vpn -> nombre del arreglo
  [[ "$1" == "dmz" ]] && echo "ACL_DMZ[@]" || echo "ACL_VPN[@]"
}

guardar_estado() {  # $1 = sufijo
  aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" > "$OUT_DIR/p3-sg-$1.json"
  aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" > "$OUT_DIR/p3-acl-$1.json"
  ok "Estado guardado en $OUT_DIR/p3-sg-$1.json y p3-acl-$1.json"
}
confirmar() {
  local R; read -r -p "Escribe si para continuar: " R
  [[ "${R,,}" == "si" ]] || { echo "Cancelado, no se cambio nada."; exit 0; }
}

# ---------- validacion por paso ----------
validar_sg_paso() {  # paso
  local L P DEST ORI PROTO F T ID DESC
  for L in "${REGLAS[@]}"; do
    IFS='|' read -r P DEST ORI PROTO F T ID DESC <<< "$L"
    [[ "$P" == "$1" ]] || continue
    [[ "$(contar "$DEST" "$ORI" "$PROTO" "$F" "$T")" -ge 1 ]] && ok "$ID $DEST <- $ORI $PROTO $F-$T" || falla "$ID falta: $DEST <- $ORI $PROTO $F-$T"
  done
}
validar_entradas() {  # acl nombre arreglo...
  local ACL="$1" N="$2" L DIR NUM PR F T CIDR ACC; shift 2
  for L in "$@"; do
    IFS='|' read -r DIR NUM PR F T CIDR ACC <<< "$L"
    [[ "$(existe_entrada "$ACL" "$DIR" "$NUM" "$PR" "$F" "$T" "$CIDR" "$ACC")" -ge 1 ]] \
      && ok "$N $DIR $NUM $PR $F-$T $CIDR $ACC" || falla "$N falta $DIR $NUM $PR $F-$T $CIDR $ACC"
  done
}
validar_acl() {  # dmz|vpn
  local N="$1" ACL SUB ACT
  SUB=$(subnet_id "$N"); ACL=$(acl_id "$N")
  [[ -n "$SUB" && "$SUB" != "None" ]] || { falla "No existe subnet-zenite-$N"; return; }
  if [[ -z "$ACL" ]]; then falla "$N: no existe acl-zenite-$N"; return; fi
  ok "$N: existe acl-zenite-$N = $ACL"
  local R; R=$(reglas_acl "$N")
  validar_entradas "$ACL" "$N" "${!R}"
  ACT=$(acl_de_subred "$SUB")
  [[ "$ACT" == "$ACL" ]] && ok "$N: subnet-zenite-$N ($SUB) esta asociada a $ACL" || falla "$N: subnet-zenite-$N usa $ACT, no $ACL"
}
validar_paso() {
  echo "--- paso $1"
  case "$1" in
    base|vpn) validar_sg_paso "$1" ;;
    monitoreo)
      validar_sg_paso monitoreo
      local V; V=$(acl_id visitantes)
      [[ -n "$V" ]] && validar_entradas "$V" visitantes "${ACL_VIS_SNMP[@]}" || falla "no existe acl-zenite-visitantes (Fase 3)"
      ;;
    acl-dmz) validar_acl dmz ;;
    acl-vpn) validar_acl vpn ;;
  esac
}

# ---------- comprobaciones globales (FW-01, IP publicas, aislamiento, EICE) ----------
validar_global() {
  echo "--- comprobaciones globales"
  local IDS REAL ESPERADO L DEST ORI PROTO F T DESC X N
  for L in "${BASE_P1[@]}"; do
    IFS='|' read -r DEST ORI PROTO F T DESC <<< "$L"
    [[ "$(contar "$DEST" "$ORI" "$PROTO" "$F" "$T")" -ge 1 ]] && ok "se conserva: $DESC en $DEST" || falla "FALTA regla de P1: $DESC en $DEST"
  done

  # FW-01: entradas desde Internet en TODOS los Security Groups de la VPC
  IDS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query "SecurityGroups[].GroupId" --output text | tr '\t' ',')
  REAL=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$IDS" \
    --query "SecurityGroupRules[?IsEgress==\`false\` && (CidrIpv4=='0.0.0.0/0' || CidrIpv6=='::/0')].[GroupId,IpProtocol,FromPort,ToPort]" --output text)
  for N in "${!SG[@]}"; do REAL="${REAL//${SG[$N]}/$N}"; done
  REAL=$(echo "$REAL" | tr '\t' ' ' | sed '/^$/d' | sort)
  ESPERADO=$(echo "$D10" | sort)
  if [[ "$REAL" == "$ESPERADO" ]]; then ok "FW-01: las unicas entradas desde Internet son TCP 80 y 443 en zenite-dmz y UDP 1194 en zenite-vpn"
  else
    X=$(comm -23 <(echo "$REAL") <(echo "$ESPERADO") | paste -sd';' -)
    [[ -n "$X" ]] && falla "FW-01: entradas desde Internet fuera de D10: $X"
    X=$(comm -13 <(echo "$REAL") <(echo "$ESPERADO") | paste -sd';' -)
    [[ -n "$X" ]] && falla "FW-01: falta abrir (D10): $X"
  fi

  # Solo zp-web-01 y zp-vpn-01 con IP publica (revisado por interfaz de red)
  X=""
  while read -r TIPO IID PUB; do
    [[ -z "${TIPO:-}" ]] && continue
    if [[ "$TIPO" != "interface" || "$IID" == "None" ]]; then info "IP publica $PUB en una interfaz de tipo $TIPO (NAT u otro servicio de AWS)"; continue; fi
    N=$(aws ec2 describe-instances --instance-ids "$IID" --query "Reservations[0].Instances[0].Tags[?Key=='Name'].Value | [0]" --output text)
    info "IP publica $PUB -> $N ($IID)"
    [[ " $PUBLICAS_OK " == *" $N "* ]] || X="$X $N"
  done < <(aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" \
            --query "NetworkInterfaces[?Association.PublicIp].[InterfaceType,Attachment.InstanceId,Association.PublicIp]" --output text)
  [[ -z "$X" ]] && ok "Solo zp-web-01 y zp-vpn-01 tienen IP publica" || falla "Instancias con IP publica no autorizada:$X"

  # Aislamiento: la DMZ no entra a Servidores ni TI; la VPN no entra a TI y a Servidores solo por TCP 80
  local Q="SecurityGroupRules[?IsEgress==\`false\` && ReferencedGroupInfo.GroupId=="
  for N in zenite-servidores zenite-ti; do
    X=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=${SG[$N]}" --query "length(${Q}'${SG[zenite-dmz]}'])" --output text)
    [[ "$X" == "0" ]] && ok "$N no admite entradas desde zenite-dmz" || falla "$N admite $X regla(s) desde zenite-dmz"
  done
  X=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=${SG[zenite-ti]}" --query "length(${Q}'${SG[zenite-vpn]}'])" --output text)
  [[ "$X" == "0" ]] && ok "zenite-ti no admite entradas desde zenite-vpn" || falla "zenite-ti admite $X regla(s) desde zenite-vpn"
  X=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=${SG[zenite-servidores]}" \
    --query "length(${Q}'${SG[zenite-vpn]}' && !(IpProtocol=='tcp' && FromPort==\`80\` && ToPort==\`80\`)])" --output text)
  [[ "$X" == "0" ]] && ok "zenite-servidores admite desde zenite-vpn solo TCP 80 (o nada)" || falla "zenite-servidores admite $X regla(s) extra desde zenite-vpn"

  # EICE: endpoint disponible, TCP 22 desde zenite-eice en los grupos de las zp-*, y en cada acl-zenite-* el permiso va antes de la denegacion
  X=$(aws ec2 describe-instance-connect-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --query "InstanceConnectEndpoints[0].State" --output text)
  [[ "$X" == "create-complete" ]] && ok "EICE disponible ($X)" || falla "EICE no disponible ($X)"
  for N in $(aws ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=zp-*" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
              --query "Reservations[].Instances[].SecurityGroups[].GroupName" --output text | tr '\t' '\n' | sort -u); do
    [[ -n "${SG[$N]:-}" ]] || { falla "grupo $N de una zp-* no es conocido por este script"; continue; }
    [[ "$(contar "$N" zenite-eice tcp 22 22)" -ge 1 ]] && ok "EICE: $N admite TCP 22 desde zenite-eice" || falla "EICE: $N NO admite TCP 22 desde zenite-eice"
  done
  local A NOM DENY_IN ALLOW_IN DENY_OUT ALLOW_OUT C="(CidrBlock=='$EICE' || CidrBlock=='$VPC')"
  while read -r A NOM; do
    [[ -z "${A:-}" ]] && continue
    DENY_IN=$(aws ec2 describe-network-acls --network-acl-ids "$A" --query "min(NetworkAcls[0].Entries[?Egress==\`false\` && RuleAction=='deny' && RuleNumber<\`32767\`].RuleNumber)" --output text)
    ALLOW_IN=$(aws ec2 describe-network-acls --network-acl-ids "$A" --query "min(NetworkAcls[0].Entries[?Egress==\`false\` && RuleAction=='allow' && $C && (Protocol=='-1' || (Protocol=='6' && PortRange.From<=\`22\` && PortRange.To>=\`22\`))].RuleNumber)" --output text)
    DENY_OUT=$(aws ec2 describe-network-acls --network-acl-ids "$A" --query "min(NetworkAcls[0].Entries[?Egress==\`true\` && RuleAction=='deny' && RuleNumber<\`32767\`].RuleNumber)" --output text)
    ALLOW_OUT=$(aws ec2 describe-network-acls --network-acl-ids "$A" --query "min(NetworkAcls[0].Entries[?Egress==\`true\` && RuleAction=='allow' && $C && (Protocol=='-1' || (Protocol=='6' && PortRange.From<=\`1024\` && PortRange.To>=\`65535\`))].RuleNumber)" --output text)
    if [[ "$ALLOW_IN" != "None" && "$ALLOW_OUT" != "None" && ( "$DENY_IN" == "None" || "$ALLOW_IN" -lt "$DENY_IN" ) && ( "$DENY_OUT" == "None" || "$ALLOW_OUT" -lt "$DENY_OUT" ) ]]; then
      ok "EICE: $NOM permite SSH ($ALLOW_IN) y su retorno ($ALLOW_OUT) antes de cualquier denegacion"
    else
      falla "EICE: $NOM corta el EICE (permiso entrada=$ALLOW_IN salida=$ALLOW_OUT, primera denegacion entrada=$DENY_IN salida=$DENY_OUT)"
    fi
  done < <(aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=acl-zenite-*" \
            --query "NetworkAcls[].[NetworkAclId, Tags[?Key=='Name'].Value | [0]]" --output text)
  info "La prueba real del EICE (FW-04) es entrar a cada instancia: bash P3_eice.sh <zp-nombre> true"
}

if [[ "$MODO" == "--validar" ]]; then
  for P in "${LISTA[@]}"; do validar_paso "$P"; done
  validar_global
  [[ $ERRORES -eq 0 ]] && echo "RESULTADO: todo correcto." || echo "RESULTADO: $ERRORES fallo(s)."
  exit $ERRORES
fi

# ---------- aplicar ----------
aplicar_sg() {  # paso
  local L P DEST ORI PROTO F T ID DESC PLAN=() PERM
  for L in "${REGLAS[@]}"; do
    IFS='|' read -r P DEST ORI PROTO F T ID DESC <<< "$L"
    [[ "$P" == "$1" ]] || continue
    if [[ "$(contar "$DEST" "$ORI" "$PROTO" "$F" "$T")" -ge 1 ]]; then ok "$ID ya existe (no se toca): $DEST <- $ORI $PROTO $F-$T"
    else PLAN+=("$L"); fi
  done
  if [[ ${#PLAN[@]} -eq 0 ]]; then ok "Todas las reglas de Security Group del paso $1 ya existen"; return; fi
  echo "Se van a AGREGAR ${#PLAN[@]} regla(s) de entrada:"
  for L in "${PLAN[@]}"; do IFS='|' read -r P DEST ORI PROTO F T ID DESC <<< "$L"; echo "  $ID  $DEST <- $ORI  $PROTO $F-$T  ($DESC)"; done
  confirmar
  guardar_estado "antes-$1"
  for L in "${PLAN[@]}"; do
    IFS='|' read -r P DEST ORI PROTO F T ID DESC <<< "$L"
    if [[ "$ORI" == */* ]]; then PERM="IpProtocol=$PROTO,FromPort=$F,ToPort=$T,IpRanges=[{CidrIp=$ORI,Description=$DESC}]"
    else PERM="IpProtocol=$PROTO,FromPort=$F,ToPort=$T,UserIdGroupPairs=[{GroupId=${SG[$ORI]},Description=$DESC}]"; fi
    aws ec2 authorize-security-group-ingress --group-id "${SG[$DEST]}" --ip-permissions "$PERM" >/dev/null \
      && ok "$ID agregada: $DEST <- $ORI $PROTO $F-$T" || falla "$ID no se pudo agregar: $DEST <- $ORI $PROTO $F-$T"
  done
}
aplicar_entradas() {  # acl nombre arreglo...
  local ACL="$1" N="$2" L DIR NUM PR F T CIDR ACC; shift 2
  for L in "$@"; do
    IFS='|' read -r DIR NUM PR F T CIDR ACC <<< "$L"
    if [[ "$(existe_entrada "$ACL" "$DIR" "$NUM" "$PR" "$F" "$T" "$CIDR" "$ACC")" -ge 1 ]]; then ok "$N ya existe $DIR $NUM"
    elif crear_entrada "$ACL" "$DIR" "$NUM" "$PR" "$F" "$T" "$CIDR" "$ACC"; then ok "$N agregada $DIR $NUM $PR $F-$T $CIDR $ACC"
    else falla "$N no se pudo agregar $DIR $NUM"; fi
  done
}
aplicar_acl() {  # dmz|vpn  (mismo procedimiento que P5_acls.sh aplicar)
  local N="$1" SUB ACL ACTUAL ASOC REG R
  R=$(reglas_acl "$N"); REG=("${!R}")
  SUB=$(subnet_id "$N"); [[ -n "$SUB" && "$SUB" != "None" ]] || { falla "No existe subnet-zenite-$N"; exit 1; }
  ACL=$(acl_id "$N"); ACTUAL=$(acl_de_subred "$SUB")
  echo "Plan para acl-zenite-$N -> subnet-zenite-$N ($SUB):"
  [[ -z "$ACL" ]] && echo "  - crear acl-zenite-$N" || echo "  - ya existe acl-zenite-$N ($ACL); solo se agregan las reglas que falten"
  echo "  - ${#REG[@]} reglas (entrada y salida, con retorno; TCP/22 desde $EICE antes de cualquier denegacion; deniega $VPC salvo lo anterior)"
  echo "  - asociarla a la subred (hoy usa $ACTUAL) SOLO cuando esten todas las reglas"
  echo "Rollback listo: bash P3_firewall_final.sh --revertir acl-$N"
  confirmar
  guardar_estado "antes-acl-$N"
  if [[ -z "$ACL" ]]; then
    ACL=$(aws ec2 create-network-acl --vpc-id "$VPC_ID" --query "NetworkAcl.NetworkAclId" --output text \
      --tag-specifications "ResourceType=network-acl,Tags=[{Key=Name,Value=acl-zenite-$N},{Key=Project,Value=ZenitePrestige},{Key=Phase,Value=Final},{Key=Environment,Value=Prototype},{Key=Owner,Value=Grupo30}]")
    ok "ACL creada: acl-zenite-$N = $ACL (todavia sin asociar)"
  fi
  aplicar_entradas "$ACL" "$N" "${REG[@]}"
  if [[ $ERRORES -ne 0 ]]; then echo "Hubo fallos al crear reglas: NO se asocia la ACL. Revisar y repetir (es idempotente)."; exit 1; fi
  if [[ "$ACTUAL" != "$ACL" ]]; then
    ASOC=$(asoc_de_subred "$SUB")
    aws ec2 replace-network-acl-association --association-id "$ASOC" --network-acl-id "$ACL" >/dev/null \
      && ok "subnet-zenite-$N asociada a $ACL" || { falla "no se pudo asociar"; exit 1; }
  fi
}

if [[ "$MODO" == "aplicar" ]]; then
  case "$PASO" in
    base|vpn) aplicar_sg "$PASO" ;;
    monitoreo)
      aplicar_sg monitoreo
      V=$(acl_id visitantes)
      if [[ -z "$V" ]]; then falla "no existe acl-zenite-visitantes (Fase 3)"
      else
        echo "Se van a agregar a acl-zenite-visitantes ($V): entrada 130 UDP 161 desde $TI y salida 130 UDP 1024-65535 hacia $TI"
        confirmar
        aplicar_entradas "$V" visitantes "${ACL_VIS_SNMP[@]}"
      fi
      ;;
    acl-dmz) aplicar_acl dmz ;;
    acl-vpn) aplicar_acl vpn ;;
  esac
  guardar_estado "despues-$PASO"
  validar_paso "$PASO"; validar_global
  if [[ $ERRORES -eq 0 ]]; then
    echo "RESULTADO: todo correcto."
    [[ "$PASO" == "acl-dmz" ]] && echo "AHORA comprueba el EICE: bash P3_eice.sh zp-web-01 true   Si falla: bash P3_firewall_final.sh --revertir acl-dmz"
    [[ "$PASO" == "acl-vpn" ]] && echo "AHORA comprueba el EICE: bash P3_eice.sh zp-vpn-01 true   Si falla: bash P3_firewall_final.sh --revertir acl-vpn"
  else echo "RESULTADO: $ERRORES fallo(s); revisar antes de continuar."; fi
  exit $ERRORES
fi

# ---------- revertir ----------
revertir_sg() {  # paso
  local L P DEST ORI PROTO F T ID DESC RID R PUBLICAS=0
  if [[ "$1" == "base" ]]; then
    read -r -p "Quitar tambien TCP 80 y 443 de zenite-dmz? El portal y la renovacion del certificado DEJAN de funcionar. Escribe si: " R
    [[ "${R,,}" == "si" ]] && PUBLICAS=1
  fi
  for L in "${REGLAS[@]}"; do
    IFS='|' read -r P DEST ORI PROTO F T ID DESC <<< "$L"
    [[ "$P" == "$1" ]] || continue
    if [[ "$DEST" == "zenite-dmz" && "$ORI" == "0.0.0.0/0" && $PUBLICAS -eq 0 ]]; then ok "$ID se conserva: $DEST <- $ORI $PROTO $F-$T"; continue; fi
    RID=$(ids_regla "$DEST" "$ORI" "$PROTO" "$F" "$T")
    if [[ -z "$RID" || "$RID" == "None" ]]; then ok "$ID ya no existe: $DEST <- $ORI $PROTO $F-$T"; continue; fi
    aws ec2 revoke-security-group-ingress --group-id "${SG[$DEST]}" --security-group-rule-ids $RID >/dev/null \
      && ok "$ID quitada ($RID)" || falla "$ID no se pudo quitar ($RID)"
  done
}
revertir_acl() {  # dmz|vpn
  local N="$1" SUB ACL ASOC
  SUB=$(subnet_id "$N"); ACL=$(acl_id "$N")
  if [[ -n "$SUB" && "$SUB" != "None" && "$(acl_de_subred "$SUB")" != "$DEFAULT_ACL" ]]; then
    ASOC=$(asoc_de_subred "$SUB")
    aws ec2 replace-network-acl-association --association-id "$ASOC" --network-acl-id "$DEFAULT_ACL" >/dev/null \
      && ok "subnet-zenite-$N de vuelta en la ACL predeterminada" || falla "no se pudo reasociar subnet-zenite-$N"
  else ok "subnet-zenite-$N ya esta en la ACL predeterminada"; fi
  if [[ -n "$ACL" ]]; then
    aws ec2 delete-network-acl --network-acl-id "$ACL" >/dev/null && ok "acl-zenite-$N ($ACL) eliminada" || falla "no se pudo eliminar $ACL"
  else ok "acl-zenite-$N ya no existe"; fi
}

if [[ "$MODO" == "--revertir" ]]; then
  case "$PASO" in
    base)      echo "Se van a QUITAR F-03 a F-05 (UDP 1194 y SSH desde TI); 80 y 443 solo si lo confirmas aparte. Las reglas de P1 no se tocan." ;;
    vpn)       echo "Se va a QUITAR F-06: la VPN deja de llegar a la Intranet." ;;
    monitoreo) echo "Se van a QUITAR F-07 y F-08 (SNMP e ICMP desde TI) y las entradas 130 de acl-zenite-visitantes." ;;
    acl-*)     echo "Se va a devolver subnet-zenite-${PASO#acl-} a la ACL predeterminada y BORRAR acl-zenite-${PASO#acl-}." ;;
  esac
  confirmar
  guardar_estado "antes-revertir-$PASO"
  case "$PASO" in
    base|vpn) revertir_sg "$PASO" ;;
    monitoreo)
      revertir_sg monitoreo
      V=$(acl_id visitantes)
      if [[ -n "$V" ]]; then
        for L in "${ACL_VIS_SNMP[@]}"; do
          IFS='|' read -r DIR NUM PR F T CIDR ACC <<< "$L"
          if [[ "$(existe_entrada "$V" "$DIR" "$NUM" "$PR" "$F" "$T" "$CIDR" "$ACC")" -ge 1 ]]; then
            [[ "$DIR" == "in" ]] && E=--ingress || E=--egress
            aws ec2 delete-network-acl-entry --network-acl-id "$V" --rule-number "$NUM" $E && ok "visitantes $DIR $NUM quitada" || falla "visitantes $DIR $NUM no se pudo quitar"
          else ok "visitantes $DIR $NUM ya no existe"; fi
        done
      fi
      ;;
    acl-dmz) revertir_acl dmz ;;
    acl-vpn) revertir_acl vpn ;;
  esac
  [[ $ERRORES -eq 0 ]] && echo "Reversion completa." || echo "Reversion con $ERRORES fallo(s)."
  exit $ERRORES
fi
