#!/usr/bin/env bash
# P3_vpn_servidor.sh - Fase final, Persona 3
# OpenVPN en zp-vpn-01 (10.20.0.132, Ubuntu 24.04): UDP 1194, pool 10.30.0.0/27, autenticacion solo por certificado (easy-rsa),
# tls-crypt, CRL, NAT (MASQUERADE) hacia la VPC y perfil "solo Intranet" (10.20.0.71:80; TI nunca).
# Se ejecuta DENTRO de zp-vpn-01 (por EICE), desde la carpeta vpn/ (junto a zenite.conf y zenite-vpn-up.sh).
# Uso:  sudo bash P3_vpn_servidor.sh --validar            (solo lectura; modo por defecto)
#       sudo bash P3_vpn_servidor.sh instalar             (paquetes, PKI, servidor y servicio; pide confirmacion (si))
#       sudo bash P3_vpn_servidor.sh cliente <nombre>     (certificado de cliente y /root/zenite-clientes/<nombre>.ovpn, modo 600)
#       sudo bash P3_vpn_servidor.sh revocar <nombre>     (revoca el certificado y publica la CRL nueva)
# La llave de la CA, las llaves de los clientes y los .ovpn no se imprimen nunca y no salen de la instancia por este script.
set -euo pipefail

HOST_ESPERADO="zp-vpn-01"
IP_ESPERADA="10.20.0.132"
DIR="$(cd "$(dirname "$0")" && pwd)"
ERSA="/etc/openvpn/easy-rsa"
SRV="/etc/openvpn/server"
CLIENTES="/root/zenite-clientes"
UNIDAD="openvpn-server@zenite"
STATUS="/run/openvpn-server/status-zenite.log"
REMOTOS=("zenite-vpn.dernait.com 1194" "3.228.84.176 1194")   # dominio de P1 y, de respaldo, la Elastic IP
MODO="${1:---validar}"
NOMBRE="${2:-}"

[[ $EUID -eq 0 ]] || { echo "Ejecutar con sudo."; exit 1; }
OUT_DIR="$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)/final-config"
mkdir -p "$OUT_DIR"
exec > >(tee -a "$OUT_DIR/P3_vpn_servidor.log") 2>&1
echo "== P3_vpn_servidor.sh $MODO $NOMBRE · $(uname -n) · $(date -u '+%Y-%m-%d %H:%M:%S') UTC"
ERRORES=0
ok()    { echo "[OK] $*"; }
falla() { echo "[FALLA] $*"; ERRORES=$((ERRORES+1)); }
info()  { echo "[INFO] $*"; }

[[ "$(uname -n)" == "$HOST_ESPERADO" ]] || { falla "Esta instancia es $(uname -n), no $HOST_ESPERADO. No se cambio nada."; exit 1; }
ip -4 -o addr show | grep -q " $IP_ESPERADA/" || { falla "No tiene la IP $IP_ESPERADA. No se cambio nada."; exit 1; }
ok "Instancia $HOST_ESPERADO ($IP_ESPERADA)"

confirmar() { local R; read -r -p "Escribe si para continuar: " R; [[ "${R,,}" == "si" ]] || { echo "Cancelado, no se cambio nada."; exit 0; }; }
easyrsa() { (cd "$ERSA" && ./easyrsa --batch "$@"); }
nombre_valido() {
  [[ "$NOMBRE" =~ ^[a-z0-9][a-z0-9-]{2,31}$ && "$NOMBRE" != "$HOST_ESPERADO" ]] \
    || { falla "Nombre de cliente invalido: '$NOMBRE' (3 a 32 caracteres: minusculas, numeros y guiones)"; exit 1; }
}
modo_de() { stat -c %a "$1" 2>/dev/null || echo "no-existe"; }
publicar_crl() { install -m 644 "$ERSA/pki/crl.pem" "$SRV/crl.pem"; }

validar() {
  local V F M L N
  for P in openvpn easy-rsa iptables; do
    dpkg -s "$P" >/dev/null 2>&1 && ok "paquete $P instalado" || falla "falta el paquete $P"
  done
  command -v openvpn >/dev/null && info "$(openvpn --version | head -1)"
  systemctl is-active --quiet "$UNIDAD" && ok "servicio $UNIDAD activo" || falla "servicio $UNIDAD no esta activo"
  systemctl is-enabled --quiet "$UNIDAD" 2>/dev/null && ok "servicio $UNIDAD habilitado al arranque" || falla "servicio $UNIDAD no esta habilitado"
  ss -Hlun 'sport = :1194' | grep -q . && ok "UDP 1194 en escucha: $(ss -Hlun 'sport = :1194' | awk '{print $4}' | paste -sd' ' -)" || falla "nada escucha en UDP 1194"
  V=$(ip -4 -o addr show dev tun0 2>/dev/null | awk '{print $4}')
  [[ "$V" == "10.30.0.1/27" ]] && ok "tun0 = $V (pool 10.30.0.0/27)" || falla "tun0 = ${V:-no existe} (esperado 10.30.0.1/27)"
  [[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]] && ok "net.ipv4.ip_forward = 1" || falla "net.ipv4.ip_forward no es 1"
  iptables -t nat -C POSTROUTING -s 10.30.0.0/27 -d 10.20.0.0/24 -j MASQUERADE 2>/dev/null && ok "NAT: MASQUERADE 10.30.0.0/27 -> 10.20.0.0/24" || falla "falta el MASQUERADE"
  iptables -C FORWARD -i tun+ -j ZENITE-VPN-FWD 2>/dev/null && ok "FORWARD desde tun+ pasa por ZENITE-VPN-FWD" || falla "falta el salto FORWARD -> ZENITE-VPN-FWD"
  iptables -C INPUT -i tun+ -j ZENITE-VPN-IN 2>/dev/null && ok "INPUT desde tun+ pasa por ZENITE-VPN-IN" || falla "falta el salto INPUT -> ZENITE-VPN-IN"
  L=$(iptables -S ZENITE-VPN-FWD 2>/dev/null | grep -- '-A' | paste -sd'|' -)
  [[ "$L" == "-A ZENITE-VPN-FWD -d 10.20.0.96/28 -j DROP|-A ZENITE-VPN-FWD -d 10.20.0.71/32 -p tcp -m tcp --dport 80 -j ACCEPT|-A ZENITE-VPN-FWD -j DROP" ]] \
    && ok "perfil: TI bloqueado, solo TCP 80 hacia 10.20.0.71, resto bloqueado" || falla "perfil ZENITE-VPN-FWD inesperado: ${L:-vacio}"
  for F in "ca.crt 644" "zp-vpn-01.crt 644" "zp-vpn-01.key 600" "tls-crypt.key 600" "crl.pem 644" "zenite.conf 644" "zenite-vpn-up.sh 755"; do
    M=$(modo_de "$SRV/${F% *}")
    [[ "$M" == "${F#* }" ]] && ok "$SRV/${F% *} modo $M" || falla "$SRV/${F% *} modo $M (esperado ${F#* })"
  done
  M=$(modo_de "$ERSA/pki/private/ca.key"); [[ "$M" == "600" ]] && ok "llave de la CA solo para root (modo 600)" || falla "llave de la CA: modo $M"
  M=$(modo_de "$ERSA"); [[ "$M" == "700" ]] && ok "$ERSA modo 700" || falla "$ERSA modo $M (esperado 700)"
  for L in "tls-crypt /etc/openvpn/server/tls-crypt.key" "crl-verify /etc/openvpn/server/crl.pem" "verify-client-cert require" "remote-cert-tls client" "tls-version-min 1.2"; do
    grep -qx "$L" "$SRV/zenite.conf" 2>/dev/null && ok "zenite.conf: $L" || falla "zenite.conf sin '$L'"
  done
  if [[ -f "$SRV/crl.pem" ]]; then
    V=$(openssl crl -in "$SRV/crl.pem" -noout -nextupdate | cut -d= -f2)
    (( $(date -d "$V" +%s) > $(date +%s) )) && ok "CRL vigente hasta $V" || falla "CRL vencida ($V)"
    N=$(openssl crl -in "$SRV/crl.pem" -noout -text | grep -c 'Serial Number' || true)
    info "certificados revocados en la CRL: $N"
  fi
  [[ -d "$CLIENTES" ]] && info "perfiles generados (solo nombres): $(cd "$CLIENTES" && ls -1 *.ovpn 2>/dev/null | paste -sd' ' -)"
  if [[ -f "$STATUS" ]]; then
    N=$(grep -c '^CLIENT_LIST' "$STATUS" || true)
    info "clientes conectados: $N $(awk -F, '/^CLIENT_LIST/ {printf "%s=%s ", $2, $4}' "$STATUS")"
  fi
}

if [[ "$MODO" == "--validar" ]]; then
  validar
  [[ $ERRORES -eq 0 ]] && echo "RESULTADO: todo correcto." || echo "RESULTADO: $ERRORES fallo(s)."
  exit $ERRORES
fi

if [[ "$MODO" == "instalar" ]]; then
  for F in zenite.conf zenite-vpn-up.sh; do [[ -f "$DIR/$F" ]] || { falla "Falta $DIR/$F"; exit 1; }; done
  echo "Se va a: instalar openvpn, easy-rsa e iptables (apt); crear la PKI en $ERSA si no existe (CA, servidor $HOST_ESPERADO, CRL);"
  echo "         crear tls-crypt.key; copiar zenite.conf y zenite-vpn-up.sh a $SRV; activar ip_forward; habilitar y reiniciar $UNIDAD."
  confirmar
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -q && apt-get install -y -q openvpn easy-rsa iptables
  if [[ ! -f "$ERSA/pki/ca.crt" ]]; then
    [[ -x "$ERSA/easyrsa" ]] || make-cadir "$ERSA"
    chmod 700 "$ERSA"
    easyrsa init-pki
    easyrsa --use-algo=ec --curve=prime256v1 --req-cn="Zenite Prestige VPN CA" build-ca nopass
    easyrsa --use-algo=ec --curve=prime256v1 build-server-full "$HOST_ESPERADO" nopass
    easyrsa gen-crl
    ok "PKI creada en $ERSA (CA, certificado de servidor $HOST_ESPERADO y CRL)"
  else ok "La PKI ya existe; se conserva"; fi
  chmod 700 "$ERSA"
  install -d -m 755 "$SRV"
  install -m 644 "$ERSA/pki/ca.crt" "$SRV/ca.crt"
  install -m 644 "$ERSA/pki/issued/$HOST_ESPERADO.crt" "$SRV/$HOST_ESPERADO.crt"
  install -m 600 "$ERSA/pki/private/$HOST_ESPERADO.key" "$SRV/$HOST_ESPERADO.key"
  publicar_crl
  [[ -f "$SRV/tls-crypt.key" ]] || openvpn --genkey secret "$SRV/tls-crypt.key"
  chmod 600 "$SRV/tls-crypt.key"
  install -m 644 "$DIR/zenite.conf" "$SRV/zenite.conf"
  install -m 755 "$DIR/zenite-vpn-up.sh" "$SRV/zenite-vpn-up.sh"
  echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-zenite-vpn.conf
  sysctl -q -p /etc/sysctl.d/99-zenite-vpn.conf
  systemctl enable "$UNIDAD" >/dev/null 2>&1
  systemctl restart "$UNIDAD"
  sleep 3
  validar
  [[ $ERRORES -eq 0 ]] && echo "RESULTADO: todo correcto." || echo "RESULTADO: $ERRORES fallo(s). Revisar: journalctl -u $UNIDAD -n 50"
  exit $ERRORES
fi

if [[ "$MODO" == "cliente" ]]; then
  nombre_valido
  [[ -f "$SRV/tls-crypt.key" ]] || { falla "Primero: instalar"; exit 1; }
  if [[ -f "$ERSA/pki/issued/$NOMBRE.crt" ]]; then ok "El certificado de $NOMBRE ya existe; se reutiliza"
  else easyrsa --use-algo=ec --curve=prime256v1 build-client-full "$NOMBRE" nopass; ok "Certificado de cliente $NOMBRE creado"; fi
  umask 077; mkdir -p "$CLIENTES"
  {
    echo "# Perfil OpenVPN de Zenite Prestige para $NOMBRE. Contiene la llave privada: NO subir al repositorio ni enviar por chat."
    echo "client"; echo "dev tun"; echo "proto udp"
    for R in "${REMOTOS[@]}"; do echo "remote $R"; done
    printf '%s\n' "resolv-retry infinite" "nobind" "persist-key" "persist-tun" "remote-cert-tls server" \
      "verify-x509-name $HOST_ESPERADO name" "tls-version-min 1.2" "data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305" "verb 3"
    echo "<ca>";        cat "$SRV/ca.crt";                                                   echo "</ca>"
    echo "<cert>";      openssl x509 -in "$ERSA/pki/issued/$NOMBRE.crt";                     echo "</cert>"
    echo "<key>";       cat "$ERSA/pki/private/$NOMBRE.key";                                 echo "</key>"
    echo "<tls-crypt>"; cat "$SRV/tls-crypt.key";                                            echo "</tls-crypt>"
  } > "$CLIENTES/$NOMBRE.ovpn"
  chmod 600 "$CLIENTES/$NOMBRE.ovpn"
  ok "Perfil $CLIENTES/$NOMBRE.ovpn ($(stat -c %s "$CLIENTES/$NOMBRE.ovpn") bytes, modo 600). No se imprime: entregarlo por un medio seguro."
  exit 0
fi

if [[ "$MODO" == "revocar" ]]; then
  nombre_valido
  [[ -f "$ERSA/pki/issued/$NOMBRE.crt" ]] || { falla "No hay un certificado vigente de $NOMBRE"; exit 1; }
  echo "Se va a REVOCAR el certificado de $NOMBRE: ese perfil ya no podra conectarse."
  confirmar
  easyrsa revoke "$NOMBRE"
  easyrsa gen-crl
  publicar_crl
  ok "Certificado de $NOMBRE revocado; CRL publicada en $SRV/crl.pem (OpenVPN la lee en cada conexion nueva)"
  exit 0
fi

echo "Modo desconocido: $MODO (usa --validar, instalar, cliente <nombre> o revocar <nombre>)"; exit 1
