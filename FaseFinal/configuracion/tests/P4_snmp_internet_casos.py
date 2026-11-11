#!/usr/bin/env python3
"""Prueba local del conductor exterior: red y AWS sustituidos, claves sintéticas."""
import copy
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

BASE = Path(__file__).resolve().parents[1]
source = (BASE / 'P4_snmp_internet.sh').read_text().split("<<'PY'\n", 1)[1].rsplit('\nPY', 1)[0]
ns = {'__name__': 'internet_test'}
exec(compile(source, 'P4_snmp_internet.sh:python', 'exec'), ns)
spec = importlib.util.spec_from_file_location('core_test', BASE / 'P4_snmp.py')
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)
Probe = ns['Probe']
result = lambda code=0, out='', err='': subprocess.CompletedProcess([], code, out, err)


class FakeProbe(Probe):
    def __init__(self, base, p4, folder):
        super().__init__(base, p4, folder)
        self.calls = []
        self.fail_control = None
        self.fail_copy = False
        self.fail_cleanup = False

    def remote(self, command):
        self.calls.append(command)
        if 'P4_TEMPORAL_ELIMINADO' in command:
            return result(1 if self.fail_cleanup else 0, 'P4_TEMPORAL_ELIMINADO')
        if 'P4_TEMPORAL_AUSENTE' in command:
            return result(out='P4_TEMPORAL_AUSENTE')
        if 'P4_TEMPORAL_PRIVADO' in command:
            return result(out='P4_TEMPORAL_PRIVADO')
        name = next(n for n in ns['HOSTS'] if n in command)
        phase = sum('control --host ' + name in c for c in self.calls)
        if self.fail_control == (name, phase):
            return result(out='')  # Un wrapper vacío podría devolver exit 0.
        return result(out='STRING: "' + name + '"\n[OK] Control autenticado desde monitor, exit=0.')

    def execute(self, argv, timeout=60):
        self.calls.append(argv)
        if '--copiar' in argv:
            assert self.stage.stat().st_mode & 0o777 == 0o600
        return result(1 if self.fail_copy else 0)


class InternetTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.folder = Path(self.tmp.name)
        self.values = dict(zip(core.KEYS, ['syntheticRO', 'A' * 43, 'B' * 43]))
        self.logs = []
        self.p4 = types.SimpleNamespace(write=core.write, envtext=core.envtext,
                                        say=self.logs.append, Failure=core.Failure,
                                        query=Mock(return_value=result(1, err='Timeout: No Response')))
        self.probe = FakeProbe(self.folder, self.p4, self.folder)
        self.targets = dict(zip(ns['HOSTS'], ['8.8.8.8', '1.1.1.1']))  # Nunca se consultan.

    def tearDown(self):
        self.tmp.cleanup()

    def run_probe(self):
        return self.probe.run(self.values, self.targets)

    def test_success_same_keys_cleanup_and_four_controls(self):
        self.run_probe()
        self.assertEqual(self.p4.query.call_count, 2)
        for call in self.p4.query.call_args_list:
            self.assertIs(call.args[0], self.values)
        self.assertEqual(sum(isinstance(c, str) and 'control --host' in c for c in self.probe.calls), 4)
        self.assertFalse(self.probe.stage.exists())
        self.assertFalse(self.probe.remote_possible)
        rendered = str(self.probe.calls) + str(self.logs)
        self.assertNotIn(self.values[core.KEYS[1]], rendered)
        self.assertNotIn(self.values[core.KEYS[2]], rendered)

    def test_empty_previous_control_blocks_public_queries(self):
        self.probe.fail_control = ('zp-web-01', 1)
        with self.assertRaises(RuntimeError):
            self.run_probe()
        self.p4.query.assert_not_called()
        self.assertFalse(self.probe.remote_possible)

    def test_wrong_key_error_is_not_network_success(self):
        self.p4.query.return_value = result(1, err='Authentication failure')
        with self.assertRaises(RuntimeError):
            self.run_probe()
        self.assertEqual(sum(isinstance(c, str) and 'control --host' in c for c in self.probe.calls), 4)

    def test_public_response_fails_and_postcontrols_still_run(self):
        self.p4.query.return_value = result(out='.1.3.6.1.2.1.1.3.0 = Timeticks: (1)')
        with self.assertRaises(RuntimeError):
            self.run_probe()
        self.assertEqual(sum(isinstance(c, str) and 'control --host' in c for c in self.probe.calls), 4)

    def test_failed_postcontrol_blocks_success(self):
        self.probe.fail_control = ('zp-web-01', 2)
        with self.assertRaises(RuntimeError):
            self.run_probe()
        self.assertFalse(any(line.startswith('[OK] Dos EIP') for line in self.logs))

    def test_partial_copy_is_cleaned(self):
        self.probe.fail_copy = True
        with self.assertRaises(RuntimeError):
            self.run_probe()
        self.p4.query.assert_not_called()
        self.assertFalse(self.probe.stage.exists())
        self.assertFalse(self.probe.remote_possible)

    def test_unconfirmed_cleanup_blocks_success(self):
        self.probe.fail_cleanup = True
        with self.assertRaises(RuntimeError):
            self.run_probe()
        self.assertFalse(self.probe.stage.exists())
        self.assertFalse(any(line.startswith('[OK] Dos EIP') for line in self.logs))

    def test_altered_core_rejected_before_import(self):
        (self.folder / 'P4_snmp.py').write_text('raise AssertionError("must not execute")')
        (self.folder / 'P3_eice.sh').write_text('test')
        with self.assertRaisesRegex(RuntimeError, 'No se importó'):
            ns['load_core'](self.folder)

    def test_destinations_only_own_associated_eips(self):
        hosts, addresses = [], []
        for index, (name, private) in enumerate(ns['HOSTS'].items()):
            public = self.targets[name]
            hosts.append({'Tags': [{'Key': 'Name', 'Value': name}], 'VpcId': ns['VPC'],
                          'PrivateIpAddress': private, 'State': {'Name': 'running'},
                          'PublicIpAddress': public, 'InstanceId': 'i-' + str(index)})
            addresses.append({'PublicIp': public, 'AllocationId': 'eipalloc-test',
                              'AssociationId': 'eipassoc-test', 'InstanceId': 'i-' + str(index)})
        inventory = {'Reservations': [{'Instances': hosts}]}
        self.assertEqual(ns['destinations'](inventory, {'Addresses': addresses}), self.targets)
        for field, value in [('VpcId', 'vpc-foreign'), ('PrivateIpAddress', '10.20.0.69'),
                             ('PublicIpAddress', '10.20.0.116'), ('State', {'Name': 'stopped'})]:
            changed = copy.deepcopy(inventory)
            changed['Reservations'][0]['Instances'][0][field] = value
            with self.subTest(field=field), self.assertRaises((RuntimeError, ValueError)):
                ns['destinations'](changed, {'Addresses': addresses})
        with self.assertRaises(RuntimeError):
            ns['destinations'](inventory, {'Addresses': addresses[:1]})
        hosts.append(copy.deepcopy(hosts[0]))
        with self.assertRaises(RuntimeError):
            ns['destinations'](inventory, {'Addresses': addresses})


if __name__ == '__main__':
    unittest.main(verbosity=2)
