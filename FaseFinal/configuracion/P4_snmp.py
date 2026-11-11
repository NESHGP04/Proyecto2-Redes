#!/usr/bin/env python3
"""P4: agentes v3 y recolección; no modifica AWS ni ejecuta comandos con claves."""
import argparse
import csv
from datetime import datetime, timezone
import fcntl
import grp
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import pwd
import re
import secrets
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request

HERE = Path(__file__).resolve().parent
CONF = Path('/etc/zenite-p4')
STATE = Path('/var/lib/zenite-p4')
ENVFILE = CONF / 'snmp.env'
CONFIG = Path('/etc/snmp/snmpd.conf')
FINALROOT = Path('/root/final-config')
MONITOR_BIN = Path('/usr/local/lib/zenite-p4')
MONITOR_UNITS = [Path('/etc/systemd/system/p4-' + x + '.service') for x in ['prometheus', 'snmp-exporter']]
UPTIME = '.1.3.6.1.2.1.1.3.0'
VERSIONS = {'snmp_exporter': '0.31.0', 'prometheus': '3.16.0'}
IPS = {'zp-ventas-01': '10.20.0.10', 'zp-ventas-02': '10.20.0.11',
       'zp-visitantes-01': '10.20.0.36', 'zp-ntp-01': '10.20.0.68',
       'zp-ldap-01': '10.20.0.69', 'zp-intranet-01': '10.20.0.71',
       'zp-ti-01': '10.20.0.102', 'zp-monitor-01': '10.20.0.103',
       'zp-web-01': '10.20.0.116', 'zp-vpn-01': '10.20.0.132'}
UBUNTU = {'zp-ldap-01', 'zp-monitor-01', 'zp-web-01', 'zp-vpn-01'}
KEYS = ['SNMP_V3_USER', 'SNMP_AUTH_PASSWORD', 'SNMP_PRIV_PASSWORD']
FAMILIES = {'uptime': UPTIME, 'cpu': '.1.3.6.1.4.1.2021.11',
            'storage': '.1.3.6.1.2.1.25.2.3.1',
            'disco': '.1.3.6.1.4.1.2021.9.1',
            'interfaces': '.1.3.6.1.2.1.31.1.1.1',
            'procesos': '.1.3.6.1.4.1.2021.2.1'}
RUN_DIR = None
SECRETS = []


class Failure(Exception):
    pass


def check(ok, message):
    if not ok:
        raise Failure(message)


def clean(text):
    for value in SECRETS:
        text = text.replace(value, '[secreto omitido]')
    return text


def say(message):
    line = clean(message) + ' · ' + datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
    print(line, flush=True)
    if RUN_DIR:
        with (RUN_DIR / 'resultado.txt').open('a') as f:
            f.write(line + '\n')


def run(argv, timeout=15, env=None, required=True):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
        raise Failure(f'{Path(argv[0]).name} agotó {timeout} s.') from None
    if RUN_DIR and p.stderr:
        with (RUN_DIR / 'diagnostico-privado.txt').open('a') as f:
            f.write(clean(p.stderr) + '\n')
    if required:
        check(p.returncode == 0, f'{Path(argv[0]).name} falló (exit={p.returncode}); conservar diagnóstico privado.')
    return p


def tools(*names):
    for name in names:
        check(shutil.which(name), f'Falta {name}; no se continúa.')


def write(path, content, mode=0o600):
    path = Path(path)
    check(not path.is_symlink(), f'Enlace inesperado: {path}.')
    path.parent.mkdir(parents=True, exist_ok=True)
    data = content.encode() if isinstance(content, str) else content
    fd, name = tempfile.mkstemp(prefix='.p4-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
        os.chmod(name, mode)
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def private(path):
    path = Path(path)
    check(path.is_file() and not path.is_symlink(), f'Falta archivo privado regular: {path}.')
    info = path.stat()
    check(stat.S_IMODE(info.st_mode) == 0o600 and info.st_uid in {0, os.getuid(),
          int(os.environ.get('SUDO_UID', os.getuid()))}, 'Credenciales deben tener permisos 600 y propietario esperado.')
    values = {}
    for line in path.read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        key, separator, value = line.partition('=')
        check(separator and key in KEYS and key not in values, 'Formato de credenciales inesperado; no se ejecuta como shell.')
        values[key] = value
    check(set(values) == set(KEYS), 'Faltan variables de SNMPv3.')
    check(re.fullmatch(r'[A-Za-z][A-Za-z0-9_]{2,31}', values[KEYS[0]]), 'Usuario SNMP inválido.')
    for key in KEYS[1:]:
        check(re.fullmatch(r'[A-Za-z0-9_-]{20,128}', values[key]), 'Claves SNMP: 20–128 caracteres alfanuméricos, _ o -.')
    check(values[KEYS[1]] != values[KEYS[2]], 'Autenticación y privacidad requieren claves diferentes.')
    SECRETS.extend(values[k] for k in KEYS[1:])
    return values


def envtext(values):
    return ''.join(k + '=' + values[k] + '\n' for k in KEYS)


def digest(data):
    return hashlib.sha256(data if isinstance(data, bytes) else data.encode()).hexdigest()


def targets():
    with (HERE / 'P4_snmp_objetivos.csv').open() as stream:
        rows = list(csv.DictReader(stream))
    check(len(rows) == 10 and {r['host']: r['ip_privada'] for r in rows} == IPS,
          'El CSV difiere de los diez objetivos aprobados.')
    return rows


def guard(monitor=False):
    check(os.geteuid() == 0, 'Ejecuta con sudo dentro de la instancia.')
    host = socket.gethostname()
    check(host in IPS and (not monitor or host == 'zp-monitor-01'), 'Host fuera del alcance aprobado.')
    tools('ip', 'systemctl', 'ss')
    addresses = json.loads(run(['ip', '-j', '-4', 'addr', 'show']).stdout)
    check(any(a.get('local') == IPS[host] for nic in addresses for a in nic.get('addr_info', [])), 'IP local distinta del plan.')
    release = dict(line.split('=', 1) for line in Path('/etc/os-release').read_text().splitlines() if '=' in line)
    osid = release.get('ID', '').strip('"')
    version = release.get('VERSION_ID', '').strip('"')
    check((host in UBUNTU and osid == 'ubuntu' and version == '24.04') or
          (host not in UBUNTU and osid == 'amzn' and version == '2023'), 'Sistema operativo no coincide con el plan.')
    targets()
    return host, osid


def confirm(description):
    say('[PLAN] ' + description)
    with open('/dev/tty') as tty:
        print('Escribe si para continuar: ', end='', flush=True)
        signal.alarm(120)
        answer = tty.readline().strip()
        signal.alarm(0)
    check(answer == 'si', 'Cancelado sin aplicar la acción.')


def credentials():
    path = Path.home() / '.config/zenite-p4/.env.p4-snmp'
    if path.exists():
        private(path)
        say('[OK] Credenciales existentes conservadas: ' + str(path))
        return
    confirm('Generar dos claves de laboratorio privadas para los agentes v3; no modifica AWS.')
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    values = {KEYS[0]: 'zeniteMonitorRO', KEYS[1]: secrets.token_urlsafe(32), KEYS[2]: secrets.token_urlsafe(32)}
    write(path, envtext(values))
    say('[OK] Credenciales guardadas sin imprimirlas: ' + str(path))
    say('[INFO] Conservar copia privada local .env; no pegar contenido ni subirlo a git.')


def cloud_validate():
    global RUN_DIR
    tools('aws')
    targets()
    out = Path.home() / 'final-config'
    out.mkdir(mode=0o700, exist_ok=True)
    RUN_DIR = Path(tempfile.mkdtemp(prefix='P4_snmp_nube_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ_'), dir=out))
    say('[INFO] Solo lectura AWS us-east-1. Registro público: ' + str(RUN_DIR / 'resultado.txt'))

    def aws(action, *args):
        check(action.startswith('describe-'), 'Operación AWS no permitida en el diagnóstico.')
        response = json.loads(run(['aws', '--region', 'us-east-1', '--no-cli-pager', '--output', 'json',
                                   '--cli-connect-timeout', '10', '--cli-read-timeout', '20',
                                   'ec2', action, *args], timeout=40).stdout)
        write(RUN_DIR / (action + '.json'), json.dumps(response, indent=2))
        return response

    vpcs = aws('describe-vpcs', '--filters', 'Name=tag:Name,Values=vpc-zenite-fase2')['Vpcs']
    check(len(vpcs) == 1 and vpcs[0]['CidrBlock'] == '10.20.0.0/24', 'VPC ausente, duplicada o distinta del plan.')
    vpc = vpcs[0]['VpcId']
    instances = aws('describe-instances', '--filters', 'Name=vpc-id,Values=' + vpc,
                    'Name=tag:Name,Values=' + ','.join(IPS),
                    'Name=instance-state-name,Values=pending,running,stopping,stopped')
    found = {}
    for reservation in instances['Reservations']:
        for instance in reservation['Instances']:
            name = next((x['Value'] for x in instance.get('Tags', []) if x['Key'] == 'Name'), '')
            check(name in IPS and name not in found and instance['PrivateIpAddress'] == IPS[name], 'Instancia duplicada o fuera del plan.')
            check(name in {'zp-web-01', 'zp-vpn-01'} or not instance.get('PublicIpAddress'), 'IPv4 pública inesperada: ' + name)
            found[name] = instance
            say(f'[INVENTARIO] {name} {instance["InstanceId"]} {IPS[name]} {instance["State"]["Name"]} {instance["InstanceType"]} {instance["Architecture"]}')
    check(set(found) == set(IPS), 'Faltan instancias del plan.')
    monitor = found['zp-monitor-01']
    say('[INFO] Monitor actual: ' + monitor['InstanceType'] + '; confirmar capacidad antes de instalar, sin cambiar tipo.')
    volume_ids = [d['Ebs']['VolumeId'] for d in monitor.get('BlockDeviceMappings', []) if 'Ebs' in d]
    check(bool(volume_ids), 'Monitor sin volumen EBS identificado.')
    volumes = aws('describe-volumes', '--volume-ids', *volume_ids)['Volumes']
    for vol in volumes:
        say(f'[DISCO] Monitor: {vol["VolumeId"]} {vol["Size"]} GiB; espacio libre dentro del SO pendiente.')
    groups = aws('describe-security-groups', '--filters', 'Name=vpc-id,Values=' + vpc)['SecurityGroups']
    named = {g['GroupName']: g for g in groups}
    check('zenite-ti' in named, 'Falta SG zenite-ti.')
    ti = named['zenite-ti']['GroupId']
    interfaces = aws('describe-network-interfaces', '--filters', 'Name=vpc-id,Values=' + vpc,
                     'Name=group-id,Values=' + ti)['NetworkInterfaces']
    check(bool(interfaces), 'SG TI sin interfaces identificadas.')
    for eni in interfaces:
        check(bool(eni.get('PrivateIpAddresses')) and all(ipaddress.ip_address(a['PrivateIpAddress']) in ipaddress.ip_network('10.20.0.96/28')
                  for a in eni.get('PrivateIpAddresses', [])), 'SG TI asignado fuera del CIDR TI; devolver conflicto a P3.')
    for name in ['zenite-ti', 'zenite-ventas', 'zenite-visitantes', 'zenite-servidores', 'zenite-dmz', 'zenite-vpn']:
        check(name in named, 'Falta SG ' + name)
        matched = []
        for rule in named[name].get('IpPermissions', []):
            if str(rule['IpProtocol']) not in {'udp', '17', '-1'}:
                continue
            if str(rule['IpProtocol']) != '-1' and not (rule.get('FromPort', -1) <= 161 <= rule.get('ToPort', -1)):
                continue
            check(not rule.get('Ipv6Ranges') and not rule.get('PrefixListIds'), 'Regla SNMP con fuente IPv6/prefix list no prevista: ' + name)
            for pair in rule.get('UserIdGroupPairs', []):
                check(pair.get('GroupId') == ti, 'Otro SG puede iniciar SNMP hacia ' + name + '; revisar con P3.')
                matched.append('zenite-ti')
            for source in rule.get('IpRanges', []):
                subnet = ipaddress.ip_network(source['CidrIp'])
                check(subnet.subnet_of(ipaddress.ip_network('10.20.0.96/28')), 'SNMP admite otro CIDR en ' + name)
                if ipaddress.ip_address('10.20.0.103') in subnet:
                    matched.append(source['CidrIp'])
        check(matched, 'No se encontró permiso UDP 161 desde el monitor hacia ' + name)
        say('[OK] SG ' + name + ': UDP 161 desde TI, sin otros orígenes detectados.')
    for name, instance in found.items():
        expected = next(r['grupo'] for r in targets() if r['host'] == name)
        check(any(g['GroupName'] == expected for g in instance['SecurityGroups']), 'SG esperado ausente en ' + name)
        extra = [g['GroupName'] for g in instance['SecurityGroups'] if g['GroupName'] != expected]
        check(not extra, 'SG adicionales en ' + name + '; revisar permisos combinados antes de continuar.')
        if name == 'zp-monitor-01':
            continue
        outbound = False
        for rule in named['zenite-ti'].get('IpPermissionsEgress', []):
            if str(rule['IpProtocol']) not in {'udp', '17', '-1'}:
                continue
            if str(rule['IpProtocol']) != '-1' and not (rule.get('FromPort', -1) <= 161 <= rule.get('ToPort', -1)):
                continue
            outbound = outbound or any(ipaddress.ip_address(IPS[name]) in ipaddress.ip_network(r['CidrIp'])
                                       for r in rule.get('IpRanges', []))
            outbound = outbound or any(r.get('GroupId') == named[expected]['GroupId']
                                       for r in rule.get('UserIdGroupPairs', []))
        check(outbound, 'SG TI no permite consulta UDP saliente a ' + name + '; revisar con P3.')
    acls = aws('describe-network-acls', '--filters', 'Name=vpc-id,Values=' + vpc)['NetworkAcls']
    assigned = {a['SubnetId']: acl for acl in acls for a in acl.get('Associations', [])}

    def permits(acl, egress, ip, port):
        for rule in sorted(acl['Entries'], key=lambda r: r['RuleNumber']):
            if rule['Egress'] != egress or 'CidrBlock' not in rule or str(rule['Protocol']) not in {'17', '-1'}:
                continue
            if ipaddress.ip_address(ip) not in ipaddress.ip_network(rule['CidrBlock']):
                continue
            if str(rule['Protocol']) != '-1' and not (rule['PortRange']['From'] <= port <= rule['PortRange']['To']):
                continue
            return rule['RuleAction'] == 'allow'
        return False

    ti_acl = assigned[monitor['SubnetId']]
    for name, instance in found.items():
        if instance['SubnetId'] == monitor['SubnetId']:
            say('[INFO] ' + name + ': agente local/TI; consulta real pendiente.')
            continue
        acl = assigned[instance['SubnetId']]
        allowed = permits(ti_acl, True, IPS[name], 161) and permits(acl, False, '10.20.0.103', 161)
        for port in [1024, 65535]:
            allowed = allowed and permits(acl, True, '10.20.0.103', port) and permits(ti_acl, False, IPS[name], port)
        check(allowed, 'ACL bloquea consulta o retorno SNMP de ' + name + '; revisar con P3.')
        say('[OK] ACL consulta/retorno UDP de ' + name + ' según reglas IPv4 actuales.')
    routes = aws('describe-route-tables', '--filters', 'Name=vpc-id,Values=' + vpc)['RouteTables']
    for route in routes:
        name = next((x['Value'] for x in route.get('Tags', []) if x['Key'] == 'Name'), route['RouteTableId'])
        defaults = [r for r in route.get('Routes', []) if r.get('DestinationCidrBlock') == '0.0.0.0/0']
        say('[RUTA] ' + name + ': ' + json.dumps(defaults))
    nats = aws('describe-nat-gateways', '--filter', 'Name=vpc-id,Values=' + vpc,
               'Name=state,Values=pending,available,deleting')['NatGateways']
    say('[NAT] Estados actuales: ' + json.dumps([{'id': n['NatGatewayId'], 'estado': n['State']} for n in nats]))
    endpoints = aws('describe-instance-connect-endpoints', '--filters', 'Name=vpc-id,Values=' + vpc)['InstanceConnectEndpoints']
    check(len(endpoints) == 1 and endpoints[0]['State'] == 'create-complete', 'EICE no está disponible de forma inequívoca.')
    say('[OK] Inventario y reglas comprobados por lectura. Agentes, repositorios y consultas reales siguen pendientes.')


def is_installed(osid):
    result = run(['dpkg-query', '-W', '-f=${Status}', 'snmpd'] if osid == 'ubuntu' else
                 ['rpm', '-q', 'net-snmp'], required=False)
    return result.returncode == 0 and (osid != 'ubuntu' or result.stdout.strip() == 'install ok installed')


def package_install(osid, monitor=False):
    if osid == 'ubuntu':
        env = dict(os.environ, DEBIAN_FRONTEND='noninteractive')
        run(['apt-get', '-o', 'Acquire::Retries=0', '-o', 'Acquire::http::Timeout=20', 'update'], timeout=120, env=env)
        names = ['python3-yaml', 'ca-certificates', 'curl'] if monitor else ['snmpd', 'snmp']
        run(['apt-get', '-y', '-o', 'Dpkg::Options::=--force-confold', 'install', *names], timeout=240, env=env)
    else:
        run(['dnf', '-y', '--setopt=timeout=20', '--setopt=retries=0', 'install', 'net-snmp', 'net-snmp-utils'], timeout=240)


def agent_config(host, values):
    row = next(r for r in targets() if r['host'] == host)
    process = row['servicio_principal_a_confirmar']
    if process != 'snmpd':
        check(run(['pgrep', '-x', process], required=False).returncode == 0,
              f'Proceso previsto {process} ausente; confirmar servicio antes de instalar.')
    roots = ['.1.3.6.1.2.1.1', '.1.3.6.1.2.1.2', '.1.3.6.1.2.1.31.1.1',
             '.1.3.6.1.2.1.25.2', '.1.3.6.1.2.1.25.3', '.1.3.6.1.4.1.2021.2',
             '.1.3.6.1.4.1.2021.11', '.1.3.6.1.4.1.2021.9']
    return ('# Gestionado por P4_snmp.py v1; sin comunidades v1/v2c\n'
            f'agentaddress udp:{IPS[host]}:161\nsysName {host}\nsysLocation Zenite-laboratorio\n'
            + ''.join('view zenite included ' + oid + '\n' for oid in roots)
            + f'rouser {values[KEYS[0]]} priv -V zenite\nproc {process} 0 1\ndisk / 10%\n')


def profile(values, path, wrong=False):
    text = ('defVersion 3\ndefSecurityLevel authPriv\ndefAuthType SHA-256\ndefPrivType AES\n'
            + 'defSecurityName ' + values[KEYS[0]] + '\n'
            + 'defAuthPassphrase ' + (secrets.token_urlsafe(32) if wrong else values[KEYS[1]]) + '\n'
            + 'defPrivPassphrase ' + values[KEYS[2]] + '\n')
    write(Path(path) / 'snmp.conf', text)
    return dict(os.environ, SNMPCONFPATH=str(path), MIBS='')


def query(values, target, oid=UPTIME, walk=False, wrong=False):
    tools('snmpget', 'snmpwalk')
    with tempfile.TemporaryDirectory(prefix='p4-snmp-') as directory:
        env = profile(values, directory, wrong)
        return run(['snmpwalk' if walk else 'snmpget', '-v3', '-l', 'authPriv', '-On',
                    '-r', '0', '-t', '2', target, oid], timeout=12, env=env, required=False)


def good_query(result, description):
    valid = [line for line in result.stdout.splitlines() if re.match(r'^\.\d[.\d]* = ', line)
             and not re.search(r'No Such|No more variables|End of MIB', line, re.I)]
    check(result.returncode == 0 and bool(valid),
          description + ' no devolvió datos válidos (exit=' + str(result.returncode) + ').')


def family_data(name, text):
    if name == 'cpu':
        check(re.search(r'\.1\.3\.6\.1\.4\.1\.2021\.11\.53\.0 = Counter(?:32|64): \d+', text),
              'Falta el contador de CPU idle requerido para calcular uso.')
    elif name == 'storage':
        prefix = r'\.1\.3\.6\.1\.2\.1\.25\.2\.3\.1\.'
        ram = re.findall(prefix + r'2\.(\d+) = OID: \.1\.3\.6\.1\.2\.1\.25\.2\.1\.2\b', text)
        check(ram, 'Almacenamiento sin identificación de RAM.')
        for index in ram:
            data = []
            for column in [4, 5, 6]:
                match = re.search(prefix + str(column) + r'\.' + index + r' = INTEGER: (\d+)', text)
                check(match, 'Datos de almacenamiento incompletos.')
                data.append(int(match[1]))
            check(data[0] > 0 and data[1] > 0 and 0 <= data[2] <= data[1], 'Valores de almacenamiento inválidos.')
    elif name == 'disco':
        prefix = r'\.1\.3\.6\.1\.4\.1\.2021\.9\.1\.'
        roots = re.findall(prefix + r'2\.(\d+) = STRING: "/"\s*$', text, re.M)
        check(roots, 'No se encontró el disco raíz declarado en dskTable.')
        for index in roots:
            data = []
            for column in [6, 8, 9]:
                match = re.search(prefix + str(column) + r'\.' + index + r' = INTEGER: (\d+)', text)
                check(match, 'Valores del disco raíz incompletos.')
                data.append(int(match[1]))
            check(data[0] > 0 and 0 <= data[1] <= data[0] and 0 <= data[2] <= 100, 'Valores del disco raíz inválidos.')
    elif name == 'interfaces':
        prefix = r'\.1\.3\.6\.1\.2\.1\.31\.1\.1\.1\.'
        received = set(re.findall(prefix + r'6\.(\d+) = Counter64:', text))
        sent = set(re.findall(prefix + r'10\.(\d+) = Counter64:', text))
        check(received & sent, 'Faltan contadores de 64 bits de entrada y salida.')
    elif name == 'procesos':
        counts = re.findall(r'\.1\.3\.6\.1\.4\.1\.2021\.2\.1\.5\.\d+ = INTEGER: (\d+)', text)
        flags = re.findall(r'\.1\.3\.6\.1\.4\.1\.2021\.2\.1\.100\.\d+ = INTEGER: (\d+)', text)
        check(counts and flags and all(int(x) >= 1 for x in counts) and all(int(x) == 0 for x in flags),
              'Conteo de proceso o indicador de error no esperado.')


def agent_validate(host, values, config):
    check(CONFIG.is_file() and CONFIG.read_text() == config, 'Configuración SNMP distinta de la gestionada; revisar sin sobrescribir.')
    run(['systemctl', 'is-active', '--quiet', 'snmpd'])
    sockets = run(['ss', '-H', '-lun', 'sport = :161']).stdout.splitlines()
    check(len(sockets) == 1 and sockets[0].split()[3] == IPS[host] + ':161',
          'UDP 161 debe escuchar únicamente en la IP privada prevista.')
    result = query(values, IPS[host])
    good_query(result, 'Consulta local v3')
    say('[OK] SNMP-01 local: agente activo, escucha privada y autenticación v3 correctas: ' + host)
    say('[DATO] ' + result.stdout.strip())


def agent_install(host, osid, values):
    tools('pgrep', 'apt-get' if osid == 'ubuntu' else 'dnf')
    config = agent_config(host, values)
    marker = STATE / 'agent.json'
    if marker.exists():
        state = json.loads(marker.read_text())
        check(state['credentials'] == digest(envtext(values)), 'Credenciales distintas de las instaladas; no se rota automáticamente.')
        agent_validate(host, values, config)
        say('[OK] Instalación existente validada; no se reinició el servicio.')
        return
    check(not is_installed(osid), 'Ya existe Net-SNMP sin marca P4; revisar configuración antes de modificarlo.')
    check(not (STATE / 'agent.failed').exists(), 'Hay un intento parcial; revisar respaldo antes de reintentar.')
    persistent = Path('/var/lib/snmp/snmpd.conf' if osid == 'ubuntu' else '/var/lib/net-snmp/snmpd.conf')
    check(not CONFIG.exists() and not persistent.exists(), 'Hay archivos de agente anteriores aunque falte el paquete; revisar antes de instalar.')
    check(not ENVFILE.exists(), 'Ya hay un archivo de credenciales de servicio sin marca; revisar.')
    check(not Path('/etc/snmp/snmpd.local.conf').exists(), 'Existe configuración local adicional de snmpd; revisar.')
    check(run(['ss', '-H', '-lun', 'sport = :161']).stdout.strip() == '', 'UDP 161 ya está ocupado.')
    confirm(f'Instalar agente v3 en {host}, escucha {IPS[host]}:161; crear usuario de solo lectura. Solo se administra snmpd.')
    backup = RUN_DIR / 'respaldo-privado'
    backup.mkdir(mode=0o700)
    originals = {}
    masked = False
    try:
        run(['systemctl', 'mask', '--runtime', 'snmpd.service'])
        masked = True
        package_install(osid)
        run(['systemctl', 'stop', 'snmpd'])
        for path in [CONFIG, persistent]:
            check(not path.is_symlink(), 'Configuración inesperada como enlace.')
            originals[path] = path.read_bytes() if path.exists() else None
            if originals[path] is not None:
                write(backup / (path.parent.name + '-' + path.name), originals[path])
        write(CONFIG, config, 0o644)
        user = pwd.getpwnam('Debian-snmp') if osid == 'ubuntu' else pwd.getpwnam('root')
        check(persistent.parent.is_dir(), 'Directorio USM del paquete no encontrado.')
        text = (originals[persistent] or b'').decode()
        check(not re.search(r'(?im)^\s*(createUser|usmUser)\s', text), 'Se encontraron usuarios USM previos; no se modifican.')
        text += f'\ncreateUser {values[KEYS[0]]} SHA-256 {values[KEYS[1]]} AES {values[KEYS[2]]}\n'
        write(persistent, text)
        os.chown(persistent, user.pw_uid, user.pw_gid)
        CONF.mkdir(mode=0o700, exist_ok=True)
        write(ENVFILE, envtext(values))
        run(['systemctl', 'unmask', '--runtime', 'snmpd.service'])
        masked = False
        run(['systemctl', 'enable', '--now', 'snmpd'])
        agent_validate(host, values, config)
        write(marker, json.dumps({'version': 1, 'host': host, 'credentials': digest(envtext(values)),
                                 'config': digest(config), 'backup': str(backup)}, indent=2))
        say('[OK] Agente instalado y validado; respaldo privado: ' + str(backup))
    except BaseException:
        for sig in [signal.SIGINT, signal.SIGTERM, signal.SIGALRM]:
            signal.signal(sig, signal.SIG_IGN)
        stopped = run(['systemctl', 'stop', 'snmpd'], required=False).returncode == 0
        run(['systemctl', 'disable', 'snmpd'], required=False)
        stopped = stopped and run(['pgrep', '-x', 'snmpd'], required=False).returncode != 0
        if stopped:
            for path, content in originals.items():
                if content is None:
                    path.unlink(missing_ok=True)
                else:
                    write(path, content)
                    if path == persistent:
                        user = pwd.getpwnam('Debian-snmp') if osid == 'ubuntu' else pwd.getpwnam('root')
                        os.chown(path, user.pw_uid, user.pw_gid)
            ENVFILE.unlink(missing_ok=True)
        write(STATE / 'agent.failed', 'Intento parcial. Paquete conservado, servicio detenido; revisar ' + str(backup))
        say('[FALLA] ' + ('Servicio detenido y archivos restaurados.' if stopped else
                         'No se confirmó la parada; no se restauran archivos con el agente en ejecución.') +
            ' Instalación parcial requiere revisión.')
        raise
    finally:
        if masked:
            run(['systemctl', 'unmask', '--runtime', 'snmpd.service'], required=False)


def collect(values, selected, negative=False):
    names = selected or list(IPS)
    check(all(n in IPS for n in names), 'Objetivo no aprobado.')
    failed = 0
    for host in names:
        ip = IPS[host]
        if negative:
            before = query(values, ip)
            good_query(before, 'Control válido previo ' + host)
            bad = query(values, ip, wrong=True)
            after = query(values, ip)
            good_query(after, 'Control válido posterior ' + host)
            check(bad.returncode != 0 and not bad.stdout.strip(), 'La consulta con clave incorrecta no fue rechazada.')
            check(re.search(r'authentication|timeout|no response|digest', bad.stderr, re.I), 'Error negativo ajeno a autenticación/espera.')
            say(f'[OK] SNMP-03 {host}: clave incorrecta falla con exit={bad.returncode}; controles previo/posterior correctos.')
            continue
        for name, oid in FAMILIES.items():
            result = query(values, ip, oid, walk=name != 'uptime')
            try:
                good_query(result, host + ' / ' + name)
                family_data(name, result.stdout)
                say('[DATO] ' + host + ' / ' + name + '\n' + result.stdout.rstrip())
            except Failure as error:
                failed += 1
                say(f'[FALLA] {host} / {name}: {error}; exit={result.returncode}. No se concluye estado EC2.')
    check(failed == 0, f'{failed} familias sin datos; no se aprueba SNMP-02 global.')


def origin_probe(host, values, selected, control=False):
    check(selected and len(selected) == 1 and selected[0] in IPS and selected[0] != host,
          'Indica exactamente un --host remoto aprobado para esta prueba.')
    target = selected[0]
    if control:
        check(host == 'zp-monitor-01', 'El control válido se ejecuta desde el monitor.')
        result = query(values, IPS[target], '.1.3.6.1.2.1.1', walk=True)
        good_query(result, 'Control SNMP desde monitor')
        say('[DATO] Control snmpwalk desde monitor hacia ' + target + '\n' + result.stdout.rstrip())
        say('[OK] Control autenticado desde monitor, exit=0.')
    else:
        check(host in {'zp-ventas-01', 'zp-visitantes-01'}, 'La prueba de origen se ejecuta en Ventas o Visitantes.')
        check(target == 'zp-ldap-01', 'Usa el servidor LDAP como destino común de los controles de red.')
        result = query(values, IPS[target])
        check(result.returncode != 0 and not result.stdout.strip() and
              re.search(r'timeout|no response', result.stderr, re.I),
              'El resultado no demuestra agotamiento de tiempo de SNMP; conservar el fallo.')
        say(f'[OBSERVADO] {host} -> {target}: SNMP sin respuesta, exit={result.returncode}, con credenciales válidas instaladas.')
        say('[PENDIENTE] Correlacionar con control desde monitor antes y después; este intento aislado no aprueba FW-05/SNMP-05.')


def extract_bundle(archive, directory, stem):
    members = archive.getmembers()
    check(bool(members), 'Archivo de release vacío.')
    for member in members:
        # TarInfo normaliza la carpeta raíz y puede quitar su barra final.
        root = member.name.rstrip('/') == stem and member.isdir()
        child = member.name.startswith(stem + '/')
        check((root or child) and not Path(member.name).is_absolute()
              and '..' not in Path(member.name).parts
              and (member.isdir() or member.isfile()),
              'Archivo de release con rutas inesperadas.')
    # Validar todos los miembros antes de escribir; se rechazan enlaces y nodos especiales.
    archive.extractall(directory, members=members)


def download_bundle(repo, architecture, directory):
    version = VERSIONS[repo]
    stem = f'{repo}-{version}.linux-{architecture}'
    base = f'https://github.com/prometheus/{repo}/releases/download/v{version}/'
    target = directory / (stem + '.tar.gz')
    manifest = urllib.request.urlopen(base + 'sha256sums.txt', timeout=30).read().decode()
    with urllib.request.urlopen(base + target.name, timeout=60) as response, target.open('wb') as stream:
        shutil.copyfileobj(response, stream)
    expected = [line.split()[0] for line in manifest.splitlines()
                if line.split()[-1].lstrip('*') == target.name]
    check(len(expected) == 1 and digest(target.read_bytes()) == expected[0], 'Checksum oficial incorrecto: ' + repo)
    with tarfile.open(target) as archive:
        extract_bundle(archive, directory, stem)
    return directory / stem


def exporter_config(official):
    import yaml
    upstream = yaml.safe_load(official.read_text())
    modules = {name: upstream['modules'][name] for name in ['if_mib', 'hrStorage', 'hrDevice', 'ucd_system_stats']}
    for module in modules.values():
        module.update({'timeout': '2s', 'retries': 0, 'max_repetitions': 10})
    modules['zenite_system'] = {'get': [UPTIME.lstrip('.')], 'timeout': '2s', 'retries': 0,
                                'metrics': [{'name': 'sysUpTime', 'oid': UPTIME.lstrip('.')[:-2],
                                             'type': 'gauge', 'help': 'SNMP subsystem uptime, TimeTicks (1/100 s)'}]}
    modules['zenite_process'] = {'walk': ['1.3.6.1.4.1.2021.2.1'], 'timeout': '2s', 'retries': 0,
        'max_repetitions': 10, 'metrics': [
            {'name': name, 'oid': '1.3.6.1.4.1.2021.2.1.' + column, 'type': 'gauge',
             'help': helptext, 'indexes': [{'labelname': 'prIndex', 'type': 'gauge'}],
             'lookups': [{'labels': ['prIndex'], 'labelname': 'prNames',
                          'oid': '1.3.6.1.4.1.2021.2.1.2', 'type': 'DisplayString'}]}
            for name, column, helptext in [('prCount', '5', 'Declared process count'),
                                            ('prErrorFlag', '100', 'Declared process error flag')]]}
    modules['zenite_disk'] = {'walk': ['1.3.6.1.4.1.2021.9.1'], 'timeout': '2s', 'retries': 0,
        'max_repetitions': 10, 'metrics': [
            {'name': name, 'oid': '1.3.6.1.4.1.2021.9.1.' + column, 'type': 'gauge',
             'help': helptext, 'indexes': [{'labelname': 'dskIndex', 'type': 'gauge'}],
             'lookups': [{'labels': ['dskIndex'], 'labelname': 'dskPath',
                          'oid': '1.3.6.1.4.1.2021.9.1.2', 'type': 'DisplayString'}]}
            for name, column, helptext in [('dskTotal', '6', 'Filesystem total, KiB'),
                                            ('dskUsed', '8', 'Filesystem used, KiB'),
                                            ('dskPercent', '9', 'Filesystem used percent')]]}
    auth = {'version': 3, 'username': '${SNMP_V3_USER}', 'security_level': 'authPriv',
            'password': '${SNMP_AUTH_PASSWORD}', 'priv_password': '${SNMP_PRIV_PASSWORD}',
            'auth_protocol': 'SHA256', 'priv_protocol': 'AES'}
    return {'auths': {'zenite_v3': auth}, 'modules': modules}


def prom_config():
    rows = targets()
    return {'global': {'scrape_interval': '30s', 'evaluation_interval': '15s'},
            'rule_files': [str(CONF / 'alerts.yml')], 'scrape_configs': [
                {'job_name': 'snmp_exporter', 'static_configs': [{'targets': ['127.0.0.1:9116']} ]},
                {'job_name': 'snmp', 'scrape_interval': '30s', 'scrape_timeout': '15s', 'metrics_path': '/snmp',
                 'params': {'auth': ['zenite_v3'], 'module': ['zenite_system,if_mib,hrStorage,hrDevice,ucd_system_stats,zenite_process,zenite_disk']},
                 'static_configs': [{'targets': [r['ip_privada']], 'labels': {'host': r['host'], 'grupo': r['grupo']}} for r in rows],
                 'relabel_configs': [{'source_labels': ['__address__'], 'target_label': '__param_target'},
                                    {'source_labels': ['__param_target'], 'target_label': 'instance'},
                                    {'target_label': '__address__', 'replacement': '127.0.0.1:9116'}]}]}


def http(path, port=9090):
    with urllib.request.urlopen(f'http://127.0.0.1:{port}' + path, timeout=20) as response:
        return response.read().decode()


def monitor_validate():
    marker = STATE / 'monitor.json'
    if marker.exists():
        previous = json.loads(marker.read_text())
        check(previous['credentials'] == digest(envtext(private(ENVFILE))), 'Credenciales del monitor cambiadas fuera del procedimiento.')
        for name, expected in previous.get('files', {}).items():
            check(Path(name).is_file() and digest(Path(name).read_bytes()) == expected,
                  'Configuración del monitor modificada: ' + name)
    for service in ['p4-snmp-exporter', 'p4-prometheus']:
        run(['systemctl', 'is-active', '--quiet', service])
    for port in [9090, 9116]:
        sockets = run(['ss', '-H', '-ltn', f'sport = :{port}']).stdout.splitlines()
        check(len(sockets) == 1 and sockets[0].split()[3] == f'127.0.0.1:{port}', 'Escucha del monitor no está limitada a loopback.')
    check(http('/-/ready').strip() == 'Prometheus Server is Ready.', 'Prometheus no está listo.')
    check('snmp_exporter_build_info' in http('/metrics', 9116), 'Exporter no devuelve métricas propias.')
    rows = []
    for attempt in range(6):
        active = json.loads(http('/api/v1/targets'))['data']['activeTargets']
        rows = [t for t in active if t['labels'].get('job') == 'snmp']
        if len(rows) == 10:
            break
        time.sleep(1)
    check(len(rows) == 10, 'Prometheus no conserva los diez objetivos.')
    check({t['labels'].get('host'): t['labels'].get('instance') for t in rows} == IPS,
          'Los objetivos activos no coinciden con las diez IP aprobadas.')
    for t in rows:
        label = t['labels']
        say(f'[ESTADO] {label["host"]} {label["instance"]}: scrape={t["health"]}; no equivale por sí solo a estado EC2.')
    say('[OK] Recolector y Prometheus activos y privados; diez objetivos configurados. Estados down no se aceptan como SNMP-02 PASS.')


def monitor_download_recovery(values, failed_log):
    """Revisa sin mutaciones el único estado parcial anterior a extraer binarios."""
    check(not (STATE / 'monitor.json').exists(), 'El monitor ya tiene marca de instalación completa.')
    marker = STATE / 'monitor.failed'
    for path in [marker, failed_log, STATE / 'agent.json']:
        check(path.is_file() and not path.is_symlink() and path.resolve() == path,
              'Falta archivo regular de recuperación: ' + str(path))
        info = path.stat()
        check(info.st_uid == os.geteuid() and stat.S_IMODE(info.st_mode) == 0o600,
              'Propietario/permisos inesperados en recuperación: ' + str(path))
    check(failed_log.name == 'resultado.txt' and failed_log.parent.parent == FINALROOT
          and failed_log.parent.name.startswith('P4_snmp_zp-monitor-01_'),
          'Indica el resultado.txt original de esta instalación del monitor.')
    text = failed_log.read_text()
    check('[PLAN] Instalar Prometheus 3.16.0 y snmp_exporter 0.31.0' in text
          and '[FALLA] Archivo de release con rutas inesperadas.' in text
          and '[OK] Monitor instalado' not in text,
          'El registro no corresponde al fallo de extracción admitido.')
    check(marker.read_text() == 'Instalación parcial; servicios detenidos. Conservar diagnóstico y revisar archivos P4.',
          'Marca de fallo distinta de la esperada.')
    check(abs(marker.stat().st_mtime - failed_log.stat().st_mtime) < 10,
          'La marca de fallo no corresponde temporalmente al registro.')
    check(not MONITOR_BIN.exists() and not MONITOR_BIN.is_symlink()
          and not any(p.exists() or p.is_symlink() for p in MONITOR_UNITS),
          'Ya existen binarios/unidades; esta recuperación no los reemplaza.')
    account = pwd.getpwnam('p4monitor')
    group = grp.getgrgid(account.pw_gid)
    check(0 < account.pw_uid < 1000 and group.gr_name == 'p4monitor' and not group.gr_mem
          and account.pw_shell == '/usr/sbin/nologin' and account.pw_dir == '/home/p4monitor'
          and not Path(account.pw_dir).exists(), 'Usuario p4monitor distinto del creado por el instalador.')
    for service in ['p4-snmp-exporter', 'p4-prometheus']:
        check(run(['systemctl', 'is-active', '--quiet', service], required=False).returncode != 0,
              'El servicio sigue activo: ' + service)
    processes = run(['pgrep', '-u', str(account.pw_uid)], required=False)
    check(processes.returncode == 1, 'Usuario de servicio con procesos activos o estado no comprobado.')
    for folder in [CONF, STATE]:
        check(folder.is_dir() and not folder.is_symlink() and folder.resolve() == folder,
              'Directorio parcial inesperado: ' + str(folder))
        info = folder.stat()
        check(info.st_uid == os.geteuid() and info.st_gid == account.pw_gid
              and stat.S_IMODE(info.st_mode) == 0o750, 'Permisos de directorio parcial distintos.')
    check({p.name for p in CONF.iterdir()} == {'snmp.env'}
          and {p.name for p in STATE.iterdir()} == {'agent.json', 'monitor.failed', 'prometheus'},
          'Archivos adicionales en la instalación parcial; requieren revisión.')
    data = STATE / 'prometheus'
    check(data.is_dir() and not data.is_symlink() and data.stat().st_uid == account.pw_uid
          and data.stat().st_gid == account.pw_gid and not any(data.iterdir()),
          'El directorio de datos no está vacío o tiene otro propietario.')
    check(private(ENVFILE) == values, 'Las credenciales existentes no coinciden.')
    agent_validate('zp-monitor-01', values, agent_config('zp-monitor-01', values))
    say('[OK] Fallo de extracción y estado parcial comprobados; agente y credenciales conservados.')
    return account


def monitor_install(values, failed_log=None):
    check(socket.gethostname() == 'zp-monitor-01', 'Monitor fuera de host.')
    recovered = monitor_download_recovery(values, failed_log) if failed_log else None
    if (STATE / 'monitor.json').exists():
        check(json.loads((STATE / 'monitor.json').read_text())['credentials'] == digest(envtext(values)), 'No se rotan credenciales automáticamente.')
        monitor_validate()
        return
    check(recovered is not None or not (STATE / 'monitor.failed').exists(), 'Instalación previa parcial; revisar antes de reintentar.')
    for port in [9090, 9116]:
        check(not run(['ss', '-H', '-ltn', f'sport = :{port}']).stdout.strip(), f'Puerto {port} ocupado.')
    units = MONITOR_UNITS
    check(not any(p.exists() or p.is_symlink() for p in units), 'Unidades P4 preexistentes sin marca; no se sobrescriben.')
    check(shutil.disk_usage('/').free > 4 * 1024 ** 3, 'Se requieren al menos 4 GiB libres para instalar el monitor.')
    check(not ENVFILE.exists() or ENVFILE.read_text() == envtext(values), 'Credenciales del agente y monitor distintas.')
    architecture = {'x86_64': 'amd64', 'aarch64': 'arm64'}.get(os.uname().machine)
    check(architecture, 'Arquitectura no soportada por este instalador.')
    confirm(('Archivar marca de extracción fallida y reutilizar usuario/directorio vacío comprobados. ' if recovered else '')
            + 'Instalar Prometheus 3.16.0 y snmp_exporter 0.31.0 desde releases oficiales verificadas; servicios solo en loopback. No instala Grafana.')
    try:
        if recovered:
            (STATE / 'monitor.failed').rename(RUN_DIR / 'monitor.failed.previo')
            write(RUN_DIR / 'recuperacion.txt', 'Registro original: ' + str(failed_log) + '\n')
        package_install('ubuntu', monitor=True)
        if not recovered:
            check(run(['getent', 'passwd', 'p4monitor'], required=False).returncode != 0, 'Usuario p4monitor preexistente sin marca; revisar.')
            run(['useradd', '--system', '--user-group', '--no-create-home', '--shell', '/usr/sbin/nologin', 'p4monitor'])
        account = pwd.getpwnam('p4monitor')
        check(not recovered or account == recovered, 'El usuario cambió durante la recuperación.')
        CONF.mkdir(mode=0o700, exist_ok=True)
        os.chmod(CONF, 0o750)
        os.chown(CONF, 0, account.pw_gid)
        write(ENVFILE, envtext(values))
        STATE.mkdir(parents=True, exist_ok=True)
        os.chmod(STATE, 0o750)
        os.chown(STATE, 0, account.pw_gid)
        data = STATE / 'prometheus'
        data.mkdir(parents=True, mode=0o750, exist_ok=recovered is not None)
        os.chown(data, account.pw_uid, account.pw_gid)
        with tempfile.TemporaryDirectory(prefix='p4-releases-') as directory:
            directory = Path(directory)
            snmp = download_bundle('snmp_exporter', architecture, directory)
            prom = download_bundle('prometheus', architecture, directory)
            binaries = MONITOR_BIN
            binaries.mkdir(parents=True, exist_ok=True)
            os.chmod(binaries, 0o755)
            for source in [snmp / 'snmp_exporter', prom / 'prometheus', prom / 'promtool']:
                dest = binaries / source.name
                check(not dest.exists(), 'Binario P4 preexistente sin marca; revisar.')
                write(dest, source.read_bytes(), 0o755)
            # YAML conserva las claves enteras de enum_values; JSON las convertiría a texto.
            import yaml
            write(CONF / 'snmp.yml', yaml.safe_dump(exporter_config(snmp / 'snmp.yml'), sort_keys=False), 0o640)
        write(CONF / 'prometheus.yml', json.dumps(prom_config(), indent=2), 0o640)
        alerts = {'groups': [{'name': 'zenite', 'rules': [
            {'alert': 'ZeniteSinRespuestaSNMP', 'expr': '(up{job="snmp"} == 0) and on() (up{job="snmp_exporter"} == 1)',
             'for': '60s', 'labels': {'severity': 'warning'}, 'annotations': {'summary': 'Sin respuesta SNMP; comprobar agente, red y EC2'}},
            {'alert': 'ZeniteRecolectorCaido', 'expr': 'up{job="snmp_exporter"} == 0', 'for': '30s',
             'labels': {'severity': 'critical'}, 'annotations': {'summary': 'Recolector sin respuesta; no se concluye caída de los hosts'}}]}]}
        write(CONF / 'alerts.yml', json.dumps(alerts, indent=2), 0o640)
        for file in ['snmp.yml', 'prometheus.yml', 'alerts.yml']:
            os.chown(CONF / file, 0, account.pw_gid)
        run(['/usr/local/lib/zenite-p4/promtool', 'check', 'config', str(CONF / 'prometheus.yml')], timeout=30)
        commands = {'snmp-exporter': '/usr/local/lib/zenite-p4/snmp_exporter --config.file=/etc/zenite-p4/snmp.yml --config.expand-environment-variables --snmp.module-concurrency=2 --web.listen-address=127.0.0.1:9116',
                    'prometheus': '/usr/local/lib/zenite-p4/prometheus --config.file=/etc/zenite-p4/prometheus.yml --storage.tsdb.path=/var/lib/zenite-p4/prometheus --storage.tsdb.retention.time=48h --storage.tsdb.retention.size=1GB --web.listen-address=127.0.0.1:9090'}
        for name, command in commands.items():
            unit = ('[Unit]\nDescription=Zenite P4 ' + name + '\nAfter=network-online.target\nWants=network-online.target\n'
                    '[Service]\nUser=p4monitor\nGroup=p4monitor\n' +
                    ('EnvironmentFile=/etc/zenite-p4/snmp.env\n' if name == 'snmp-exporter' else '') +
                    'ExecStart=' + command + '\nRestart=on-failure\nRestartSec=5\nNoNewPrivileges=true\nPrivateTmp=true\n'
                    'ProtectHome=true\nProtectSystem=strict\nReadWritePaths=/var/lib/zenite-p4/prometheus\nUMask=0077\n'
                    '[Install]\nWantedBy=multi-user.target\n')
            write(next(p for p in units if p.name == 'p4-' + name + '.service'), unit, 0o644)
        run(['systemctl', 'daemon-reload'])
        run(['systemctl', 'enable', '--now', 'p4-snmp-exporter', 'p4-prometheus'], timeout=30)
        # Dar margen a readiness sin ocultar fallos de configuración.
        for attempt in range(10):
            try:
                http('/-/ready')
                break
            except (OSError, ValueError):
                time.sleep(1)
        monitor_validate()
        tracked = [CONF / f for f in ['snmp.yml', 'prometheus.yml', 'alerts.yml']] + units
        write(STATE / 'monitor.json', json.dumps({'credentials': digest(envtext(values)), 'versions': VERSIONS,
              'files': {str(p): digest(p.read_bytes()) for p in tracked}}, indent=2))
        say('[OK] Monitor instalado; los estados de las diez instancias se validan con recolectar.')
    except BaseException:
        for sig in [signal.SIGINT, signal.SIGTERM, signal.SIGALRM]:
            signal.signal(sig, signal.SIG_IGN)
        run(['systemctl', 'stop', 'p4-snmp-exporter', 'p4-prometheus'], required=False)
        run(['systemctl', 'disable', 'p4-snmp-exporter', 'p4-prometheus'], required=False)
        write(STATE / 'monitor.failed', 'Instalación parcial; servicios detenidos. Conservar diagnóstico y revisar archivos P4.')
        active = any(run(['systemctl', 'is-active', '--quiet', s], required=False).returncode == 0
                     for s in ['p4-snmp-exporter', 'p4-prometheus'])
        say('[FALLA] ' + ('Parada de servicios sin confirmar.' if active else 'Servicios P4 detenidos.') +
            ' Archivos parciales conservados para revisión. No se informa instalación completa.')
        raise


def main():
    global RUN_DIR
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rol', choices=['agente', 'monitor', 'nube'])
    parser.add_argument('modo', choices=['credenciales', 'preflight', 'instalar', 'recuperar-descarga', '--validar', 'validar', 'recolectar', 'negativa', 'control', 'origen'])
    parser.add_argument('--credenciales', type=Path)
    parser.add_argument('--registro-fallido', type=Path)
    parser.add_argument('--host', action='append')
    # Permitir la forma histórica --validar sin que argparse la trate como opción.
    argv = ['validar' if x == '--validar' else x for x in sys.argv[1:]]
    args = parser.parse_args(argv)
    check((args.modo == 'recuperar-descarga' and args.rol == 'monitor' and args.registro_fallido is not None)
          or (args.modo != 'recuperar-descarga' and args.registro_fallido is None),
          'recuperar-descarga requiere rol monitor y --registro-fallido; otras operaciones no admiten ese registro.')
    os.umask(0o077)
    if args.rol == 'nube':
        check(args.modo == 'validar', 'La nube solo admite --validar.')
        cloud_validate()
        return
    if args.modo == 'credenciales':
        credentials()
        return
    host, osid = guard(monitor=args.rol == 'monitor' or args.modo in {'recolectar', 'negativa', 'control'})
    root = FINALROOT
    root.mkdir(mode=0o700, exist_ok=True)
    lock = (root / '.p4-snmp.lock').open('a')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise Failure('Otra operación SNMP P4 está en ejecución.') from None
    RUN_DIR = Path(tempfile.mkdtemp(prefix='P4_snmp_' + host + '_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ_'), dir=root))
    say('[INFO] Registro público resultado.txt y diagnóstico privado en ' + str(RUN_DIR))
    if args.modo == 'preflight':
        say(f'[INFO] {host} {IPS[host]} {osid}; paquete SNMP presente={is_installed(osid)}; modo solo lectura.')
        say('[INFO] Espacio libre raíz: ' + str(shutil.disk_usage('/').free // 1024 ** 2) + ' MiB')
        return
    source = args.credenciales or ENVFILE
    values = private(source)
    if args.rol == 'monitor':
        if args.modo == 'instalar':
            monitor_install(values)
        elif args.modo == 'recuperar-descarga':
            monitor_install(values, failed_log=args.registro_fallido)
        elif args.modo == 'validar':
            monitor_validate()
        else:
            raise Failure('Usa instalar, recuperar-descarga, preflight o --validar para el monitor.')
    elif args.modo == 'instalar':
        agent_install(host, osid, values)
        if args.credenciales and source.name == '.env.p4-snmp' and source != ENVFILE:
            source.unlink()
            say('[OK] Copia de transporte de credenciales eliminada; archivo de servicio privado conservado.')
    elif args.modo == 'validar':
        agent_validate(host, values, agent_config(host, values))
    elif args.modo in {'recolectar', 'negativa'}:
        collect(values, args.host, negative=args.modo == 'negativa')
    elif args.modo in {'control', 'origen'}:
        origin_probe(host, values, args.host, control=args.modo == 'control')


def interrupted(signum, frame):
    raise Failure('Interrupción recibida; la operación no se considera completa.')


if __name__ == '__main__':
    for sig in [signal.SIGINT, signal.SIGTERM, signal.SIGALRM]:
        signal.signal(sig, interrupted)
    try:
        main()
    except (Failure, OSError, ValueError, KeyError, ImportError, StopIteration) as error:
        if isinstance(error, Failure):
            say('[FALLA] ' + str(error))
        else:
            say('[FALLA] Archivo, herramienta o respuesta inesperada (' + type(error).__name__ + '); conservar diagnóstico privado.')
        sys.exit(1)
