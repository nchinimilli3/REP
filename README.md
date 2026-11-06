# REP.

Less tapping. More lifting.

A native SwiftUI strength-training app for Apple Watch, with an iPhone companion. Log sets with one tap, edit loads and reps, use rest timers, and review progress. The Watch records a real indoor Traditional Strength Training workout in Apple Health.

## Install your own build

You need a Mac with Xcode, an Apple Account, an iPhone running iOS 17 or later, and a paired Apple Watch running watchOS 10.6 or later. This project is currently developed with Xcode 26.3. There are no third-party package dependencies.

**[Follow the Xcode installation guide](docs/INSTALL.md).** Downloading this repository gives you source code; each person signs and installs their own build.

## Make it yours

Use **Plan** on iPhone to create, duplicate, rename, reorder and archive routines; add or create exercises; and change loads, sets, reps, rest, colors and notes. The included Back + Biceps, Glutes and Legs routines are editable starter templates. Their starting loads are estimates from the original personal routine, not recommendations for you—set your own loads before training. An optional Abs finisher stays in the same workout session.

Settings and logs live on your devices. WatchConnectivity syncs between your paired iPhone and Watch. Editing your plan does not edit anyone else's installation or this repository. Completed sets retain their recorded values when you change future targets. No account, analytics or mandatory cloud service is used.

The optional Mac companion provides local encrypted backup and a progress viewer. Pair it only with your own devices; its data and pairing key are excluded from Git.

## Development

See [development and update notes](docs/DEVELOPMENT.md). Source checks and simulator previews do not establish physical workout reliability. Before relying on a new install, verify a short workout, background recording, local set retention, phone sync and exactly one saved Apple Health workout on your own devices. This personal project has no guarantee of compatibility with every device or future OS version.

MIT licensed. Apple's frameworks, SF Symbols and other Apple-provided resources remain subject to Apple's applicable terms.
