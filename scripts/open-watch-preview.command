#!/bin/bash
# Build the Watch target, then install/launch directly without Xcode's debugger.
set -euo pipefail
REP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${REP_PREVIEW_BUILD:-}" ]]; then
    REP_PREVIEW_BUILD="${TMPDIR:-/tmp}/REP-watch-preview"
    # Preserve the already verified default build location on this Mac.
    if [[ -d /tmp/REP-watch-preview ]]; then REP_PREVIEW_BUILD=/tmp/REP-watch-preview; fi
fi
REP_SIMCTL=/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl
if [[ ! -x "$REP_SIMCTL" ]]; then REP_SIMCTL="$(xcrun --find simctl)"; fi
export DEVELOPER_DIR="$(xcode-select -p)"
REP_PREVIEW_BUILD="$REP_PREVIEW_BUILD" REP_SIMCTL="$REP_SIMCTL" REP_ROOT="$REP_ROOT" python3 - "$@" <<'PY'
import json, os, pathlib, platform, subprocess, sys, time
root=pathlib.Path(os.environ['REP_ROOT'])
build=pathlib.Path(os.environ['REP_PREVIEW_BUILD'])
sim=os.environ['REP_SIMCTL']
app=build/'Products/Debug-watchsimulator/fitness Watch App.app'
def run(args, timeout=45, check=True):
    result=subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    if check and result.returncode: sys.exit(result.stdout or 'Command failed: '+repr(args))
    return result
if '--reuse-build' not in sys.argv:
    build.mkdir(parents=True,exist_ok=True)
    print('Building REP Watch UI…',flush=True)
    with (build/'build.log').open('w') as log:
        p=subprocess.run(['xcodebuild','-project',str(root/'fitness/fitness.xcodeproj'),
          '-target','fitness Watch App','-configuration','Debug','-sdk','watchsimulator',
          '-jobs','1','CODE_SIGNING_ALLOWED=YES','CODE_SIGN_IDENTITY=-','SYMROOT='+str(build/'Products'),
          'OBJROOT='+str(build/'Intermediates'),'build'],stdout=log,stderr=subprocess.STDOUT)
    if p.returncode: sys.exit('Build failed. See '+str(build/'build.log'))
if not (app/'fitness Watch App').exists(): sys.exit('No built Watch app. Run without --reuse-build.')
verification=run(['codesign','--verify','--strict',str(app)],check=False)
if verification.returncode: sys.exit('Invalid or missing simulator signature. Rebuild without --reuse-build.\n'+verification.stdout)
devices=json.loads(run([sim,'list','devices','available','-j']).stdout)['devices']
device=next((d for ds in devices.values() for d in ds if d['name']=='REP Isolated Preview 40mm'),None)
if device is None:
    udid=run([sim,'create','REP Isolated Preview 40mm',
      'com.apple.CoreSimulator.SimDeviceType.Apple-Watch-SE-3-40mm',
      'com.apple.CoreSimulator.SimRuntime.watchOS-26-2']).stdout.strip()
else: udid=device['udid']
if device is None or device['state']!='Booted':
    run([sim,'boot',udid,'--arch='+platform.machine()])
    # Optional work only; no HealthKit, pairing or recording services are removed.
    for job in ['com.apple.diagnosticd','com.apple.corespotlightd',
                'com.apple.proactiveeventtrackerd','com.apple.triald']:
        try: run([sim,'spawn',udid,'launchctl','bootout','system/'+job],timeout=8,check=False)
        except subprocess.TimeoutExpired: pass
subprocess.run(['open','-a','Simulator','--args','-CurrentDeviceUDID',udid],check=True)
print('Waiting for watchOS installation services…',flush=True)
for attempt in range(6):
    try:
        result=run([sim,'install',udid,str(app)],timeout=35,check=False)
        if result.returncode==0: break
        if attempt==5: sys.exit(result.stdout)
    except subprocess.TimeoutExpired:
        if attempt==5: sys.exit('watchOS installation service still unresponsive; no successful launch claimed.')
    time.sleep(2)
launch_args = ['--logger-preview'] if '--logger-preview' in sys.argv else []
if '--countdown-preview' in sys.argv: launch_args = ['--countdown-preview']
if '--controls-preview' in sys.argv: launch_args = ['--controls-preview']
if '--hamstring-preview' in sys.argv: launch_args = ['--logger-preview']
# watchOS may discard argv during app activation; simctl's documented child
# environment also selects the read-only fixture. Normal launch clears it.
os.environ['SIMCTL_CHILD_REP_VISUAL_PREVIEW'] = (
    'controls' if '--controls-preview' in sys.argv else
    'countdown' if '--countdown-preview' in sys.argv else
    'logger' if '--logger-preview' in sys.argv or '--hamstring-preview' in sys.argv else 'none')
os.environ['SIMCTL_CHILD_REP_PREVIEW_EXERCISE'] = 'hamstring' if '--hamstring-preview' in sys.argv else 'pullup'
print(run([sim,'launch','--terminate-running-process',udid,'nehachinimilli.fitness.watchkitapp'] + launch_args,timeout=45).stdout,flush=True)
print('REP launch requested. Confirm the workout carousel is visible in Simulator.',flush=True)
PY
