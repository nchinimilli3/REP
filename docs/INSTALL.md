# Install REP with Xcode

## 1. Get the source and Xcode

Install Xcode from Apple and open it once to finish setup. This project is developed with Xcode 26.3; install the iOS/watchOS platform support Xcode requests. You need iOS 17+ and watchOS 10.6+ on your physical devices.

Clone or fork the repository, or choose GitHub's **Code → Download ZIP** and extract it. Open `fitness/fitness.xcodeproj`.

## 2. Use your own signing

Add your Apple Account in **Xcode → Settings → Accounts**. In the project editor, select each application target: **fitness** (iPhone) and **fitness Watch App**. Under **Signing & Capabilities**, enable automatic signing and select your own Team for both.

Choose a unique iPhone bundle identifier, such as `com.yourname.rep`, and use `com.yourname.rep.watchkitapp` for Watch. The Watch companion identifier must exactly match the iPhone identifier in both the Watch target's build settings (`INFOPLIST_KEY_WKCompanionAppBundleIdentifier`) and `fitness/WatchInfo.plist` (`WKCompanionAppBundleIdentifier`). Keep the HealthKit capability on both apps.

To set these related values together, close Xcode and run the included helper from the repository root (requires Python 3):

```sh
python3 scripts/configure-signing.py --team YOURTEAMID --bundle-id com.yourname.rep --dry-run
python3 scripts/configure-signing.py --team YOURTEAMID --bundle-id com.yourname.rep
```

Use your own 10-character Team ID, shown in your signing/account details. Reopen the project afterward. This helper edits only the Xcode project and Watch Info.plist in your checkout. It never installs an app or reads workout data. These changes are personal to your checkout; don't contribute your signing values upstream. Manual setup in Xcode works too.

Apple's free Personal Team signing has short-lived provisioning (currently seven days), so expect to rebuild and reinstall periodically. See [Apple's account guide](https://developer.apple.com/help/account/basics/about-your-developer-account). Provisioning and HealthKit availability must be verified with your actual account; a successful simulator run does not prove device signing works.

## 3. Connect and install

1. Pair your Watch with your iPhone normally. Connect the iPhone to your Mac, trust the Mac, and keep both devices unlocked and nearby.
2. Enable Developer Mode on the devices if Xcode requests it. Follow Apple's device prompts and restarts.
3. Select the shared **REP** scheme and your physical iPhone as the destination. Build and run. Resolve any trust/signing prompts and open REP on the phone.
4. Select **fitness Watch App** and your paired physical Watch as the destination. Build and run directly from Xcode. If a Watch scheme isn't visible, use **Product → Scheme → Manage Schemes** to enable/create one for that target.
5. Open REP on Watch and respond to its Health permission prompts. Review the requested permissions on iPhone as well.

If the iPhone Watch app's Install button fails with free signing, use the direct Watch build/run route in Xcode. Let Xcode finish pairing/preparing devices. Don't repeatedly uninstall: deleting the app can delete local logs.

## 4. Customize and verify

Open **Plan** on iPhone and adjust the starter routines and loads before training. Keep both apps open nearby for initial plan synchronization. A fresh install starts without the author's workout history or Mac pairing key.

Record a short test workout. Verify that sets persist after reopening, recording continues when the Watch screen sleeps, the iPhone receives the log, and exactly one strength workout appears in Apple Health/Fitness. Local storage, Health save and iPhone receipt are separate statuses; confirm each. Simulators cannot validate these physical-device checks.

## Updates without losing your plan

Keep the same signing team and bundle identifiers across your own updates. Export a backup using REP's backup controls, finish any active workout, pull/download the newer source, preserve your personal signing configuration, and build/run over the existing installation. Do not delete the app as an update step. Changing identifiers installs a separate app with separate local storage.

Repository updates do not contain your live plan or history. An update can include storage migrations, so keep a backup before installing it. With a Git checkout, commit your signing edits on a local branch or save them before pulling and reapply them afterward.
