#!/usr/bin/env bash
# Restaura archivos P4 vacíos en CloudShell y los vuelve a copiar a Intranet.
# No genera claves ni instala paquetes ni cambia recursos AWS. Copias privadas temporales.
# Uso: bash P4_recuperar_archivos_cloudshell.sh [directorio CloudShell; por defecto HOME]
set +x
set +v
set -euo pipefail
umask 077
ulimit -c 0
[[ "$(uname -n)" != zp-* ]] || { echo '[FALLA] Ejecuta este rescate desde CloudShell, no dentro de una instancia.' >&2; exit 1; }
echo '[PLAN] Respaldar archivos locales, restaurar wrapper/CSV y recuperar las mismas claves desde el monitor.'
echo '[PLAN] Copiar los cuatro archivos corregidos a Intranet. No instala servicios ni modifica reglas.'
read -r -p 'Escribe si para continuar: ' p4_respuesta
[[ "$p4_respuesta" == si ]] || { echo '[INFO] Cancelado sin restaurar archivos.'; exit 1; }
python3 - "${1:-$HOME}" <<'PY'
import importlib.util
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
os.umask(0o077)
base = Path(sys.argv[1]).resolve()
helper = base / 'P3_eice.sh'
core = base / 'P4_snmp.py'
env = base / '.config/zenite-p4/.env.p4-snmp'
wrapper = '''#!/usr/bin/env bash
# Agente/recolección SNMPv3. Copiar también P4_snmp.py y P4_snmp_objetivos.csv.
set +x
set +v
set -euo pipefail
umask 077
ulimit -c 0
exec python3 "$(dirname -- "$0")/P4_snmp.py" agente "$@"
'''
csv = '''host,ip_privada,grupo,sistema_previsto,servicio_principal_a_confirmar
zp-ventas-01,10.20.0.10,zenite-ventas,al2023,sshd
zp-ventas-02,10.20.0.11,zenite-ventas,al2023,sshd
zp-visitantes-01,10.20.0.36,zenite-visitantes,al2023,sshd
zp-ntp-01,10.20.0.68,zenite-servidores,al2023,chronyd
zp-ldap-01,10.20.0.69,zenite-servidores,ubuntu24.04,slapd
zp-intranet-01,10.20.0.71,zenite-servidores,al2023,nginx
zp-ti-01,10.20.0.102,zenite-ti,al2023,sshd
zp-monitor-01,10.20.0.103,zenite-ti,ubuntu24.04,snmpd
zp-web-01,10.20.0.116,zenite-dmz,ubuntu24.04,nginx
zp-vpn-01,10.20.0.132,zenite-vpn,ubuntu24.04,openvpn
'''
public = {base / 'P4_snmp.sh': wrapper, base / 'P4_snmp_objetivos.csv': csv}
run_dir = None
remote_ready = False

def check(ok, message):
    if not ok:
        raise RuntimeError(message)

def owned_file(path):
    check(path.is_file() and not path.is_symlink() and path.stat().st_uid == os.getuid(),
          'Archivo no regular o con otro propietario: ' + path.name)

def command(*args):
    result = subprocess.run(['bash', str(helper), *args], capture_output=True, text=True, timeout=150)
    with (run_dir / 'transporte-privado.txt').open('a') as log:
        log.write(result.stdout + result.stderr)
    check(result.returncode == 0, 'Falló transporte/comprobación remota; conservar el registro privado y compartir solo este mensaje.')

prepare = '''set -eu
umask 077
p4_rescate="$HOME/.env.p4-snmp-rescate"
if [ -e "$p4_rescate" ] || [ -L "$p4_rescate" ]; then
  test -f "$p4_rescate" && test ! -L "$p4_rescate"
  test "$(stat -c %u "$p4_rescate")" = "$(id -u)"
  test "$(stat -c %a "$p4_rescate")" = 600
  sudo -n cmp -s /etc/zenite-p4/snmp.env "$p4_rescate"
else
  sudo -n install -o "$(id -u)" -g "$(id -g)" -m 600 /etc/zenite-p4/snmp.env "$p4_rescate"
fi
test -s "$p4_rescate"
'''
cleanup = '''set -eu
p4_rescate="$HOME/.env.p4-snmp-rescate"
test -f "$p4_rescate" && test ! -L "$p4_rescate"
test "$(stat -c %u "$p4_rescate")" = "$(id -u)"
test "$(stat -c %a "$p4_rescate")" = 600
sudo -n cmp -s /etc/zenite-p4/snmp.env "$p4_rescate"
rm -- "$p4_rescate"
'''
try:
    owned_file(helper)
    check(helper.stat().st_size > 0, 'El ayudante P3 está vacío; requiere recuperar su copia original.')
    owned_file(core)
    import hashlib
    check(hashlib.sha256(core.read_bytes()).hexdigest() == '22b74f5e5e2b87b863d30159e9289490d2a94165194a5651a71f274b3eadbc30',
          'P4_snmp.py no coincide con la versión revisada; subir su copia correcta antes de recuperar.')
    for path, expected in public.items():
        if path.exists() or path.is_symlink():
            owned_file(path)
            check(path.stat().st_size == 0 or path.read_bytes() == expected.encode(),
                  'Archivo público no vacío y distinto; se conserva: ' + path.name)
    for folder in [base / '.config', env.parent, base / 'final-config']:
        if folder.exists() or folder.is_symlink():
            check(folder.is_dir() and not folder.is_symlink() and folder.resolve() == folder
                  and folder.stat().st_uid == os.getuid(), 'Directorio local inesperado: ' + str(folder))
    if env.exists() or env.is_symlink():
        owned_file(env)
    spec = importlib.util.spec_from_file_location('p4_recovery', core)
    p4 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(p4)
    root = base / 'final-config'
    root.mkdir(mode=0o700, exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix='P4_rescate_archivos_', dir=root))
    print('[INFO] Respaldo y diagnóstico privados: ' + str(run_dir), flush=True)
    remote_ready = True
    command('zp-monitor-01', prepare)
    recovered = run_dir / '.env.recuperada-temporal'
    try:
        command('zp-monitor-01', '--traer', '.env.p4-snmp-rescate', str(recovered))
        values = p4.private(recovered)
        if env.exists() and env.stat().st_size:
            check(p4.private(env) == values, 'Credenciales locales distintas del monitor; se conservan sin sobrescribir.')
        for path in [*public, env]:
            if path.exists():
                backup = run_dir / (path.name + '.anterior')
                shutil.copyfile(path, backup)
                backup.chmod(0o600)
        env.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
        env.parent.chmod(0o700)
        for path, content in public.items():
            p4.write(path, content, 0o644)
        p4.write(env, p4.envtext(values))
        p4.private(env)
        print('[OK] Wrapper y CSV restaurados; mismas credenciales del monitor recuperadas con permisos 600.', flush=True)
    finally:
        recovered.unlink(missing_ok=True)
    command('zp-monitor-01', cleanup)
    remote_ready = False
    print('[OK] Copia temporal del monitor eliminada; archivo de servicio conservado.', flush=True)
    command('zp-intranet-01', '--copiar', str(base / 'P4_snmp.sh'), str(core),
            str(base / 'P4_snmp_objetivos.csv'), str(env))
    print('[OK] Archivos corregidos copiados a Intranet. Instalación de snmpd pendiente.', flush=True)
except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired, p4.Failure if 'p4' in globals() else RuntimeError) as error:
    print('[FALLA] ' + str(error), file=sys.stderr)
    sys.exit(1)
finally:
    if remote_ready:
        try:
            command('zp-monitor-01', cleanup)
            print('[OK] Copia temporal del monitor eliminada al finalizar.', flush=True)
        except (OSError, RuntimeError, subprocess.TimeoutExpired):
            print('[PENDIENTE] Comprobar/eliminar solo .env.p4-snmp-rescate del monitor; permisos privados. Conservar diagnóstico.', file=sys.stderr)
PY
