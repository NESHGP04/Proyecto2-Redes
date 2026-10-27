#!/usr/bin/env bash
# P3_ldap.sh - Fase 3, Persona 3
# Instala y valida OpenLDAP (slapd) en zp-ldap-01 (10.20.0.69, Ubuntu 24.04): dominio zenite.internal, arbol
# ou=People / ou=Groups, grupos ventas y ti, cuatro usuarios de prueba y LDAPS (636) con certificado autofirmado.
# Se ejecuta DENTRO de zp-ldap-01, en la carpeta donde estan zenite.ldif y tls.ldif:
# Uso:  bash P3_ldap.sh --validar        (solo lectura)
#       sudo bash P3_ldap.sh instalar    (pide confirmacion (si) antes de cambiar nada)
# Contrasenas solo de laboratorio: LDAP_ADMIN_PASSWORD y LDAP_USER_PASSWORD del entorno; si faltan, se piden sin eco.
# Nunca se pasan como argumento de un comando (no aparecen en ps): van en archivos temporales 600 que se borran al salir.
set -euo pipefail

HOST_ESPERADO="zp-ldap-01"
IP_ESPERADA="10.20.0.69"
DOMINIO="zenite.internal"
ORGANIZACION="Zenite Prestige"
BASE_DN="dc=zenite,dc=internal"
ADMIN_DN="cn=admin,$BASE_DN"
CERT="/etc/ldap/zenite-ldap.crt"
LLAVE="/etc/ldap/zenite-ldap.key"
USUARIOS_ESPERADOS=4
GRUPOS_ESPERADOS=2
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)/fase3-config"
MODO="${1:---validar}"

mkdir -p "$OUT_DIR"
exec > >(tee -a "$OUT_DIR/P3_ldap.log") 2>&1
echo "== P3_ldap.sh $MODO · $(uname -n) · $(date -u '+%Y-%m-%d %H:%M:%S') UTC"
ERRORES=0
ok()    { echo "[OK] $*"; }
falla() { echo "[FALLA] $*"; ERRORES=$((ERRORES+1)); }

# numero de entradas que devuelve una busqueda anonima ($1 = filtro)
contar() {
  ldapsearch -x -LLL -H ldap://localhost -b "$BASE_DN" "$1" dn 2>/dev/null | grep -c '^dn:' || true
}

validar() {
  pgrep -x slapd >/dev/null && ok "slapd en ejecucion" || falla "slapd no esta en ejecucion"
  for p in 389 636; do
    ss -tln | grep -q ":$p " && ok "Escucha en TCP $p" || falla "No escucha en TCP $p"
  done
  n=$(contar "(objectClass=posixAccount)")
  [[ $n -eq $USUARIOS_ESPERADOS ]] && ok "Usuarios en ou=People: $n" || falla "Usuarios en ou=People: $n (se esperaban $USUARIOS_ESPERADOS)"
  n=$(contar "(objectClass=posixGroup)")
  [[ $n -eq $GRUPOS_ESPERADOS ]] && ok "Grupos en ou=Groups: $n" || falla "Grupos en ou=Groups: $n (se esperaban $GRUPOS_ESPERADOS)"
  ldapsearch -x -LLL -H ldap://localhost -b "ou=People,$BASE_DN" userPassword 2>/dev/null | grep -q '^userPassword' \
    && falla "userPassword visible sin autenticar" || ok "userPassword no visible sin autenticar"
  LDAPTLS_CACERT="$CERT" ldapsearch -x -LLL -H "ldaps://$IP_ESPERADA" -b "$BASE_DN" -s base dn >/dev/null 2>&1 \
    && ok "LDAPS responde en $IP_ESPERADA:636 con certificado valido" || falla "LDAPS no responde o el certificado no es valido"
  openssl x509 -in "$CERT" -noout -ext subjectAltName 2>/dev/null | grep -q "IP Address:$IP_ESPERADA" \
    && ok "Certificado con SAN IP:$IP_ESPERADA" || falla "Certificado sin SAN IP:$IP_ESPERADA"
}

# lee la variable $1 sin eco si no viene del entorno
pedir() {
  if [[ -z "${!1:-}" ]]; then read -r -s -p "$1: " "$1"; echo; fi
  [[ -n "${!1}" ]] || { falla "$1 vacia"; exit 1; }
}

instalar() {
  [[ $EUID -eq 0 ]] || { falla "instalar requiere sudo"; exit 1; }
  [[ "$(uname -n)" == "$HOST_ESPERADO" ]] || { falla "Este host es $(uname -n), no $HOST_ESPERADO. No se cambio nada."; exit 1; }
  ip -4 -o addr show | grep -q "inet $IP_ESPERADA/" || { falla "Este host no tiene la IP $IP_ESPERADA. No se cambio nada."; exit 1; }
  for f in zenite.ldif tls.ldif; do
    [[ -f "$DIR/$f" ]] || { falla "Falta $DIR/$f. No se cambio nada."; exit 1; }
  done

  echo "Se va a instalar y configurar OpenLDAP en $HOST_ESPERADO ($IP_ESPERADA):"
  echo "  base: $BASE_DN | admin: $ADMIN_DN | puertos: 389 (ldap) y 636 (ldaps, certificado autofirmado)"
  read -r -p "Escribe si para continuar: " R
  [[ "${R,,}" == "si" ]] || { echo "Cancelado, no se cambio nada."; exit 0; }
  pedir LDAP_ADMIN_PASSWORD
  pedir LDAP_USER_PASSWORD

  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
  printf %s "$LDAP_ADMIN_PASSWORD" > "$TMP/admin"
  printf %s "$LDAP_USER_PASSWORD" > "$TMP/usuario"

  # 1. slapd y ldap-utils
  if dpkg -s slapd >/dev/null 2>&1; then
    ACTUAL=$(slapcat -n 0 -a '(olcSuffix=*)' 2>/dev/null | awk '/^olcSuffix:/{print $2}')
    [[ "$ACTUAL" == "$BASE_DN" ]] && ok "slapd ya instalado con $BASE_DN" \
      || { falla "slapd ya instalado con otro sufijo ($ACTUAL). No se cambio nada."; exit 1; }
  else
    debconf-set-selections <<EOF
slapd slapd/no_configuration boolean false
slapd slapd/domain string $DOMINIO
slapd shared/organization string $ORGANIZACION
slapd slapd/password1 password $LDAP_ADMIN_PASSWORD
slapd slapd/password2 password $LDAP_ADMIN_PASSWORD
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
EOF
    apt-get update -q
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q slapd ldap-utils
    # la contrasena del administrador no se queda en la base de debconf
    printf 'slapd slapd/password1 password\nslapd slapd/password2 password\n' | debconf-set-selections
    ok "slapd instalado con $BASE_DN"
  fi
  dpkg -s ldap-utils >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get install -y -q ldap-utils
  ok "ldap-utils instalado"

  # 2. TLS: certificado autofirmado valido para la IP y el nombre del servidor
  if [[ -s "$CERT" && -s "$LLAVE" ]]; then
    ok "Certificado ya existe ($CERT); no se vuelve a crear"
  else
    (umask 077; openssl req -x509 -newkey rsa:2048 -nodes -days 365 -sha256 \
      -subj "/O=$ORGANIZACION/CN=$HOST_ESPERADO.$DOMINIO" \
      -addext "subjectAltName=IP:$IP_ESPERADA,DNS:$HOST_ESPERADO.$DOMINIO" \
      -keyout "$LLAVE" -out "$CERT")
    ok "Certificado autofirmado creado ($CERT, 365 dias)"
  fi
  chgrp openldap "$LLAVE"; chmod 0640 "$LLAVE"; chmod 0644 "$CERT"
  ldapmodify -Q -Y EXTERNAL -H ldapi:/// -f "$DIR/tls.ldif" >/dev/null
  ok "TLS configurado en cn=config"
  if grep -q '^SLAPD_SERVICES=.*ldaps:///' /etc/default/slapd; then
    ok "ldaps:/// ya estaba habilitado en /etc/default/slapd"
  else
    sed -i 's|^SLAPD_SERVICES=.*|SLAPD_SERVICES="ldap:/// ldapi:/// ldaps:///"|' /etc/default/slapd
    ok "ldaps:/// habilitado en /etc/default/slapd"
  fi
  systemctl restart slapd
  ok "slapd reiniciado"

  # 3. Arbol, grupos y usuarios (ldapadd -c: lo que ya existe se reporta como "Already exists" y se continua)
  HASH=$(slappasswd -h '{SSHA}' -T "$TMP/usuario")
  sed "s|@@HASH_USUARIOS@@|$HASH|" "$DIR/zenite.ldif" > "$TMP/zenite.ldif"
  set +e
  SALIDA=$(ldapadd -c -x -H ldapi:/// -D "$ADMIN_DN" -y "$TMP/admin" -f "$TMP/zenite.ldif" 2>&1)
  set -e
  echo "$SALIDA" | grep '^adding new entry' || true
  if echo "$SALIDA" | grep -E '^ldap_(add|bind):' | grep -vq 'Already exists (68)'; then
    echo "$SALIDA"; falla "Error al cargar zenite.ldif"; exit 1
  fi
  ok "zenite.ldif cargado (las entradas que ya existian no se modificaron)"
}

case "$MODO" in
  --validar) validar ;;
  instalar)  instalar; validar ;;
  *) echo "Modo desconocido: $MODO (usar --validar o instalar)"; exit 1 ;;
esac
[[ $ERRORES -eq 0 ]] && echo "RESULTADO: todo correcto." || echo "RESULTADO: $ERRORES fallo(s)."
exit $ERRORES
