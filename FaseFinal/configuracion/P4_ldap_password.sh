#!/usr/bin/env bash
# Recuperación local de ventas01: sudo bash P4_ldap_password.sh --validar|cambiar
# No requiere contraseña LDAP anterior. Solo para zp-ldap-01, Ubuntu y sudo.
# cambiar detiene slapd para usar slapmodify como openldap, y restaura el servicio.
# AVISO: cambiar está deshabilitado tras un segfault real en slapmodify -u.
# --validar sigue siendo de solo lectura. No eliminar este bloqueo para reintentar.
set +x
set +v
set -euo pipefail
umask 077

MODO="${1:-}"
[[ $# -eq 1 && ( "$MODO" == --validar || "$MODO" == cambiar ) ]] || {
    echo 'Uso: sudo bash P4_ldap_password.sh --validar|cambiar' >&2
    exit 2
}
fallar() { echo "[FALLA] $*" >&2; exit 1; }
if [[ "$MODO" == cambiar ]]; then
    fallar 'Método offline deshabilitado: slapmodify -u sufrió una caída real. Se está preparando recuperación por LDAP local; no se detuvo ni modificó el servicio.'
fi
[[ $EUID -eq 0 ]] || fallar 'Requiere sudo para administrar la base local.'
[[ $(uname -n) == zp-ldap-01 ]] || fallar 'Este guion solo puede ejecutarse en zp-ldap-01.'
IP_LOCAL=$(ip -4 -o addr show)
awk '{split($4,a,"/"); if(a[1]=="10.20.0.69") ok=1} END{exit !ok}' <<<"$IP_LOCAL" \
    || fallar 'La IP local no coincide con 10.20.0.69.'
for p4_tool in timeout ldapsearch ldapwhoami slappasswd slapcat slapmodify runuser python3 openssl pgrep systemctl mktemp; do
    command -v "$p4_tool" >/dev/null || fallar "Falta $p4_tool. No se cambió LDAP."
done

BASE='dc=zenite,dc=internal'
DN="uid=ventas01,ou=People,$BASE"
CONF=/etc/ldap/slapd.d
CERT=/etc/ldap/zenite-ldap.crt
[[ -d "$CONF" && -r "$CERT" ]] || fallar 'No se encontraron la configuración y el certificado previstos.'
getent passwd openldap >/dev/null || fallar 'No existe el usuario de servicio openldap.'
systemctl is-active --quiet slapd || fallar 'slapd debe estar activo antes de comenzar.'

CONSULTA=$(timeout --kill-after=2s 10s ldapsearch -x -LLL -o nettimeout=5 -l 5 -H ldap://127.0.0.1 -D '' -b "$DN" -s base '(uid=ventas01)' uid) \
    || fallar 'No se pudo comprobar la entrada de ventas01; no se cambió nada.'
[[ $(awk '/^dn: /{n++} END{print n+0}' <<<"$CONSULTA") == 1 ]] || fallar 'No se encontró exactamente la entrada solicitada.'
timeout --kill-after=2s 10s openssl verify -CAfile "$CERT" -purpose sslserver -verify_ip 10.20.0.69 "$CERT" \
    || fallar 'El certificado no pasó la validación.'
echo "[OK] zp-ldap-01 · 10.20.0.69 · $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "[OK] Servicio, herramientas y entrada comprobados: $DN"
if [[ "$MODO" == --validar ]]; then
    echo '[OK] Preparación comprobada; no se modificó la contraseña ni se detuvo slapd.'
    exit 0
fi

[[ -t 0 && -r /dev/tty ]] || fallar 'Usa cambiar desde una terminal interactiva de la instancia.'
echo 'Plan: cambiar solo la contraseña LDAP de ventas01 con una pausa breve de slapd.'
echo 'Se conserva un respaldo privado en /root/final-config/. No se cambia cn=admin, certificados ni reglas.'
read -r -t 120 -p "Escribe si para continuar: " P4_SI < /dev/tty || fallar 'No se recibió confirmación.'
[[ "$P4_SI" == si ]] || { echo 'Cancelado; no se cambió nada.'; exit 0; }

P4_NUEVA=""; P4_CONFIRMACION=""
export -n P4_NUEVA P4_CONFIRMACION
read -r -s -t 120 -p 'Nueva contraseña de laboratorio para ventas01: ' P4_NUEVA < /dev/tty || fallar 'No se recibió la nueva contraseña.'
echo
read -r -s -t 120 -p 'Repite la nueva contraseña: ' P4_CONFIRMACION < /dev/tty || fallar 'No se recibió confirmación de contraseña.'
echo
[[ -n "$P4_NUEVA" && "$P4_NUEVA" == "$P4_CONFIRMACION" ]] || fallar 'Las contraseñas están vacías o no coinciden. No se cambió nada.'

BK="/root/final-config/P4_ldap_respaldo_$(date -u '+%Y%m%dT%H%M%SZ')_$$"
mkdir -p "$BK"
chmod 700 "$BK"
TMP=$(mktemp -d /tmp/p4-ldap-password.XXXXXXXX)
chgrp openldap "$TMP"
chmod 710 "$TMP"
PARADA_SOLICITADA=0
CAMBIO_INTENTADO=0
CONFIRMADO=0

fin() {
    local rc=$? recuperado=1
    trap - EXIT
    set +e
    unset P4_NUEVA P4_CONFIRMACION P4_HASH
    if (( CAMBIO_INTENTADO && ! CONFIRMADO )); then
        echo '[INFO] No se confirmó la nueva contraseña; se intenta restaurar el atributo anterior.'
        timeout --kill-after=2s 15s systemctl stop slapd >> "$BK/diagnostico-privado.txt" 2>&1
        if ! pgrep -x slapd >/dev/null; then
            timeout --kill-after=2s 20s runuser -u openldap -- slapmodify -F "$CONF" -b "$BASE" -l "$TMP/revertir.ldif" >> "$BK/diagnostico-privado.txt" 2>&1
            recuperado=$?
        else
            recuperado=1
        fi
        if (( recuperado == 0 )); then echo '[OK] Atributo de contraseña anterior restaurado.'
        else echo "[FALLA] Restauración automática no confirmada. Conserva el respaldo privado $BK y coordina recuperación local."; fi
        rc=1
    fi
    if (( PARADA_SOLICITADA )); then
        if timeout --kill-after=2s 15s systemctl start slapd >> "$BK/diagnostico-privado.txt" 2>&1 && systemctl is-active --quiet slapd; then
            echo '[OK] slapd activo al finalizar.'
        else
            echo "[FALLA] No se confirmó el inicio de slapd. Diagnóstico privado: $BK/diagnostico-privado.txt"
            rc=1
        fi
    fi
    rm -f -- "$TMP/nueva" "$TMP/cambiar.ldif" "$TMP/revertir.ldif"
    rmdir -- "$TMP"
    exit "$rc"
}
trap fin EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s' "$P4_NUEVA" > "$TMP/nueva"
unset P4_NUEVA P4_CONFIRMACION
P4_HASH=$(timeout --kill-after=2s 10s slappasswd -h '{SSHA}' -T "$TMP/nueva" 2> "$BK/diagnostico-privado.txt") \
    || fallar 'No se pudo generar el hash. No se detuvo el servicio.'
[[ "$P4_HASH" == '{SSHA}'* && "$P4_HASH" != *$'\n'* ]] || fallar 'Formato de hash inesperado; no se cambió nada.'
printf 'dn: %s\nchangetype: modify\nreplace: userPassword\nuserPassword: %s\n' "$DN" "$P4_HASH" > "$TMP/cambiar.ldif"
unset P4_HASH
chgrp openldap "$TMP/cambiar.ldif"
chmod 640 "$TMP/cambiar.ldif"
echo "Respaldo privado: $BK"

PARADA_SOLICITADA=1
timeout --kill-after=2s 15s systemctl stop slapd >> "$BK/diagnostico-privado.txt" 2>&1 || fallar 'No se confirmó la parada; no se aplica la modificación.'
if pgrep -x slapd >/dev/null; then fallar 'slapd sigue ejecutándose; no se abre la base para escritura.'; fi

timeout --kill-after=2s 20s runuser -u openldap -- slapcat -F "$CONF" -b "$BASE" > "$BK/base.ldif" 2>> "$BK/diagnostico-privado.txt" \
    || fallar 'No se pudo respaldar la base; no se cambia la contraseña.'
chmod 600 "$BK/base.ldif"

# Extraer solo los valores originales del atributo, sin imprimirlos. Soporta LDIF plegado/base64.
python3 - "$BK/base.ldif" "$TMP/revertir.ldif" "$DN" <<'PY'
import base64, pathlib, sys
source, output, target = sys.argv[1:]
logical=[]
for line in pathlib.Path(source).read_text().splitlines():
    if line.startswith(' '):
        if not logical: raise SystemExit('LDIF inválido; no se modificó la base.')
        logical[-1]+=line[1:]
    else: logical.append(line)
records=[]; record=[]
for line in logical+['']:
    if line: record.append(line)
    elif record: records.append(record); record=[]
matches=[]
for record in records:
    for line in record:
        if line.startswith('dn:: '): dn=base64.b64decode(line[5:],validate=True).decode()
        elif line.startswith('dn: '): dn=line[4:]
        else: continue
        if dn.lower()==target.lower(): matches.append(record)
        break
if len(matches)!=1: raise SystemExit('El respaldo no contiene exactamente el usuario esperado; no se modificó la base.')
values=[line for line in matches[0] if line.lower().startswith('userpassword:')]
pathlib.Path(output).write_text(f'dn: {target}\nchangetype: modify\nreplace: userPassword\n'+'\n'.join(values)+'\n')
PY
chgrp openldap "$TMP/revertir.ldif"
chmod 640 "$TMP/revertir.ldif"

timeout --kill-after=2s 20s runuser -u openldap -- slapmodify -u -F "$CONF" -b "$BASE" -l "$TMP/cambiar.ldif" >> "$BK/diagnostico-privado.txt" 2>&1 \
    || fallar 'La simulación de la modificación falló; no se cambió la contraseña.'
CAMBIO_INTENTADO=1
timeout --kill-after=2s 20s runuser -u openldap -- slapmodify -F "$CONF" -b "$BASE" -l "$TMP/cambiar.ldif" >> "$BK/diagnostico-privado.txt" 2>&1 \
    || fallar 'No se confirmó la modificación; se intentará restaurar el atributo anterior.'
timeout --kill-after=2s 15s systemctl start slapd >> "$BK/diagnostico-privado.txt" 2>&1 || fallar 'No se confirmó el inicio de slapd.'

BIND_RESULTADO=$(timeout --kill-after=2s 10s env -u LDAPNOINIT LDAPTLS_CACERT="$CERT" LDAPTLS_REQCERT=demand \
    ldapwhoami -x -o nettimeout=5 -H ldaps://10.20.0.69 -D "$DN" -y "$TMP/nueva" 2>> "$BK/diagnostico-privado.txt") \
    || fallar 'El bind con la nueva contraseña falló; se intentará restaurar el atributo anterior.'
[[ "${BIND_RESULTADO,,}" == "dn:${DN,,}" ]] || fallar 'El bind no devuelve el usuario esperado; se intentará restaurar.'
CONFIRMADO=1
echo "[OK] Contraseña de ventas01 cambiada y bind LDAPS confirmado · $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo '[INFO] Guarda la nueva contraseña de laboratorio en tu .env local ignorado por git. No se imprimió ni se guardó en el repositorio.'
