"""Pruebas del túnel con AWS/SSH/socket sustituidos; no usa credenciales reales."""
import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'P4_grafana_tunel.sh'
SOURCE = SCRIPT.read_text().split("<<'PY'\n", 1)[1].rsplit('\nPY', 1)[0]


class TunnelCases(unittest.TestCase):
    def execute(self, profile='zenite-ti', account='703461917799', state='running', ssh_status=0):
        self.commands = []
        self.ssh = []
        self.output = io.StringIO()

        def fake_run(argv, **kwargs):
            self.commands.append(argv)
            if argv[0] == 'ssh-keygen':
                Path(argv[-1]).write_text('synthetic-private-key')
                Path(argv[-1] + '.pub').write_text('synthetic-public-key')
                text = ''
            elif 'get-caller-identity' in argv:
                text = account
            elif 'describe-instances' in argv:
                text = json.dumps({'Reservations': [{'Instances': [{'VpcId': 'vpc-0e4c1d0b2314ab4df',
                    'PrivateIpAddress': '10.20.0.103', 'State': {'Name': state},
                    'Tags': [{'Key': 'Name', 'Value': 'zp-monitor-01'}]}]}]})
            elif 'send-ssh-public-key' in argv:
                text = '{"Success": true}'
            else:
                raise AssertionError('Llamada no prevista: ' + str(argv))
            return subprocess.CompletedProcess(argv, 0, text, '')

        def fake_ssh(argv):
            self.ssh.append(argv)
            self.key = Path(argv[argv.index('-i') + 1])
            self.assertTrue(self.key.is_file())
            return ssh_status

        with tempfile.TemporaryDirectory() as folder, patch.object(Path, 'home', return_value=Path(folder)), \
             patch.object(sys, 'argv', ['test', profile]), patch('shutil.which', return_value='/fake/tool'), \
             patch('socket.socket'), patch('socket.gethostname', return_value='fedora'), \
             patch('subprocess.run', side_effect=fake_run), patch('subprocess.call', side_effect=fake_ssh), \
             contextlib.redirect_stdout(self.output):
            exec(compile(SOURCE, str(SCRIPT), 'exec'), {'__name__': 'test_tunnel'})

    def test_loopback_eice_and_key_cleanup(self):
        self.execute()
        ssh = self.ssh[0]
        self.assertEqual(ssh[ssh.index('-L') + 1], '127.0.0.1:3000:127.0.0.1:3000')
        proxy = next(a for a in ssh if a.startswith('ProxyCommand='))
        self.assertIn('--remote-port 22', proxy)
        self.assertIn('--instance-connect-endpoint-id eice-0f41a9a04ed4dc3e2', proxy)
        self.assertNotIn('0.0.0.0', str(ssh))
        self.assertFalse(self.key.exists())
        self.assertNotIn('synthetic-private-key', self.output.getvalue())

    def test_foreign_account_blocks_key_and_ssh(self):
        with self.assertRaises(SystemExit):
            self.execute(account='000000000000')
        self.assertFalse(self.ssh)
        self.assertFalse(any('send-ssh-public-key' in a for a in self.commands))

    def test_stopped_monitor_blocks_key_and_ssh(self):
        with self.assertRaises(SystemExit):
            self.execute(state='stopped')
        self.assertFalse(self.ssh)

    def test_untrusted_profile_never_reaches_shell(self):
        with self.assertRaises(SystemExit):
            self.execute(profile='test; touch /tmp/never')
        self.assertFalse(self.commands)

    def test_ssh_failure_still_removes_private_key(self):
        with self.assertRaises(SystemExit):
            self.execute(ssh_status=255)
        self.assertFalse(self.key.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
