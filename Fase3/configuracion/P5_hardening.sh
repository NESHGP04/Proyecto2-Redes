#!/usr/bin/env bash
# P5_hardening.sh - Fase 3, Persona 5
# Hardening de una instancia (se ejecuta DENTRO de cada instancia, por EICE): endurece sshd y desactiva servicios innecesarios.
#   sshd:      PermitRootLogin no, X11Forwarding no, MaxAuthTries 3 (archivo propio 00-zenite-hardening.conf; no se edita sshd_config)
#   servicios: Amazon Linux: atd, gssproxy, libstoragemgmt  |  Ubuntu: ModemManager, multipathd, fwupd, udisks2
# Uso:  bash P5_hardening.sh --validar    (solo lectura; es el modo por defecto)
#       bash P5_hardening.sh aplicar      (muestra el plan y pide confirmacion (si))
#       bash P5_hardening.sh --revertir   (quita el archivo y vuelve a activar los servicios que se desactivaron; pide (si))
# Seguridad: sshd -t antes de recargar (si falla, se borra el archivo y no se recarga); se usa reload, no restart, y las
# sesiones abiertas no se cortan. Deja una segunda sesion de EICE abierta mientras pruebas.
set -euo pipefail

MODO="${1:---validar}"
CONF="/etc/ssh/sshd_config.d/00-zenite-hardening.conf"
ESTADO="/var/lib/zenite-hardening-servicios.txt"
SSHD="$(command -v sshd || echo /usr/sbin/sshd)"
ERRORES=0
ok()    { echo "[OK] $*"; }
falla() { echo "[FALLA] $*"; ERRORES=$((ERRORES+1)); }

. /etc/os-release
if [[ "${ID:-}" == "ubuntu" ]]; then SERV="ModemManager multipathd fwupd udisks2"; else SERV="atd gssproxy libstoragemgmt"; fi
if systemctl is-active --quiet sshd 2>/dev/null; then SSH_SVC=sshd; else SSH_SVC=ssh; fi
echo "Instancia $(hostname) ($(hostname -I | awk '{print $1}')) - ${PRETTY_NAME:-$ID} - servicio SSH: $SSH_SVC"

existe() { [[ -n "$(systemctl list-unit-files "$1.service" --no-legend 2>/dev/null)" ]]; }

validar() {
  local K V
  for P in "permitrootlogin no" "x11forwarding no" "maxauthtries 3" "passwordauthentication no" "pubkeyauthentication yes" "kbdinteractiveauthentication no"; do
    K="${P% *}"
    V=$(sudo "$SSHD" -T | awk -v k="$K" '$1==k {print $2}')
    [[ "$V" == "${P#* }" ]] && ok "sshd $K = $V" || falla "sshd $K = ${V:-?} (esperado ${P#* })"
  done
  for S in $SERV; do
    if ! existe "$S"; then ok "$S no esta instalado"
    elif systemctl is-active --quiet "$S"; then falla "$S sigue activo"
    else ok "$S desactivado"; fi
  done
  echo "--- puertos en escucha ---"; sudo ss -tuln | awk 'NR==1 || /LISTEN|UNCONN/'
}

if [[ "$MODO" == "--validar" ]]; then
  validar
  [[ $ERRORES -eq 0 ]] && echo "Validacion completa sin fallos." || echo "Validacion con $ERRORES fallo(s)."
  exit $ERRORES
fi

if [[ "$MODO" == "aplicar" ]]; then
  echo "Se va a: crear $CONF (PermitRootLogin no, X11Forwarding no, MaxAuthTries 3), recargar $SSH_SVC y desactivar: $SERV"
  read -r -p "Escribe si para continuar: " R
  [[ "${R,,}" == "si" ]] || { echo "Cancelado, no se cambio nada."; exit 0; }
  printf '%s\n' "# P5 hardening (Fase 3)" "PermitRootLogin no" "X11Forwarding no" "MaxAuthTries 3" | sudo tee "$CONF" >/dev/null
  if sudo "$SSHD" -t; then
    sudo systemctl reload "$SSH_SVC" && ok "sshd -t correcto y $SSH_SVC recargado"
  else
    sudo rm -f "$CONF"; falla "sshd -t fallo: se borro $CONF y NO se recargo nada"; exit 1
  fi
  for S in $SERV; do
    if existe "$S" && { systemctl is-active --quiet "$S" || systemctl is-enabled --quiet "$S" 2>/dev/null; }; then
      echo "$S" | sudo tee -a "$ESTADO" >/dev/null
      sudo systemctl disable --now "$S" >/dev/null 2>&1 && ok "$S desactivado" || falla "no se pudo desactivar $S"
    fi
  done
  validar
  [[ $ERRORES -eq 0 ]] && echo "RESULTADO: todo correcto. Abre una sesion NUEVA de EICE para comprobar que sigue entrando." || echo "RESULTADO: $ERRORES fallo(s)."
  exit $ERRORES
fi

if [[ "$MODO" == "--revertir" ]]; then
  echo "Se va a quitar $CONF, recargar $SSH_SVC y volver a activar los servicios desactivados por este script."
  read -r -p "Escribe si para continuar: " R
  [[ "${R,,}" == "si" ]] || { echo "Cancelado, no se cambio nada."; exit 0; }
  sudo rm -f "$CONF"
  sudo "$SSHD" -t && sudo systemctl reload "$SSH_SVC" && ok "$CONF quitado y $SSH_SVC recargado" || falla "sshd -t fallo tras quitar el archivo"
  if [[ -f "$ESTADO" ]]; then
    while read -r S; do
      [[ -n "$S" ]] && { sudo systemctl enable --now "$S" >/dev/null 2>&1 && ok "$S activado de nuevo" || falla "no se pudo activar $S"; }
    done < <(sort -u "$ESTADO")
    sudo rm -f "$ESTADO"
  fi
  [[ $ERRORES -eq 0 ]] && echo "Reversion completa." || echo "Reversion con $ERRORES fallo(s)."
  exit $ERRORES
fi

echo "Modo desconocido: $MODO (usa --validar, aplicar o --revertir)"; exit 1
