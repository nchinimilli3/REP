#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
rep_app="$PWD/laptop/build/REP Laptop.app"
if [[ ! -x "$rep_app/Contents/MacOS/REPDesktop" ]]; then ./scripts/build-laptop.sh; fi
if [[ "${1:-}" == "--enable-login" ]]; then
    # User-owned LaunchAgent: no sudo, no public listener, no cloud service.
    /usr/bin/python3 - "$rep_app" <<'PY'
import os, pathlib, plistlib, subprocess, sys
folder = pathlib.Path.home() / 'Library/LaunchAgents'
folder.mkdir(parents=True, exist_ok=True)
plist = folder / 'local.rep.laptop.plist'
entry = dict(Label='local.rep.laptop',
             ProgramArguments=[str(pathlib.Path(sys.argv[1]) / 'Contents/MacOS/REPDesktop')],
             RunAtLoad=True, KeepAlive=dict(SuccessfulExit=False), ThrottleInterval=30)
with plist.open('wb') as f: plistlib.dump(entry, f)
os.chmod(plist, 0o600)
domain = f'gui/{os.getuid()}'
subprocess.run(['launchctl', 'bootout', domain, str(plist)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.run(['launchctl', 'bootstrap', domain, str(plist)], check=True)
print('REP Laptop started and enabled at login.')
PY
else
    open "$rep_app"
fi
