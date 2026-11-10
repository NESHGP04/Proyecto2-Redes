#!/usr/bin/env bash
# P4 · checkpoint 2 · SOLO LECTURA EN AWS. Ejecutar en CloudShell.
# Uso: bash P4_ldap_diagnostico.sh --validar
# Consulta inventario, salud, EICE, grupos y ACL; no enciende instancias.
# Solo escribe un registro local en ~/final-config/. No carga .env ni pide secretos.
set -euo pipefail
umask 077

[[ $# -eq 1 && "$1" == --validar ]] || {
    echo 'Uso: bash P4_ldap_diagnostico.sh --validar' >&2
    exit 2
}
for herramienta in aws jq tee date; do
    command -v "$herramienta" >/dev/null || {
        echo "[FALLA] Falta $herramienta. Ejecuta este script en AWS CloudShell." >&2
        exit 1
    }
done

REGION=us-east-1
OUT_DIR="${P4_OUT_DIR:-$HOME/final-config}"
mkdir -p "$OUT_DIR"
LOG="$OUT_DIR/P4_ldap_nube_$(date -u '+%Y%m%dT%H%M%SZ')_$$.txt"
exec > >(tee "$LOG") 2>&1
trap 'echo "[FALLA] Recolección interrumpida en línea $LINENO; conserva el error. No se cambió AWS."' ERR
export AWS_PAGER=""
export AWS_CLI_AUTO_PROMPT=off

awsr() {
    # Mantener aquí únicamente operaciones de consulta.
    aws --region "$REGION" --no-cli-pager --output json \
        --cli-connect-timeout 10 --cli-read-timeout 30 "$@"
}
fallar() { echo "[FALLA] $*"; exit 1; }
PENDIENTES=0
pendiente() { echo "[PENDIENTE] $*"; PENDIENTES=$((PENDIENTES + 1)); }

echo "P4 · diagnóstico LDAP · $(date -u '+%Y-%m-%d %H:%M:%S UTC') · $REGION"
echo 'Las consultas AWS no comprueban slapd, TLS ni el bind dentro de las instancias.'
echo "Registro local: $LOG"

VPC_J=$(awsr ec2 describe-vpcs --filters 'Name=tag:Name,Values=vpc-zenite-fase2')
[[ $(jq '.Vpcs | length' <<<"$VPC_J") == 1 ]] || fallar 'La VPC falta o su nombre está duplicado.'
[[ $(jq -r '.Vpcs[0].CidrBlock' <<<"$VPC_J") == 10.20.0.0/24 ]] || fallar 'CIDR de VPC inesperado.'
VPC_ID=$(jq -r '.Vpcs[0].VpcId' <<<"$VPC_J")
echo "[OK] VPC única: $VPC_ID · 10.20.0.0/24"

INST_J=$(awsr ec2 describe-instances --filters "Name=vpc-id,Values=$VPC_ID" \
    'Name=tag:Name,Values=zp-ldap-01,zp-ventas-01,zp-ti-01,zp-visitantes-01' \
    'Name=instance-state-name,Values=pending,running,stopping,stopped')
HOSTS_J=$(jq '[.Reservations[].Instances[]]' <<<"$INST_J")
for NOMBRE in zp-ldap-01 zp-ventas-01 zp-ti-01 zp-visitantes-01; do
    N=$(jq --arg n "$NOMBRE" '[.[] | select(any(.Tags[]?; .Key=="Name" and .Value==$n))] | length' <<<"$HOSTS_J")
    [[ "$N" == 1 ]] || fallar "$NOMBRE: se esperaba una instancia y hay $N. Coordinar con P1."
    HOST_J=$(jq -c --arg n "$NOMBRE" '.[] | select(any(.Tags[]?; .Key=="Name" and .Value==$n))' <<<"$HOSTS_J")
    [[ $(jq -r '.Tags[]? | select(.Key=="Project") | .Value' <<<"$HOST_J") == ZenitePrestige ]] \
        || fallar "$NOMBRE no tiene la etiqueta Project esperada."
    case "$NOMBRE" in
        zp-ldap-01) IP=10.20.0.69 ;;
        zp-ventas-01) IP=10.20.0.10 ;;
        zp-ti-01) IP=10.20.0.102 ;;
        zp-visitantes-01) IP=10.20.0.36 ;;
    esac
    [[ $(jq -r '.PrivateIpAddress' <<<"$HOST_J") == "$IP" ]] || fallar "$NOMBRE: IP fuera del plan."
    [[ $(jq -r '.PublicIpAddress // "ninguna"' <<<"$HOST_J") == ninguna ]] \
        || fallar "$NOMBRE tiene IPv4 pública inesperada."
    ESTADO=$(jq -r '.State.Name' <<<"$HOST_J")
    jq -r --arg n "$NOMBRE" '"[INFO] \($n) · \(.InstanceId) · \(.State.Name) · \(.PrivateIpAddress) · \(.SubnetId) · SG=\([.SecurityGroups[].GroupName] | join(","))"' <<<"$HOST_J"
    if [[ "$NOMBRE" != zp-visitantes-01 && "$ESTADO" != running ]]; then
        pendiente "$NOMBRE está $ESTADO. Solicitar a P1 su encendido antes de las pruebas remotas."
    fi
done

mapfile -t IDS < <(jq -r '.[].InstanceId' <<<"$HOSTS_J")
STATUS_J=$(awsr ec2 describe-instance-status --include-all-instances --instance-ids "${IDS[@]}")
echo '--- Salud EC2: sistema / instancia / EBS ---'
for NOMBRE in zp-ldap-01 zp-ventas-01 zp-ti-01 zp-visitantes-01; do
    IID=$(jq -r --arg n "$NOMBRE" '.[] | select(any(.Tags[]?; .Key=="Name" and .Value==$n)) | .InstanceId' <<<"$HOSTS_J")
    SALUD=$(jq -r --arg id "$IID" '[.InstanceStatuses[] | select(.InstanceId==$id)][0] // {} | "\(.SystemStatus.Status // "sin dato")/\(.InstanceStatus.Status // "sin dato")/\(.AttachedEbsStatus.Status // "sin dato")"' <<<"$STATUS_J")
    echo "[INFO] $NOMBRE · $SALUD"
    ESTADO=$(jq -r --arg id "$IID" '.[] | select(.InstanceId==$id) | .State.Name' <<<"$HOSTS_J")
    if [[ "$NOMBRE" != zp-visitantes-01 && "$ESTADO" == running && "$SALUD" != ok/ok/ok ]]; then
        pendiente "$NOMBRE: salud aún no confirmada 3/3. Comprobar también la consola; no asumir que falta de dato es un fallo de LDAP."
    fi
done

echo '--- EICE ---'
EICE_J=$(awsr ec2 describe-instance-connect-endpoints --filters "Name=vpc-id,Values=$VPC_ID" \
    'Name=tag:Name,Values=eice-zenite-fase2')
[[ $(jq '.InstanceConnectEndpoints | length' <<<"$EICE_J") == 1 ]] || fallar 'El EICE falta o está duplicado.'
jq '.InstanceConnectEndpoints[] | {InstanceConnectEndpointId,State,SubnetId,SecurityGroupIds,PreserveClientIp}' <<<"$EICE_J"
[[ $(jq -r '.InstanceConnectEndpoints[0].State' <<<"$EICE_J") == create-complete ]] \
    || pendiente 'El EICE no está disponible; coordinar con P1.'

echo '--- Grupos efectivos de las cuatro instancias y del EICE ---'
SG_IDS_J=$(jq --argjson e "$EICE_J" '([.[].SecurityGroups[].GroupId] + [$e.InstanceConnectEndpoints[].SecurityGroupIds[]]) | unique' <<<"$HOSTS_J")
mapfile -t SG_IDS < <(jq -r '.[]' <<<"$SG_IDS_J")
SG_J=$(awsr ec2 describe-security-groups --group-ids "${SG_IDS[@]}")
jq '.SecurityGroups[] | {GroupName,GroupId,IpPermissions,IpPermissionsEgress}' <<<"$SG_J"
echo '[INFO] Revisar TCP 389/636 hacia LDAP desde los grupos efectivos de Ventas y TI, y TCP 22 desde EICE.'

echo '--- Subredes y ACL efectivas (incluyen retornos y número de regla) ---'
SUBS_J=$(jq --argjson e "$EICE_J" '([.[].SubnetId] + [$e.InstanceConnectEndpoints[].SubnetId]) | unique' <<<"$HOSTS_J")
mapfile -t SUB_IDS < <(jq -r '.[]' <<<"$SUBS_J")
SUB_J=$(awsr ec2 describe-subnets --subnet-ids "${SUB_IDS[@]}")
jq '.Subnets[] | {SubnetId,CidrBlock,Name:([.Tags[]? | select(.Key=="Name") | .Value][0])}' <<<"$SUB_J"
ACL_J=$(awsr ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID")
jq --argjson subs "$SUBS_J" '.NetworkAcls[] | select(any(.Associations[]?; .SubnetId as $s | $subs | index($s))) | {NetworkAclId,IsDefault,Associations,Entries}' <<<"$ACL_J"
echo '[INFO] SG con estado; ACL sin estado. Revisar ida 389/636 y retorno efímero antes de atribuir la causa a una capa.'

echo "[INFO] Recolección AWS terminada; pendientes de disponibilidad: $PENDIENTES."
echo '[INFO] Faltan las comprobaciones dentro de LDAP, Ventas y TI. Este registro no acredita LDAP-01..05 ni identifica por sí solo la falla histórica.'
if (( PENDIENTES > 0 )); then exit 1; fi
