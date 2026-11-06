#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
rep_test_dir=$(mktemp -d /tmp/rep-core-tests.XXXXXX)
trap 'rm -rf "$rep_test_dir"' EXIT
xcrun swiftc -parse-as-library -module-cache-path /tmp/rep-module-cache \
    fitness/Shared/TrainingModel.swift fitness/Shared/CycleProgress.swift fitness/Shared/TrainingJournal.swift fitness/Shared/TrainingStore.swift fitness/Shared/WorkoutStartCleanup.swift \
    Tests/TrainingCoreTests.swift Tests/FinishingTests.swift -o "$rep_test_dir/core-tests"
"$rep_test_dir/core-tests"
