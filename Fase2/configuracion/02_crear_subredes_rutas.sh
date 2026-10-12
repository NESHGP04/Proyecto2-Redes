#!/usr/bin/env bash
# 02_crear_subredes_rutas.sh – Crea y valida las 7 subredes VLSM y las 3 route tables en vpc-zenite-fase2 (MD_2).
# Ejecutar en AWS CloudShell (us-east-1). No guarda ni pide credenciales.
#
#   bash 02_crear_subredes_rutas.sh                 crea (o reutiliza) subredes y route tables y valida
#   bash 02_crear_subredes_rutas.sh --validar       solo valida; no modifica nada
#   AZ=us-east-1b bash 02_crear_subredes_rutas.sh   usa otra AZ (por defecto us-east-1a)
#
# Es idempotente: reutiliza las subredes y tablas que ya existan con el nombre y CIDR correctos.
# Se detiene sin modificar nada si encuentra un conflicto (CIDR ajeno al plan, subred en otra AZ, uso de las reservas).
# No crea Internet Gateway, NAT Gateway, Elastic IP ni instancias.
# Salida en ~/fase2-config/: subnets.json, route-tables.json, subredes-validacion.txt y segmentacion.md
set -euo pipefail

ENV_FILE="$(cd "$(dirname "$0")" && pwd)/../../.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

REGION="us-east-1"
VPC_NAME="vpc-zenite-fase2"
VPC_CIDR="10.20.0.0/24"
AZ="${AZ:-us-east-1a}"
OUT_DIR="$HOME/fase2-config"
MODO="crear"
[[ "${1:-}" == "--validar" ]] && MODO="validar"

# nombre | CIDR | route table | uso
PLAN=(
  "subnet-zenite-ventas|10.20.0.0/27|rt-zenite-interna|Prueba de usuarios de Ventas"
  "subnet-zenite-visitantes|10.20.0.32/27|rt-zenite-interna|Segmento de invitados"
  "subnet-zenite-servidores|10.20.0.64/27|rt-zenite-interna|Servicios internos"
  "subnet-zenite-ti|10.20.0.96/28|rt-zenite-interna|Administración"
  "subnet-zenite-dmz|10.20.0.112/28|rt-zenite-dmz|Servicios publicados"
  "subnet-zenite-vpn|10.20.0.128/28|rt-zenite-interna|Segmento lógico de VPN"
  "subnet-zenite-infra|10.20.0.144/28|rt-zenite-infra|Gestión e infraestructura"
)
RTS=(rt-zenite-interna rt-zenite-dmz rt-zenite-infra)
RESERVAS=(10.20.0.160/27 10.20.0.192/26)
TAGS="{Key=Project,Value=ZenitePrestige},{Key=Phase,Value=Fase2},{Key=Environment,Value=Prototype},{Key=Owner,Value=Grupo30}"

awsr() { aws --region "$REGION" "$@"; }
mkdir -p "$OUT_DIR"

ip2int() { local a b c d; IFS=. read -r a b c d <<<"$1"; echo $(( (a<<24) + (b<<16) + (c<<8) + d )); }
rango() {  # CIDR -> "inicio fin" en enteros
  local ip=${1%/*} len=${1#*/} n
  n=$(ip2int "$ip")
  echo "$n" $(( n + (1 << (32 - len)) - 1 ))
}
solapan() {  # CIDR_A CIDR_B -> 0 si se solapan
  local a1 a2 b1 b2
  read -r a1 a2 <<<"$(rango "$1")"
  read -r b1 b2 <<<"$(rango "$2")"
  (( a1 <= b2 && b1 <= a2 ))
}
int2ip() { echo "$(( ($1>>24)&255 )).$(( ($1>>16)&255 )).$(( ($1>>8)&255 )).$(( $1&255 ))"; }

IDS=$(awsr ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME" --query "Vpcs[].VpcId" --output text)
read -ra ARR <<<"$IDS"
if (( ${#ARR[@]} != 1 )); then
  echo "ERROR: se esperaba 1 VPC llamada $VPC_NAME y hay ${#ARR[@]}. Ejecuta primero 01_crear_vpc.sh." >&2
  exit 1
fi
VPC_ID="${ARR[0]}"
echo "VPC: $VPC_NAME · $VPC_ID · AZ del prototipo: $AZ"

subnet_id() {  # CIDR -> SubnetId (vacío si no existe)
  awsr ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=cidr-block,Values=$1" \
    --query "Subnets[0].SubnetId" --output text | sed 's/^None$//'
}
rt_id() {  # nombre -> RouteTableId (vacío si no existe)
  awsr ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$1" \
    --query "RouteTables[0].RouteTableId" --output text | sed 's/^None$//'
}

# ---------- Comprobaciones previas (no modifican nada) ----------
preflight() {
  local err=0 cidr name plan_cidrs=() e
  for e in "${PLAN[@]}"; do IFS='|' read -r _ cidr _ _ <<<"$e"; plan_cidrs+=("$cidr"); done

  while read -r sid cidr az name; do
    [[ -z "${sid:-}" ]] && continue
    if [[ ! " ${plan_cidrs[*]} " =~ " $cidr " ]]; then
      echo "ERROR: $sid ($name, $cidr) no pertenece al plan de Fase 2. Revísala en la consola." >&2; err=1
    elif [[ "$az" != "$AZ" ]]; then
      echo "ERROR: $sid ($name, $cidr) está en $az y el prototipo usa $AZ. Usa AZ=$az o elimínala." >&2; err=1
    fi
  done < <(awsr ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
            --query "Subnets[].[SubnetId,CidrBlock,AvailabilityZone,Tags[?Key=='Name']|[0].Value]" --output text)

  local n_az
  n_az=$(awsr ec2 describe-availability-zones --zone-names "$AZ" --query "length(AvailabilityZones)" --output text 2>/dev/null || echo 0)
  [[ "$n_az" == "1" ]] || { echo "ERROR: la AZ $AZ no existe en $REGION." >&2; err=1; }

  local rt n
  for rt in "${RTS[@]}"; do
    n=$(awsr ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=$rt" \
      --query "length(RouteTables)" --output text)
    (( n > 1 )) && { echo "ERROR: hay $n route tables llamadas $rt. Elimina las duplicadas." >&2; err=1; }
  done
  return "$err"
}

# ---------- Creación ----------
crear() {
  local e name cidr rt uso sid rid aid actual
  for e in "${PLAN[@]}"; do
    IFS='|' read -r name cidr rt uso <<<"$e"
    sid=$(subnet_id "$cidr")
    if [[ -z "$sid" ]]; then
      echo "Creando $name ($cidr) en $AZ ..."
      sid=$(awsr ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block "$cidr" --availability-zone "$AZ" \
        --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name},$TAGS]" \
        --query "Subnet.SubnetId" --output text)
      awsr ec2 wait subnet-available --subnet-ids "$sid"
    else
      echo "Ya existe $sid con $cidr; se reutiliza."
      awsr ec2 create-tags --resources "$sid" --tags "Key=Name,Value=$name" \
        Key=Project,Value=ZenitePrestige Key=Phase,Value=Fase2 Key=Environment,Value=Prototype Key=Owner,Value=Grupo30
    fi
    awsr ec2 modify-subnet-attribute --subnet-id "$sid" --no-map-public-ip-on-launch
  done

  for rt in "${RTS[@]}"; do
    rid=$(rt_id "$rt")
    if [[ -z "$rid" ]]; then
      echo "Creando route table $rt ..."
      awsr ec2 create-route-table --vpc-id "$VPC_ID" \
        --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$rt},$TAGS]" \
        --query "RouteTable.RouteTableId" --output text >/dev/null
    else
      echo "Ya existe $rid ($rt); se reutiliza."
    fi
  done

  for e in "${PLAN[@]}"; do
    IFS='|' read -r name cidr rt uso <<<"$e"
    sid=$(subnet_id "$cidr")
    rid=$(rt_id "$rt")
    read -r actual aid < <(awsr ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$sid" \
      --query "RouteTables[0].[RouteTableId,Associations[?SubnetId=='$sid']|[0].RouteTableAssociationId]" --output text)
    if [[ "$actual" == "$rid" ]]; then
      echo "$name ya está asociada a $rt."
    elif [[ "$actual" == "None" || -z "$actual" ]]; then
      awsr ec2 associate-route-table --route-table-id "$rid" --subnet-id "$sid" >/dev/null
      echo "$name asociada a $rt."
    else
      awsr ec2 replace-route-table-association --association-id "$aid" --route-table-id "$rid" >/dev/null
      echo "$name movida de $actual a $rt."
    fi
  done
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

  local SJ RJ
  SJ=$(awsr ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --output json)
  RJ=$(awsr ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --output json)
  printf '%s\n' "$SJ" > "$OUT_DIR/subnets.json"
  printf '%s\n' "$RJ" > "$OUT_DIR/route-tables.json"

  echo "Validación de subredes y rutas de $VPC_NAME · $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "  VPC ID: $VPC_ID · región: $REGION · AZ: $AZ"
  check "Subredes en la VPC (total)" "${#PLAN[@]}" "$(jq '.Subnets | length' <<<"$SJ")"

  local e name cidr rt uso s sid
  for e in "${PLAN[@]}"; do
    IFS='|' read -r name cidr rt uso <<<"$e"
    s=$(jq -c --arg c "$cidr" '.Subnets[] | select(.CidrBlock==$c)' <<<"$SJ")
    if [[ -z "$s" ]]; then
      echo "  -- $name ($cidr)"
      check "Existe" "sí" "no"; continue
    fi
    sid=$(jq -r '.SubnetId' <<<"$s")
    tagv() { jq -r --arg k "$1" '.Tags[]? | select(.Key==$k) | .Value' <<<"$s"; }
    echo "  -- $name ($cidr) · $sid · IP disponibles: $(jq -r '.AvailableIpAddressCount' <<<"$s") de $(( 1 << (32 - ${cidr#*/}) )) (AWS reserva 5)"
    check "Estado" "available" "$(jq -r '.State' <<<"$s")"
    check "Availability Zone" "$AZ" "$(jq -r '.AvailabilityZone' <<<"$s")"
    check "MapPublicIpOnLaunch" "false" "$(jq -r '.MapPublicIpOnLaunch' <<<"$s")"
    check "Tag Name" "$name" "$(tagv Name)"
    check "Tags Project/Phase/Environment" "ZenitePrestige/Fase2/Prototype" "$(tagv Project)/$(tagv Phase)/$(tagv Environment)"
    check "Route table asociada" "$rt" "$(jq -r --arg s "$sid" \
      '[.RouteTables[] | select(any(.Associations[]?; .SubnetId==$s)) | (.Tags[]? | select(.Key=="Name") | .Value)] | first // "ninguna (usa la principal)"' <<<"$RJ")"
  done

  echo "  -- Solapamiento y reservas"
  local cidrs=() i j over=0 res
  mapfile -t cidrs < <(jq -r '.Subnets[].CidrBlock' <<<"$SJ")
  for (( i=0; i<${#cidrs[@]}; i++ )); do
    for (( j=i+1; j<${#cidrs[@]}; j++ )); do
      solapan "${cidrs[i]}" "${cidrs[j]}" && { echo "    ${cidrs[i]} se solapa con ${cidrs[j]}"; over=1; }
    done
  done
  check "Subredes que se solapan" "0" "$over"
  for res in "${RESERVAS[@]}"; do
    over=0
    for cidr in "${cidrs[@]}"; do solapan "$cidr" "$res" && over=1; done
    check "Reserva $res libre" "0" "$over"
  done

  echo "  -- Route tables (solo la ruta local)"
  local r
  for rt in "${RTS[@]}"; do
    r=$(jq -c --arg n "$rt" '.RouteTables[] | select(any(.Tags[]?; .Key=="Name" and .Value==$n))' <<<"$RJ")
    if [[ -z "$r" ]]; then check "$rt existe" "sí" "no"; continue; fi
    check "$rt ($(jq -r '.RouteTableId' <<<"$r")) rutas" \
      "$VPC_CIDR->local" "$(jq -r '[.Routes[] | "\(.DestinationCidrBlock // .DestinationIpv6CidrBlock // .DestinationPrefixListId)->\(.GatewayId // .NatGatewayId // .InstanceId // .NetworkInterfaceId // .TransitGatewayId // .VpcPeeringConnectionId // "?")"] | join(",")' <<<"$r")"
  done

  local igw inst nat eip
  igw=$(awsr ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query "length(InternetGateways)" --output text)
  check "Internet Gateway asociado a la VPC" "0" "$igw"
  inst=$(awsr ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" \
    "Name=instance-state-name,Values=pending,running" --query "length(Reservations[].Instances[])" --output text)
  nat=$(awsr ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" \
    "Name=state,Values=pending,available" --query "length(NatGateways)" --output text)
  eip=$(awsr ec2 describe-addresses --query "length(Addresses)" --output text)
  echo "  Control de costos (esta parte debe estar en 0): EC2=$inst NAT=$nat ElasticIP=$eip"
  [[ "$inst$nat$eip" != "000" ]] && echo "  AVISO: hay recursos con costo. No son parte de este paso; revísalos."

  if (( fallas == 0 )); then echo "RESULTADO: todo correcto."; else echo "RESULTADO: hay fallas; corrígelas antes de continuar."; fi
  return "$fallas"
}

# ---------- Registro con los IDs reales ----------
registro() {
  local SJ RJ e name cidr rt uso sid rid n ini fin
  SJ=$(cat "$OUT_DIR/subnets.json")
  RJ=$(cat "$OUT_DIR/route-tables.json")
  {
    echo "# Registro de implementación: subredes y tablas de rutas"
    echo
    echo "Generado por \`02_crear_subredes_rutas.sh\` a partir de AWS el $(date -u '+%Y-%m-%d %H:%M UTC')."
    echo "VPC \`$VPC_NAME\` · \`$VPC_ID\` · \`$VPC_CIDR\` · región \`$REGION\`."
    echo
    echo "| Nombre lógico | CIDR | Subnet ID | Route Table | Route Table ID | Availability Zone | Asignables | Uso |"
    echo "|---|---|---|---|---|---|---|---|"
    for e in "${PLAN[@]}"; do
      IFS='|' read -r name cidr rt uso <<<"$e"
      sid=$(jq -r --arg c "$cidr" '.Subnets[] | select(.CidrBlock==$c) | .SubnetId' <<<"$SJ")
      rid=$(jq -r --arg s "$sid" '[.RouteTables[] | select(any(.Associations[]?; .SubnetId==$s)) | .RouteTableId] | first // "-"' <<<"$RJ")
      read -r ini fin <<<"$(rango "$cidr")"
      echo "| \`$name\` | \`$cidr\` | \`${sid:--}\` | \`$rt\` | \`$rid\` | \`$AZ\` | \`$(int2ip $((ini+4))) – $(int2ip $((fin-1)))\` | $uso |"
    done
    echo
    echo "## Tablas de rutas"
    echo
    echo "| Route table | Route Table ID | Rutas | Subredes asociadas |"
    echo "|---|---|---|---|"
    for rt in "${RTS[@]}"; do
      jq -r --arg n "$rt" '
        .RouteTables[] | select(any(.Tags[]?; .Key=="Name" and .Value==$n)) as $r
        | ($r.Associations // [] | map(select(.SubnetId)) | map(.SubnetId)) as $ids
        | "| `\($n)` | `\($r.RouteTableId)` | \([$r.Routes[] | "`\(.DestinationCidrBlock) -> \(.GatewayId)`"] | join("<br>")) | \($ids | map("`" + . + "`") | join("<br>")) |"' <<<"$RJ"
    done
    local main
    main=$(jq -r '.RouteTables[] | select(any(.Associations[]?; .Main==true)) | .RouteTableId' <<<"$RJ")
    echo
    echo "La tabla principal de la VPC (\`$main\`) la crea AWS automáticamente; no tiene subredes asociadas de forma explícita."
    echo
    echo "Bloques de reserva sin usar: \`10.20.0.160/27\` (Reserva A) y \`10.20.0.192/26\` (Reserva B)."
    echo "No hay Internet Gateway, NAT Gateway, Elastic IP ni instancias en este paso."
  } > "$OUT_DIR/segmentacion.md"
}

if [[ "$MODO" == "crear" ]]; then
  preflight || { echo "No se modificó nada." >&2; exit 1; }
  crear
  echo
fi

set +e
validar | tee "$OUT_DIR/subredes-validacion.txt"
RC=${PIPESTATUS[0]}
set -e
registro

echo
echo "Archivos en $OUT_DIR: subnets.json, route-tables.json, subredes-validacion.txt y segmentacion.md"
echo "(descárgalos a Fase2/configuracion/)."
echo "Faltan las capturas E02 (VPC > Subnets, ordenar por IPv4 CIDR) y E03 (Route tables: pestaña Routes de cada tabla)."
exit "$RC"
