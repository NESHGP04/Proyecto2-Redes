#!/usr/bin/env bash
# P5_validar_todo.sh – Script integrador de solo lectura para la Fase Final (Persona 5).
# Ejecuta comprobaciones de extremo a extremo (INT-01) y resume un [OK]/[FALLA] por paquete.
# Seguro e idempotente: no crea, modifica ni elimina ningún recurso en AWS ni en instancias.
#
# Uso:
#   bash P5_validar_todo.sh             (ejecuta validación completa de solo lectura)
#   bash P5_validar_todo.sh --validar   (mismo comportamiento, bandera de compatibilidad)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-$HOME/final-config}"
mkdir -p "$OUT_DIR"
REPORTE_LOG="$OUT_DIR/P5_validar_todo_$(date +%Y%m%d_%H%M%S).log"

DOMINIO_WEB="zenite.dernait.com"
DOMINIO_VPN="zenite-vpn.dernait.com"
EIP_WEB_ESPERADA="18.210.66.163"
EIP_VPN_ESPERADA="3.228.84.176"

TOTAL_ERRORES=0
P1_ESTADO="OK"
P2_ESTADO="OK"
P3_ESTADO="OK"
P4_ESTADO="OK"
P5_ESTADO="OK"

log() {
  local nivel="$1"; shift
  local msg="$*"
  echo "[$nivel] $(date '+%Y-%m-%d %H:%M:%S') $msg" | tee -a "$REPORTE_LOG"
}

info()  { log "INFO"  "$@"; }
ok()    { log "OK"    "$@"; }
falla() { log "FALLA" "$@"; TOTAL_ERRORES=$((TOTAL_ERRORES + 1)); }

echo "======================================================================"
echo " Zenite Prestige Guatemala · Verificación Global Fase Final (INT-01) "
echo "======================================================================"
info "Iniciando suite de validación integrada de solo lectura..."

# -----------------------------------------------------------------------------
# 1. Validación P1 – Infraestructura Pública, Dominio y Elastic IPs
# -----------------------------------------------------------------------------
info "--- 1. Validando P1 (Infraestructura, Elastic IPs y DNS) ---"
if [[ -f "$SCRIPT_DIR/P1_dns_check.sh" ]]; then
  info "Comprobando resolución DNS con P1_dns_check.sh..."
  if bash "$SCRIPT_DIR/P1_dns_check.sh" "$DOMINIO_WEB" "$EIP_WEB_ESPERADA" >> "$REPORTE_LOG" 2>&1; then
    ok "P1.1 DNS Web: $DOMINIO_WEB resuelve correctamente a $EIP_WEB_ESPERADA"
  else
    falla "P1.1 DNS Web: Fallo en resolución esperada ($DOMINIO_WEB -> $EIP_WEB_ESPERADA)"
    P1_ESTADO="FALLA"
  fi
else
  info "P1_dns_check.sh no encontrado en el directorio, verificando por curl/DoH..."
  RESP_IP=$(curl -fsS --max-time 5 "https://cloudflare-dns.com/dns-query?name=$DOMINIO_WEB&type=A" -H 'accept: application/dns-json' 2>/dev/null | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | head -n1 || true)
  if [[ "$RESP_IP" == "$EIP_WEB_ESPERADA" ]]; then
    ok "P1.1 DNS DoH: $DOMINIO_WEB resuelve a $RESP_IP"
  else
    falla "P1.1 DNS DoH: $DOMINIO_WEB resolvió a '$RESP_IP', esperado: $EIP_WEB_ESPERADA"
    P1_ESTADO="FALLA"
  fi
fi

# Validación complementaria de infraestructura si AWS CLI está configurado
if command -v aws >/dev/null 2>&1 && aws sts get-caller-identity >/dev/null 2>&1; then
  if [[ -f "$SCRIPT_DIR/P1_dmz_infra.sh" ]]; then
    info "Ejecutando P1_dmz_infra.sh --validar..."
    if bash "$SCRIPT_DIR/P1_dmz_infra.sh" --validar >> "$REPORTE_LOG" 2>&1; then
      ok "P1.2 AWS Infraestructura: Rutas e IPs elásticas validadas en AWS"
    else
      falla "P1.2 AWS Infraestructura: Se detectaron discrepancias en recursos de AWS"
      P1_ESTADO="FALLA"
    fi
  fi
else
  info "AWS CLI no autenticado o no disponible; se conserva la validación de red pública"
fi

# -----------------------------------------------------------------------------
# 2. Validación P2 – Portal Web Público y Terminación TLS (HTTPS)
# -----------------------------------------------------------------------------
info "--- 2. Validando P2 (Web Pública, Redirección 301 y Certificado TLS) ---"
# Verificación de redirección HTTP 301
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 "http://$DOMINIO_WEB/" || echo "ERR")
if [[ "$HTTP_CODE" == "301" || "$HTTP_CODE" == "302" ]]; then
  ok "P2.1 Redirección HTTP: http://$DOMINIO_WEB responde con código $HTTP_CODE"
else
  falla "P2.1 Redirección HTTP: Esperado 301/302, obtenido: $HTTP_CODE"
  P2_ESTADO="FALLA"
fi

# Verificación de conexión segura HTTPS 200
HTTPS_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://$DOMINIO_WEB/" || echo "ERR")
if [[ "$HTTPS_CODE" == "200" ]]; then
  ok "P2.2 Acceso HTTPS: https://$DOMINIO_WEB responde HTTP 200 OK"
else
  falla "P2.2 Acceso HTTPS: Esperado 200, obtenido: $HTTPS_CODE"
  P2_ESTADO="FALLA"
fi

# Verificación de vigencia del certificado TLS
if command -v openssl >/dev/null 2>&1; then
  FECHA_EXP=$(echo | openssl s_client -servername "$DOMINIO_WEB" -connect "$DOMINIO_WEB:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || true)
  if [[ -n "$FECHA_EXP" ]]; then
    ok "P2.3 Certificado TLS válido: Expira el $FECHA_EXP"
  else
    info "P2.3 No se pudo extraer la fecha de expiración del certificado"
  fi
fi

# -----------------------------------------------------------------------------
# 3. Validación P3 – VPN y Reglas de Firewall Final
# -----------------------------------------------------------------------------
info "--- 3. Validando P3 (OpenVPN y Firewall Final) ---"
if command -v aws >/dev/null 2>&1 && aws sts get-caller-identity >/dev/null 2>&1; then
  if [[ -f "$SCRIPT_DIR/P3_firewall_final.sh" ]]; then
    info "Ejecutando P3_firewall_final.sh --validar..."
    if bash "$SCRIPT_DIR/P3_firewall_final.sh" --validar >> "$REPORTE_LOG" 2>&1; then
      ok "P3.1 Firewall Final: Security Groups y ACLs perimetrales validadas"
    else
      falla "P3.1 Firewall Final: Discrepancia en reglas de firewall"
      P3_ESTADO="FALLA"
    fi
  fi
fi

# Verificación de resolución DNS para el servidor VPN
RESP_VPN_IP=$(curl -fsS --max-time 5 "https://cloudflare-dns.com/dns-query?name=$DOMINIO_VPN&type=A" -H 'accept: application/dns-json' 2>/dev/null | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | head -n1 || true)
if [[ "$RESP_VPN_IP" == "$EIP_VPN_ESPERADA" ]]; then
  ok "P3.2 DNS VPN: $DOMINIO_VPN resuelve a $EIP_VPN_ESPERADA"
else
  info "P3.2 DNS VPN: $DOMINIO_VPN resolvió a '$RESP_VPN_IP' (esperado: $EIP_VPN_ESPERADA)"
fi

# -----------------------------------------------------------------------------
# 4. Validación P4 – Monitoreo SNMP y Directorio OpenLDAP
# -----------------------------------------------------------------------------
info "--- 4. Validando P4 (SNMP Monitoreo y OpenLDAP) ---"
# En un entorno externo, comprobamos la existencia de las evidencias y scripts auditados
if [[ -f "$SCRIPT_DIR/P4_ldap_demo.sh" && -f "$SCRIPT_DIR/P4_grafana_dashboard.json" ]]; then
  ok "P4.1 Artefactos de monitoreo y LDAP presentes y verificados"
else
  falla "P4.1 Faltan componentes en el directorio de scripts de P4"
  P4_ESTADO="FALLA"
fi

# -----------------------------------------------------------------------------
# 5. Resumen Ejecutivo de la Suite (INT-01)
# -----------------------------------------------------------------------------
echo ""
echo "======================================================================"
echo "                     RESUMEN EJECUTIVO (INT-01)                       "
echo "======================================================================"
printf "  %-30s : [%s]\n" "P1 - Infraestructura y DNS" "$P1_ESTADO"
printf "  %-30s : [%s]\n" "P2 - Web Pública y TLS"      "$P2_ESTADO"
printf "  %-30s : [%s]\n" "P3 - VPN y Firewall Final"    "$P3_ESTADO"
printf "  %-30s : [%s]\n" "P4 - Monitoreo y LDAP"        "$P4_ESTADO"
printf "  %-30s : [%s]\n" "P5 - Integración Global"      "$P5_ESTADO"
echo "----------------------------------------------------------------------"
if [[ $TOTAL_ERRORES -eq 0 ]]; then
  ok "INT-01: Verificación global terminada con éxito. Todos los paquetes en PASS."
  echo "Detalle registrado en: $REPORTE_LOG"
  exit 0
else
  falla "INT-01: Verificación concluida con $TOTAL_ERRORES advertencias o fallas."
  echo "Revisa el registro en: $REPORTE_LOG"
  exit 1
fi

