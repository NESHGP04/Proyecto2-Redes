#!/usr/bin/env bash
# Grafana privado; descargar en CloudShell, instalar dentro del monitor.
set +x
set +v
set -euo pipefail
umask 077
ulimit -c 0
exec python3 "$(dirname -- "$0")/P4_grafana.py" "$@"
