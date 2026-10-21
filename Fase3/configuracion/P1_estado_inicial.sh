#!/usr/bin/env bash
# P1_estado_inicial.sh – SOLO LECTURA: no crea, modifica ni borra nada en AWS (Fase 3 · Persona 1, checkpoint 2).
# Ejecutar en AWS CloudShell. No guarda ni pide credenciales.
#
#   bash P1_estado_inicial.sh
#
# Muestra el estado real de vpc-zenite-fase2 (subredes, rutas, Security Groups, ACL, instancias, EICE), los recursos
# con costo en TODAS las regiones, la AMI que se usaría y si el usuario tiene permisos para lo que viene (con --dry-run,
# que comprueba permisos sin crear nada). El número de cuenta se enmascara en la salida.
# Salida en ~/fase3-config/P1_estado_inicial.txt
set -uo pipefail

ENV_FILE="$(cd "$(dirname "$0")" && pwd)/../../.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

REGION="us-east-1"
VPC_NAME="vpc-zenite-fase2"
OUT_DIR="$HOME/fase3-config"
mkdir -p "$OUT_DIR"

awsr() { aws --region "$REGION" --output json "$@"; }
awsx() { local r="$1"; shift; aws --region "$r" --output json "$@"; }  # otra región
tabla() { column -t -s $'\t' 2>/dev/null || cat; }

ID_J=$(aws sts get-caller-identity --output json 2>/dev/null) || { echo "ERROR: no hay sesión de AWS (CloudShell o aws login)." >&2; exit 1; }
ACCT=$(jq -r '.Account' <<<"$ID_J")
ARN=$(jq -r '.Arn' <<<"$ID_J")

informe() {
  echo "Estado inicial de AWS · Fase 3 · $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo
  echo "== 1. Identidad =="
  echo "  $ARN"
  echo "  Región consultada: $REGION (la consola debe mostrar N. Virginia)"

  local V VPC_ID DHCP S RT SG NA I E
  V=$(awsr ec2 describe-vpcs --filters "Name=tag:Name,Values=$VPC_NAME")
  VPC_ID=$(jq -r '.Vpcs[0].VpcId // empty' <<<"$V")
  if [[ -z "$VPC_ID" ]]; then echo "ERROR: no existe la VPC $VPC_NAME en $REGION."; return 1; fi
  DHCP=$(jq -r '.Vpcs[0].DhcpOptionsId' <<<"$V")
  echo
  echo "== 2. VPC =="
  echo "  $VPC_NAME · $VPC_ID · $(jq -r '.Vpcs[0].CidrBlock' <<<"$V") · estado $(jq -r '.Vpcs[0].State' <<<"$V") · DHCP options $DHCP"

  S=$(awsr ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID")
  RT=$(awsr ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID")
  echo
  echo "== 3. Subredes (nombre · CIDR · AZ · ID · route table · IP libres) =="
  jq -r --argjson rt "$RT" '
    def nm: (.Tags // [] | map(select(.Key=="Name").Value) | first // "-");
    .Subnets | sort_by(.CidrBlock)[] | . as $s
    | ($rt.RouteTables | map(select(any(.Associations[]?; .SubnetId==$s.SubnetId))) | first // null) as $r
    | [($s|nm), $s.CidrBlock, $s.AvailabilityZone, $s.SubnetId, (if $r then ($r|nm) else "principal" end), ($s.AvailableIpAddressCount|tostring)] | @tsv' <<<"$S" | sed 's/^/  /' | tabla

  echo
  echo "== 4. Route tables y rutas =="
  jq -r '
    def nm: (.Tags // [] | map(select(.Key=="Name").Value) | first // "(principal)");
    .RouteTables[] | "  \(nm) · \(.RouteTableId) · subredes asociadas: \([.Associations[]? | select(.SubnetId) ] | length)",
      (.Routes[] | "      \(.DestinationCidrBlock // .DestinationPrefixListId) -> \(.GatewayId // .NatGatewayId // .NetworkInterfaceId // "?") (\(.State))")' <<<"$RT"

  SG=$(awsr ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID")
  echo
  echo "== 5. Security Groups =="
  jq -r '
    (.SecurityGroups | map({(.GroupId): .GroupName}) | add) as $n
    | def orig: ([.UserIdGroupPairs[]? | ($n[.GroupId] // .GroupId)] + [.IpRanges[]? | .CidrIp]) | join(",");
    def pr: (if .IpProtocol=="-1" then "todo" else "\(.IpProtocol):\(.FromPort // "-")-\(.ToPort // "-")" end);
    .SecurityGroups[] | "  \(.GroupName) · \(.GroupId)",
      (.IpPermissions[]? | "      entrada \(pr) <- \(orig)"),
      (if (.IpPermissions|length)==0 then "      entrada: (ninguna)" else empty end),
      (.IpPermissionsEgress[]? | "      salida  \(pr) -> \(orig)")' <<<"$SG"

  NA=$(awsr ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID")
  echo
  echo "== 6. Network ACL =="
  jq -r '.NetworkAcls[] | "  \(.NetworkAclId) · predeterminada: \(.IsDefault) · subredes asociadas: \(.Associations|length)",
      (.Entries[] | "      regla \(.RuleNumber) \(if .Egress then "salida " else "entrada" end) \(.RuleAction) proto=\(.Protocol) \(.CidrBlock // "-")")' <<<"$NA"

  I=$(awsr ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID")
  echo
  echo "== 7. Instancias (nombre · ID · estado · IP privada · tipo · IP pública) =="
  jq -r '[.Reservations[].Instances[] | select(.State.Name!="terminated")]
    | sort_by(.PrivateIpAddress)[]
    | [(.Tags // [] | map(select(.Key=="Name").Value) | first // "-"), .InstanceId, .State.Name, (.PrivateIpAddress // "-"), .InstanceType, (.PublicIpAddress // "ninguna")] | @tsv' <<<"$I" | sed 's/^/  /' | tabla

  E=$(awsr ec2 describe-instance-connect-endpoints --filters "Name=vpc-id,Values=$VPC_ID")
  echo
  echo "== 8. EC2 Instance Connect Endpoint =="
  local eni eip_priv
  jq -r '.InstanceConnectEndpoints[]? | "  \(.InstanceConnectEndpointId) · \(.State) · \(.SubnetId)"' <<<"$E"
  eni=$(jq -r '.InstanceConnectEndpoints[0].NetworkInterfaceIds[0] // empty' <<<"$E")
  if [[ -n "$eni" ]]; then
    eip_priv=$(awsr ec2 describe-network-interfaces --network-interface-ids "$eni" | jq -r '.NetworkInterfaces[0].PrivateIpAddress // "?"')
    echo "  IP privada del endpoint: $eip_priv (esa IP no se puede usar para el NAT Gateway)"
  fi

  echo
  echo "== 9. Gateways y recursos con costo en la VPC =="
  echo "  Internet Gateway adjunto: $(awsr ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" | jq '.InternetGateways|length')"
  echo "  NAT Gateway activos:      $(awsr ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=pending,available" | jq '.NatGateways|length')"
  echo "  Elastic IP (cuenta/región): $(awsr ec2 describe-addresses | jq '.Addresses|length')"
  echo "  VPN Site-to-Site activas:   $(awsr ec2 describe-vpn-connections --filters "Name=state,Values=pending,available" | jq '.VpnConnections|length')"

  echo
  echo "== 10. Barrido de recursos con costo en TODAS las regiones =="
  echo "  (los US\$4.22 de octubre son todos de EC2: instancias, discos EBS, IPv4 públicas, snapshots)"
  local reg n_i n_v gib n_a n_n regs vistas=0 total_regs=0
  regs=$(awsr ec2 describe-regions | jq -r '.Regions[].RegionName')
  printf '  %-16s %-12s %-14s %-10s %s\n' "región" "inst.activas" "discos(GiB)" "Elastic IP" "NAT"
  for reg in $regs; do
    total_regs=$((total_regs+1))
    n_i=$(awsx "$reg" ec2 describe-instances --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" 2>/dev/null | jq '[.Reservations[].Instances[]]|length' 2>/dev/null) || n_i="n/d"
    n_v=$(awsx "$reg" ec2 describe-volumes 2>/dev/null | jq '.Volumes|length' 2>/dev/null) || n_v="n/d"
    gib=$(awsx "$reg" ec2 describe-volumes 2>/dev/null | jq '[.Volumes[].Size]|add // 0' 2>/dev/null) || gib="n/d"
    n_a=$(awsx "$reg" ec2 describe-addresses 2>/dev/null | jq '.Addresses|length' 2>/dev/null) || n_a="n/d"
    n_n=$(awsx "$reg" ec2 describe-nat-gateways --filter "Name=state,Values=pending,available" 2>/dev/null | jq '.NatGateways|length' 2>/dev/null) || n_n="n/d"
    if [[ "${n_i:-0}" != "0" || "${n_v:-0}" != "0" || "${n_a:-0}" != "0" || "${n_n:-0}" != "0" || "$reg" == "$REGION" ]]; then
      printf '  %-16s %-12s %-14s %-10s %s\n' "$reg" "${n_i:-n/d}" "${n_v:-n/d}($gib)" "${n_a:-n/d}" "${n_n:-n/d}"
    else
      vistas=$((vistas+1))
    fi
  done
  echo "  Regiones sin ningún recurso: $vistas de $total_regs (no se listan)."
  echo "  Snapshots propios en $REGION: $(awsr ec2 describe-snapshots --owner-ids self | jq '.Snapshots|length') ·" \
       "$(awsr ec2 describe-snapshots --owner-ids self | jq '[.Snapshots[].VolumeSize]|add // 0') GiB"

  echo
  echo "== 11. AMI candidatas (la última publicada) =="
  local AL UB
  AL=$(awsr ec2 describe-images --owners amazon --filters "Name=name,Values=al2023-ami-2023.*-x86_64" "Name=state,Values=available" \
        | jq -r '.Images | sort_by(.CreationDate) | last | "\(.ImageId)  \(.Name)"')
  UB=$(awsr ec2 describe-images --owners 099720109477 \
        --filters "Name=name,Values=ubuntu/images/hvm-ssd*/ubuntu-noble-24.04-amd64-server-*" "Name=state,Values=available" \
        | jq -r '.Images | sort_by(.CreationDate) | last | "\(.ImageId)  \(.Name)"')
  echo "  Amazon Linux 2023: $AL"
  echo "  Ubuntu 24.04:      $UB   (usuario de conexión: ubuntu)"

  echo
  echo "== 12. Permisos necesarios para Fase 3 =="
  local out_dry
  dry() {  # descripción, comando...
    local d="$1"; shift
    local o; o=$("$@" 2>&1) || true
    if grep -q 'DryRunOperation' <<<"$o"; then echo "  [OK]    $d"
    elif grep -qE 'UnauthorizedOperation|AccessDenied' <<<"$o"; then echo "  [FALTA] $d"
    else echo "  [?]     $d -> $(tr '\n' ' ' <<<"$o" | cut -c1-150)"; fi
  }
  local SUB_ID AMI_ID
  SUB_ID=$(jq -r '.Subnets[0].SubnetId' <<<"$S")
  AMI_ID=$(awk '{print $1}' <<<"$AL")
  echo "  Comprobación con --dry-run (no crea nada):"
  dry "crear Internet Gateway"      aws --region "$REGION" ec2 create-internet-gateway --dry-run
  dry "reservar Elastic IP"         aws --region "$REGION" ec2 allocate-address --domain vpc --dry-run
  dry "crear Security Group"        aws --region "$REGION" ec2 create-security-group --group-name zz-dryrun --description dryrun --vpc-id "$VPC_ID" --dry-run
  dry "crear Network ACL"           aws --region "$REGION" ec2 create-network-acl --vpc-id "$VPC_ID" --dry-run
  dry "crear DHCP Option Set"       aws --region "$REGION" ec2 create-dhcp-options --dhcp-configurations "Key=domain-name,Values=zenite.internal" --dry-run
  dry "lanzar instancia"            aws --region "$REGION" ec2 run-instances --image-id "$AMI_ID" --instance-type t3.micro --subnet-id "$SUB_ID" --dry-run
  if [[ "$ARN" == *":user/"* ]]; then
    echo "  Comprobación con simulate-principal-policy (acciones que no admiten --dry-run):"
    aws --output json iam simulate-principal-policy --policy-source-arn "$ARN" --action-names \
      ec2:CreateNatGateway ec2:DeleteNatGateway ec2:CreateRoute ec2:ReplaceRoute ec2:DeleteRoute \
      ec2:AttachInternetGateway ec2:ReleaseAddress ec2:AssociateDhcpOptions ec2:CreateNetworkAclEntry \
      ec2:AuthorizeSecurityGroupIngress ec2:AuthorizeSecurityGroupEgress ec2:RevokeSecurityGroupEgress \
      ec2:TerminateInstances ec2:StopInstances ec2:StartInstances ec2-instance-connect:OpenTunnel ec2-instance-connect:SendSSHPublicKey 2>/dev/null \
      | jq -r '.EvaluationResults[] | "  \(if .EvalDecision=="allowed" then "[OK]   " else "[FALTA]" end) \(.EvalActionName)"' \
      || echo "  [?] no se pudo simular (falta iam:SimulatePrincipalPolicy); se verá al ejecutar."
  else
    echo "  (identidad no es un usuario IAM: no se usa simulate-principal-policy)"
  fi

  echo
  echo "Fin del informe. Solo lectura: no se creó ni modificó nada."
}

informe | sed "s/$ACCT/<cuenta>/g" | tee "$OUT_DIR/P1_estado_inicial.txt"
echo
echo "Guardado en $OUT_DIR/P1_estado_inicial.txt (cuenta enmascarada). Pega aquí el informe para revisarlo."
