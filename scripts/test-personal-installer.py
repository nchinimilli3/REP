#!/usr/bin/env python3
"""Portable installer checks using temporary fixtures, never physical devices."""
from contextlib import redirect_stdout, redirect_stderr
from datetime import datetime, timedelta, timezone
import importlib.util
import io
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('installer', Path(__file__).with_name('install-personal.py'))
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)
TEAM = 'ABCDEFGHIJ'
BUNDLE = 'com.example.personalrep'
PHONE = {'identifier': 'fixture-phone', 'hardwareProperties': {'deviceType': 'iPhone'},
         'deviceProperties': {'name': 'Fixture Phone'}}
WATCH = {'identifier': 'fixture-watch', 'hardwareProperties': {'deviceType': 'appleWatch'},
         'deviceProperties': {'name': 'Fixture Watch'}}


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='rep-installer-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / 'fitness/fitness.xcodeproj/project.pbxproj'
        self.project.parent.mkdir(parents=True)
        self.project.write_text('\n'.join([
            f'DEVELOPMENT_TEAM = {TEAM};' for _ in range(4)] + [
            f'PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE};' for _ in range(2)] + [
            f'PRODUCT_BUNDLE_IDENTIFIER = {BUNDLE}.watchkitapp;' for _ in range(2)] + [
            f'INFOPLIST_KEY_WKCompanionAppBundleIdentifier = {BUNDLE};' for _ in range(2)]))
        self.info = self.root / 'fitness/WatchInfo.plist'
        self.info.write_bytes(plistlib.dumps({'WKCompanionAppBundleIdentifier': BUNDLE}))
        self.root_patch = patch.object(installer, 'ROOT', self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)

    def args(self, stage='phone', preview=False):
        return SimpleNamespace(stage=stage, team=TEAM, bundle_id=BUNDLE,
                               device='fixture-' + stage, dry_run=preview)

    def test_matching_and_reconfigured_signing(self):
        installer.configured_values(self.root, TEAM, BUNDLE)
        script = self.root / 'scripts/configure-signing.py'
        script.parent.mkdir()
        script.write_text(Path(__file__).with_name('configure-signing.py').read_text())
        original = self.project.read_bytes(), self.info.read_bytes()
        command = [sys.executable, str(script), '--team', 'KLMNOPQRST', '--bundle-id', 'com.other.rep']
        subprocess.run(command + ['--dry-run'], check=True, capture_output=True)
        self.assertEqual(original, (self.project.read_bytes(), self.info.read_bytes()))
        for _ in range(2):
            subprocess.run(command, check=True, capture_output=True)
            installer.configured_values(self.root, 'KLMNOPQRST', 'com.other.rep')

    def test_mismatched_team_or_any_companion_value_blocks(self):
        for mutation in ('team', 'build-setting', 'plist', 'watch-id'):
            with self.subTest(mutation=mutation):
                project, info = self.project.read_bytes(), self.info.read_bytes()
                if mutation == 'team':
                    self.project.write_text(self.project.read_text().replace(TEAM, 'KLMNOPQRST', 1))
                elif mutation == 'build-setting':
                    self.project.write_text(self.project.read_text().replace(
                        f'INFOPLIST_KEY_WKCompanionAppBundleIdentifier = {BUNDLE};',
                        'INFOPLIST_KEY_WKCompanionAppBundleIdentifier = com.wrong.rep;', 1))
                elif mutation == 'plist':
                    self.info.write_bytes(plistlib.dumps({'WKCompanionAppBundleIdentifier': 'com.wrong.rep'}))
                else:
                    self.project.write_text(self.project.read_text().replace(BUNDLE + '.watchkitapp', 'com.wrong.watch', 1))
                with self.assertRaises(installer.InstallError):
                    installer.configured_values(self.root, TEAM, BUNDLE)
                self.project.write_bytes(project)
                self.info.write_bytes(info)

    def test_only_exact_device_of_correct_kind_is_accepted(self):
        self.assertEqual(installer.select_device([PHONE, WATCH], 'fixture-watch', 'watch'), WATCH)
        for values, identifier, kind in [([PHONE], 'fixture-phone', 'watch'),
                                         ([PHONE], 'somebody-else', 'phone'),
                                         ([PHONE, PHONE], 'fixture-phone', 'phone'),
                                         ([{'identifier': 'unknown'}], 'unknown', 'phone')]:
            with self.subTest(identifier=identifier, kind=kind):
                with self.assertRaises(installer.InstallError):
                    installer.select_device(values, identifier, kind)

    def test_preview_has_no_device_build_or_source_mutations(self):
        original = self.project.read_bytes(), self.info.read_bytes()
        with patch.object(installer, 'run') as run, patch.object(installer, 'devices') as devices:
            with redirect_stdout(io.StringIO()) as output:
                installer.install(self.args(preview=True), self.root)
            run.assert_not_called()
            devices.assert_not_called()
            self.assertIn('Preview only', output.getvalue())
            self.assertNotIn('-sdk iphoneos', output.getvalue())
        self.assertEqual(original, (self.project.read_bytes(), self.info.read_bytes()))

    def test_stage_order_direct_install_and_watch_sdk(self):
        for stage, device in [('phone', PHONE), ('watch', WATCH)]:
            with self.subTest(stage=stage):
                events = []
                def record(command, log_dir, label, timeout=60):
                    events.append((label, command))
                with patch.object(installer, 'devices', return_value=[device]), \
                     patch.object(installer, 'run', side_effect=record), \
                     patch.object(installer, 'verify_product', side_effect=lambda *a: events.append(('signature', []))), \
                     redirect_stdout(io.StringIO()):
                    installer.install(self.args(stage), self.root)
                self.assertEqual([item[0] for item in events],
                                 ['build-' + stage, 'signature', 'install-' + stage, 'launch-' + stage])
                self.assertEqual(events[2][1][4:7], ['device', 'install', 'app'])
                self.assertIn('fixture-' + stage, events[2][1])
                if stage == 'watch':
                    self.assertEqual(events[0][1][-3:], ['-sdk', 'watchos', 'build'])
                    self.assertEqual(events[-1][1][-1], BUNDLE + '.watchkitapp')
                else:
                    self.assertNotIn('-sdk', events[0][1])
                    self.assertEqual(events[-1][1][-1], BUNDLE)

    def test_failure_at_each_stage_stops_later_actions(self):
        for failed in ('build-phone', 'signature', 'install-phone', 'launch-phone'):
            with self.subTest(failed=failed):
                events = []
                def record(command, log_dir, label, timeout=60):
                    events.append(label)
                    if label == failed:
                        raise installer.InstallError('fixture failure')
                def verify(*args):
                    events.append('signature')
                    if failed == 'signature':
                        raise installer.InstallError('fixture signature failure')
                with patch.object(installer, 'devices', return_value=[PHONE]), \
                     patch.object(installer, 'run', side_effect=record), \
                     patch.object(installer, 'verify_product', side_effect=verify), \
                     redirect_stdout(io.StringIO()) as output:
                    with self.assertRaises(installer.InstallError):
                        installer.install(self.args(), self.root)
                self.assertEqual(events[-1], failed)
                self.assertNotIn('passed', output.getvalue())

    def test_cli_requires_human_checks_before_device_access(self):
        base = ['--device', 'fixture-watch', '--team', TEAM, '--bundle-id', BUNDLE]
        for flags in ([], ['--stage', 'phone'], ['--stage', 'watch', '--ready']):
            with self.subTest(flags=flags), patch.object(installer, 'devices') as devices, \
                 redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    installer.main(base + flags)
                self.assertEqual(raised.exception.code, 2)
                devices.assert_not_called()

    def test_cli_rejects_cloud_physical_install(self):
        with patch.object(installer.sys, 'platform', 'linux'), redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                installer.main(['--stage', 'phone', '--device', 'fixture-phone', '--team', TEAM,
                                '--bundle-id', BUNDLE, '--ready'])

    def test_profile_verification_requires_unexpired_healthkit_and_identity(self):
        app = self.root / 'Fixture.app'
        app.mkdir()
        (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': BUNDLE}))
        for mutation in ('valid', 'expired', 'wrong-team', 'profile-health', 'signed-health', 'wrong-app'):
            with self.subTest(mutation=mutation):
                entitlements = {'application-identifier': TEAM + '.' + BUNDLE,
                                'com.apple.developer.healthkit': True,
                                'com.apple.developer.team-identifier': TEAM}
                profile = {'TeamIdentifier': [TEAM], 'ApplicationIdentifierPrefix': [TEAM],
                           'ExpirationDate': datetime.now(timezone.utc).replace(tzinfo=None) + timedelta(days=1),
                           'Entitlements': dict(entitlements)}
                if mutation == 'expired':
                    profile['ExpirationDate'] -= timedelta(days=2)
                elif mutation == 'wrong-team':
                    profile['TeamIdentifier'] = ['KLMNOPQRST']
                elif mutation == 'profile-health':
                    profile['Entitlements']['com.apple.developer.healthkit'] = False
                elif mutation == 'signed-health':
                    entitlements['com.apple.developer.healthkit'] = False
                elif mutation == 'wrong-app':
                    entitlements['application-identifier'] = TEAM + '.com.wrong.app'
                results = [SimpleNamespace(stdout=plistlib.dumps(value)) for value in (profile, entitlements)]
                with patch.object(installer, 'run'), \
                     patch.object(installer.subprocess, 'run', side_effect=results), \
                     redirect_stdout(io.StringIO()):
                    if mutation == 'valid':
                        installer.verify_product(app, TEAM, BUNDLE, self.root)
                    else:
                        with self.assertRaises(installer.InstallError):
                            installer.verify_product(app, TEAM, BUNDLE, self.root)

    def test_real_child_process_failure_and_timeout_are_bounded(self):
        with redirect_stdout(io.StringIO()):
            with self.assertRaises(installer.InstallError):
                installer.run([sys.executable, '-c', 'raise SystemExit(4)'], self.root, 'failure', 5)
            with self.assertRaises(installer.InstallError):
                installer.run([sys.executable, '-c', 'import time; time.sleep(10)'], self.root, 'timeout', 0.1)
        self.assertTrue((self.root / 'failure.log').is_file())
        self.assertTrue((self.root / 'timeout.log').is_file())

    def test_second_installer_cannot_acquire_same_lock(self):
        with installer.installation_lock(self.root):
            with self.assertRaises(installer.InstallError):
                with installer.installation_lock(self.root):
                    self.fail('A second install must not start')
        with installer.installation_lock(self.root):
            pass


if __name__ == '__main__':
    unittest.main(verbosity=2)
