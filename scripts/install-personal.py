#!/usr/bin/env python3
"""Install a configured REP checkout on explicitly selected personal devices.

No stored device IDs, credentials, source edits, uninstalls, or automatic retries.
Run phone and watch separately to allow human trust/Bluetooth checks between them.
"""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import signal
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent


class InstallError(Exception):
    pass


@contextmanager
def installation_lock(directory):
    import fcntl
    # Keep the lock file in place; unlinking can let concurrent callers bypass it.
    with (directory / 'rep-personal-installer.lock').open('a') as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise InstallError('Another personal installer is running. Wait for it to finish.')
        yield


def run(command, log_dir, label, timeout=60):
    """Bound each process group; leave its output on disk for diagnosis."""
    log = log_dir / (label + '.log')
    print(f'{label}: {shlex.join([str(item) for item in command])}', flush=True)
    print(f'Log: {log}', flush=True)
    with log.open('wb') as output:
        process = subprocess.Popen(command, cwd=ROOT, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except (subprocess.TimeoutExpired, KeyboardInterrupt):
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            raise InstallError(f'{label} stopped. Read {log}; do not loop retries.')
    if code:
        raise InstallError(f'{label} failed (exit {code}). Read {log}. Installation is incomplete.')


def configured_values(root, team, bundle):
    project = (root / 'fitness/fitness.xcodeproj/project.pbxproj').read_text()
    watch = plistlib.loads((root / 'fitness/WatchInfo.plist').read_bytes())
    teams = re.findall(r'DEVELOPMENT_TEAM = ([A-Z0-9]+);', project)
    identifiers = re.findall(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;\n]+);', project)
    identifiers = [value.strip('"') for value in identifiers]
    companions = re.findall(r'INFOPLIST_KEY_WKCompanionAppBundleIdentifier = ([^;\n]+);', project)
    if (len(teams) != 4 or set(teams) != {team}
            or identifiers.count(bundle) != 2
            or identifiers.count(bundle + '.watchkitapp') != 2
            or len(companions) != 2
            or any(value.strip('"') != bundle for value in companions)
            or watch.get('WKCompanionAppBundleIdentifier') != bundle):
        raise InstallError('Signing values do not match your --team and --bundle-id. '
                           'Follow INSTALL step 5 or configure-signing.py first. '
                           'For an existing installation, preserve its original Team and identifiers.')


def devices(log_dir):
    report = log_dir / 'devices.json'
    run(['xcrun', 'devicectl', '--timeout', '30', '--json-output', str(report),
         'list', 'devices'], log_dir, 'list-devices', 90)
    values = json.loads(report.read_text())['result']['devices']
    if not isinstance(values, list):
        raise InstallError('Unexpected device list. Inspect devices.json before continuing.')
    return values


def device_kind(device):
    hardware = device.get('hardwareProperties', {})
    description = ' '.join(str(hardware.get(key, ''))
                           for key in ('deviceType', 'productType', 'platform')).lower()
    if 'watch' in description:
        return 'watch'
    if 'iphone' in description:
        return 'phone'
    return 'unknown'


def select_device(values, identifier, stage):
    matches = [item for item in values if item.get('identifier') == identifier]
    if len(matches) != 1 or device_kind(matches[0]) != stage:
        raise InstallError('The selected ID does not identify exactly one physical '
                           f'{stage}. Run --list-devices and select its identifier; '
                           'never use the author\'s IDs or a Simulator.')
    return matches[0]


def verify_product(app, team, bundle, log_dir):
    run(['codesign', '--verify', '--deep', '--strict', str(app)],
        log_dir, 'verify-signature')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != bundle:
        raise InstallError('Built app has the wrong bundle identifier. Nothing installed.')
    # Read provisioning data in memory, never print/save the full profile.
    profile = subprocess.run(['security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')],
                             check=True, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, timeout=30)
    profile = plistlib.loads(profile.stdout)
    entitlement_output = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)],
                                        check=True, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, timeout=30)
    signed = plistlib.loads(entitlement_output.stdout)
    entitlements = profile.get('Entitlements', {})
    allowed_ids = {prefix + '.' + bundle
                   for prefix in profile.get('ApplicationIdentifierPrefix', [])}
    expiration = profile['ExpirationDate'].replace(tzinfo=timezone.utc)
    if (team not in profile.get('TeamIdentifier', [])
            or entitlements.get('application-identifier') not in allowed_ids
            or signed.get('application-identifier') != entitlements.get('application-identifier')
            or signed.get('com.apple.developer.team-identifier') != team
            or entitlements.get('com.apple.developer.healthkit') is not True
            or signed.get('com.apple.developer.healthkit') is not True
            or expiration <= datetime.now(timezone.utc)):
        raise InstallError('Wrong/expired provisioning or missing HealthKit signing. '
                           'Nothing installed; resolve Xcode automatic signing for your account.')
    print(f'Verified {bundle}; profile expires {expiration.isoformat()}.', flush=True)


def install(args, log_dir):
    configured_values(ROOT, args.team, args.bundle_id)
    target = 'fitness' if args.stage == 'phone' else 'fitness Watch App'
    suffix = 'iphoneos' if args.stage == 'phone' else 'watchos'
    bundle = args.bundle_id + ('.watchkitapp' if args.stage == 'watch' else '')
    product = log_dir / 'Products' / ('Debug-' + suffix) / (target + '.app')
    build = ['xcodebuild', '-project', str(ROOT / 'fitness/fitness.xcodeproj'),
             '-target', target, '-configuration', 'Debug', '-jobs', '2',
             '-allowProvisioningUpdates', '-allowProvisioningDeviceRegistration',
             f'SYMROOT={log_dir / "Products"}', f'OBJROOT={log_dir / "Intermediates"}',
             f'CLANG_MODULE_CACHE_PATH={log_dir / "ModuleCache.noindex"}',
             f'SWIFT_MODULE_CACHE_PATH={log_dir / "ModuleCache.noindex"}',
             'ONLY_ACTIVE_ARCH=NO', 'CODE_SIGNING_ALLOWED=YES']
    # Forcing iphoneos across a mixed-target phone build breaks Watch dependencies.
    if args.stage == 'watch':
        build += ['-sdk', 'watchos']
    build += ['build']
    installation = ['xcrun', 'devicectl', '--timeout', '120', 'device',
                    'install', 'app', '--device', args.device, str(product)]
    launch = ['xcrun', 'devicectl', '--timeout', '30', 'device', 'process',
              'launch', '--device', args.device, bundle]
    if args.dry_run:
        for command in (build, installation, launch):
            print(shlex.join(command))
        print('Preview only: no build, device access, installation, or launch occurred.')
        return
    selected = select_device(devices(log_dir), args.device, args.stage)
    print('Selected: ' + selected.get('deviceProperties', {}).get('name', args.device), flush=True)
    run(build, log_dir, 'build-' + args.stage, 1200)
    verify_product(product, args.team, bundle, log_dir)
    run(installation, log_dir, 'install-' + args.stage, 180)
    # A failed launch deliberately stops: it is not full install/opening success.
    run(launch, log_dir, 'launch-' + args.stage, 90)
    if args.stage == 'phone':
        print('iPhone install and automated launch passed. STOP HERE: tap REP on the '
              'phone, finish any trust prompt, restore phone Bluetooth ON, and confirm '
              'Automatic App Install OFF before running the watch stage.')
    else:
        print('Watch direct install and automated launch passed. Now unplug the '
              'phone and manually open REP on BOTH devices. Workout saving and sync '
              'are separate checks; no workout has been started by this installer.')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--list-devices', action='store_true', help='List physical devices without installing')
    parser.add_argument('--stage', choices=('phone', 'watch'), help='Install one device, then stop')
    parser.add_argument('--device', help='Exact CoreDevice identifier from --list-devices')
    parser.add_argument('--team', help='Your configured 10-character Apple Team ID')
    parser.add_argument('--bundle-id', help='Your configured iPhone app identifier')
    parser.add_argument('--ready', action='store_true', help='Confirm no active workout, backup considered, '
                        'devices ready, and Automatic App Install OFF')
    parser.add_argument('--phone-open-confirmed', action='store_true', help='Required for watch: phone '
                        'opens after trust prompts and phone Bluetooth is back ON')
    parser.add_argument('--dry-run', action='store_true', help='Check settings and preview commands only')
    args = parser.parse_args(argv)
    if args.list_devices:
        if any((args.stage, args.device, args.team, args.bundle_id, args.dry_run)):
            parser.error('--list-devices must be used separately from installation options')
    else:
        if not all((args.stage, args.device, args.team, args.bundle_id)):
            parser.error('Choose --list-devices, or supply --stage, --device, --team, and --bundle-id')
        if not re.fullmatch(r'[A-Z0-9]{10}', args.team):
            parser.error('--team must be your 10-character uppercase Apple Team ID')
        if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', args.bundle_id):
            parser.error('--bundle-id must be your own reverse-domain identifier')
        if not args.dry_run and (not args.ready or (args.stage == 'watch' and not args.phone_open_confirmed)):
            parser.error('Confirm readiness with --ready; watch also needs --phone-open-confirmed. '
                         'See AI_INSTALL.md for the human checks these flags represent.')
    if not args.dry_run and sys.platform != 'darwin':
        parser.error('Physical installation requires a local Mac with Xcode, not a cloud/Linux chat')
    log_dir = Path(tempfile.mkdtemp(prefix='rep-personal-install-'))
    print(f'Private local build/log folder: {log_dir}', flush=True)
    try:
        if args.list_devices:
            for device in devices(log_dir):
                print(json.dumps({'name': device.get('deviceProperties', {}).get('name'),
                                  'kind': device_kind(device), 'identifier': device.get('identifier')},
                                 ensure_ascii=False))
        else:
            if args.dry_run:
                install(args, log_dir)
            else:
                with installation_lock(log_dir.parent):
                    install(args, log_dir)
    except (InstallError, OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        print(f'INCOMPLETE: {error}\nKeep logs in {log_dir}; see docs/INSTALL.md for fixes.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
