#!/usr/bin/env bash
# P1_gateways.sh – Internet Gateway, Elastic IP, NAT Gateway y rutas de Fase 3 (Persona 1).
# Ejecutar en AWS CloudShell (us-east-1). No guarda ni pide credenciales.
#
#   bash P1_gateways.sh crear              crea (o reutiliza) IGW, Elastic IP, NAT Gateway y las rutas; valida
#   bash P1_gateways.sh destruir           quita la ruta del NAT, elimina el NAT Gateway y libera la Elastic IP
#                                          (el Internet Gateway y su ruta en rt-zenite-infra se conservan: no cobran)
#   bash P1_gateways.sh --validar          solo lee: comprueba que todo esté ENCENDIDO
#   bash P1_gateways.sh --validar-apagado  solo lee: comprueba que no quede nada con costo (NAT y Elastic IP)
#   NAT_IP=10.20.0.149 bash P1_gateways.sh crear   usa otra IP privada para el NAT (por defecto 10.20.0.148)
#   SI=1 bash P1_gateways.sh crear         omite la pregunta de confirmación
#
# El NAT Gateway cobra por hora (≈ US$0.045/h + ≈ US$0.005/h de su IPv4 pública ≈ US$1.20 por día): se crea al empezar
# la sesión de trabajo y se destruye al terminar. Es idempotente y se detiene sin cambiar nada ante un conflicto.
# Salida en ~/fase3-config/: gateways-validacion.txt, gateways-sesiones.log y los JSON (internet-gateways, nat-gateways,
# addresses, route-tables).
set -euo pipefail

ENV_FILE="$(cd "$(dirname "$0")" && pwd)/../../.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

REGION="us-east-1"
VPC_NAME="vpc-zenite-fase2"
SUBNET_NAT="subnet-zenite-infra"
RT_INFRA="rt-zenite-infra"
RT_INTERNA="rt-zenite-interna"
RT_DMZ="rt-zenite-dmz"
IGW_NAME="igw-zenite-fase3"
EIP_NAME="eip-nat-zenite-fase3"
NAT_NAME="nat-zenite-fase3"
NAT_IP="${NAT_IP:-10.20.0.148}"
OUT_DIR="$HOME/fase3-config"
MODO="${1:-}"

uso() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}
case "$MODO" in crear|destruir|--validar|--validar-apagado) ;; *) uso ;; esac

awsr() { aws --region "$REGION" --output json "$@"; }
mkdir -p "$OUT_DIR"

tagspec() {  # tipo de recurso, nombre -> valor para --tag-specifications
  echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},{Key=Project,Value=ZenitePrestige},{Key=Phase,Value=Fase3},{Key=Environment,Value=Prototype},{Key=Owner,Value=Grupo30}]"
}
registrar() { echo "$(date '+%Y-%m-%d %H:%M:%S %Z') · $*" >> "$OUT_DIR/gateways-sesiones.log"; }
ip2int() { local IFS=.; set -- $1; echo $(( ($1 << 24) + ($2 << 16) + ($3 << 8) + $4 )); }

# ---------- Búsquedas (todas por nombre, nunca por ID copiado a mano) ----------
IDS=$(awsr ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" | jq -r '.Vpcs[].VpcId')
read -ra ARR <<<"$IDS"
if (( ${#ARR[@]} != 1 )); then
  echo "ERROR: se esperaba 1 VPC llamada $VPC_NAME y hay ${#ARR[@]}." >&2; exit 1
fi
VPC_ID="${ARR[0]}"

subnet_json() { awsr ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$1" | jq -c '.Subnets[0] // empty'; }
rt_id() { awsr ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$1" | jq -r '.RouteTables[0].RouteTableId // empty'; }
igw_nombre() { awsr ec2 describe-internet-gateways --filters "Name=tag:Name,Values=$IGW_NAME" | jq -r '.InternetGateways[0].InternetGatewayId // empty'; }
igw_adjuntos() {  # IGW adjuntos a la VPC: "id|nombre" por línea
  awsr ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    | jq -r '.InternetGateways[] | "\(.InternetGatewayId)|\((.Tags // []) | map(select(.Key=="Name").Value) | first // "-")"'
}
eip_json() { awsr ec2 describe-addresses --filters "Name=tag:Name,Values=$EIP_NAME" | jq -c '.Addresses[0] // empty'; }
nat_json() {  # NAT Gateway del proyecto en estado vivo (pending, available o deleting)
  awsr ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$NAT_NAME" \
    "Name=state,Values=pending,available,deleting" | jq -c '.NatGateways[0] // empty'
}
ruta_default() {  # route table id -> "destino estado" de 0.0.0.0/0 (vacío si no existe)
  awsr ec2 describe-route-tables --route-table-ids "$1" \
    | jq -r '.RouteTables[0].Routes[] | select(.DestinationCidrBlock=="0.0.0.0/0") | "\(.GatewayId // .NatGatewayId // "otro") \(.State)"'
}

esperar_nat() {  # id, estado esperado, límite en segundos
  local id="$1" want="$2" lim="${3:-600}" t=0 st
  while (( t < lim )); do
    st=$(awsr ec2 describe-nat-gateways --nat-gateway-ids "$id" | jq -r '.NatGateways[0].State')
    if [[ "$st" == "$want" ]]; then echo; return 0; fi
    if [[ "$st" == "failed" ]]; then
      echo; echo "ERROR: el NAT Gateway $id quedó en 'failed': $(awsr ec2 describe-nat-gateways --nat-gateway-ids "$id" | jq -r '.NatGateways[0].FailureMessage // "sin detalle"')" >&2
      return 1
    fi
    sleep 10; t=$((t + 10)); printf '.'
  done
  echo; echo "ERROR: el NAT Gateway $id no llegó a '$want' en ${lim}s (estado: $st)." >&2
  return 1
}

confirmar() {
  [[ "${SI:-}" == "1" ]] && return 0
  local r; read -r -p "Escribe 'si' para continuar: " r
  [[ "$r" == "si" ]] || { echo "Cancelado. No se modificó nada."; exit 1; }
}

# ---------- Comprobaciones previas de crear (solo lectura) ----------
preflight_crear() {
  local err=0 sn cidr base pre size off n eni nat adj igw_id rtI rtN rtD d
  sn=$(subnet_json "$SUBNET_NAT")
  [[ -n "$sn" ]] || { echo "ERROR: no existe la subred $SUBNET_NAT." >&2; return 1; }
  cidr=$(jq -r '.CidrBlock' <<<"$sn")
  base=${cidr%/*}; pre=${cidr#*/}; size=$(( 1 << (32 - pre) ))
  n=$(ip2int "$NAT_IP"); off=$(( n - $(ip2int "$base") ))
  if (( off < 4 || off >= size - 1 )); then
    echo "ERROR: $NAT_IP no es asignable en $cidr (AWS reserva las 4 primeras y la última)." >&2; err=1
  fi
  nat=$(nat_json)
  eni=$(awsr ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$VPC_ID" "Name=addresses.private-ip-address,Values=$NAT_IP" \
        | jq -r '.NetworkInterfaces[0].NetworkInterfaceId // empty')
  if [[ -n "$eni" ]]; then
    if [[ -z "$nat" ]] || [[ "$(jq -r '.NatGatewayAddresses[0].NetworkInterfaceId' <<<"$nat")" != "$eni" ]]; then
      echo "ERROR: la IP $NAT_IP ya la usa la interfaz $eni (no es nuestro NAT). Elige otra con NAT_IP=..." >&2; err=1
    fi
  fi

  igw_id=$(igw_nombre)
  adj=$(igw_adjuntos)
  while IFS='|' read -r i nm; do
    [[ -z "$i" ]] && continue
    if [[ "$nm" != "$IGW_NAME" ]]; then
      echo "ERROR: la VPC ya tiene adjunto otro Internet Gateway ($i, nombre '$nm'). Una VPC admite solo uno; revísalo en la consola." >&2; err=1
    fi
  done <<<"$adj"
  if [[ -n "$igw_id" ]]; then
    d=$(awsr ec2 describe-internet-gateways --internet-gateway-ids "$igw_id" | jq -r '.InternetGateways[0].Attachments[0].VpcId // empty')
    if [[ -n "$d" && "$d" != "$VPC_ID" ]]; then
      echo "ERROR: $IGW_NAME ($igw_id) está adjunto a otra VPC ($d)." >&2; err=1
    fi
  fi

  rtI=$(rt_id "$RT_INFRA"); rtN=$(rt_id "$RT_INTERNA"); rtD=$(rt_id "$RT_DMZ")
  for d in "$RT_INFRA:$rtI" "$RT_INTERNA:$rtN" "$RT_DMZ:$rtD"; do
    [[ -n "${d#*:}" ]] || { echo "ERROR: no existe la route table ${d%%:*}." >&2; err=1; }
  done
  if [[ -n "$rtI" ]]; then
    d=$(ruta_default "$rtI")
    if [[ -n "$d" && "${d%% *}" != "$igw_id" ]]; then
      echo "ERROR: $RT_INFRA ya tiene una ruta 0.0.0.0/0 distinta de nuestro IGW ($d). No se modifica." >&2; err=1
    fi
  fi
  if [[ -n "$rtN" ]]; then
    d=$(ruta_default "$rtN")
    if [[ -n "$d" ]] && { [[ -z "$nat" ]] || [[ "${d%% *}" != "$(jq -r '.NatGatewayId' <<<"$nat")" ]]; }; then
      echo "ERROR: $RT_INTERNA ya tiene una ruta 0.0.0.0/0 distinta de nuestro NAT ($d). No se modifica." >&2; err=1
    fi
  fi
  if [[ -n "$rtD" && -n "$(ruta_default "$rtD")" ]]; then
    echo "AVISO: $RT_DMZ tiene ruta por defecto; el plan es dejarla solo local." >&2
  fi
  return "$err"
}

# ---------- crear ----------
crear() {
  local igw_id eip nat alloc nat_id sn_id rtI rtN d
  sn_id=$(subnet_json "$SUBNET_NAT" | jq -r '.SubnetId')
  rtI=$(rt_id "$RT_INFRA"); rtN=$(rt_id "$RT_INTERNA")

  # 1. Internet Gateway
  igw_id=$(igw_nombre)
  if [[ -z "$igw_id" ]]; then
    echo "Creando Internet Gateway $IGW_NAME ..."
    igw_id=$(awsr ec2 create-internet-gateway --tag-specifications "$(tagspec internet-gateway "$IGW_NAME")" \
             | jq -r '.InternetGateway.InternetGatewayId')
    registrar "IGW creado $igw_id"
  else
    echo "Ya existe $IGW_NAME ($igw_id); se reutiliza."
  fi
  d=$(awsr ec2 describe-internet-gateways --internet-gateway-ids "$igw_id" | jq -r '.InternetGateways[0].Attachments[0].VpcId // empty')
  if [[ -z "$d" ]]; then
    echo "Adjuntando $igw_id a $VPC_NAME ..."
    awsr ec2 attach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$VPC_ID" >/dev/null
  fi

  # 2. NAT Gateway previo en 'deleting': esperar a que termine antes de crear otro
  nat=$(nat_json)
  if [[ -n "$nat" && "$(jq -r '.State' <<<"$nat")" == "deleting" ]]; then
    echo "Hay un NAT Gateway en eliminación; se espera a que termine ..."
    esperar_nat "$(jq -r '.NatGatewayId' <<<"$nat")" deleted 900
    nat=""
  fi

  # 3. Elastic IP
  eip=$(eip_json)
  if [[ -z "$eip" ]]; then
    echo "Reservando Elastic IP $EIP_NAME ..."
    eip=$(awsr ec2 allocate-address --domain vpc --tag-specifications "$(tagspec elastic-ip "$EIP_NAME")" | jq -c '.')
    registrar "Elastic IP reservada $(jq -r '.AllocationId' <<<"$eip")"
  else
    echo "Ya existe la Elastic IP $EIP_NAME ($(jq -r '.AllocationId' <<<"$eip")); se reutiliza."
  fi
  alloc=$(jq -r '.AllocationId' <<<"$eip")

  # 4. NAT Gateway
  if [[ -z "$nat" ]]; then
    echo "Creando NAT Gateway $NAT_NAME en $SUBNET_NAT con IP privada $NAT_IP ..."
    nat_id=$(awsr ec2 create-nat-gateway --subnet-id "$sn_id" --allocation-id "$alloc" --private-ip-address "$NAT_IP" \
             --tag-specifications "$(tagspec natgateway "$NAT_NAME")" | jq -r '.NatGateway.NatGatewayId')
    registrar "NAT creado $nat_id (inicio del cobro por hora)"
  else
    nat_id=$(jq -r '.NatGatewayId' <<<"$nat")
    echo "Ya existe $NAT_NAME ($nat_id, $(jq -r '.State' <<<"$nat")); se reutiliza."
  fi
  printf 'Esperando que el NAT Gateway esté disponible (suele tardar 1 a 3 minutos) '
  esperar_nat "$nat_id" available 900 || exit 1

  # 5. Rutas
  d=$(ruta_default "$rtI")
  if [[ -z "$d" ]]; then
    echo "Ruta 0.0.0.0/0 -> $igw_id en $RT_INFRA ..."
    awsr ec2 create-route --route-table-id "$rtI" --destination-cidr-block 0.0.0.0/0 --gateway-id "$igw_id" >/dev/null
  else
    echo "$RT_INFRA ya tiene 0.0.0.0/0 -> ${d%% *}."
  fi
  d=$(ruta_default "$rtN")
  if [[ -z "$d" ]]; then
    echo "Ruta 0.0.0.0/0 -> $nat_id en $RT_INTERNA ..."
    awsr ec2 create-route --route-table-id "$rtN" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$nat_id" >/dev/null
  else
    echo "$RT_INTERNA ya tiene 0.0.0.0/0 -> ${d%% *}."
  fi
  echo "RECORDATORIO: el NAT Gateway cobra por hora mientras exista. Al terminar la sesión: bash P1_gateways.sh destruir"
}

# ---------- destruir ----------
destruir() {
  local nat nat_id eip alloc rtN d i
  rtN=$(rt_id "$RT_INTERNA")
  nat=$(nat_json)

  if [[ -n "$rtN" ]]; then
    d=$(ruta_default "$rtN")
    if [[ -n "$d" ]]; then
      if [[ -n "$nat" && "${d%% *}" == "$(jq -r '.NatGatewayId' <<<"$nat")" ]] || [[ "${d%% *}" == nat-* ]]; then
        echo "Quitando la ruta 0.0.0.0/0 de $RT_INTERNA ..."
        awsr ec2 delete-route --route-table-id "$rtN" --destination-cidr-block 0.0.0.0/0 >/dev/null
      else
        echo "AVISO: $RT_INTERNA tiene 0.0.0.0/0 -> ${d%% *}, que no es un NAT; no se toca." >&2
      fi
    fi
  fi

  if [[ -n "$nat" ]]; then
    nat_id=$(jq -r '.NatGatewayId' <<<"$nat")
    if [[ "$(jq -r '.State' <<<"$nat")" != "deleting" ]]; then
      echo "Eliminando el NAT Gateway $nat_id ..."
      awsr ec2 delete-nat-gateway --nat-gateway-id "$nat_id" >/dev/null
    fi
    printf 'Esperando a que el NAT Gateway quede eliminado '
    esperar_nat "$nat_id" deleted 900 || exit 1
    registrar "NAT eliminado $nat_id (fin del cobro por hora)"
  else
    echo "No hay NAT Gateway vivo."
  fi

  eip=$(eip_json)
  if [[ -n "$eip" ]]; then
    alloc=$(jq -r '.AllocationId' <<<"$eip")
    echo "Liberando la Elastic IP $alloc ..."
    for i in 1 2 3 4 5 6; do
      if awsr ec2 release-address --allocation-id "$alloc" >/dev/null 2>"$OUT_DIR/.release.err"; then
        registrar "Elastic IP liberada $alloc"; rm -f "$OUT_DIR/.release.err"; break
      fi
      (( i == 6 )) && { echo "ERROR: no se pudo liberar $alloc: $(cat "$OUT_DIR/.release.err")" >&2; exit 1; }
      sleep 5
    done
  else
    echo "No hay Elastic IP del proyecto."
  fi
  echo "Listo. El Internet Gateway se conserva (no cobra)."
}

# ---------- validar ----------
validar() {  # encendido | apagado
  local modo="$1" fallas=0 igw_id rtI rtN rtD nat eip d n
  check() {  # descripción, esperado, real
    if [[ "$2" == "$3" ]]; then printf "  [OK]    %-46s %s\n" "$1" "$3"
    else printf "  [FALLA] %-46s esperado=%s real=%s\n" "$1" "$2" "$3"; fallas=1; fi
  }
  rtI=$(rt_id "$RT_INFRA"); rtN=$(rt_id "$RT_INTERNA"); rtD=$(rt_id "$RT_DMZ")
  igw_id=$(igw_nombre)
  nat=$(nat_json); eip=$(eip_json)

  awsr ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" > "$OUT_DIR/internet-gateways.json"
  awsr ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" > "$OUT_DIR/nat-gateways.json"
  awsr ec2 describe-addresses > "$OUT_DIR/addresses.json"
  awsr ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" > "$OUT_DIR/route-tables.json"

  echo "Validación de gateways ($modo) · $VPC_NAME · $VPC_ID · $(date '+%Y-%m-%d %H:%M:%S %Z')"
  check "Internet Gateway $IGW_NAME adjunto a la VPC" "sí" "$([[ -n "$igw_id" ]] && grep -q "^$igw_id|" <<<"$(igw_adjuntos)" && echo sí || echo no)"
  d=$(ruta_default "$rtI")
  check "$RT_INFRA: 0.0.0.0/0 -> IGW (activa)" "$igw_id active" "${d:-ninguna}"
  d=$(ruta_default "$rtD")
  check "$RT_DMZ sin ruta por defecto (solo local)" "ninguna" "${d:-ninguna}"

  if [[ "$modo" == "encendido" ]]; then
    check "NAT Gateway $NAT_NAME disponible" "available" "$([[ -n "$nat" ]] && jq -r '.State' <<<"$nat" || echo "no existe")"
    if [[ -n "$nat" ]]; then
      check "NAT en $SUBNET_NAT" "$(subnet_json "$SUBNET_NAT" | jq -r '.SubnetId')" "$(jq -r '.SubnetId' <<<"$nat")"
      check "IP privada del NAT" "$NAT_IP" "$(jq -r '.NatGatewayAddresses[0].PrivateIp' <<<"$nat")"
      check "IPv4 pública (Elastic IP) asociada" "sí" "$([[ -n "$(jq -r '.NatGatewayAddresses[0].PublicIp // empty' <<<"$nat")" ]] && echo sí || echo no)"
      d=$(ruta_default "$rtN")
      check "$RT_INTERNA: 0.0.0.0/0 -> NAT (activa)" "$(jq -r '.NatGatewayId' <<<"$nat") active" "${d:-ninguna}"
    fi
  else
    check "NAT Gateway vivo (pending/available/deleting)" "0" "$([[ -n "$nat" ]] && echo 1 || echo 0)"
    d=$(ruta_default "$rtN")
    check "$RT_INTERNA sin ruta por defecto" "ninguna" "${d:-ninguna}"
    check "Elastic IP del proyecto" "liberada" "$([[ -n "$eip" ]] && echo "sigue reservada" || echo liberada)"
    n=$(jq '.Addresses | length' "$OUT_DIR/addresses.json")
    check "Elastic IP en la cuenta/región" "0" "$n"
  fi

  if (( fallas == 0 )); then echo "RESULTADO: todo correcto."; else echo "RESULTADO: hay fallas; revísalas antes de continuar."; fi
  return "$fallas"
}

case "$MODO" in
  crear)
    echo "Plan: Internet Gateway $IGW_NAME (se queda), Elastic IP $EIP_NAME, NAT Gateway $NAT_NAME en $SUBNET_NAT ($NAT_IP),"
    echo "      ruta 0.0.0.0/0 -> IGW en $RT_INFRA y 0.0.0.0/0 -> NAT en $RT_INTERNA. Región $REGION, VPC $VPC_ID."
    echo "      Costo: ≈ US\$0.05 por hora (≈ US\$1.20 por día) mientras exista el NAT Gateway."
    preflight_crear || { echo "No se modificó nada." >&2; exit 1; }
    confirmar
    crear
    echo
    set +e; validar encendido | tee "$OUT_DIR/gateways-validacion.txt"; RC=${PIPESTATUS[0]}; set -e
    ;;
  destruir)
    echo "Plan: quitar 0.0.0.0/0 de $RT_INTERNA, eliminar el NAT Gateway $NAT_NAME y liberar la Elastic IP $EIP_NAME."
    echo "      El Internet Gateway y su ruta en $RT_INFRA se conservan."
    confirmar
    destruir
    echo
    set +e; validar apagado | tee "$OUT_DIR/gateways-validacion.txt"; RC=${PIPESTATUS[0]}; set -e
    ;;
  --validar)
    set +e; validar encendido | tee "$OUT_DIR/gateways-validacion.txt"; RC=${PIPESTATUS[0]}; set -e
    ;;
  --validar-apagado)
    set +e; validar apagado | tee "$OUT_DIR/gateways-validacion.txt"; RC=${PIPESTATUS[0]}; set -e
    ;;
esac
echo
echo "Archivos en $OUT_DIR: gateways-validacion.txt, gateways-sesiones.log, internet-gateways.json, nat-gateways.json, addresses.json, route-tables.json."
exit "${RC:-0}"
