#!/usr/bin/env bash
# Fedora nativo: puerto local por SSH/EICE, sin publicar Grafana en AWS.
set +x
set +v
set -euo pipefail
umask 077
ulimit -c 0
python3 - "${1:-zenite-ti}" <<'PY'
import json
import os
from pathlib import Path
import re
import shutil
import socket
import stat
import subprocess
import sys
import tempfile

profile = sys.argv[1]
instance = 'i-00e786cb51a422c36'
endpoint = 'eice-0f41a9a04ed4dc3e2'


def check(ok, message):
    if not ok:
        raise RuntimeError(message)


def run(argv):
    result = subprocess.run(argv, capture_output=True, text=True, timeout=45)
    check(result.returncode == 0, Path(argv[0]).name + ' falló; revisa sesión/permisos IAM de TI. No cambies reglas.')
    return result.stdout


try:
    os.umask(0o077)
    check(not socket.gethostname().startswith('zp-'), 'Ejecuta en la terminal nativa de Fedora.')
    check(re.fullmatch(r'[A-Za-z0-9_-]{1,64}', profile), 'Nombre de perfil inesperado.')
    for tool in ['aws', 'ssh', 'ssh-keygen']:
        check(shutil.which(tool), 'Falta ' + tool + ' en Fedora.')
    aws = ['aws', '--profile', profile, '--region', 'us-east-1', '--no-cli-pager']
    check(run(aws + ['sts', 'get-caller-identity', '--query', 'Account', '--output', 'text']).strip() == '703461917799',
          'Cuenta AWS distinta de la del proyecto.')
    data = json.loads(run(aws + ['ec2', 'describe-instances', '--instance-ids', instance, '--output', 'json']))
    rows = [i for r in data['Reservations'] for i in r['Instances']]
    check(len(rows) == 1 and rows[0]['VpcId'] == 'vpc-0e4c1d0b2314ab4df'
          and rows[0]['PrivateIpAddress'] == '10.20.0.103'
          and rows[0]['State']['Name'] == 'running'
          and any(t['Key'] == 'Name' and t['Value'] == 'zp-monitor-01' for t in rows[0].get('Tags', [])),
          'Monitor apagado o distinto del plan.')
    # Comprobar disponibilidad local; ssh vuelve a comprobarla al hacer bind.
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 3000))
    sshdir = Path.home() / '.ssh'
    check(not sshdir.is_symlink(), 'Directorio SSH enlazado; revisar antes de continuar.')
    sshdir.mkdir(mode=0o700, exist_ok=True)
    check(sshdir.stat().st_uid == os.getuid() and not sshdir.stat().st_mode & 0o077,
          'Directorio SSH requiere propietario propio y permisos 700.')
    known = sshdir / 'zenite-p4-known-hosts'
    check(not known.is_symlink(), 'Archivo known_hosts enlazado; revisar.')
    if known.exists():
        check(known.stat().st_uid == os.getuid() and stat.S_IMODE(known.stat().st_mode) == 0o600,
              'known_hosts requiere propietario propio y modo 600.')
    with tempfile.TemporaryDirectory(prefix='p4-grafana-ssh-') as temp:
        key = Path(temp) / 'id_ed25519'
        run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', 'zenite-p4-grafana', '-f', str(key)])
        sent = json.loads(run(aws + ['ec2-instance-connect', 'send-ssh-public-key', '--instance-id', instance,
                                    '--instance-os-user', 'ubuntu', '--ssh-public-key', 'file://' + str(key) + '.pub', '--output', 'json']))
        check(sent.get('Success') is True, 'AWS no confirmó la clave pública temporal.')
        proxy = ('aws --profile ' + profile + ' --region us-east-1 ec2-instance-connect open-tunnel '
                 '--instance-id ' + instance + ' --instance-connect-endpoint-id ' + endpoint
                 + ' --remote-port 22 --max-tunnel-duration 3600')
        print('[INFO] Mantén esta terminal abierta. En tu navegador: http://localhost:3000/d/zenite-snmp', flush=True)
        print('[INFO] Usa zeniteTI y tu contraseña de Grafana. Ctrl+C cierra el túnel; no apaga el monitor.', flush=True)
        status = subprocess.call(['ssh', '-N', '-T', '-i', str(key),
            '-L', '127.0.0.1:3000:127.0.0.1:3000', '-o', 'ExitOnForwardFailure=yes',
            '-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=accept-new',
            '-o', 'UserKnownHostsFile=' + str(known), '-o', 'ConnectTimeout=30',
            '-o', 'ServerAliveInterval=30', '-o', 'ServerAliveCountMax=3',
            '-o', 'ProxyCommand=' + proxy, 'ubuntu@' + instance])
        check(status == 0, 'El túnel terminó con error; conserva el mensaje SSH, sin compartir datos de sesión.')
except KeyboardInterrupt:
    print('\n[INFO] Túnel cerrado; clave SSH temporal local eliminada.')
except Exception as error:
    print('[FALLA] ' + (str(error) if isinstance(error, RuntimeError) else type(error).__name__ + '; revisar entorno local.'))
    sys.exit(1)
PY
