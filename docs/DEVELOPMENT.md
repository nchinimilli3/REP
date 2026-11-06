# Development

The source lives in `fitness/`: shared training models/storage/sync, iPhone views in `Phone/`, and the Watch app in `fitness Watch App/`. The Watch owns the real HealthKit workout session. Do not fabricate measurements or save success. Preserve completed-set snapshots, durable local logging, idempotent sync and separate local/Health/iPhone status.

Run model/storage checks from the repository root:

```sh
./scripts/test-core.sh
./scripts/test-progress.sh
./scripts/test-laptop.sh
```

These use synthetic temporary fixtures; they do not write Apple Health or establish device acceptance. `scripts/build-devices.sh` is a build-only helper that uses the project's current signing configuration; install from Xcode using your own destinations. The original owner's device-specific installer and private evidence are intentionally not published.

The optional Mac app can be built with `scripts/build-laptop.sh` and started with `scripts/start-laptop.sh`. Its runtime records and pairing key stay in the ignored `laptop/data/` directory. Never share another person's pairing key or backups.

## Publish changes from the existing project

This working directory is the repository; no separate export or duplicate project is needed. After editing and validating, review what will be published:

```sh
git status --short
git diff
```

Stage the intended source/documentation changes, review `git diff --cached`, commit, and push to `main`. Files only reach GitHub after a push. Check staged filenames for runtime records or secrets before every commit; ignore rules do not protect a file that was force-added or already tracked.

Personal planning documents, hardware logs and screenshots remain local. Keep private development evidence current locally. For public changes, describe relevant validation and material limits in the commit/PR. Friends can pull the updated source and reinstall while retaining their own bundle identifiers and app containers.
