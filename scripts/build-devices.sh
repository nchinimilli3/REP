#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
rep_build_root="${TMPDIR:-/tmp}/REP-paired-build"
# Let each target select its SDK. Forcing -sdk iphoneos also affects the Watch.
# Building the target avoids scheme destination selection requiring an iOS runtime.
xcodebuild -project fitness/fitness.xcodeproj -target fitness -configuration Debug \
    -jobs 2 -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    "SYMROOT=$rep_build_root/Products" "OBJROOT=$rep_build_root/Intermediates" \
    ONLY_ACTIVE_ARCH=NO build
print "Signed iPhone app: $rep_build_root/Products/Debug-iphoneos/fitness.app"
print "Signed Watch app: $rep_build_root/Products/Debug-watchos/fitness Watch App.app"
print 'Build only. Finish active workouts and export history before reinstalling.'
