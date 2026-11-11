"""Regresiones locales: no modifica servicios, AWS ni archivos del sistema."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tarfile
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('p4', Path(__file__).resolve().parents[1] / 'P4_snmp.py')
p4 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p4)


class Seguridad(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.values = {p4.KEYS[0]: 'syntheticMonitor', p4.KEYS[1]: secrets.token_urlsafe(32),
                       p4.KEYS[2]: secrets.token_urlsafe(32)}
        self.file = self.root / '.env.p4-snmp'
        self.file.write_text(p4.envtext(self.values))
        self.file.chmod(0o600)

    def tearDown(self):
        self.temp.cleanup()

    def test_private_regular_credentials(self):
        self.assertEqual(p4.private(self.file), self.values)

    def test_permissions_and_symlinks_rejected(self):
        self.file.chmod(0o644)
        with self.assertRaises(p4.Failure): p4.private(self.file)
        self.file.chmod(0o600)
        link = self.root / 'link'
        link.symlink_to(self.file)
        with self.assertRaises(p4.Failure): p4.private(link)

    def test_shell_payload_not_executed(self):
        self.file.write_text('SNMP_V3_USER=$(touch ' + str(self.root / 'unexpected') + ')\n')
        with self.assertRaises(p4.Failure): p4.private(self.file)
        self.assertFalse((self.root / 'unexpected').exists())

    def test_equal_keys_rejected(self):
        self.values[p4.KEYS[2]] = self.values[p4.KEYS[1]]
        self.file.write_text(p4.envtext(self.values))
        with self.assertRaises(p4.Failure): p4.private(self.file)

    def test_no_such_with_exit_zero_rejected(self):
        bad = subprocess.CompletedProcess([], 0, '.1.2.3 = No Such Instance currently exists at this OID\n', '')
        with self.assertRaises(p4.Failure): p4.good_query(bad, 'test')

    def test_valid_walk_can_end_at_mib_boundary(self):
        value = '.1.2.3.0 = INTEGER: 1\n.1.2.3.0 = No more variables left in this MIB View\n'
        p4.good_query(subprocess.CompletedProcess([], 0, value, ''), 'test')

    def test_output_redacts_known_keys(self):
        p4.private(self.file)
        self.assertNotIn(self.values[p4.KEYS[1]], p4.clean(self.values[p4.KEYS[1]]))

    def test_wrong_host_rejected_before_commands(self):
        with patch.object(p4.os, 'geteuid', return_value=0), patch.object(p4.socket, 'gethostname', return_value='cloudshell'), patch.object(p4, 'run') as run:
            with self.assertRaises(p4.Failure): p4.guard()
            run.assert_not_called()

    def test_monitor_operations_reject_other_hosts(self):
        with patch.object(p4.os, 'geteuid', return_value=0), patch.object(p4.socket, 'gethostname', return_value='zp-ventas-01'), patch.object(p4, 'run') as run:
            with self.assertRaises(p4.Failure): p4.guard(monitor=True)
            run.assert_not_called()

    def test_read_only_user_required(self):
        with patch.object(p4.os, 'geteuid', return_value=1000):
            with self.assertRaises(p4.Failure): p4.guard()

    def test_agent_conflict_causes_no_installation(self):
        with patch.object(p4, 'STATE', self.root), patch.object(p4, 'tools'), patch.object(p4, 'is_installed', return_value=True), patch.object(p4, 'package_install') as install:
            with self.assertRaises(p4.Failure): p4.agent_install('zp-monitor-01', 'ubuntu', self.values)
            install.assert_not_called()

    def test_marker_does_not_allow_wrong_credentials(self):
        (self.root / 'agent.json').write_text(json.dumps({'credentials': 'different'}))
        with patch.object(p4, 'STATE', self.root), patch.object(p4, 'tools'), patch.object(p4, 'agent_validate') as validate:
            with self.assertRaises(p4.Failure): p4.agent_install('zp-monitor-01', 'ubuntu', self.values)
            validate.assert_not_called()

    def test_retained_config_is_not_overwritten_when_package_absent(self):
        retained = self.root / 'snmpd.conf'
        retained.write_text('# configuración anterior\n')
        with patch.object(p4, 'STATE', self.root), patch.object(p4, 'CONFIG', retained), patch.object(p4, 'tools'), patch.object(p4, 'is_installed', return_value=False), patch.object(p4, 'package_install') as install:
            with self.assertRaises(p4.Failure): p4.agent_install('zp-monitor-01', 'ubuntu', self.values)
            install.assert_not_called()
            self.assertEqual(retained.read_text(), '# configuración anterior\n')

    def test_incomplete_metrics_rejected(self):
        with self.assertRaises(p4.Failure): p4.family_data('storage', '.1.2.3 = INTEGER: 1')
        with self.assertRaises(p4.Failure): p4.family_data('disco', '.1.2.3 = INTEGER: 1')
        with self.assertRaises(p4.Failure): p4.family_data('cpu', '.1.2.3 = INTEGER: 1')

    def test_process_error_is_not_pass(self):
        data = '.1.3.6.1.4.1.2021.2.1.5.1 = INTEGER: 0\n.1.3.6.1.4.1.2021.2.1.100.1 = INTEGER: 1'
        with self.assertRaises(p4.Failure): p4.family_data('procesos', data)

    def test_origin_uses_remote_ldap_and_real_timeout(self):
        response = subprocess.CompletedProcess([], 1, '', 'Timeout: No Response from 10.20.0.69')
        with patch.object(p4, 'query', return_value=response), patch.object(p4, 'RUN_DIR', None), contextlib.redirect_stdout(io.StringIO()) as out:
            p4.origin_probe('zp-ventas-01', self.values, ['zp-ldap-01'])
            self.assertIn('[PENDIENTE]', out.getvalue())
            self.assertNotIn('[OK]', out.getvalue())
        with self.assertRaises(p4.Failure): p4.origin_probe('zp-ventas-01', self.values, ['zp-ventas-01'])

    def archive(self, entries):
        stream = io.BytesIO()
        with tarfile.open(fileobj=stream, mode='w') as archive:
            for name, kind in entries:
                member = tarfile.TarInfo(name)
                member.type = kind
                if kind in {tarfile.SYMTYPE, tarfile.LNKTYPE}:
                    member.linkname = '/tmp/unexpected'
                archive.addfile(member)
        stream.seek(0)
        return tarfile.open(fileobj=stream)

    def test_release_root_directory_without_slash_is_accepted(self):
        with self.archive([('release', tarfile.DIRTYPE), ('release/bin', tarfile.REGTYPE)]) as archive:
            p4.extract_bundle(archive, self.root / 'extract', 'release')
        self.assertTrue((self.root / 'extract/release/bin').is_file())

    def test_release_rejects_unsafe_entries_before_writing(self):
        cases = [('release', tarfile.REGTYPE), ('release/../../escape', tarfile.REGTYPE),
                 ('/release/escape', tarfile.REGTYPE), ('other/bin', tarfile.REGTYPE),
                 ('release/link', tarfile.SYMTYPE), ('release/hard', tarfile.LNKTYPE),
                 ('release/pipe', tarfile.FIFOTYPE), ('release/device', tarfile.CHRTYPE)]
        for entry in cases:
            with self.subTest(entry=entry), self.archive([('release/good', tarfile.REGTYPE), entry]) as archive:
                with self.assertRaises(p4.Failure):
                    p4.extract_bundle(archive, self.root / 'rejected', 'release')
                self.assertFalse((self.root / 'rejected').exists())

    def test_empty_release_is_rejected(self):
        with self.archive([]) as archive:
            with self.assertRaises(p4.Failure):
                p4.extract_bundle(archive, self.root / 'empty', 'release')


@unittest.skipUnless(os.geteuid() == 0, 'Recuperación: ejecutar en contenedor como root sobre archivos temporales.')
class RecuperacionDescarga(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.conf, self.state = self.root / 'conf', self.root / 'state'
        self.logs = self.root / 'logs'
        self.current = self.logs / 'current'
        self.log = self.logs / 'P4_snmp_zp-monitor-01_fixture' / 'resultado.txt'
        self.log.parent.mkdir(parents=True)
        self.current.mkdir()
        self.conf.mkdir(mode=0o750)
        self.state.mkdir(mode=0o750)
        self.data = self.state / 'prometheus'
        self.data.mkdir(mode=0o700)
        self.account = SimpleNamespace(pw_uid=999, pw_gid=998, pw_shell='/usr/sbin/nologin', pw_dir='/home/p4monitor')
        for folder in [self.conf, self.state]:
            os.chown(folder, 0, self.account.pw_gid)
        os.chown(self.data, self.account.pw_uid, self.account.pw_gid)
        self.values = {p4.KEYS[0]: 'syntheticMonitor', p4.KEYS[1]: secrets.token_urlsafe(32), p4.KEYS[2]: secrets.token_urlsafe(32)}
        self.env = self.conf / 'snmp.env'
        p4.write(self.env, p4.envtext(self.values))
        p4.write(self.state / 'agent.json', '{}')
        self.failed = self.state / 'monitor.failed'
        p4.write(self.failed, 'Instalación parcial; servicios detenidos. Conservar diagnóstico y revisar archivos P4.')
        p4.write(self.log, '[PLAN] Instalar Prometheus 3.16.0 y snmp_exporter 0.31.0\n[FALLA] Archivo de release con rutas inesperadas.\n')
        self.units = [self.root / 'p4-prometheus.service', self.root / 'p4-snmp-exporter.service']
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.addCleanup(self.temp.cleanup)
        for name, value in [('CONF', self.conf), ('STATE', self.state), ('ENVFILE', self.env),
                            ('FINALROOT', self.logs), ('RUN_DIR', self.current),
                            ('MONITOR_BIN', self.root / 'bin'), ('MONITOR_UNITS', self.units)]:
            self.stack.enter_context(patch.object(p4, name, value))
        self.stack.enter_context(patch.object(p4.pwd, 'getpwnam', return_value=self.account))
        self.stack.enter_context(patch.object(p4.grp, 'getgrgid', return_value=SimpleNamespace(gr_name='p4monitor', gr_mem=[])))
        self.stack.enter_context(patch.object(p4.socket, 'gethostname', return_value='zp-monitor-01'))
        self.stack.enter_context(patch.object(p4.shutil, 'disk_usage', return_value=SimpleNamespace(free=8 * 1024 ** 3)))
        self.validate = self.stack.enter_context(patch.object(p4, 'agent_validate'))
        self.confirm = self.stack.enter_context(patch.object(p4, 'confirm'))
        self.install = self.stack.enter_context(patch.object(p4, 'package_install'))
        self.run = self.stack.enter_context(patch.object(p4, 'run', side_effect=self.command))
        self.stack.enter_context(contextlib.redirect_stdout(io.StringIO()))

    def command(self, argv, **kwargs):
        rc = 1 if argv[0] in {'pgrep', 'getent'} else 3 if argv[:2] == ['systemctl', 'is-active'] else 0
        return subprocess.CompletedProcess(argv, rc, '', '')

    def test_expected_partial_state_is_read_only_and_validates_agent(self):
        marker = self.failed.read_bytes()
        self.assertEqual(p4.monitor_download_recovery(self.values, self.log), self.account)
        self.assertEqual(self.failed.read_bytes(), marker)
        self.assertEqual(self.env.read_text(), p4.envtext(self.values))
        self.validate.assert_called_once()
        self.install.assert_not_called()

    def test_data_prevents_recovery_without_mutation(self):
        (self.data / 'wal').mkdir()
        with self.assertRaises(p4.Failure): p4.monitor_install(self.values, self.log)
        self.assertTrue(self.failed.exists())
        self.confirm.assert_not_called()
        self.install.assert_not_called()

    def test_existing_unit_prevents_recovery(self):
        self.units[0].write_text('existing unit')
        with self.assertRaises(p4.Failure): p4.monitor_install(self.values, self.log)
        self.assertTrue(self.failed.exists())
        self.confirm.assert_not_called()

    def test_other_failure_prevents_recovery(self):
        self.log.write_text('[FALLA] Another error\n')
        with self.assertRaises(p4.Failure): p4.monitor_install(self.values, self.log)
        self.assertTrue(self.failed.exists())
        self.install.assert_not_called()

    def test_active_process_prevents_recovery(self):
        self.run.side_effect = lambda argv, **kw: subprocess.CompletedProcess(argv, 0 if argv[0] == 'pgrep' else 3, '', '')
        with self.assertRaises(p4.Failure): p4.monitor_install(self.values, self.log)
        self.confirm.assert_not_called()

    def test_ordinary_install_keeps_partial_state_blocked(self):
        with self.assertRaises(p4.Failure): p4.monitor_install(self.values)
        self.assertTrue(self.failed.exists())
        self.install.assert_not_called()

    def test_cancel_keeps_original_marker_and_credentials(self):
        self.confirm.side_effect = p4.Failure('cancelled')
        with self.assertRaises(p4.Failure): p4.monitor_install(self.values, self.log)
        self.assertTrue(self.failed.exists())
        self.assertFalse((self.current / 'monitor.failed.previo').exists())
        self.install.assert_not_called()
        self.assertEqual(self.env.read_text(), p4.envtext(self.values))

    def test_retry_failure_archives_marker_reuses_user_and_keeps_agent(self):
        with patch.object(p4, 'download_bundle', side_effect=p4.Failure('simulated download failure')):
            with self.assertRaises(p4.Failure): p4.monitor_install(self.values, self.log)
        self.assertTrue((self.current / 'monitor.failed.previo').is_file())
        self.assertTrue(self.failed.is_file())
        self.assertTrue((self.state / 'agent.json').is_file())
        self.assertEqual(self.env.read_text(), p4.envtext(self.values))
        self.assertFalse(any(call.args[0][0] == 'useradd' for call in self.run.call_args_list))
        self.assertFalse(any(call.args[0][:2] == ['systemctl', 'stop'] and 'snmpd' in call.args[0] for call in self.run.call_args_list))

    def test_retry_completion_preserves_agent_and_normal_repeat_is_idempotent(self):
        bundle = self.root / 'fixture-bundle'
        bundle.mkdir()
        for name in ['snmp_exporter', 'prometheus', 'promtool']:
            (bundle / name).write_text('fixture binary, not executed')
        yaml = SimpleNamespace(safe_dump=lambda *a, **kw: 'fixture: yaml\n')
        with patch.object(p4, 'download_bundle', return_value=bundle), patch.object(p4, 'exporter_config', return_value={}), \
                patch.dict(sys.modules, {'yaml': yaml}), patch.object(p4, 'http', return_value='Prometheus Server is Ready.'), \
                patch.object(p4, 'monitor_validate') as validate:
            p4.monitor_install(self.values, self.log)
            self.assertTrue((self.current / 'monitor.failed.previo').is_file())
            self.assertFalse(self.failed.exists())
            self.assertTrue((self.state / 'monitor.json').is_file())
            self.assertEqual((self.state / 'agent.json').read_text(), '{}')
            self.assertEqual(self.env.read_text(), p4.envtext(self.values))
            self.assertTrue(all(unit.is_file() for unit in self.units))
            calls = self.install.call_count
            p4.monitor_install(self.values)
            self.assertEqual(self.install.call_count, calls)
            self.assertEqual(validate.call_count, 2)


if __name__ == '__main__':
    unittest.main()
