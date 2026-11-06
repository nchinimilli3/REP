#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
rep_test_dir=$(mktemp -d /tmp/rep-laptop-tests.XXXXXX)
trap 'rm -rf "$rep_test_dir"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path /tmp/rep-module-cache \
    fitness/Shared/TrainingModel.swift fitness/Shared/CycleProgress.swift \
    fitness/Shared/TrainingJournal.swift fitness/Shared/TrainingStore.swift fitness/Shared/LaptopProtocol.swift \
    laptop/LaptopRepository.swift Tests/LaptopSyncTests.swift -o "$rep_test_dir/laptop-tests"
"$rep_test_dir/laptop-tests"
