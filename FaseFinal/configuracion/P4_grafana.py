#!/usr/bin/env python3
"""Checkpoint 6: Grafana OSS privado, sin instalar paquetes ni modificar AWS."""
import argparse
import base64
from datetime import datetime, timezone
import fcntl
import getpass
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import secrets
import shutil
import signal
import socket
import stat
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
CORE_SHA256 = '22b74f5e5e2b87b863d30159e9289490d2a94165194a5651a71f274b3eadbc30'
VERSION = '13.3.0'
ARCHIVE = 'grafana_13.3.0_40412481033_linux_amd64.tar.gz'
URL = 'https://dl.grafana.com/grafana/release/13.3.0/' + ARCHIVE
SHA256 = 'cec8f98cc59bc1a1945833b652371a073be678c5c159a9b1695ad63c04fae5a7'
CONF = Path('/etc/zenite-p4-grafana')
DATA = Path('/var/lib/zenite-p4-grafana')
LIB = Path('/usr/local/lib/zenite-p4-grafana')
UNIT = Path('/etc/systemd/system/p4-grafana.service')
MARKER = CONF / 'instalado.json'
FAILED = CONF / 'instalacion.failed'
ADMIN = 'zeniteTI'
DS_UID = 'zenite-prometheus'
DASH_UID = 'zenite-snmp'
p4 = None


def check(ok, message):
    if not ok:
        raise RuntimeError(message)


def core():
    path = HERE / 'P4_snmp.py'
    check(path.is_file() and not path.is_symlink()
          and not path.stat().st_mode & 0o022
          and path.stat().st_uid in {0, os.getuid(), int(os.environ.get('SUDO_UID', os.getuid()))},
          'Módulo SNMP ausente o con propietario/permisos inesperados.')
    check(hashlib.sha256(path.read_bytes()).hexdigest() == CORE_SHA256, 'Módulo SNMP distinto del revisado.')
    spec = importlib.util.spec_from_file_location('p4_grafana_core', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha_file(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def verified(path):
    check(path.is_file() and not path.is_symlink(), 'Paquete debe ser archivo regular, sin enlaces.')
    check(sha_file(path) == SHA256, 'SHA-256 del paquete no coincide con la publicación oficial.')


def extract(archive, parent):
    stem = 'grafana-' + VERSION
    members = archive.getmembers()
    check(members and sum(m.size for m in members) < 4 * 1024 ** 3, 'Paquete vacío o demasiado grande.')
    for member in members:
        path = Path(member.name)
        check(not path.is_absolute() and '..' not in path.parts and path.parts[0] == stem
              and (member.isfile() or member.isdir()), 'Miembro inesperado en paquete; no se extrae.')
    archive.extractall(parent, members=members)
    for path in [parent / stem, *(parent / stem).rglob('*')]:
        if os.geteuid() == 0:
            os.chown(path, 0, 0)
        os.chmod(path, 0o755 if path.is_dir() or path.stat().st_mode & 0o111 else 0o644)
    return parent / stem


def download():
    check(not socket.gethostname().startswith('zp-'), 'Descarga desde CloudShell, no desde una instancia.')
    target = Path.home() / ARCHIVE
    if target.exists() or target.is_symlink():
        verified(target)
        p4.say('[OK] Paquete existente verificado: ' + str(target))
        return
    check(shutil.disk_usage(target.parent).free > 600 * 1024 ** 2, 'Se requieren 600 MiB libres para la descarga.')
    p4.say('[PLAN] Descargar Grafana OSS ' + VERSION + ' oficial en CloudShell (~460 MiB), sin modificar AWS.')
    fd, name = tempfile.mkstemp(prefix='.p4-grafana-', dir=target.parent)
    try:
        with os.fdopen(fd, 'wb') as stream, urllib.request.urlopen(URL, timeout=60) as response:
            total = 0
            while True:
                block = response.read(1024 * 1024)
                if not block:
                    break
                total += len(block)
                check(total <= 600 * 1024 ** 2, 'Descarga excede tamaño máximo previsto.')
                stream.write(block)
        verified(Path(name))
        os.replace(name, target)
        p4.say('[OK] Descarga y SHA-256 oficial correctos: ' + str(target))
    finally:
        Path(name).unlink(missing_ok=True)


def dashboard():
    selector = 'job="snmp",host=~"$host"'
    panels = []

    def panel(title, expr, kind='timeseries', unit='short', legend='{{host}}', description=''):
        index = len(panels)
        item = {'id': index + 1, 'title': title, 'type': kind, 'description': description,
                'datasource': {'type': 'prometheus', 'uid': DS_UID},
                'gridPos': {'x': (index % 2) * 12, 'y': (index // 2) * 8, 'w': 12, 'h': 8},
                'targets': [{'refId': 'A', 'expr': expr, 'legendFormat': legend, 'range': kind == 'timeseries',
                             'instant': kind != 'timeseries', 'datasource': {'type': 'prometheus', 'uid': DS_UID}}],
                'fieldConfig': {'defaults': {'unit': unit}, 'overrides': []},
                'options': {'legend': {'displayMode': 'list', 'placement': 'bottom'}}}
        if kind == 'stat':
            item['options'] = {'reduceOptions': {'calcs': ['lastNotNull'], 'fields': '', 'values': False},
                               'colorMode': 'background', 'graphMode': 'none', 'textMode': 'auto'}
        panels.append(item)
        return item

    availability = panel('Respuesta SNMP por host', 'up{' + selector + '}', 'stat', description='0: sin respuesta; no equivale por sí solo a EC2 apagada. Revisar también recolector.')
    availability['fieldConfig']['defaults'].update({'min': 0, 'max': 1, 'mappings': [
        {'type': 'value', 'options': {'0': {'text': 'Sin respuesta', 'color': 'red'}, '1': {'text': 'Responde', 'color': 'green'}}}]})
    collector = panel('Recolector SNMP', 'up{job="snmp_exporter"}', 'stat', legend='Recolector')
    collector['fieldConfig']['defaults']['mappings'] = availability['fieldConfig']['defaults']['mappings']
    panel('CPU media por host', 'avg by(host) (hrProcessorLoad{' + selector + '})', unit='percent', description='Carga porcentual informada por cada procesador, media por host; promedio aproximado del último minuto.')
    panel('RAM física utilizada', '100 * hrStorageUsed{' + selector + ',hrStorageDescr="Physical memory"} / hrStorageSize{' + selector + ',hrStorageDescr="Physical memory"}', unit='percent')
    incoming = panel('Tráfico recibido', '8 * rate(ifHCInOctets{' + selector + ',ifName!="lo"}[2m])', unit='bps', legend='{{host}} · {{ifName}}', description='Necesita dos o más muestras. Ausencia de datos no se sustituye por cero.')
    outgoing = panel('Tráfico enviado', '8 * rate(ifHCOutOctets{' + selector + ',ifName!="lo"}[2m])', unit='bps', legend='{{host}} · {{ifName}}', description=incoming['description'])
    panel('Disco raíz utilizado', 'dskPercent{' + selector + ',dskPath="/"}', unit='percent')
    panel('Uptime del agente SNMP', 'sysUpTime{' + selector + '} / 100', 'stat', 's', description='Tiempo del agente SNMP, no necesariamente uptime del sistema operativo.')
    down = panel('Hosts sin respuesta SNMP', 'count(up{' + selector + '} == 0) or vector(0)', 'stat', legend='Sin respuesta', description='Estado visible para GRAF-03; revisar recolector, EC2, red y agente. Incluye paradas intencionales.')
    down['fieldConfig']['defaults']['thresholds'] = {'mode': 'absolute', 'steps': [{'color': 'green', 'value': None}, {'color': 'red', 'value': 1}]}
    panel('Procesos declarados', 'prCount{' + selector + '}', 'stat', legend='{{host}} · {{prNames}}')
    return {'id': None, 'uid': DASH_UID, 'title': 'Zenite · Monitoreo SNMP', 'tags': ['zenite', 'p4', 'snmp'],
            'schemaVersion': 39, 'version': 1, 'editable': False, 'timezone': 'browser', 'refresh': '30s',
            'time': {'from': 'now-30m', 'to': 'now'}, 'panels': panels,
            'templating': {'list': [{'name': 'host', 'label': 'Host', 'type': 'query',
                'datasource': {'type': 'prometheus', 'uid': DS_UID},
                'query': 'label_values(up{job="snmp"}, host)', 'refresh': 1, 'multi': True,
                'includeAll': True, 'allValue': '.*', 'current': {'text': 'All', 'value': '$__all'}, 'sort': 1}]}}


def configuration():
    return f'''[paths]
data = {DATA}
logs = {DATA}/logs
plugins = {DATA}/plugins
provisioning = {CONF}/provisioning
[server]
protocol = http
http_addr = 127.0.0.1
http_port = 3000
domain = localhost
root_url = http://localhost:3000/
[security]
admin_user = {ADMIN}
admin_password = $__file{{{CONF}/admin-password}}
secret_key = $__file{{{CONF}/secret-key}}
disable_gravatar = true
cookie_samesite = strict
allow_embedding = false
[auth.anonymous]
enabled = false
[users]
allow_sign_up = false
allow_org_create = false
[analytics]
reporting_enabled = false
check_for_updates = false
check_for_plugin_updates = false
[plugins]
preinstall_disabled = true
public_key_retrieval_disabled = true
[log]
mode = console
level = warn
'''


def unit():
    return f'''[Unit]
Description=Zenite P4 Grafana privado
After=network-online.target p4-prometheus.service
Wants=network-online.target
[Service]
User=p4grafana
Group=p4grafana
WorkingDirectory={LIB}
ExecStart={LIB}/bin/grafana server --homepath={LIB} --config={CONF}/grafana.ini
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths={DATA}
UMask=0077
MemoryMax=768M
[Install]
WantedBy=multi-user.target
'''


def api(path, password=None):
    headers = {}
    if password is not None:
        headers['Authorization'] = 'Basic ' + base64.b64encode((ADMIN + ':' + password).encode()).decode()
    request = urllib.request.Request('http://127.0.0.1:3000' + path, headers=headers)
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def admin_password():
    path = CONF / 'admin-password'
    check(path.is_file() and not path.is_symlink() and path.stat().st_uid == 0
          and stat.S_IMODE(path.stat().st_mode) == 0o640
          and path.stat().st_gid == pwd.getpwnam('p4grafana').pw_gid, 'Archivo de contraseña con permisos inesperados.')
    value = path.read_text().strip()
    p4.SECRETS.append(value)
    return value


def validate():
    check(MARKER.is_file() and not MARKER.is_symlink(), 'No hay instalación completa P4 de Grafana.')
    previous = json.loads(MARKER.read_text())
    check(previous['version'] == VERSION, 'Versión de instalación distinta.')
    for name, digest in previous['files'].items():
        path = Path(name)
        check(path.is_file() and not path.is_symlink() and sha_file(path) == digest, 'Archivo Grafana modificado: ' + name)
    p4.run(['systemctl', 'is-active', '--quiet', 'p4-grafana'])
    sockets = p4.run(['ss', '-H', '-ltn', 'sport = :3000']).stdout.splitlines()
    check(len(sockets) == 1 and sockets[0].split()[3] == '127.0.0.1:3000', 'Grafana no escucha exclusivamente en loopback.')
    health = api('/api/health')
    check(health.get('database') == 'ok' and health.get('version') == VERSION, 'Grafana o SQLite sin salud/version esperadas.')
    try:
        api('/api/user')
    except urllib.error.HTTPError as error:
        check(error.code == 401, 'Respuesta anónima inesperada.')
    else:
        raise RuntimeError('Grafana permitió acceso anónimo autenticado.')
    password = admin_password()
    source = api('/api/datasources/uid/' + DS_UID, password)
    check(source.get('url') == 'http://127.0.0.1:9090' and source.get('type') == 'prometheus', 'Fuente de datos distinta del Prometheus local.')
    doc = api('/api/dashboards/uid/' + DASH_UID, password)['dashboard']
    check(doc.get('uid') == DASH_UID and len(doc.get('panels', [])) >= 10, 'Dashboard esperado no está provisionado.')
    # Comprueba consultas reales en Prometheus, sin confundir el JSON del panel con datos.
    targets = json.loads(p4.http('/api/v1/query?query=' + urllib.parse.quote('up{job="snmp"}')))['data']['result']
    check({t['metric'].get('host'): t['metric'].get('instance') for t in targets} == p4.IPS,
          'Prometheus no devuelve los diez objetivos previstos.')
    for target in sorted(targets, key=lambda t: t['metric']['host']):
        p4.say('[ESTADO] ' + target['metric']['host'] + ': respuesta SNMP=' + target['value'][1])
    p4.say('[OK] Grafana ' + VERSION + ' activo en 127.0.0.1:3000, autenticación exigida, diez paneles y Prometheus local.')
    p4.say('[PENDIENTE] GRAF-01/02/03 requieren además navegador por túnel, capturas reales y rechazo desde Ventas; esta validación local no los cierra.')


def preflight():
    p4.guard(monitor=True)
    check(os.uname().machine == 'x86_64', 'Paquete revisado solo para x86_64.')
    p4.monitor_validate()
    free = shutil.disk_usage('/').free // 1024 ** 2
    memory = dict(line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines())
    available = int(memory['MemAvailable'].split()[0]) // 1024
    p4.say(f'[INFO] Monitor Ubuntu x86_64; raíz libre={free} MiB; RAM disponible={available} MiB.')
    check(free >= 4096 and available >= 600, 'Se requieren 4 GiB de disco y 600 MiB de RAM disponible para instalar.')
    if MARKER.exists():
        validate()
        return
    check(not FAILED.exists(), 'Instalación Grafana previa parcial; conservar registro y revisar antes de reintentar.')
    for path in [CONF, DATA, LIB, UNIT, Path('/etc/grafana'), Path('/usr/share/grafana')]:
        check(not path.exists() and not path.is_symlink(), 'Configuración/instalación preexistente: ' + str(path))
    check(p4.run(['getent', 'passwd', 'p4grafana'], required=False).returncode == 2,
          'Usuario de servicio ya existe o no se pudo comprobar.')
    check(not p4.run(['ss', '-H', '-ltn', 'sport = :3000']).stdout.strip(), 'Puerto 3000 ya ocupado.')
    p4.say('[OK] Preflight de solo lectura; agente/recolector conservados, sin instalación Grafana previa.')


def origin():
    check(socket.gethostname() == 'zp-ventas-01', 'Prueba de origen solo desde Ventas-01.')
    try:
        with socket.create_connection(('10.20.0.103', 3000), timeout=5):
            pass
    except (TimeoutError, ConnectionRefusedError, socket.timeout, ConnectionResetError):
        # AL2023/Python 3.9 eleva socket.timeout; 3.10+ lo alias a TimeoutError.
        p4.say('[OBSERVADO] Ventas-01 no puede conectar a 10.20.0.103:3000.')
        p4.say('[PENDIENTE] Correlacionar con controles locales del monitor antes/después y acceso por túnel TI; este intento aislado no cierra GRAF-02.')
    else:
        raise RuntimeError('Ventas logró conexión TCP a Grafana; no se aprueba aislamiento.')


def install(package):
    preflight()
    if MARKER.exists():
        return
    verified(package)
    p4.confirm('Instalar Grafana OSS ' + VERSION + ' desde paquete local verificado; crear solo p4grafana, sus directorios/unidad y dashboard. Escucha 127.0.0.1:3000. No cambia SNMP, Prometheus ni AWS.')
    check(sys.stdin.isatty(), 'Conecta interactivamente por EICE para introducir la contraseña oculta.')
    password = getpass.getpass('Nueva contraseña de laboratorio para Grafana (16–128 caracteres, entrada oculta): ')
    p4.SECRETS.append(password)
    check(16 <= len(password) <= 128 and password.isascii() and all(33 <= ord(c) <= 126 for c in password),
          'Usa 16–128 caracteres ASCII sin espacios.')
    check(password == getpass.getpass('Repite la nueva contraseña: '), 'Contraseñas distintas; no se instaló.')
    # Verificar/extractar en espacio temporal antes de crear usuario/configuración.
    with tempfile.TemporaryDirectory(prefix='p4-grafana-') as tmp:
        with tarfile.open(package) as archive:
            extracted = extract(archive, Path(tmp))
        check((extracted / 'bin/grafana').is_file() and (extracted / 'conf/defaults.ini').is_file(), 'Faltan binario/defaults en paquete.')
        try:
            p4.run(['useradd', '--system', '--user-group', '--no-create-home', '--shell', '/usr/sbin/nologin', 'p4grafana'])
            account = pwd.getpwnam('p4grafana')
            CONF.mkdir(mode=0o750)
            os.chown(CONF, 0, account.pw_gid)
            p4.write(FAILED, 'Instalación parcial de Grafana; conservar diagnóstico y revisar antes de reintentar.\n')
            DATA.mkdir(mode=0o700)
            os.chown(DATA, account.pw_uid, account.pw_gid)
            shutil.move(str(extracted), str(LIB))
            tracked = []

            def config(relative, value):
                path = CONF / relative
                if not path.parent.exists():
                    path.parent.mkdir(parents=True)
                # Solo son directorios de configuración del nuevo servicio.
                for parent in [path.parent, *path.parent.parents]:
                    if parent == CONF.parent:
                        break
                    os.chmod(parent, 0o750)
                    os.chown(parent, 0, account.pw_gid)
                p4.write(path, value, 0o640)
                os.chown(path, 0, account.pw_gid)
                tracked.append(path)

            config('admin-password', password + '\n')
            config('secret-key', secrets.token_urlsafe(48) + '\n')
            config('grafana.ini', configuration())
            config('dashboard/zenite.json', json.dumps(dashboard(), ensure_ascii=False, indent=2))
            config('provisioning/datasources/zenite.yml', json.dumps({'apiVersion': 1, 'datasources': [
                {'name': 'Zenite Prometheus', 'uid': DS_UID, 'type': 'prometheus', 'access': 'proxy',
                 'url': 'http://127.0.0.1:9090', 'isDefault': True, 'editable': False,
                 'jsonData': {'timeInterval': '30s', 'httpMethod': 'POST'}}]}))
            config('provisioning/dashboards/zenite.yml', json.dumps({'apiVersion': 1, 'providers': [
                {'name': 'zenite', 'folder': 'Zenite', 'type': 'file', 'disableDeletion': True,
                 'allowUiUpdates': False, 'updateIntervalSeconds': 30, 'options': {'path': str(CONF / 'dashboard')}}]}))
            p4.write(UNIT, unit(), 0o644)
            tracked.append(UNIT)
            p4.run(['systemctl', 'daemon-reload'])
            p4.run(['systemctl', 'enable', '--now', 'p4-grafana'], timeout=45)
            for attempt in range(45):
                try:
                    if api('/api/health').get('database') == 'ok':
                        break
                except (OSError, ValueError):
                    pass
                time.sleep(1)
            p4.write(MARKER, json.dumps({'version': VERSION, 'package_sha256': SHA256,
                                        'files': {str(path): sha_file(path) for path in tracked}}, indent=2))
            validate()
            FAILED.unlink()
            p4.say('[OK] Instalación completa. Usuario de acceso: ' + ADMIN + '. Conserva la contraseña en tu gestor o .env local ignorado; no la compartas.')
        except BaseException:
            for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGALRM):
                signal.signal(sig, signal.SIG_IGN)
            p4.run(['systemctl', 'stop', 'p4-grafana'], required=False)
            p4.run(['systemctl', 'disable', 'p4-grafana'], required=False)
            MARKER.unlink(missing_ok=True)
            active = p4.run(['systemctl', 'is-active', '--quiet', 'p4-grafana'], required=False).returncode == 0
            p4.say('[FALLA] ' + ('Parada de Grafana no confirmada.' if active else 'Grafana inactivo según systemd.')
                   + ' Instalación incompleta y archivos parciales conservados. No se detuvieron servicios SNMP/Prometheus.')
            raise


def main():
    global p4
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('modo', choices=['descargar', 'preflight', 'instalar', 'validar', 'origen'])
    parser.add_argument('--paquete', type=Path)
    args = parser.parse_args(['validar' if value == '--validar' else value for value in sys.argv[1:]])
    check((args.modo == 'instalar') == (args.paquete is not None), 'Solo instalar requiere/admite --paquete.')
    os.umask(0o077)
    p4 = core()
    root = Path.home() / 'final-config' if args.modo == 'descargar' else Path('/root/final-config')
    if args.modo != 'descargar':
        p4.guard(monitor=args.modo != 'origen')
    root.mkdir(mode=0o700, exist_ok=True)
    lock = None
    if args.modo != 'descargar':
        lock = (root / '.p4-grafana.lock').open('a')
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Otra operación Grafana está en curso.') from None
    p4.RUN_DIR = Path(tempfile.mkdtemp(prefix='P4_grafana_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ_'), dir=root))
    p4.say('[INFO] Registro público resultado.txt; diagnóstico privado en ' + str(p4.RUN_DIR))
    if args.modo == 'descargar':
        download()
    elif args.modo == 'preflight':
        preflight()
    elif args.modo == 'validar':
        validate()
    elif args.modo == 'origen':
        origin()
    else:
        check(args.paquete is not None, 'Instalar requiere --paquete con tar.gz local.')
        install(args.paquete)


def interrupted(signum, frame):
    raise RuntimeError('Interrupción; operación no se considera completa.')


if __name__ == '__main__':
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGALRM):
        signal.signal(sig, interrupted)
    try:
        main()
    except Exception as error:
        message = str(error) if isinstance(error, RuntimeError) or (p4 and isinstance(error, p4.Failure)) else type(error).__name__ + '; conservar diagnóstico privado.'
        if p4:
            p4.say('[FALLA] ' + message)
        else:
            print('[FALLA] ' + message)
        sys.exit(1)
