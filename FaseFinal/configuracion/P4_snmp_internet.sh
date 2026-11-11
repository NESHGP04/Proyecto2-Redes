#!/usr/bin/env bash
# Desde CloudShell: consultas a las dos EIP propias; no cambia recursos AWS.
set +x
set +v
set -euo pipefail
umask 077
ulimit -c 0
[[ "$(uname -n)" != zp-* ]] || { echo '[FALLA] Ejecuta desde CloudShell.' >&2; exit 1; }
echo '[PLAN] Consultar UDP 161 en las EIP actuales de Web/VPN desde CloudShell.'
echo '[PLAN] Controles privados desde monitor con las mismas claves; copia temporal privada y limpieza al terminar.'
echo '[PLAN] No cambia servicios, reglas ni recursos AWS; conserva las credenciales originales.'
read -r -p 'Escribe si para continuar: ' p4_respuesta
[[ "$p4_respuesta" == si ]] || { echo '[INFO] Cancelado.'; exit 1; }
python3 - "$HOME" <<'PY'
import hashlib
import importlib.util
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import urllib.request

sys.dont_write_bytecode = True
CORE_SHA256 = '22b74f5e5e2b87b863d30159e9289490d2a94165194a5651a71f274b3eadbc30'
VPC = 'vpc-0e4c1d0b2314ab4df'
NETWORK = ipaddress.ip_network('10.20.0.0/24')
HOSTS = {'zp-web-01': '10.20.0.116', 'zp-vpn-01': '10.20.0.132'}
RUNTIME = None


def check(ok, message):
    if not ok:
        raise RuntimeError(message)


def regular_owned(path):
    check(path.is_file() and not path.is_symlink(), 'Falta archivo regular: ' + str(path))
    info = path.stat()
    check(info.st_uid == os.getuid() and not info.st_mode & 0o022,
          'Propietario/permisos inesperados: ' + str(path))


def load_core(base):
    core = base / 'P4_snmp.py'
    regular_owned(core)
    regular_owned(base / 'P3_eice.sh')
    check(hashlib.sha256(core.read_bytes()).hexdigest() == CORE_SHA256,
          'P4_snmp.py difiere de la versión revisada. No se importó ni se leyeron claves.')
    spec = importlib.util.spec_from_file_location('p4_snmp_internet_core', core)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def destinations(inventory, addresses):
    result = {}
    for reservation in inventory.get('Reservations', []):
        for instance in reservation.get('Instances', []):
            name = next((t['Value'] for t in instance.get('Tags', []) if t['Key'] == 'Name'), '')
            check(name in HOSTS and name not in result, 'Inventario duplicado o ajeno a Web/VPN.')
            check(instance.get('VpcId') == VPC and instance.get('PrivateIpAddress') == HOSTS[name]
                  and instance.get('State', {}).get('Name') == 'running',
                  name + ': VPC/IP/estado difieren del plan.')
            public = instance.get('PublicIpAddress', '')
            check(ipaddress.IPv4Address(public).is_global, name + ': no tiene IPv4 pública válida.')
            enis = {n['NetworkInterfaceId'] for n in instance.get('NetworkInterfaces', [])}
            check(any(a.get('PublicIp') == public and a.get('AllocationId') and a.get('AssociationId')
                      and (a.get('InstanceId') == instance['InstanceId'] or a.get('NetworkInterfaceId') in enis)
                      for a in addresses.get('Addresses', [])), name + ': no se confirmó EIP propia asociada.')
            result[name] = public
    check(set(result) == set(HOSTS), 'Deben encontrarse exactamente Web y VPN.')
    return result


def timed_out(result):
    return (result.returncode != 0 and not result.stdout.strip()
            and bool(re.search(r'timeout|no response', result.stderr, re.I)))


class Probe:
    def __init__(self, base, p4, folder):
        self.base, self.p4, self.folder = base, p4, folder
        self.remote_name = '.env.p4-snmp-internet-' + secrets.token_hex(12)
        self.stage = folder / self.remote_name
        self.remote_possible = False

    def execute(self, argv, timeout=60):
        result = subprocess.run(argv, stdin=subprocess.DEVNULL, capture_output=True,
                                text=True, timeout=timeout)
        with (self.folder / 'transporte-privado.txt').open('a') as stream:
            stream.write(self.p4.clean(result.stdout + '\n' + result.stderr) + '\n')
        return result

    def remote(self, command):
        return self.execute(['bash', str(self.base / 'P3_eice.sh'), 'zp-monitor-01', command])

    def aws(self, service, operation, *args):
        result = self.execute(['aws', service, operation, '--region', 'us-east-1',
                               '--output', 'json', '--no-cli-pager', *args])
        check(result.returncode == 0, operation + ' falló; conservar diagnóstico privado.')
        data = json.loads(result.stdout)
        self.p4.write(self.folder / (operation + '.json'), json.dumps(data, indent=2))
        return data

    def control(self, name, phase):
        path = '"$HOME/' + self.remote_name + '"'
        command = ('sudo -n bash "$HOME/P4_snmp.sh" control --host ' + shlex.quote(name)
                   + ' --credenciales ' + path)
        result = self.remote(command)
        check(result.returncode == 0 and '[OK] Control autenticado desde monitor, exit=0.' in result.stdout
              and 'STRING: "' + name + '"' in result.stdout,
              'Control ' + phase + ' falló: ' + name + '. No se aprueba prueba exterior.')
        self.p4.say('[DATO] Control ' + phase + ' monitor -> ' + name + '\n' + result.stdout.rstrip())

    def cleanup(self):
        self.stage.unlink(missing_ok=True)
        if self.remote_possible:
            path = '"$HOME/' + self.remote_name + '"'
            # El nombre era inexistente antes de copiar; solo se borra ese archivo regular propio.
            command = ('p4_tmp=' + path + '; if [ ! -e "$p4_tmp" ] && [ ! -L "$p4_tmp" ]; then :; '
                       'elif [ -f "$p4_tmp" ] && [ ! -L "$p4_tmp" ] && '
                       '[ "$(stat -c %u "$p4_tmp")" = "$(id -u)" ]; then rm -- "$p4_tmp"; '
                       'else exit 1; fi; test ! -e "$p4_tmp" && test ! -L "$p4_tmp" '
                       '&& echo P4_TEMPORAL_ELIMINADO')
            result = self.remote(command)
            check(result.returncode == 0 and 'P4_TEMPORAL_ELIMINADO' in result.stdout,
                  'Limpieza remota pendiente: ' + self.remote_name + '. No se declara prueba completa.')
            self.remote_possible = False
            self.p4.say('[OK] Copias temporales eliminadas; credenciales originales conservadas.')

    def run(self, values, targets):
        path = '"$HOME/' + self.remote_name + '"'
        absent = self.remote('test ! -e ' + path + ' && test ! -L ' + path + ' && echo P4_TEMPORAL_AUSENTE')
        check(absent.returncode == 0 and 'P4_TEMPORAL_AUSENTE' in absent.stdout,
              'No se confirmó ausencia del archivo temporal remoto; no se copia.')
        try:
            self.p4.write(self.stage, self.p4.envtext(values))
            self.remote_possible = True  # Incluye una posible copia SCP parcial.
            copied = self.execute(['bash', str(self.base / 'P3_eice.sh'), 'zp-monitor-01',
                                   '--copiar', str(self.stage)])
            check(copied.returncode == 0, 'Falló copia temporal privada; no se consulta Internet.')
            secured = self.remote('chmod 600 ' + path + ' && test -s ' + path + ' && echo P4_TEMPORAL_PRIVADO')
            check(secured.returncode == 0 and 'P4_TEMPORAL_PRIVADO' in secured.stdout,
                  'No se confirmó copia temporal privada no vacía.')
            for name in HOSTS:
                self.control(name, 'previo')
            errors = []
            for name, public in targets.items():
                self.p4.say('[CONSULTA] CloudShell exterior -> ' + name + ' EIP ' + public + ', UDP 161, SNMPv3 authPriv.')
                try:
                    result = self.p4.query(values, public)
                    self.p4.say('[DATO] ' + name + ': exit=' + str(result.returncode) + '\n'
                                + result.stdout.rstrip() + '\n' + result.stderr.rstrip())
                    check(timed_out(result), 'Respuesta o error distinto de timeout: ' + name)
                    self.p4.say('[OBSERVADO] ' + name + ': sin datos SNMP, timeout; exit=' + str(result.returncode))
                except (RuntimeError, self.p4.Failure) as error:
                    errors.append(str(error))
            # También se intentan ambos controles posteriores si una consulta pública falla.
            for name in HOSTS:
                try:
                    self.control(name, 'posterior')
                except RuntimeError as error:
                    errors.append(str(error))
            check(not errors, '; '.join(errors))
        finally:
            self.cleanup()
        self.p4.say('[OK] Dos EIP propias sin respuesta desde este origen exterior, con controles privados antes/después y las mismas claves.')
        self.p4.say('[ALCANCE] Un timeout UDP no identifica el dispositivo que filtra ni demuestra todos los orígenes de Internet. Correlacionar con SG/ACL revisados.')


def main():
    global RUNTIME
    os.umask(0o077)
    check(not socket.gethostname().startswith('zp-'), 'Ejecuta desde CloudShell.')
    base = Path(sys.argv[1]).resolve()
    p4 = load_core(base)
    RUNTIME = p4
    p4.tools('aws', 'ip', 'snmpget', 'snmpwalk')
    root = base / 'final-config'
    check(not root.is_symlink(), 'Directorio de registros inesperado.')
    root.mkdir(mode=0o700, exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix='P4_snmp_internet_' + p4.datetime.now(p4.timezone.utc).strftime('%Y%m%dT%H%M%SZ_'), dir=root))
    p4.RUN_DIR = folder
    p4.say('[INFO] Registro público: ' + str(folder / 'resultado.txt'))
    values = p4.private(base / '.config/zenite-p4/.env.p4-snmp')
    probe = Probe(base, p4, folder)
    local = probe.execute(['ip', '-j', '-4', 'addr', 'show'])
    check(local.returncode == 0, 'No se pudo comprobar dirección local.')
    check(not any(ipaddress.IPv4Address(a['local']) in NETWORK
                  for nic in json.loads(local.stdout) for a in nic.get('addr_info', []) if 'local' in a),
          'El origen tiene dirección de la VPC; no se presenta como prueba exterior.')
    with urllib.request.urlopen('https://checkip.amazonaws.com', timeout=15) as response:
        egress = response.read(128).decode().strip()
    check(ipaddress.IPv4Address(egress).is_global, 'No se confirmó salida IPv4 pública.')
    p4.write(folder / 'origen-privado.txt', egress + '\n')
    p4.say('[OK] Origen sin dirección local de la VPC; salida IPv4 pública comprobada por HTTPS (guardada en privado).')
    inventory = probe.aws('ec2', 'describe-instances', '--filters', 'Name=vpc-id,Values=' + VPC,
                          'Name=tag:Name,Values=' + ','.join(HOSTS))
    addresses = probe.aws('ec2', 'describe-addresses')
    probe.run(values, destinations(inventory, addresses))


def interrupted(signum, frame):
    raise RuntimeError('Interrupción recibida; no se considera prueba completa.')


if __name__ == '__main__':
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, interrupted)
    try:
        main()
    except Exception as error:
        message = str(error) if isinstance(error, RuntimeError) else type(error).__name__ + ': conservar diagnóstico privado.'
        if RUNTIME:
            RUNTIME.say('[FALLA] ' + message)
        else:
            print('[FALLA] ' + message, flush=True)
        sys.exit(1)
PY
