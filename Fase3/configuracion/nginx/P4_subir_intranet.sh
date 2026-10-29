#!/usr/bin/env bash
# P4: subir el paquete de la intranet desde CloudShell mediante EICE.
# bash P4_subir_intranet.sh --validar  solo consulta AWS; guarda registro local
# bash P4_subir_intranet.sh subir     pide confirmación y copia a la instancia
# No crea infraestructura ni modifica Security Groups o authorized_keys.
set -euo pipefail
umask 077

MODO="${1:---validar}"
case "$MODO" in --validar|subir) ;; *) echo 'Uso: bash P4_subir_intranet.sh [--validar|subir]' >&2; exit 2 ;; esac
BASE="$(cd "$(dirname "$0")" && pwd)"
PAQUETE="$BASE/P4_intranet.tar.gz"
REGION="us-east-1"
IP="10.20.0.71"
OUT_DIR="${P4_OUT_DIR:-$HOME/fase3-config}"
TEMP_DIR=""
awsr() { aws --region "$REGION" --no-cli-pager --output json "$@"; }
fallar() { echo "[FALLA] $*" >&2; exit 1; }
limpiar() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -f -- "$TEMP_DIR/eice" "$TEMP_DIR/eice.pub"
        rmdir -- "$TEMP_DIR"
    fi
}
trap limpiar EXIT

main() {
    # La función se ejecuta en la tubería de tee; limpiar también en ese proceso.
    trap limpiar EXIT
    local herramienta vpc instancia endpoint iid eid az respuesta resultado listado
    for herramienta in aws jq tar ssh-keygen scp; do
        command -v "$herramienta" >/dev/null || fallar "Falta $herramienta en CloudShell."
    done
    echo "P4 · transferencia privada · $(date -u '+%Y-%m-%d %H:%M:%S UTC') · $REGION"
    [[ -s "$PAQUETE" ]] || fallar "Sube también P4_intranet.tar.gz a $BASE."
    listado=$(tar -tzf "$PAQUETE")
    [[ "$(printf '%s\n' "$listado" | sort)" == "$(printf '%s\n' index.html styles.css intranet.js nginx.conf | sort)" ]] \
        || fallar 'El paquete debe contener únicamente index.html, styles.css, intranet.js y nginx.conf.'
    echo '[OK] Paquete con los cuatro archivos previstos.'

    vpc=$(awsr ec2 describe-vpcs --filters 'Name=tag:Name,Values=vpc-zenite-fase2')
    [[ "$(jq '.Vpcs | length' <<<"$vpc")" == 1 ]] || fallar 'La VPC falta o está duplicada.'
    [[ "$(jq -r '.Vpcs[0].CidrBlock' <<<"$vpc")" == '10.20.0.0/24' ]] || fallar 'CIDR inesperado.'
    vpc=$(jq -r '.Vpcs[0].VpcId' <<<"$vpc")
    instancia=$(awsr ec2 describe-instances --filters "Name=vpc-id,Values=$vpc" \
        'Name=tag:Name,Values=zp-intranet-01' 'Name=instance-state-name,Values=pending,running,stopping,stopped')
    [[ "$(jq '[.Reservations[].Instances[]] | length' <<<"$instancia")" == 1 ]] || fallar 'La instancia falta o está duplicada.'
    instancia=$(jq -c '.Reservations[].Instances[]' <<<"$instancia")
    [[ "$(jq -r '.State.Name' <<<"$instancia")" == running ]] || fallar 'La intranet no está encendida.'
    [[ "$(jq -r '.PrivateIpAddress' <<<"$instancia")" == "$IP" ]] || fallar 'IP privada inesperada.'
    [[ "$(jq -r '.PublicIpAddress // "ninguna"' <<<"$instancia")" == ninguna ]] || fallar 'La instancia tiene IPv4 pública.'
    [[ "$(jq -r '.Tags[]? | select(.Key=="Project") | .Value' <<<"$instancia")" == ZenitePrestige ]] || fallar 'Proyecto inesperado.'
    iid=$(jq -r '.InstanceId' <<<"$instancia")
    az=$(jq -r '.Placement.AvailabilityZone' <<<"$instancia")
    [[ "$iid" =~ ^i-[a-f0-9]+$ ]] || fallar 'Instance ID inválido.'
    echo "[OK] zp-intranet-01 · $iid · $IP · running · sin IPv4 pública."

    endpoint=$(awsr ec2 describe-instance-connect-endpoints --filters "Name=vpc-id,Values=$vpc" \
        'Name=tag:Name,Values=eice-zenite-fase2')
    [[ "$(jq '.InstanceConnectEndpoints | length' <<<"$endpoint")" == 1 ]] || fallar 'El EICE falta o está duplicado.'
    [[ "$(jq -r '.InstanceConnectEndpoints[0].State' <<<"$endpoint")" == create-complete ]] || fallar 'El EICE no está disponible.'
    eid=$(jq -r '.InstanceConnectEndpoints[0].InstanceConnectEndpointId' <<<"$endpoint")
    [[ "$eid" =~ ^eice-[a-f0-9]+$ ]] || fallar 'Endpoint ID inválido.'
    echo "[OK] EICE disponible: $eid."
    ssh-keygen -F "$IP" >/dev/null || fallar "Falta la huella conocida de $IP. Conéctate primero por EICE desde este CloudShell y verifica su identidad."
    echo '[OK] La identidad SSH del servidor ya está registrada en CloudShell.'
    if [[ "$MODO" == --validar ]]; then
        echo 'RESULTADO: comprobaciones previas correctas; transferencia y permisos SendSSHPublicKey/OpenTunnel por verificar al subir.'
        return
    fi

    echo 'Plan: copiar P4_intranet.tar.gz a /home/ec2-user/P4_intranet.tar.gz en zp-intranet-01.'
    echo 'Se usa una llave temporal local para EICE, que se elimina al terminar. No se instala una llave permanente.'
    echo 'Si ya hay un paquete con ese nombre, se reemplaza. No se publica ni se reinicia Nginx.'
    read -r -p "Escribe 'si' para continuar: " respuesta
    [[ "$respuesta" == si ]] || { echo 'Cancelado; no se transfirió nada.'; return; }
    TEMP_DIR=$(mktemp -d /tmp/p4-eice.XXXXXXXX)
    ssh-keygen -q -t ed25519 -N '' -f "$TEMP_DIR/eice"
    resultado=$(awsr ec2-instance-connect send-ssh-public-key --instance-id "$iid" \
        --instance-os-user ec2-user --availability-zone "$az" --ssh-public-key "file://$TEMP_DIR/eice.pub")
    [[ "$(jq -r '.Success' <<<"$resultado")" == true ]] || fallar 'AWS no aceptó la llave temporal.'
    scp -B -i "$TEMP_DIR/eice" \
        -o IdentitiesOnly=yes -o PasswordAuthentication=no \
        -o StrictHostKeyChecking=yes -o "HostKeyAlias=$IP" \
        -o "ProxyCommand=aws --region $REGION ec2-instance-connect open-tunnel --instance-id %h --instance-connect-endpoint-id $eid --remote-port 22" \
        "$PAQUETE" "ec2-user@$iid:P4_intranet.tar.gz"
    echo '[OK] Paquete copiado a /home/ec2-user/P4_intranet.tar.gz.'
    echo 'RESULTADO: transferencia correcta. Falta extraer, publicar y validar dentro de la instancia.'
}

mkdir -p "$OUT_DIR"
main 2>&1 | tee "$OUT_DIR/P4_transferencia.log"
