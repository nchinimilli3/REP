# REP Laptop

Native SwiftUI progress viewer and encrypted local receiver. Build with `./scripts/build-laptop.sh`, then `./scripts/start-laptop.sh --enable-login` from the repository root. Pair once from the updated iPhone app's **Today → Laptop Sync** screen.

Workout data automatically appears in `data/training.json` and `data/sets.csv` after a successful received snapshot. `data/` also holds the authoritative replication ledger and private pairing key; keep it local and out of version control. Never replace it with test fixtures.

See [development and verification notes](../docs/DEVELOPMENT.md).
