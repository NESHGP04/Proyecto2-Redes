#!/usr/bin/env bash
# P1_dns_check.sh – Comprueba que el dominio resuelve a la Elastic IP de la web (DNS-01 y DNS-02, fase final · Persona 1).
# Solo lee: no crea ni cambia nada en AWS ni en el DNS. Ejecutar en AWS CloudShell o en cualquier equipo con curl.
#
#   bash P1_dns_check.sh <dominio>              compara con la IP de eip-zenite-web (la busca con aws)
#   bash P1_dns_check.sh <dominio> <ip>         compara con la IP indicada (no usa aws)
#   DOMINIO=zenite.me bash P1_dns_check.sh      el dominio también puede venir de la variable DOMINIO (o del .env)
#
# DNS-01: el dominio resuelve a la IP esperada.  DNS-02: resuelve igual con @8.8.8.8 y @1.1.1.1.
# Si el equipo no tiene dig (CloudShell suele no traerlo), usa DNS sobre HTTPS de Google y Cloudflare con curl.
# Salida en ~/final-config/dns-validacion.txt.
set -euo pipefail

ENV_FILE="$(cd "$(dirname "$0")" && pwd)/../../.env"
[[ -f "$ENV_FILE" ]] && { set -a; source "$ENV_FILE"; set +a; }

REGION="us-east-1"
EIP_WEB="eip-zenite-web"
OUT_DIR="${OUT_DIR:-$HOME/final-config}"

DOM="${1:-${DOMINIO:-}}"
ESPERADA="${2:-}"
[[ -n "$DOM" ]] || { echo "Uso: bash P1_dns_check.sh <dominio> [ip_esperada]" >&2; exit 2; }
DOM="${DOM%.}"
[[ "$DOM" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] || { echo "Dominio no válido: $DOM" >&2; exit 2; }

mkdir -p "$OUT_DIR"
SALIDA="$OUT_DIR/dns-validacion.txt"
FALLAS=0
IPV4='^[0-9]{1,3}(\.[0-9]{1,3}){3}$'

linea() { # etiqueta esperado real
  local ok="OK"; [[ "$2" == "$3" ]] || { ok="FALLA"; FALLAS=$((FALLAS+1)); }
  if [[ "$ok" == "OK" ]]; then printf '  [OK]    %-52s %s\n' "$1" "$3"
  else printf '  [FALLA] %-52s esperado=%s real=%s\n' "$1" "$2" "$3"; fi
}

# resolver <servidor: 8.8.8.8|1.1.1.1> -> IPv4 ordenadas, separadas por coma ("" si no resuelve)
resolver() {
  local srv="$1" r=""
  if command -v dig >/dev/null 2>&1; then
    r=$(dig +short +time=3 +tries=1 A "$DOM" "@$srv" 2>/dev/null | grep -E "$IPV4" || true)
  else
    local url
    case "$srv" in
      8.8.8.8) url="https://dns.google/resolve?name=$DOM&type=A" ;;
      *)       url="https://cloudflare-dns.com/dns-query?name=$DOM&type=A" ;;
    esac
    r=$(curl -fsS --max-time 8 -H 'accept: application/dns-json' "$url" 2>/dev/null \
        | grep -oE '"data": ?"[0-9.]+"' | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' || true)
  fi
  printf '%s\n' "$r" | sed '/^$/d' | sort -u | paste -sd, -
}

if [[ -z "$ESPERADA" ]]; then
  command -v aws >/dev/null 2>&1 || { echo "No hay aws en este equipo: pasa la IP como segundo argumento." >&2; exit 2; }
  ESPERADA=$(aws ec2 describe-addresses --region "$REGION" --filters "Name=tag:Name,Values=$EIP_WEB" \
             --query 'Addresses[0].PublicIp' --output text 2>/dev/null || true)
  [[ "$ESPERADA" =~ $IPV4 ]] || { echo "No encontré la Elastic IP $EIP_WEB; pasa la IP como segundo argumento." >&2; exit 2; }
fi

{
  echo "Validación de DNS · $DOM · IP esperada $ESPERADA · $(date -u '+%Y-%m-%d %H:%M:%S') UTC"
  G=$(resolver 8.8.8.8); C=$(resolver 1.1.1.1)
  echo "  -- DNS-01 · el dominio resuelve a la Elastic IP de la web"
  linea "A $DOM -> Elastic IP (@8.8.8.8)" "$ESPERADA" "${G:-sin respuesta}"
  linea "A $DOM -> Elastic IP (@1.1.1.1)" "$ESPERADA" "${C:-sin respuesta}"
  echo "  -- DNS-02 · dos resolutores distintos coinciden"
  if [[ -z "$G" || -z "$C" ]]; then linea "8.8.8.8 y 1.1.1.1 dan la misma respuesta" "respuesta en ambos" "sin respuesta"
  else linea "8.8.8.8 y 1.1.1.1 dan la misma respuesta" "$G" "$C"; fi
  if [[ $FALLAS -eq 0 ]]; then echo "RESULTADO: todo correcto."
  else echo "RESULTADO: hay fallas; si acabas de crear o cambiar el registro, espera unos minutos (propagación) y repite."; fi
  [[ $FALLAS -eq 0 ]]   # el grupo va en un pipe: con pipefail su código de salida es el del script
} | tee "$SALIDA"
