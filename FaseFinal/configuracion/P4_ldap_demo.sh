#!/usr/bin/env bash
# P4 · LDAP por CA explícita. Dentro de la instancia: bash P4_ldap_demo.sh --validar|demo
# --validar: servicio (si es LDAP), certificado y árbol por LDAP/LDAPS; sin contraseña.
# demo: solo Ventas/TI; bind válido, rechazos con exit 49 y tres búsquedas autenticadas.
# No cambia servicios, firewall ni confianza global. Solo escribe log y temporales privados.
set +x
set +v
set -euo pipefail
umask 077

MODO="${1:-}"
[[ $# -eq 1 && ( "$MODO" == --validar || "$MODO" == demo ) ]] || {
    echo 'Uso: bash P4_ldap_demo.sh --validar|demo' >&2
    exit 2
}
P4_SECRETO=""
export -n P4_SECRETO
if [[ "$MODO" == demo ]]; then P4_SECRETO="${LDAP_USER_PASSWORD:-}"; fi
unset LDAP_USER_PASSWORD

IP_LDAP=10.20.0.69
BASE_DN='dc=zenite,dc=internal'
BIND_DN="uid=ventas01,ou=People,$BASE_DN"
HUELLA='A9:AE:94:A9:13:AA:7B:DC:10:FD:03:AF:D2:52:52:92:DD:B6:08:53:7F:72:7C:B2:68:65:F1:66:7F:B1:D5:0F'
FILTRO='(|(objectClass=posixAccount)(objectClass=posixGroup))'
INICIO=$SECONDS
LIMITE_TOTAL=110
TEMP_DIR=""
RESULTADO=""
CODIGO=0

fallar() { printf '[FALLA] %s\n' "$*"; exit 1; }
limpiar() {
    unset P4_SECRETO
    if [[ -n "$TEMP_DIR" ]]; then
        rm -f -- "$TEMP_DIR/correcta" "$TEMP_DIR/incorrecta"
        rmdir -- "$TEMP_DIR"
    fi
}
trap limpiar EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for p4_herramienta in uname ip awk sort openssl timeout ldapsearch date tee; do
    command -v "$p4_herramienta" >/dev/null || fallar "Falta $p4_herramienta; coordina su instalación antes de repetir."
done
HOST=$(uname -n)
case "$HOST" in
    zp-ventas-01) IP_HOST=10.20.0.10; CERT_DEFECTO="$HOME/zenite-ldap.crt" ;;
    zp-ti-01) IP_HOST=10.20.0.102; CERT_DEFECTO="$HOME/zenite-ldap.crt" ;;
    zp-ldap-01) IP_HOST=10.20.0.69; CERT_DEFECTO=/etc/ldap/zenite-ldap.crt ;;
    *) fallar "Host $HOST no autorizado para este guion. Usa zp-ldap-01, zp-ventas-01 o zp-ti-01." ;;
esac
[[ "$MODO" != demo || "$HOST" != zp-ldap-01 ]] || fallar 'demo se ejecuta desde Ventas o TI. En el servidor usa --validar.'
IPS=$(ip -4 -o addr show)
awk -v esperada="$IP_HOST" '{split($4,a,"/"); if(a[1]==esperada) encontrada=1} END{exit !encontrada}' <<<"$IPS" \
    || fallar "$HOST no tiene la IP esperada $IP_HOST; no se inicia ninguna consulta LDAP."

CERT="${P4_LDAP_CERT:-$CERT_DEFECTO}"
[[ -f "$CERT" && -r "$CERT" && -s "$CERT" ]] || fallar "Falta el certificado público legible $CERT. No se desactiva TLS."
if [[ "$MODO" == demo ]]; then
    for p4_herramienta in ldapwhoami mktemp rm rmdir; do
        command -v "$p4_herramienta" >/dev/null || fallar "Falta $p4_herramienta."
    done
fi

OUT_DIR="${P4_OUT_DIR:-$HOME/final-config}"
mkdir -p "$OUT_DIR"
LOG="$OUT_DIR/P4_ldap_${HOST}_${MODO#--}_$(date -u '+%Y%m%dT%H%M%SZ')_$$.txt"
exec > >(tee "$LOG") 2>&1
echo "== P4 LDAP · $HOST · $IP_HOST · $MODO · $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "Registro local: $LOG"
echo "[OK] Host e IP del plan. CA explícita: $CERT"

# Cada operación tiene como máximo 10 s y el presupuesto conjunto es de 110 s.
consultar() {
    local descripcion="$1" restante plazo
    shift
    restante=$((LIMITE_TOTAL - (SECONDS - INICIO) - 2))
    (( restante > 0 )) || fallar 'Se agotó el tiempo total de la demostración; conserva el log y revisa el último paso.'
    plazo=10
    (( restante >= plazo )) || plazo=$restante
    echo "--- $descripcion · $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    printf '+ timeout --kill-after=2s %ss ' "$plazo"
    printf '%q ' "$@"
    printf '\n'
    if RESULTADO=$(timeout --kill-after=2s "${plazo}s" "$@" 2>&1); then CODIGO=0; else CODIGO=$?; fi
    [[ -z "$RESULTADO" ]] || printf '%s\n' "$RESULTADO"
    echo "[INFO] exit=$CODIGO"
}
exigir_exito() {
    case "$CODIGO" in
        0) return ;;
        124|137) fallar "$1: se agotó el tiempo. Comprueba que las instancias sigan encendidas y conserva la salida." ;;
        49) fallar "$1: credenciales rechazadas (49). Verifica la contraseña de laboratorio; no hay reintentos automáticos." ;;
        *) fallar "$1: exit=$CODIGO. Revisa el error anterior, la CA y la conectividad; no se cambió la configuración." ;;
    esac
}
validar_arbol() {
    local dns esperados miembros grupo
    dns=$(awk '/^dn: /{sub(/^dn: /,""); print}' <<<"$RESULTADO" | LC_ALL=C sort)
    esperados=$(printf '%s\n' "cn=ventas,ou=Groups,$BASE_DN" "cn=ti,ou=Groups,$BASE_DN" \
        "uid=ventas01,ou=People,$BASE_DN" "uid=ventas02,ou=People,$BASE_DN" \
        "uid=ti01,ou=People,$BASE_DN" "uid=ti02,ou=People,$BASE_DN" | LC_ALL=C sort)
    [[ "$dns" == "$esperados" ]] || fallar 'El árbol recibido no contiene exactamente los cuatro usuarios y dos grupos del plan. No se acepta un resultado parcial.'
    for grupo in ventas ti; do
        miembros=$(awk -v dn="cn=$grupo,ou=Groups,$BASE_DN" \
            '/^dn: /{activo=($0=="dn: " dn)} activo && /^memberUid: /{print $2}' <<<"$RESULTADO" | LC_ALL=C sort)
        esperados=$(printf '%s\n' "${grupo}01" "${grupo}02" | LC_ALL=C sort)
        [[ "$miembros" == "$esperados" ]] || fallar "Los miembros del grupo $grupo difieren del plan."
    done
    echo '[OK] Cuatro usuarios, dos grupos y sus miembros coinciden con el plan.'
}

consultar 'Certificado público' openssl x509 -in "$CERT" -noout -subject -dates -ext subjectAltName -fingerprint -sha256
exigir_exito 'Lectura del certificado'
HUELLA_REAL=$(awk -F= '/Fingerprint=/{print $NF}' <<<"$RESULTADO")
[[ "$HUELLA_REAL" == "$HUELLA" ]] || fallar 'El certificado no coincide con la huella aprobada. Coordina cualquier renovación antes de actualizar el guion.'
consultar 'Vigencia, confianza y SAN de IP' openssl verify -CAfile "$CERT" -purpose sslserver -verify_ip "$IP_LDAP" "$CERT"
exigir_exito 'Verificación del certificado'

if [[ "$HOST" == zp-ldap-01 ]]; then
    command -v systemctl >/dev/null || fallar 'Falta systemctl.'
    command -v ss >/dev/null || fallar 'Falta ss.'
    consultar 'LDAP-01 · servicio slapd' systemctl is-active slapd
    exigir_exito 'Estado slapd'
    [[ "$RESULTADO" == active ]] || fallar 'slapd no está activo.'
    consultar 'LDAP-01 · escucha TCP 389/636' ss -H -ltn '( sport = :389 or sport = :636 )'
    exigir_exito 'Consulta de puertos'
    for p4_puerto in 389 636; do
        awk -v p=":$p4_puerto" '$4 ~ (p "$"){encontrado=1} END{exit !encontrado}' <<<"$RESULTADO" \
            || fallar "Falta escucha TCP $p4_puerto."
    done
fi

# -D '' fuerza consulta anónima. Nunca hay contraseñas sobre ldap:// (389).
consultar 'Árbol por LDAP 389 · consulta anónima' \
    ldapsearch -x -LLL -o nettimeout=5 -l 5 -H "ldap://$IP_LDAP" -D '' -b "$BASE_DN" "$FILTRO" uid cn memberUid
exigir_exito 'Consulta anónima LDAP 389'
validar_arbol

# LDAPNOINIT deshabilita los valores de ldap.conf y su entorno: quitarlo solo en el hijo.
TLS=(env -u LDAPNOINIT "LDAPTLS_CACERT=$CERT" LDAPTLS_REQCERT=demand)
consultar 'Árbol por LDAPS 636 · CA explícita' \
    "${TLS[@]}" ldapsearch -x -LLL -o nettimeout=5 -l 5 -H "ldaps://$IP_LDAP" -D '' -b "$BASE_DN" "$FILTRO" uid cn memberUid
exigir_exito 'Consulta anónima LDAPS 636'
validar_arbol

if [[ "$MODO" == --validar ]]; then
    echo '[OK] Validación de lectura terminada. Bind, credenciales incorrectas, repetibilidad y bloqueo desde Visitantes se validan por separado.'
    exit 0
fi

if [[ -z "$P4_SECRETO" ]]; then
    [[ -t 0 && -r /dev/tty ]] || fallar 'demo requiere una terminal interactiva para introducir la contraseña de ventas01 de forma oculta.'
    echo '[INFO] Usa la contraseña de laboratorio de ventas01. La entrada permanece oculta; plazo: hasta 20 s.'
    P4_ESPERA=$((LIMITE_TOTAL - (SECONDS - INICIO) - 2))
    (( P4_ESPERA > 0 )) || fallar 'Tiempo total agotado antes de solicitar la contraseña.'
    (( P4_ESPERA <= 20 )) || P4_ESPERA=20
    if ! read -r -s -t "$P4_ESPERA" -p 'Contraseña de ventas01: ' P4_SECRETO < /dev/tty; then
        echo
        fallar 'No se recibió la contraseña dentro del plazo. Ejecuta demo cuando la tengas disponible.'
    fi
    echo
fi
[[ -n "$P4_SECRETO" ]] || fallar 'La contraseña no puede estar vacía.'
TEMP_DIR=$(mktemp -d /tmp/p4-ldap.XXXXXXXX)
printf '%s' "$P4_SECRETO" > "$TEMP_DIR/correcta"
P4_AZAR=$(openssl rand -hex 24)
[[ "$P4_AZAR" != "$P4_SECRETO" ]] || P4_AZAR="${P4_AZAR}x"
printf '%s' "$P4_AZAR" > "$TEMP_DIR/incorrecta"
unset P4_SECRETO P4_AZAR

consultar 'LDAP-04 · bind válido de ventas01 por LDAPS' \
    "${TLS[@]}" ldapwhoami -x -o nettimeout=5 -H "ldaps://$IP_LDAP" -D "$BIND_DN" -y "$TEMP_DIR/correcta"
exigir_exito 'Bind válido'
[[ "${RESULTADO,,}" == "dn:${BIND_DN,,}" ]] || fallar 'El bind no devolvió el DN de ventas01; una respuesta anónima no es un éxito.'
echo '[OK] Bind autenticado devuelve el DN esperado.'

consultar 'LDAP-04 · contraseña incorrecta rechazada' \
    "${TLS[@]}" ldapwhoami -x -o nettimeout=5 -H "ldaps://$IP_LDAP" -D "$BIND_DN" -y "$TEMP_DIR/incorrecta"
[[ "$CODIGO" == 49 ]] || fallar "La contraseña incorrecta debe dar exit=49; se obtuvo $CODIGO. Un timeout o error TLS no acredita rechazo de credenciales."
echo '[OK] Contraseña incorrecta rechazada con exit=49.'

consultar 'Usuario inexistente rechazado' \
    "${TLS[@]}" ldapwhoami -x -o nettimeout=5 -H "ldaps://$IP_LDAP" -D "uid=p4-inexistente,ou=People,$BASE_DN" -y "$TEMP_DIR/incorrecta"
[[ "$CODIGO" == 49 ]] || fallar "El usuario inexistente debe dar exit=49; se obtuvo $CODIGO."
echo '[OK] Usuario inexistente rechazado con exit=49.'

for p4_intento in 1 2 3; do
    consultar "LDAP-R2 · búsqueda autenticada $p4_intento/3 desde $HOST" \
        "${TLS[@]}" ldapsearch -x -LLL -o nettimeout=5 -l 5 -H "ldaps://$IP_LDAP" \
        -D "$BIND_DN" -y "$TEMP_DIR/correcta" -b "$BASE_DN" "$FILTRO" uid cn memberUid
    exigir_exito "Búsqueda autenticada $p4_intento/3"
    validar_arbol
    echo "[OK] LDAP-R2 $p4_intento/3 desde $HOST."
done
echo "[OK] Demo completada desde $HOST · duración $((SECONDS - INICIO)) s · $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo '[INFO] Repite demo desde la otra subred para completar LDAP-R2. LDAP-05 requiere la prueba de Visitantes.'
