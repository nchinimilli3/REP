#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
rep_app="$PWD/laptop/build/REP Laptop.app"
mkdir -p "$rep_app/Contents/MacOS"
xcrun swiftc -swift-version 5 -parse-as-library -O -module-cache-path /tmp/rep-module-cache \
    fitness/Shared/TrainingModel.swift fitness/Shared/REPStyle.swift fitness/Shared/CycleProgress.swift \
    fitness/Shared/TrainingJournal.swift fitness/Shared/TrainingStore.swift fitness/Shared/LaptopProtocol.swift \
    laptop/LaptopRepository.swift laptop/REPDesktop.swift -o "$rep_app/Contents/MacOS/REPDesktop"
/usr/bin/python3 - "$rep_app/Contents/Info.plist" "$PWD/laptop/data" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='local.rep.laptop', CFBundleName='REP Laptop',
        CFBundleExecutable='REPDesktop', CFBundlePackageType='APPL', CFBundleShortVersionString='1.0',
        NSLocalNetworkUsageDescription='Receive encrypted REP workout backups from your paired iPhone on your local network.',
        NSBonjourServices=['_repbackup._tcp'], REPDataDirectory=sys.argv[2]), f)
PY
codesign --force --sign - "$rep_app"
print "Built: $rep_app"
