# REP.

Less tapping. More lifting.

A native SwiftUI strength-training app for Apple Watch, with an iPhone companion. Log sets with one tap, edit loads and reps, use rest timers, and review progress. The Watch records a real indoor Traditional Strength Training workout in Apple Health.

## First time installing an app? Start here

**[Want an AI assistant to handle setup? Copy this installation prompt](AI_INSTALL.md).** Open the downloaded REP folder in an assistant with command access to your Mac, then paste the prompt. It can use the included installer to build and install directly on your phone and Watch, pausing for your Apple sign-in, device prompts, and Bluetooth checks. A chat without access to your Mac can guide the steps but cannot perform the installation.

**[Open the beginner guide: put REP on your iPhone and Apple Watch](docs/INSTALL.md).** Start at step 1, even if you have never downloaded Xcode or connected your phone to a computer. No coding, Terminal commands, Claude, or other AI tools are needed for the main walkthrough.

You need a **Mac**, an **iPhone**, its **paired Apple Watch**, a **USB cable that connects your phone to your Mac and transfers data**, and your own **Apple Account** (the account you use for the App Store). The guide covers:

1. Downloading Xcode and REP, then opening the right file.
2. Plugging in and trusting your phone, and enabling Developer Mode on both devices.
3. Setting up your own Apple signing account with clearly listed fields.
4. Installing and opening REP on your phone, then directly on your Watch.
5. Fixing the connection and Watch installation problems encountered with this project.
6. Checking both apps without the cable and renewing a free installation later.

**Known wired-install workaround:** if the phone installation stalls, leave the iPhone plugged into the Mac, turn **iPhone Bluetooth OFF in Settings**, and leave **Mac and Watch Bluetooth ON**. This is a workaround reported by the app's author. The guide gives the sequence, including turning iPhone Bluetooth back on for Watch setup and sync.

**Read before installing:** REP is installed from source using Xcode; there is no App Store download. Apple's free Personal Team profiles expire **7 days after issuance**, so you will need to install again through Xcode periodically. [Apple explains the free-account limits here](https://developer.apple.com/help/account/basics/about-your-developer-account). Your Mac/Xcode version must support your devices' software; the project is developed with Xcode 26.3, with app minimums of iOS 17 and watchOS 10.6. Signing and Health permissions must work with your own account and devices.

## Make it yours

Use **Plan** on iPhone to create, duplicate, rename, reorder and archive routines; add or create exercises; and change loads, sets, reps, rest, colors and notes. The included Back + Biceps, Glutes and Legs routines are editable starter templates. Their starting loads are estimates from the original personal routine, not recommendations for you—set your own loads before training. An optional Abs finisher stays in the same workout session.

Settings and logs live on your devices. WatchConnectivity syncs between your paired iPhone and Watch. Editing your plan does not edit anyone else's installation or this repository. Completed sets retain their recorded values when you change future targets. No account, analytics or mandatory cloud service is used.

The optional Mac companion provides local encrypted backup and a progress viewer. Pair it only with your own devices; its data and pairing key are excluded from Git.

## Development

See [development and update notes](docs/DEVELOPMENT.md). Source checks and simulator previews do not establish physical workout reliability. Before relying on a new install, verify a short workout, background recording, local set retention, phone sync and exactly one saved Apple Health workout on your own devices. This personal project has no guarantee of compatibility with every device or future OS version.

MIT licensed. Apple's frameworks, SF Symbols and other Apple-provided resources remain subject to Apple's applicable terms.
