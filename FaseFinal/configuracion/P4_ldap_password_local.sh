#!/usr/bin/env bash
# Recuperación online de ventas01 mediante SASL EXTERNAL; no usa slapmodify.
# sudo bash P4_ldap_password_local.sh --validar|cambiar
set +x
set +v
set -euo pipefail
umask 077
ulimit -c 0
[[ $# -eq 1 && ( $1 == --validar || $1 == cambiar ) ]] || {
    echo 'Uso: sudo bash P4_ldap_password_local.sh --validar|cambiar' >&2
    exit 2
}
[[ $EUID -eq 0 ]] || { echo '[FALLA] Ejecuta con sudo.' >&2; exit 1; }
for p4_tool in python3 ip systemctl openssl ldapsearch ldapwhoami ldapmodify ldappasswd; do
    command -v "$p4_tool" >/dev/null || { echo "[FALLA] Falta $p4_tool." >&2; exit 1; }
done
python3 - "$1" <<'PY'
import base64
import fcntl
import getpass
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

MODE = sys.argv[1]
IP = '10.20.0.69'
CERT = '/etc/ldap/zenite-ldap.crt'
BASE = 'dc=zenite,dc=internal'
TARGET = 'uid=ventas01,ou=People,' + BASE
IDENTITY = 'gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth'
DB = 'olcDatabase={1}mdb,cn=config'
EXPECTED = [
    '{0}to attrs=userPassword by self write by anonymous auth by * none',
    '{1}to attrs=shadowLastChange by self write by * read',
    '{2}to * by * read',
]
RULE = (f'to dn.exact="{TARGET}" attrs=userPassword '
        f'by dn.exact="{IDENTITY}" write by * break')
LOCAL = ['-Q', '-Y', 'EXTERNAL', '-H', 'ldapi:///', '-o', 'nettimeout=5']
state = {'acl_attempted': False, 'password_attempted': False,
         'confirmed': False, 'backup': None}
log = None
work = None
original = None


class Failure(Exception):
    pass


def require(ok, message):
    if not ok:
        raise Failure(message)


def now():
    return datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')


def say(message):
    line = f'{message} · {now()}'
    print(line, flush=True)
    if log:
        with log.open('a') as stream:
            stream.write(line + '\n')


def run(args, *, env=None, data=None):
    # No argumentos con contraseñas: se usan ficheros privados -T/-y.
    try:
        result = subprocess.run(args, input=data, capture_output=True,
                                timeout=12, env=env, check=False)
    except subprocess.TimeoutExpired as exc:
        if work:
            with (work / 'diagnostico-privado.txt').open('ab') as stream:
                stream.write(exc.stderr or b'')
        raise Failure('Una operación agotó 12 s; se comprueba la recuperación.') from None
    if work and result.stderr:
        with (work / 'diagnostico-privado.txt').open('ab') as stream:
            stream.write(result.stderr)
    require(result.returncode == 0,
            f'Falló {args[0]} (exit={result.returncode}); consulta el diagnóstico privado.')
    return result.stdout.decode('utf-8', errors='strict')


def ldif(text):
    logical = []
    for line in text.splitlines():
        if line.startswith(' '):
            require(bool(logical), 'LDIF plegado inválido.')
            logical[-1] += line[1:]
        else:
            logical.append(line)
    records, record = [], {}
    for line in logical + ['']:
        if not line:
            if record:
                records.append(record)
                record = {}
            continue
        if line.startswith('#'):
            continue
        name, separator, value = line.partition(':')
        require(bool(separator), 'Respuesta LDIF inesperada.')
        if value.startswith(':'):
            value = base64.b64decode(value[1:].strip(), validate=True).decode()
        else:
            require(not value.startswith('<'), 'No se admiten referencias externas LDIF.')
            value = value.lstrip(' ')
        record.setdefault(name.lower(), []).append(value)
    return records


def single(text, dn):
    records = ldif(text)
    require(len(records) == 1 and
            records[0].get('dn', [''])[0].lower() == dn.lower(),
            'No se encontró exactamente la entrada prevista.')
    return records[0]


def snapshot():
    text = run(['ldapsearch', *LOCAL, '-LLL', '-o', 'ldif_wrap=no',
                '-b', DB, '-s', 'base', '(objectClass=*)', 'olcAccess'])
    record = single(text, DB)
    return text, record['olcaccess']


def body(rule):
    return re.sub(r'^\{\d+\}', '', rule)


def normalized(rule):
    # slapd normaliza dn.exact a dn.base y puede explicitar el nivel +0.
    value = re.sub(r'\s+', '', body(rule)).lower().replace('dn.exact=', 'dn.base=')
    return value.replace('by*+0break', 'by*break')


def attr(name, value):
    return name + ':: ' + base64.b64encode(value.encode()).decode() + '\n'


def modify_config(operation, rule, file):
    content = f'dn: {DB}\nchangetype: modify\n{operation}: olcAccess\n' + attr('olcAccess', rule)
    file.write_text(content)
    # add inserta una sola regla; delete recibe su valor completo SIN índice.
    # No reemplazar olcAccess ni borrar por posición: preserva cambios ajenos.
    run(['ldapmodify', *LOCAL, '-f', str(file)])


def password_read():
    with open('/dev/tty', 'r') as reader, open('/dev/tty', 'w') as tty:
        tty.write('Permiso TEMPORAL: root local podrá escribir userPassword solo de ventas01.\n'
                  'Se retirará al terminar; slapd seguirá activo. Escribe si para continuar: ')
        tty.flush()
        signal.alarm(120)
        answer = reader.readline().strip()
        signal.alarm(0)
        require(answer == 'si', 'Cancelado; no se cambió nada.')
        signal.alarm(120)
        first = getpass.getpass('Nueva contraseña de laboratorio para ventas01: ', stream=tty)
        signal.alarm(120)
        second = getpass.getpass('Repite la nueva contraseña: ', stream=tty)
        signal.alarm(0)
    require(bool(first) and first == second, 'Contraseñas vacías o distintas; no se cambió nada.')
    require('\x00' not in first, 'La contraseña contiene un carácter no admitido.')
    (work / 'nueva').write_bytes(first.encode())  # Sin salto de línea.


def interrupted(signum, frame):
    raise Failure('Interrupción recibida; se ejecuta la limpieza.')


def cleanup():
    ok = True
    # No interrumpir la retirada del permiso; cada operación mantiene su timeout.
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGALRM):
        signal.signal(sig, signal.SIG_IGN)
    signal.alarm(0)
    if state['password_attempted'] and not state['confirmed']:
        try:
            run(['ldapmodify', *LOCAL, '-f', str(work / 'restaurar-password.ldif')])
            restored = single(run(['ldapsearch', *LOCAL, '-LLL', '-o', 'ldif_wrap=no',
                                   '-b', TARGET, '-s', 'base', '(objectClass=*)', 'userPassword']), TARGET)
            require(restored.get('userpassword', []) == state['old_password'],
                    'El atributo restaurado no coincide con el respaldo.')
            say('[OK] Atributo de contraseña anterior restaurado')
        except (Failure, OSError, ValueError):
            say('[FALLA] Restauración de contraseña no confirmada; conserva el respaldo privado')
            ok = False
    if state['acl_attempted']:
        try:
            _, rules = snapshot()
            matches = [r for r in rules if normalized(r) == normalized(RULE)]
            require(len(matches) <= 1, 'Regla temporal duplicada; requiere revisión local.')
            if matches:
                modify_config('delete', body(matches[0]), work / 'retirar-permiso.ldif')
            _, after = snapshot()
            require(after == original, 'Las ACL difieren del respaldo; no se sobrescriben cambios ajenos.')
            say('[OK] Permiso temporal retirado; las tres ACL originales coinciden')
        except (Failure, OSError, ValueError):
            say('[FALLA] Retirada del permiso o restauración exacta de ACL sin confirmar; revisa el respaldo privado')
            ok = False
        try:
            run(['systemctl', 'is-active', '--quiet', 'slapd'])
            say('[OK] slapd sigue activo')
        except Failure:
            say('[FALLA] No se confirmó slapd activo al finalizar')
            ok = False
    if work:
        (work / 'nueva').unlink(missing_ok=True)
    return ok


rc = 1
try:
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGALRM):
        signal.signal(sig, interrupted)
    require(socket.gethostname() == 'zp-ldap-01', 'Solo se permite zp-ldap-01.')
    addresses = run(['ip', '-4', '-o', 'addr', 'show'])
    require(any(re.search(r'\binet ' + re.escape(IP) + r'/', line) for line in addresses.splitlines()),
            'La IP local no es 10.20.0.69.')
    run(['systemctl', 'is-active', '--quiet', 'slapd'])
    root = Path('/root/final-config')
    require(not root.is_symlink(), 'El directorio de registros no puede ser un enlace.')
    root.mkdir(mode=0o700, exist_ok=True)
    lock = (root / '.P4_ldap_local.lock').open('a')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise Failure('Ya hay otra recuperación local en ejecución.') from None
    work = Path(tempfile.mkdtemp(prefix='P4_ldap_local_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ_'), dir=root))
    log = work / 'resultado.txt'
    say('[INFO] Registro y respaldo privados: ' + str(work))
    identity = run(['ldapwhoami', *LOCAL]).strip()
    require(identity.lower() == ('dn:' + IDENTITY).lower(), 'Identidad SASL EXTERNAL inesperada.')
    # Comprueba que esta es la única base del sufijo antes de fijar su DN.
    found = run(['ldapsearch', *LOCAL, '-LLL', '-o', 'ldif_wrap=no', '-b', 'cn=config',
                 '(olcSuffix=' + BASE + ')', 'dn'])
    single(found, DB)
    before, original = snapshot()
    require(original == EXPECTED, 'Las ACL no coinciden con las tres reglas revisadas; no se modifica nada.')
    (work / 'acl-original.ldif').write_text(before)
    single(run(['ldapsearch', *LOCAL, '-LLL', '-o', 'ldif_wrap=no', '-b', TARGET,
                '-s', 'base', '(uid=ventas01)', 'uid']), TARGET)
    run(['openssl', 'verify', '-CAfile', CERT, '-purpose', 'sslserver', '-verify_ip', IP, CERT])
    fingerprint = run(['openssl', 'x509', '-in', CERT, '-noout', '-fingerprint', '-sha256']).strip()
    require(fingerprint.split('=', 1)[-1] == 'A9:AE:94:A9:13:AA:7B:DC:10:FD:03:AF:D2:52:52:92:DD:B6:08:53:7F:72:7C:B2:68:65:F1:66:7F:B1:D5:0F',
            'La huella del certificado no coincide con la revisada.')
    say('[OK] Servicio, identidad local, base, tres ACL, usuario y certificado comprobados')
    if MODE == '--validar':
        say('[OK] Validación terminada; no se modificaron LDAP ni slapd')
    else:
        password_read()
        require(snapshot()[1] == original, 'Las ACL cambiaron durante la confirmación; no se modifica nada.')
        # Se marca ANTES de enviar: una respuesta perdida también exige limpieza.
        state['acl_attempted'] = True
        modify_config('add', '{0}' + RULE, work / 'agregar-permiso.ldif')
        _, active = snapshot()
        require(len(active) == 4 and normalized(active[0]) == normalized(RULE) and
                [body(r) for r in active[1:]] == [body(r) for r in original],
                'Las ACL resultantes no coinciden; se retira el permiso sin cambiar la contraseña.')
        # Se conserva una retirada revisable para una interrupción no recuperable.
        (work / 'retirar-permiso.ldif').write_text(
            f'dn: {DB}\nchangetype: modify\ndelete: olcAccess\n' + attr('olcAccess', body(active[0])))
        old_text = run(['ldapsearch', *LOCAL, '-LLL', '-o', 'ldif_wrap=no',
                        '-b', TARGET, '-s', 'base', '(objectClass=*)', 'userPassword'])
        old = single(old_text, TARGET).get('userpassword', [])
        require(bool(old), 'No se pudo respaldar userPassword; no se cambia la contraseña.')
        state['old_password'] = old
        (work / 'password-anterior.ldif').write_text(old_text)
        (work / 'restaurar-password.ldif').write_text(
            f'dn: {TARGET}\nchangetype: modify\nreplace: userPassword\n' + ''.join(attr('userPassword', p) for p in old))
        say('[OK] Permiso temporal comprobado y atributo anterior respaldado de forma privada')
        state['password_attempted'] = True
        run(['ldappasswd', *LOCAL, '-T', str(work / 'nueva'), TARGET])
        env = dict(os.environ, LDAPTLS_CACERT=CERT, LDAPTLS_REQCERT='demand')
        env.pop('LDAPNOINIT', None)
        who = run(['ldapwhoami', '-x', '-H', 'ldaps://' + IP, '-o', 'nettimeout=5',
                   '-D', TARGET, '-y', str(work / 'nueva')], env=env).strip()
        require(who.lower() == ('dn:' + TARGET).lower(), 'El bind no confirmó ventas01.')
        state['confirmed'] = True
    rc = 0
except Failure as exc:
    say('[FALLA] ' + str(exc))
except (OSError, ValueError, KeyError):
    say('[FALLA] Respuesta o archivo inesperado; se ejecuta la limpieza sin imprimir datos privados')
finally:
    if not cleanup():
        rc = 1
if rc == 0 and MODE == 'cambiar':
    say('[OK] Contraseña de ventas01 cambiada, bind LDAPS confirmado y ACL originales restauradas')
    say('[INFO] Conserva la contraseña en tu gestor o .env local ignorado; no la compartas en el chat')
elif rc != 0 and state['confirmed']:
    say('[ATENCION] La nueva contraseña sí permitió el bind, pero la recuperación quedó incompleta; consérvala y revisa el fallo')
sys.exit(rc)
PY
