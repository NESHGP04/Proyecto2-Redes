"""Rescate de archivos con transporte simulado, sin AWS y sin credenciales reales."""
import importlib.util
import os
from pathlib import Path
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
CONFIG = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('p4', CONFIG / 'P4_snmp.py')
p4 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p4)


class Rescate(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
        self.env = self.base / '.config/zenite-p4/.env.p4-snmp'
        self.env.parent.mkdir(parents=True, mode=0o700)
        self.env.touch(mode=0o600)
        self.values = {p4.KEYS[0]: 'syntheticMonitor', p4.KEYS[1]: secrets.token_urlsafe(32), p4.KEYS[2]: secrets.token_urlsafe(32)}
        self.source = self.base / 'monitor-secret-fixture'
        p4.write(self.source, p4.envtext(self.values))
        shutil.copyfile(CONFIG / 'P4_snmp.py', self.base / 'P4_snmp.py')
        for name in ['P4_snmp.sh', 'P4_snmp_objetivos.csv']:
            (self.base / name).touch()
        (self.base / 'P3_eice.sh').write_text('''#!/bin/bash
set -euo pipefail
p4_fixture="$(cd -- "$(dirname -- "$0")" && pwd)"
printf '%s %s\n' "$1" "${2:0:9}" >> "$p4_fixture/calls-fixture"
case "${2:-}" in
  --traer)
    cp -- "$p4_fixture/monitor-secret-fixture" "$4"
    chmod 600 "$4"
    [[ ! -e "$p4_fixture/fail-fetch" ]]
    ;;
  --copiar)
    [[ ! -e "$p4_fixture/fail-copy" ]]
    mkdir -p "$p4_fixture/intranet-fixture"
    shift 2
    for p4_file in "$@"; do
      test -s "$p4_file"
      cp -- "$p4_file" "$p4_fixture/intranet-fixture/"
    done
    ;;
  *)
    if [[ "$2" == *'rm --'* ]]; then
      rm -- "$p4_fixture/remote-stage-fixture"
    else
      cp -- "$p4_fixture/monitor-secret-fixture" "$p4_fixture/remote-stage-fixture"
    fi
    ;;
esac
''')

    def execute(self, answer='si'):
        result = subprocess.run(['bash', str(CONFIG / 'P4_recuperar_archivos_cloudshell.sh'), str(self.base)],
                                input=answer + '\n', text=True, capture_output=True, timeout=15)
        for secret in [self.values[p4.KEYS[1]], self.values[p4.KEYS[2]]]:
            self.assertNotIn(secret, result.stdout + result.stderr)
        return result

    def test_empty_files_restore_exact_public_files_and_same_credentials(self):
        result = self.execute()
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in ['P4_snmp.sh', 'P4_snmp_objetivos.csv']:
            self.assertEqual((self.base / name).read_bytes(), (CONFIG / name).read_bytes())
        self.assertEqual(p4.private(self.env), self.values)
        self.assertEqual(stat.S_IMODE(self.env.stat().st_mode), 0o600)
        self.assertFalse((self.base / 'remote-stage-fixture').exists())
        self.assertEqual((self.base / 'intranet-fixture/.env.p4-snmp').read_bytes(), self.env.read_bytes())
        for run in (self.base / 'final-config').iterdir():
            self.assertEqual(stat.S_IMODE(run.stat().st_mode), 0o700)
            self.assertFalse((run / '.env.recuperada-temporal').exists())
            for file in run.iterdir():
                self.assertEqual(stat.S_IMODE(file.stat().st_mode), 0o600)

    def test_wrong_nonempty_public_file_is_preserved_before_transport(self):
        path = self.base / 'P4_snmp.sh'
        path.write_text('different custom configuration')
        result = self.execute()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(path.read_text(), 'different custom configuration')
        self.assertFalse((self.base / 'calls-fixture').exists())

    def test_other_local_credentials_preserved_without_rotation(self):
        other = dict(self.values, SNMP_AUTH_PASSWORD=secrets.token_urlsafe(32))
        p4.write(self.env, p4.envtext(other))
        result = self.execute()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(p4.private(self.env), other)
        self.assertFalse((self.base / 'remote-stage-fixture').exists())
        self.assertEqual((self.base / 'P4_snmp.sh').stat().st_size, 0)

    def test_partial_fetch_is_cleaned_and_no_false_success(self):
        (self.base / 'fail-fetch').touch()
        result = self.execute()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.base / 'remote-stage-fixture').exists())
        self.assertFalse(list((self.base / 'final-config').glob('*/.env.recuperada-temporal')))
        self.assertEqual(self.env.stat().st_size, 0)
        self.assertNotIn('Archivos corregidos copiados', result.stdout)

    def test_failed_copy_keeps_cloud_recovery_and_reports_failure(self):
        (self.base / 'fail-copy').touch()
        result = self.execute()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(p4.private(self.env), self.values)
        self.assertFalse((self.base / 'remote-stage-fixture').exists())
        self.assertNotIn('Archivos corregidos copiados', result.stdout)

    def test_cancel_has_no_mutations(self):
        result = self.execute('no')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.base / 'final-config').exists())
        self.assertFalse((self.base / 'calls-fixture').exists())

    def test_wrong_core_is_not_imported(self):
        marker = self.base / 'unsafe-code-executed'
        (self.base / 'P4_snmp.py').write_text('from pathlib import Path\nPath(' + repr(str(marker)) + ').touch()\n')
        result = self.execute()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(marker.exists())
        self.assertFalse((self.base / 'calls-fixture').exists())

    def test_existing_correct_files_and_credentials_can_be_recovered_again(self):
        self.assertEqual(self.execute().returncode, 0)
        self.assertEqual(self.execute().returncode, 0)
        self.assertEqual(p4.private(self.env), self.values)


if __name__ == '__main__':
    unittest.main()
