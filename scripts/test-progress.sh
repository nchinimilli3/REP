#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
rep_progress_dir=$(mktemp -d /tmp/rep-progress-tests.XXXXXX)
trap 'rm -rf "$rep_progress_dir"' EXIT
xcrun swiftc -parse-as-library -module-cache-path /tmp/rep-module-cache \
    fitness/Shared/TrainingModel.swift fitness/Shared/CycleProgress.swift \
    fitness/Shared/TrainingJournal.swift fitness/Shared/TrainingStore.swift fitness/Shared/ConfirmedPreferences.swift \
    Tests/TrainingProgressTests.swift -o "$rep_progress_dir/progress-tests"
"$rep_progress_dir/progress-tests"
