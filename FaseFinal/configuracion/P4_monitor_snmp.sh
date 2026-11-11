#!/usr/bin/env bash
# Prometheus y snmp_exporter privados. Grafana se instala en el checkpoint 6.
set +x
set +v
set -euo pipefail
umask 077
ulimit -c 0
exec python3 "$(dirname -- "$0")/P4_snmp.py" monitor "$@"
