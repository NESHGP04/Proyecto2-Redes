"""Pruebas locales sin AWS, sin servicios y con contraseñas sintéticas."""
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import Mock, patch

BASE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('grafana_test', BASE / 'P4_grafana.py')
g = importlib.util.module_from_spec(spec)
spec.loader.exec_module(g)


class GrafanaCases(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.p4 = Mock()
        self.p4.SECRETS = []
        self.patches = [patch.object(g, 'p4', self.p4)]
        for name in ['CONF', 'DATA', 'LIB', 'UNIT', 'MARKER', 'FAILED']:
            self.patches.append(patch.object(g, name, self.root / name))
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()
        self.tmp.cleanup()

    def archive(self, members):
        out = io.BytesIO()
        with tarfile.open(fileobj=out, mode='w') as archive:
            for name, kind in members:
                item = tarfile.TarInfo(name)
                item.type = kind
                item.linkname = '/tmp/never-write'
                archive.addfile(item)
        out.seek(0)
        return tarfile.open(fileobj=out)

    def test_reject_archive_before_any_extraction(self):
        for name, kind in [('grafana-13.3.0/../outside', tarfile.REGTYPE),
                           ('/grafana-13.3.0/file', tarfile.REGTYPE),
                           ('foreign/file', tarfile.REGTYPE),
                           ('grafana-13.3.0/link', tarfile.SYMTYPE),
                           ('grafana-13.3.0/hard', tarfile.LNKTYPE),
                           ('grafana-13.3.0/device', tarfile.CHRTYPE)]:
            with self.subTest(name=name, kind=kind):
                with self.archive([('grafana-13.3.0/good', tarfile.REGTYPE), (name, kind)]) as archive:
                    with self.assertRaises(RuntimeError):
                        g.extract(archive, self.root)
                self.assertFalse((self.root / 'grafana-13.3.0').exists())

    def test_root_directory_without_trailing_slash_accepted(self):
        with self.archive([('grafana-13.3.0', tarfile.DIRTYPE), ('grafana-13.3.0/file', tarfile.REGTYPE)]) as archive:
            result = g.extract(archive, self.root)
        self.assertTrue((result / 'file').is_file())

    def test_bad_package_rejected(self):
        package = self.root / 'package'
        package.write_bytes(b'untrusted')
        with self.assertRaises(RuntimeError):
            g.verified(package)
        alias = self.root / 'link'
        alias.symlink_to(package)
        with self.assertRaises(RuntimeError):
            g.verified(alias)

    def test_invalid_arch_stops_before_monitor_or_mutations(self):
        with patch.object(g.os, 'uname') as uname:
            uname.return_value.machine = 'aarch64'
            with self.assertRaises(RuntimeError):
                g.preflight()
        self.p4.monitor_validate.assert_not_called()
        self.p4.run.assert_not_called()

    def test_partial_installation_blocks_retry(self):
        g.FAILED.write_text('partial')
        with self.assertRaisesRegex(RuntimeError, 'parcial'):
            g.preflight()
        self.p4.run.assert_not_called()

    def test_foreign_installation_is_not_overwritten(self):
        g.CONF.mkdir()
        original = g.CONF / 'original'
        original.write_text('keep')
        with self.assertRaisesRegex(RuntimeError, 'preexistente'):
            g.preflight()
        self.assertEqual(original.read_text(), 'keep')

    def test_cancelled_installation_no_mutations(self):
        self.p4.confirm.side_effect = RuntimeError('cancelled')
        with patch.object(g, 'preflight'), patch.object(g, 'verified'):
            with self.assertRaisesRegex(RuntimeError, 'cancelled'):
                g.install(self.root / 'package')
        self.p4.run.assert_not_called()
        self.assertFalse(g.CONF.exists())

    def test_bad_password_does_not_create_user_or_files(self):
        with patch.object(g, 'preflight'), patch.object(g, 'verified'), \
             patch.object(g.sys.stdin, 'isatty', return_value=True), \
             patch.object(g.getpass, 'getpass', return_value='short'):
            with self.assertRaises(RuntimeError):
                g.install(self.root / 'package')
        self.p4.run.assert_not_called()
        self.assertFalse(g.CONF.exists())

    def test_repeated_installation_keeps_database_and_credentials(self):
        g.MARKER.write_text('{}')
        with patch.object(g, 'preflight') as preflight, patch.object(g, 'verified') as verified:
            g.install(self.root / 'package')
        preflight.assert_called_once()
        verified.assert_not_called()
        self.p4.confirm.assert_not_called()

    def test_dashboard_and_service_do_not_contain_passwords_or_public_endpoints(self):
        dashboard = g.dashboard()
        self.assertEqual(len(dashboard['panels']), 10)
        self.assertEqual(len({p['id'] for p in dashboard['panels']}), 10)
        for panel in dashboard['panels']:
            self.assertEqual(panel['datasource']['uid'], g.DS_UID)
        text = g.configuration()
        self.assertIn('http_addr = 127.0.0.1', text)
        self.assertIn('admin_password = $__file{', text)
        self.assertIn('[auth.anonymous]\nenabled = false', text)
        self.assertNotIn('0.0.0.0', text)
        self.assertNotIn('SNMP_AUTH_PASSWORD', json.dumps(dashboard) + text + g.unit())
        self.assertNotIn('p4monitor\n', g.unit())

    def test_origin_wrong_host_does_not_query_network(self):
        with patch.object(g.socket, 'gethostname', return_value='cloudshell'), patch.object(g.socket, 'create_connection') as connect:
            with self.assertRaises(RuntimeError):
                g.origin()
        connect.assert_not_called()

    def test_origin_unexpected_success_rejected(self):
        with patch.object(g.socket, 'gethostname', return_value='zp-ventas-01'), patch.object(g.socket, 'create_connection'):
            with self.assertRaises(RuntimeError):
                g.origin()

    def test_origin_timeout_requires_correlated_controls(self):
        with patch.object(g.socket, 'gethostname', return_value='zp-ventas-01'), \
             patch.object(g.socket, 'create_connection', side_effect=TimeoutError):
            g.origin()
        self.assertTrue(any('[PENDIENTE]' in call.args[0] for call in self.p4.say.call_args_list))

    def test_origin_accepts_socket_timeout_name_from_py39(self):
        # En Python 3.9, socket.timeout es una clase distinta cuyo __name__ es "timeout".
        with patch.object(g.socket, 'gethostname', return_value='zp-ventas-01'), \
             patch.object(g.socket, 'create_connection', side_effect=g.socket.timeout(5)):
            g.origin()
        self.assertTrue(any('[OBSERVADO]' in call.args[0] for call in self.p4.say.call_args_list))


if __name__ == '__main__':
    unittest.main(verbosity=2)
