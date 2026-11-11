#!/usr/bin/env bash
# Inventario y reglas actuales, solo describe-*; no enciende instancias ni crea NAT.
set +x
set +v
set -euo pipefail
umask 077
exec python3 "$(dirname -- "$0")/P4_snmp.py" nube "$@"
