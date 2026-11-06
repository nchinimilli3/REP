#!/bin/bash
# Isolated iPhone preview: build first, then boot and install without a debugger.
set -euo pipefail
REP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export REP_ROOT
export REP_PHONE_BUILD="${REP_PHONE_BUILD:-/tmp/REP-phone-preview}"
export REP_SIMCTL=/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl
if [[ ! -x "$REP_SIMCTL" ]]; then export REP_SIMCTL="$(xcrun --find simctl)"; fi
python3 - "$@" <<'PY'
import argparse, json, os, pathlib, platform, shutil, signal, subprocess, sys, time
parser = argparse.ArgumentParser(description='Open an isolated REP iPhone simulator. Other booted simulators are shut down, never erased.')
parser.add_argument('--demo', action='store_true', help='Open isolated simulator sample history; Health and sync stay off')
parser.add_argument('--screen', choices=['today', 'progress', 'exercise', 'plan'], default='today')
parser.add_argument('--exercise', default='pullup', help='Exercise ID for the demo exercise screen')
parser.add_argument('--reuse-build', action='store_true')
parser.add_argument('--boot-only', action='store_true', help='Boot iOS without building or installing REP')
parser.add_argument('--phone-only', action='store_true', help='Use a temporary project copy without the embedded Watch dependency')
args = parser.parse_args()
sim = os.environ['REP_SIMCTL']
root = pathlib.Path(os.environ['REP_ROOT'])
build = pathlib.Path(os.environ['REP_PHONE_BUILD'])
products = build/('PhoneOnlyProducts' if args.phone_only else 'Products')
intermediates = build/('PhoneOnlyIntermediates' if args.phone_only else 'Intermediates')
app = products/'Debug-iphonesimulator/fitness.app'
name = 'REP Isolated iPhone Preview'
build.mkdir(parents=True, exist_ok=True)
def run(command, timeout=45, check=True):
    try:
        result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise RuntimeError('Timed out after %ss: %s' % (timeout, ' '.join(command)))
    if check and result.returncode:
        raise RuntimeError(result.stdout or 'Command failed: '+repr(command))
    return result
try:
    devices = json.loads(run([sim, 'list', 'devices', 'available', '-j']).stdout)['devices']
    # Preserve existing device data. Avoid building alongside a cold-booted OS.
    for group in devices.values():
        for device in group:
            if device['state'] == 'Booted' and (device['name'] != name or not (args.reuse_build or args.boot_only)):
                print('Shutting down '+device['name']+' (data retained)…', flush=True)
                run([sim, 'shutdown', device['udid']], timeout=90)
    if not args.boot_only:
        if not args.reuse_build:
            source = root/'fitness'
            if args.phone_only:
                source = build/'PhoneSource'
                if source.exists():
                    shutil.rmtree(source)
                shutil.copytree(root/'fitness', source,
                                ignore=shutil.ignore_patterns('.git', 'xcuserdata'))
                project = source/'fitness.xcodeproj/project.pbxproj'
                text = project.read_text()
                for entry in ['9C12A1043081D8DA004322DE /* Embed Watch Content */',
                              '9C12A0E13081D8C7004322DE /* PBXTargetDependency */']:
                    line = '\t\t\t\t'+entry+',\n'
                    if text.count(line) != 1:
                        raise RuntimeError('Project structure changed; cannot prepare phone-only copy: '+entry)
                    text = text.replace(line, '')
                project.write_text(text)
            print('Building REP iPhone with one worker; see '+str(build/'build.log'), flush=True)
            with (build/'build.log').open('w') as log:
                process = subprocess.Popen(['xcodebuild', '-project', str(source/'fitness.xcodeproj'),
                    '-scheme', 'REP', '-configuration', 'Debug',
                    '-destination', 'generic/platform=iOS Simulator', '-jobs', '1',
                    'ONLY_ACTIVE_ARCH=YES', 'ARCHS='+platform.machine(),
                    'CODE_SIGNING_ALLOWED=YES', 'CODE_SIGN_IDENTITY=-',
                    'SYMROOT='+str(products), 'OBJROOT='+str(intermediates), 'build'],
                    stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    status = process.wait(timeout=1200)
                except (subprocess.TimeoutExpired, KeyboardInterrupt):
                    os.killpg(process.pid, signal.SIGTERM)
                    raise RuntimeError('Build cancelled or exceeded 20 minutes; see '+str(build/'build.log'))
                if status:
                    raise RuntimeError('Build failed; see '+str(build/'build.log'))
        if not (app/'fitness').exists():
            raise RuntimeError('No built iPhone app. Run without --reuse-build.')
        run(['codesign', '--verify', '--strict', str(app)])
    device = next((d for runtime, group in devices.items() if '.iOS-' in runtime
                   for d in group if d['name'] == name), None)
    if device is None:
        runtimes = json.loads(run([sim, 'list', 'runtimes', '-j']).stdout)['runtimes']
        available = [r for r in runtimes if r.get('isAvailable') and '.iOS-' in r['identifier']]
        if not available:
            raise RuntimeError('No available iOS runtime.')
        # Prefer the installed 26.2 runtime used by the existing phone.
        runtime = next((r for r in available if r['version'] == '26.2'), available[-1])
        udid = run([sim, 'create', name, 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro',
                    runtime['identifier']]).stdout.strip()
    else:
        udid = device['udid']
    (build/'device-id.txt').write_text(udid+'\n')
    if device is None or device['state'] != 'Booted' or not (args.reuse_build or args.boot_only):
        print('Booting isolated iPhone '+udid+'…', flush=True)
        run([sim, 'boot', udid, '--arch='+platform.machine()], timeout=60)
        for job in ['com.apple.diagnosticd', 'com.apple.corespotlightd',
                    'com.apple.proactiveeventtrackerd', 'com.apple.triald']:
            try:
                run([sim, 'spawn', udid, 'launchctl', 'bootout', 'system/'+job], timeout=8, check=False)
            except RuntimeError:
                pass
    run(['open', '-a', 'Simulator', '--args', '-CurrentDeviceUDID', udid])
    print('Waiting up to 5 minutes for iOS startup…', flush=True)
    with (build/'boot.log').open('w') as log:
        try:
            status = subprocess.run([sim, 'bootstatus', udid], stdout=log,
                                    stderr=subprocess.STDOUT, timeout=300)
        except subprocess.TimeoutExpired:
            raise RuntimeError('iOS startup exceeded 5 minutes; see '+str(build/'boot.log'))
    if status.returncode:
        raise RuntimeError('iOS boot did not complete. See '+str(build/'boot.log'))
    if args.boot_only:
        print('iOS reports startup complete. Confirm the Home/Welcome screen visually.', flush=True)
        sys.exit(0)
    for attempt in range(4):
        try:
            result = run([sim, 'install', udid, str(app)], timeout=35, check=False)
            if result.returncode == 0:
                break
        except RuntimeError:
            if attempt == 3:
                raise
        if attempt == 3:
            raise RuntimeError(result.stdout)
        time.sleep(2)
    os.environ['SIMCTL_CHILD_REP_PHONE_DEMO'] = '1' if args.demo else '0'
    os.environ['SIMCTL_CHILD_REP_PHONE_SCREEN'] = args.screen
    os.environ['SIMCTL_CHILD_REP_PHONE_EXERCISE'] = args.exercise
    print(run([sim, 'launch', '--terminate-running-process', udid,
               'nehachinimilli.fitness'], timeout=45).stdout, flush=True)
    print('REP launch requested. Confirm Today/Progress/Plan visually; PID alone is not visual proof.', flush=True)
except (RuntimeError, ValueError, KeyError) as error:
    sys.exit(str(error))
PY
