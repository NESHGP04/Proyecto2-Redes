#!/usr/bin/env bash
# Agente/recolección SNMPv3. Copiar también P4_snmp.py y P4_snmp_objetivos.csv.
set +x
set +v
set -euo pipefail
umask 077
ulimit -c 0
exec python3 "$(dirname -- "$0")/P4_snmp.py" agente "$@"
