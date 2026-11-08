#!/usr/bin/env bash
# P2_web_publica.sh - Fase final, Persona 2
# Instala y valida el portal publico de Zenite Prestige en zp-web-01 (10.20.0.116, Ubuntu 24.04):
# Nginx + Flask/gunicorn (solo en 127.0.0.1:8000) + SQLite con datos ficticios.
# Se ejecuta DENTRO de zp-web-01 (por EICE), desde FaseFinal/configuracion/ del repositorio clonado.
# Uso:  bash P2_web_publica.sh --validar     (solo lectura)
#       sudo bash P2_web_publica.sh instalar (pide confirmacion (si) antes de cambiar nada)
# Esta version sirve el portal por HTTP (fase de pruebas). HTTPS y la redireccion 301 se agregan despues.
# No maneja contrasenas ni llaves: el certificado se pide en otro paso y su llave no sale de la instancia.
set -euo pipefail

HOST_ESPERADO="zp-web-01"
IP_ESPERADA="10.20.0.116"
DIR="$(cd "$(dirname "$0")" && pwd)"
WEB="$DIR/web"
APP_DIR="/opt/zenite-portal"
DATA_DIR="/var/lib/zenite-portal"
SVC_USER="zenite-portal"
OUT_DIR="$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)/final-config"
MODO="${1:---validar}"

mkdir -p "$OUT_DIR"
touch "$OUT_DIR/P2_web_publica.log"
[[ -n "${SUDO_USER:-}" ]] && chown -R "$SUDO_USER:" "$OUT_DIR"
exec > >(tee -a "$OUT_DIR/P2_web_publica.log") 2>&1
echo "== P2_web_publica.sh $MODO · $(uname -n) · $(date -u '+%Y-%m-%d %H:%M:%S') UTC"
ERRORES=0
ok()    { echo "[OK] $*"; }
falla() { echo "[FALLA] $*"; ERRORES=$((ERRORES+1)); }

codigo_http() { curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1$1" || true; }

validar() {
  [[ "$(uname -n)" == "$HOST_ESPERADO" ]] && ok "Host $HOST_ESPERADO" || falla "Este host es $(uname -n), se esperaba $HOST_ESPERADO"
  for s in nginx zenite-portal; do
    systemctl is-active --quiet "$s" && ok "$s activo" || falla "$s no esta activo"
  done
  systemctl is-enabled --quiet zenite-portal && ok "zenite-portal arranca con el sistema" || falla "zenite-portal no esta habilitado"
  local SS; SS=$(ss -tln)
  grep -q '127.0.0.1:8000 ' <<<"$SS" && ok "gunicorn escucha en 127.0.0.1:8000" || falla "gunicorn no escucha en 127.0.0.1:8000"
  if grep ':8000 ' <<<"$SS" | grep -vq '127.0.0.1:8000'; then falla "El puerto 8000 escucha fuera de localhost"; else ok "El puerto 8000 no esta expuesto fuera de localhost"; fi
  grep -qE '(0.0.0.0|\*):80 ' <<<"$SS" && ok "Nginx escucha en TCP 80" || falla "Nginx no escucha en TCP 80"
  local r c
  for r in / /gestiones /consulta /salud /static/portal.css; do
    c=$(codigo_http "$r"); [[ "$c" == "200" ]] && ok "GET $r = 200" || falla "GET $r = $c (se esperaba 200)"
  done
  local cab; cab=$(curl -sI http://127.0.0.1/ || true)
  grep -qi '^content-security-policy:' <<<"$cab" && ok "Cabecera Content-Security-Policy" || falla "Falta Content-Security-Policy"
  grep -qi '^x-content-type-options: *nosniff' <<<"$cab" && ok "Cabecera X-Content-Type-Options" || falla "Falta X-Content-Type-Options"
  if grep -i '^server:' <<<"$cab" | grep -q '/'; then falla "La cabecera Server revela la version de Nginx"; else ok "Server sin version (server_tokens off)"; fi
  [[ "$(stat -c '%U:%a' "$DATA_DIR" 2>/dev/null || true)" == "$SVC_USER:750" ]] && ok "$DATA_DIR de $SVC_USER con permisos 750" || falla "Permisos de $DATA_DIR inesperados"
  [[ "$(getent passwd "$SVC_USER" | cut -d: -f7)" == "/usr/sbin/nologin" ]] && ok "$SVC_USER sin shell" || falla "$SVC_USER tiene shell o no existe"
}

instalar() {
  [[ $EUID -eq 0 ]] || { falla "instalar requiere sudo"; exit 1; }
  [[ "$(uname -n)" == "$HOST_ESPERADO" ]] || { falla "Este host es $(uname -n), no $HOST_ESPERADO. No se cambio nada."; exit 1; }
  ip -4 -o addr show | grep -q "inet $IP_ESPERADA/" || { falla "Este host no tiene la IP $IP_ESPERADA. No se cambio nada."; exit 1; }
  for f in app/app.py app/templates/base.html app/static/portal.css nginx/zenite-portal-http.conf zenite-portal.service; do
    [[ -f "$WEB/$f" ]] || { falla "Falta $WEB/$f. No se cambio nada."; exit 1; }
  done
  echo "Se va a instalar en $HOST_ESPERADO ($IP_ESPERADA): nginx, python3-flask y gunicorn (apt),"
  echo "  el portal en $APP_DIR, datos en $DATA_DIR (usuario $SVC_USER), el servicio zenite-portal"
  echo "  y el sitio /etc/nginx/sites-available/zenite-portal (se desactiva el sitio predeterminado de Nginx)."
  read -r -p "Escribe si para continuar: " R
  [[ "${R,,}" == "si" ]] || { echo "Cancelado, no se cambio nada."; exit 0; }

  apt-get update -q
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q nginx python3-flask gunicorn
  ok "Paquetes instalados"

  id "$SVC_USER" >/dev/null 2>&1 || useradd --system --home-dir "$DATA_DIR" --no-create-home --shell /usr/sbin/nologin "$SVC_USER"
  install -d -o "$SVC_USER" -g "$SVC_USER" -m 750 "$DATA_DIR"
  ok "Usuario $SVC_USER y $DATA_DIR listos"

  rm -rf "$APP_DIR"; install -d -o root -g root -m 755 "$APP_DIR"
  cp -r "$WEB/app/." "$APP_DIR/"
  chown -R root:root "$APP_DIR"; find "$APP_DIR" -type d -exec chmod 755 {} +; find "$APP_DIR" -type f -exec chmod 644 {} +
  ok "Portal copiado a $APP_DIR"

  install -m 644 "$WEB/zenite-portal.service" /etc/systemd/system/zenite-portal.service
  systemctl daemon-reload
  systemctl enable zenite-portal >/dev/null 2>&1
  systemctl restart zenite-portal
  ok "Servicio zenite-portal iniciado"

  install -d -m 755 /var/www/certbot
  install -m 644 "$WEB/nginx/zenite-portal-http.conf" /etc/nginx/sites-available/zenite-portal
  ln -sf /etc/nginx/sites-available/zenite-portal /etc/nginx/sites-enabled/zenite-portal
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl enable nginx >/dev/null 2>&1
  systemctl restart nginx
  ok "Nginx configurado y reiniciado"
  sleep 2
}

case "$MODO" in
  --validar) validar ;;
  instalar)  instalar; validar ;;
  *) echo "Modo desconocido: $MODO (usar --validar o instalar)"; exit 1 ;;
esac
[[ $ERRORES -eq 0 ]] && echo "RESULTADO: todo correcto." || echo "RESULTADO: $ERRORES fallo(s)."
exit $ERRORES
