# Put REP on your iPhone and Apple Watch

This guide starts from zero. You do not need to know how to code, use Terminal, or use Claude or any other AI tool. Follow the steps in order. **Settings → Bluetooth** means “open Settings, then choose Bluetooth.”

REP is not in the App Store. You download its files, then use Apple's free Mac app **Xcode** to turn those files into an app and put it on your devices. Xcode calls that **building and running**.

**Before you begin:** Apple's free installation permission expires **7 days after issuance**. REP may stop opening until you install it again through Xcode. Keep the downloaded project and your personal settings. [Apple explains Personal Team limits here](https://developer.apple.com/help/account/basics/about-your-developer-account).

[What you need](#what-you-need) · [Start here](#1-download-xcode-on-your-mac) · [Fix a problem](#if-something-doesnt-work) · [Renew next week](#renew-or-update-without-losing-your-data)

## What you need

- A **Mac** that can run a suitable Xcode version. This method does not run on Windows, an iPad, or an iPhone alone.
- Your **Apple Account** email and password—the account you use for the App Store. Start with your free Personal Team; you do not need to buy a membership to try these steps.
- An **iPhone with iOS 17 or later** and an **Apple Watch with watchOS 10.6 or later**, already paired to that phone. If your Watch appears in the iPhone's Watch app, it is paired. Otherwise, [set up the Watch with Apple's instructions](https://support.apple.com/en-us/109015) first.
- A **USB cable that supports data**, with one end that fits your iPhone and the other that fits your Mac. A phone charging cable often works; a charging-only cable will not. You may need a USB adapter if the plug does not fit your Mac.
- Internet for downloads and Apple signing, and enough Mac storage for Xcode and its requested downloads. Allow extra time for large downloads and first-time device preparation.

This project is developed with **Xcode 26.3**. Your Xcode must also support your Mac's macOS and your devices' software versions. Check [Apple's Xcode compatibility table](https://developer.apple.com/support/xcode/) if installation says a version is unsupported. Newer Xcode versions may use slightly different menu names.

## 1. Download Xcode on your Mac

1. On your **Mac**, open **App Store**—the blue icon with an “A.”
2. Search for **Xcode**, published by **Apple**, and click **Get** or the download button. You can also use [Apple's Xcode download page](https://developer.apple.com/xcode/resources/).
3. Wait for installation to finish, then click **Open**.
4. Accept the license and install the additional components Xcode requests. Enter your **Mac login password** if macOS asks for permission.
5. If asked which platforms to install, include **iOS** and **watchOS**. To add missing platform support later, look in **Xcode → Settings → Components** (called **Platforms** in some versions).

**Ready to continue:** Xcode opens without asking you to finish its initial installation. You do not need to create a new project.

## 2. Download REP and open the project

1. On the Mac, open [REP on GitHub](https://github.com/nchinimilli3/REP).
2. Click the green **Code** button, then **Download ZIP**. No GitHub account, fork, or clone is needed.
3. Open **Finder**—the blue smiling face in the Mac's Dock—and select **Downloads** on the left.
4. Double-click the ZIP to unpack it if your browser has not already done so. Open the resulting folder, usually **REP-main**.
5. Open the **fitness** folder inside it, then double-click **fitness.xcodeproj**. Finder may hide the extension and show **fitness** with an Xcode project icon instead.
6. If Xcode asks whether you trust the project, proceed only if it is the REP project you downloaded from the link above.

**Ready to continue:** Xcode displays the existing REP project. Keep the entire downloaded folder; the project needs its neighboring files. You do not need to open or edit Swift code.

## 3. Plug your iPhone into the Mac

1. Plug one end of the cable into your **iPhone's charging port** and the other into a **USB port on your Mac**. The Watch connects wirelessly; its charging puck is not a Mac data connection.
2. Unlock your iPhone with its passcode and leave it connected.
3. If the Mac asks **Allow accessory to connect?**, click **Allow**.
4. On the iPhone, tap **Trust** when **Trust This Computer?** appears and enter the iPhone passcode. If it does not appear, select your iPhone under **Locations** in Finder and click **Trust** there, then check the phone again.
5. Keep the Watch nearby and unlocked. Start with Wi-Fi and Bluetooth on for all three devices and the Mac and devices on the same reachable Wi-Fi network.
6. In Xcode, open **Window → Devices and Simulators** and check that your iPhone appears. In newer versions, use **Xcode → Open Developer Tool → Device Hub** instead. Complete any pairing prompts there for the phone and Watch, including confirmations on the devices themselves.

If the phone only charges and never appears in Finder, try another data-capable cable or Mac USB port.

### Wired phone workaround: Bluetooth OFF on the phone only

The app's author reports needing the following setup to make the **iPhone installation succeed while connected by cable**. Try it if phone installation stalls or repeatedly cannot connect:

| Device | Setting during this workaround |
| --- | --- |
| iPhone | Keep the USB cable plugged into the Mac. Open **Settings → Bluetooth** and turn Bluetooth **OFF**. Leave Wi-Fi on. |
| Mac | Open **System Settings → Bluetooth** and leave Bluetooth **ON**. Leave Wi-Fi on. |
| Apple Watch | On the Watch, open **Settings → Bluetooth** and leave Bluetooth **ON**. Leave Wi-Fi on and keep the Watch unlocked nearby. |

Use the phone's actual **Settings** switch. The Bluetooth button in Control Center does not fully turn Bluetooth off; [Apple explains the difference here](https://support.apple.com/en-us/102412).

Then select your **physical iPhone** in Xcode and retry Run as described in step 7. This is an author-reported workaround, not a requirement for every device. **After the phone installs, turn iPhone Bluetooth back ON before installing on the Watch or checking sync.** If turning it off makes the phone disappear from Xcode, turn it back on, reconnect the cable, and repeat the Finder trust check above.

## 4. Enable Developer Mode on both devices

**Developer Mode** lets your device run apps installed through Xcode.

1. On the **iPhone**, open **Settings → Privacy & Security → Developer Mode**, turn it on, and accept the restart.
2. After restarting, unlock it and confirm **Turn On** when asked. Keep it connected to the Mac.
3. On the **Watch itself**, open **Settings → Privacy & Security → Developer Mode**, turn it on, and follow its restart and confirmation prompts too.
4. Return to Xcode and let it finish preparing both devices. Confirm any pairing/trust prompt on either device.

If **Developer Mode is missing**, first connect/pair the device with Xcode as in step 3, then look in Settings again. Restore iPhone Bluetooth before pairing the Watch if you used the phone-only workaround. See [Apple's Developer Mode instructions](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

**Ready to continue:** Xcode recognizes the devices and no longer reports Developer Mode is disabled. “Preparing device” means setup work is underway; let it finish before repeatedly pressing Run.

## 5. Set up your own Apple signing account

Apple requires a digital signature for your copy of the app. Xcode handles it after you choose your account and fill in the app's identifiers.

1. In the Mac menu bar, choose **Xcode → Settings → Accounts** (or **Apple Accounts**).
2. Click **+**, choose **Apple Account** if asked, and sign in with your own account. Complete verification and accept Apple's developer agreement if requested. Close Settings when your account appears.
3. Press **Command–1** to show Xcode's file list on the left. Click the blue **fitness project icon** at the top. A settings panel opens with a list labeled **PROJECT** and **TARGETS**. A **target** is one of the apps Xcode builds.
4. Under **TARGETS**, choose **fitness**—the **iPhone app**. Open **Signing & Capabilities**, choose **All** configurations if offered, check **Automatically manage signing**, and set **Team** to **your name (Personal Team)** or your own existing developer team.
5. Repeat for **fitness Watch App**, using the **same Team**. Keep the existing **HealthKit** capability on both targets.

### Fill in four related app identifiers

A **Bundle Identifier** is the app's internal name. Choose a personal value like `com.jamiechen.rep`. Replace `jamiechen` with your own distinctive name or nickname, using letters/numbers with no spaces. If Apple says it is taken, add a few digits. Save your chosen values for future updates.

Fill in **all four places** below. The Watch needs to know which iPhone app belongs to it:

| Where | Example value—use your own name consistently |
| --- | --- |
| **fitness** target → **Signing & Capabilities** → **Bundle Identifier** | `com.jamiechen.rep` |
| **fitness Watch App** target → **Signing & Capabilities** → **Bundle Identifier** | `com.jamiechen.rep.watchkitapp` |
| **fitness Watch App** target → **Build Settings** → search for `WKCompanionAppBundleIdentifier` | `com.jamiechen.rep` |
| **WatchInfo.plist** file → `WKCompanionAppBundleIdentifier` value | `com.jamiechen.rep` |

For **Build Settings**, choose **All** rather than Basic if the field is hidden. Update both **Debug** and **Release** if shown separately. Leave unrelated settings alone.

To open **WatchInfo.plist**, choose **File → Open** in Xcode and browse to **REP-main → fitness → WatchInfo.plist** in your downloaded folder. In the property-list editor, names appear on the left and values on the right. The row may display a readable name such as “Companion app bundle identifier”; its key is `WKCompanionAppBundleIdentifier`. Double-click its current value, enter your **iPhone identifier**, and press **Command–S** to save. Leave other rows alone.

**Check:** the iPhone identifier and both companion values match exactly. The Watch app identifier is that same value with `.watchkitapp` added. Both targets use **your own Team**, not the author's. Xcode may ask to register your devices when you run; allow it. If signing still reports a problem, use the matching fix below.

## 6. Turn off automatic Watch app installation

On the **iPhone**, open the **Watch** app → **My Watch → General** and turn **Automatic App Install OFF**. This also stops automatic installation of other new Watch apps; they can still be managed manually.

Keep this off for REP installs and updates. With this project's free signing setup, installation through the iPhone Watch app previously failed with **“Unable to install REP”**, even after a direct Watch install succeeded. We install REP **directly from Xcode** instead. **Do not use the Watch app's Install button for REP or toggle REP's “Show App on Apple Watch” setting as a fix.**

## 7. Install and open REP on the iPhone first

At the top of Xcode are a triangle **▶ Run** button and selectors for the app configuration and destination. Xcode calls the app configuration a **scheme**. The destination is the device that receives the app.

1. Choose the **REP** scheme. Do not choose **REPPhoneQuality** or anything with “Tests” in its name.
2. Beside it, choose **your actual iPhone by name**. **Simulator** means a pretend phone on the Mac; it will not install on your real phone. “Any iOS Device” is not your specific phone either.
3. Keep the phone connected and unlocked. Click **▶ Run**, or press **Command–R**. Allow device registration if asked.
4. Wait for building and installation. If Xcode requests missing iOS/watchOS support, install it, then Run again.
5. If a Mac **Keychain** prompt says Xcode or `codesign` wants access to an Apple Development key, enter your **Mac login password**. This allows Apple's signing tool to use the key; REP has no separate password.
6. Confirm **REP opens on the iPhone**. If the phone reports an untrusted developer, open **Settings → General → VPN & Device Management**, choose the developer entry for **your own Apple Account** if present, and follow its Trust/Verify prompts. Keep internet available for verification, then open REP again.

If installation stalls or cannot connect, use the **wired Bluetooth workaround in step 3** and retry. Turn iPhone Bluetooth back **ON** afterward.

**Ready to continue:** tapping REP on the actual iPhone opens its screens. “Build Succeeded” on the Mac alone is not this check. Resolve phone trust/opening **before** the final Watch installation: a phone trust change previously triggered the unsuccessful automatic Watch install.

## 8. Install directly onto the Apple Watch

1. Restore **iPhone Bluetooth ON**. Leave **Mac and Watch Bluetooth ON**, Wi-Fi on, the phone connected by cable, and the Watch nearby and unlocked. Keep **Automatic App Install OFF**.
2. At the top of Xcode, change the scheme from **REP** to **fitness Watch App**.
3. If the Watch scheme is missing, choose **Product → Scheme → New Scheme**, select the **fitness Watch App** target, and click **OK**. Then choose that scheme. Do not create a new project.
4. Select **your physical Apple Watch by name** as the destination. Xcode may display it alongside the paired phone. Do not choose a Simulator or “Any watchOS Device.” If it is missing, use the Watch connection fix below.
5. Click **▶ Run** or press **Command–R**. Let preparation, building, installation, and launch finish. Confirm any pairing prompt on the Watch.
6. On the Watch, press the **Digital Crown**—the round side dial—to see your apps and tap **REP**. Follow its Health permission prompts and check the phone for related permission screens. Allow the workout-writing and measurement permissions you want REP to use; denied permissions can block recording or leave readings unavailable.

**Ready to continue:** REP actually opens on the Watch. An icon, an Install button, a successful phone install, or “Build Succeeded” alone does not establish that.

If you see **“Unable to install REP”**, confirm automatic installation is still off, finish any phone Trust/Verify prompts, then repeat **this direct Watch Run**. Do not delete REP or repeatedly press Install in the phone's Watch app.

## 9. Check both devices before the gym

1. On iPhone, open REP → **Plan** and adjust routines and loads for yourself. Back + Biceps, Glutes, and Legs are editable starter plans; their loads are the author's estimates, not recommendations for you. You can create your own routines. Abs is an optional finisher within the same workout.
2. Keep REP open on both devices nearby for initial sync. Confirm the Watch shows your plan changes.
3. Close REP normally, **unplug the phone from the Mac**, and open REP again on both devices. It should open without Xcode running. If a Watch installation error appears, return to steps 6–8; the earlier installation is not a final success.
4. When ready, record a short **real** test workout on the Watch. Do not also start Apple's Workout app for it. Log a set, let the screen sleep briefly, wake it, and end the workout in REP. This saves a real workout, not demo data.
5. Check each outcome separately: the set remains after reopening REP, the phone receives the workout, and **exactly one** Traditional Strength Training workout appears in Apple Health/Fitness. Local logging, Health saving, and phone receipt are separate outcomes.

Opening the app does not prove every workout feature works on every device. Complete the real-device check before relying on this personal project for training.

## If something doesn't work

Find the matching row. After a fix, retry the relevant step once instead of repeatedly clicking Run.

| What you see | What to do next |
| --- | --- |
| Xcode cannot install on this Mac | Check [Apple's compatibility table](https://developer.apple.com/support/xcode/). A compatible macOS update or supported Xcode may be needed. Older Xcode downloads are on Apple's [resources page](https://developer.apple.com/xcode/resources/); the version must support both this project and your devices. |
| Phone charges but never appears | Unlock it, try another Mac USB port and data-capable cable, then repeat Finder Trust in step 3. |
| Wired phone installation stalls or loses connection | Use step 3: **phone Bluetooth OFF in Settings; Mac and Watch Bluetooth ON; USB connected; Wi-Fi on**. Run the phone scheme again. Restore phone Bluetooth afterward. |
| Developer Mode is missing | Connect/pair the device with Xcode first, then check **Privacy & Security** on that device. Keep phone Bluetooth on while pairing the Watch. See step 4. |
| Device is locked, busy, or preparing | Unlock the named device and confirm its prompts. Keep the Watch nearby. Allow preparation to finish; if unchanged for several minutes, try the reconnection sequence below. |
| Watch is missing from destinations | Choose the **Watch scheme first**. Confirm the Watch is paired in the iPhone Watch app, restore phone Bluetooth, then use the reconnection sequence below. |
| “Signing requires a development team” / author's name shown | Repeat step 5 for **both app targets**, choosing your Team and automatic signing. Choose All configurations if offered. |
| Identifier unavailable / cannot be registered | During first setup, choose a more distinctive prefix and update **all four values** in step 5. Preserve the chosen identifiers once you start storing your data. |
| Companion identifier mismatch / Watch app identifier error | Both companion values must exactly equal the iPhone identifier. The Watch app identifier adds `.watchkitapp`. Compare all four fields in step 5. |
| No provisioning profile / device not registered | Connect/unlock the physical device, select it as destination, verify automatic signing and your Team for both targets, and accept **Register Device** or **Try Again** if offered. Keep internet available. |
| No Personal Team appears | Check Xcode's Accounts settings for incomplete sign-in, verification, or agreements. If requested, sign into [Apple Developer](https://developer.apple.com/account/) with your own account and accept the free developer agreement, then return to Xcode. |
| Your Team cannot support a required capability, such as HealthKit | Keep the capability intact; do not buy anything just to clear the error. Apple's signing restriction must be resolved for this account before installation can complete. Use [Apple Developer Support](https://developer.apple.com/support/). Another person's install does not verify your account. |
| Untrusted Developer / cannot verify app | Finish the own-account Trust/Verify check in step 7 with internet available. Once the phone opens, repeat the direct Watch install. If no developer entry appears, recheck your signing Team and Run from Xcode; do not install an unrelated profile. |
| Watch says “Unable to install REP” / icon disappears after phone update or trust | Turn **Automatic App Install OFF**, finish phone trust/opening, then Run the **fitness Watch App** scheme to the physical Watch again. Do not use the phone Watch app's Install button. |
| Phone works but Watch does not | Complete step 8 and verify Watch opening after the phone works. The phone installation is only half the setup. |
| Unsupported device OS / missing platform support | Install requested platform support or use a compatible Xcode from [Apple's table](https://developer.apple.com/support/xcode/). Selecting a Simulator does not fix physical installation. |
| REP stops opening about a week later | Free signing may have expired. Renew below with the same account and identifiers. Do not delete REP. |
| Plan changes or logs do not arrive | Restore Bluetooth and Wi-Fi, keep devices nearby, open REP on both, and use Retry if offered. Check receipt/status rather than assuming connectivity proves delivery. |

### Reconnect without erasing anything

1. Click **■ Stop** in Xcode if a Run is in progress. Finish any real workout before device restarts or REP updates.
2. Restore phone Bluetooth **ON**, leave Mac and Watch Bluetooth on, and check Wi-Fi. Unlock both devices and keep them nearby.
3. Disconnect/reconnect the phone's USB cable and confirm trust if asked.
4. Open **Window → Devices and Simulators**, or **Xcode → Open Developer Tool → Device Hub** in newer versions. Select the device and complete pairing/preparation prompts, including any on the Watch. If offered **Connect via network**, enable it for wireless device access.
5. If still disconnected, quit/reopen Xcode. If necessary, restart the phone and Watch normally, unlock them, and reopen the project. Let preparation finish.
6. Select the right scheme and physical device and Run once. If only the wired **phone** install fails, try the phone Bluetooth workaround; restore Bluetooth before the Watch install.

Do not unpair/reset the Watch, delete REP, change identifiers after setup, or erase app storage to fix a connection. These actions can remove data. If an error has no matching fix here, retain its exact text. Unsupported hardware, Apple account restrictions, and unknown failures cannot honestly be guaranteed away by a guide.

## Renew or update without losing your data

You do **not** need to repeat the entire setup each week.

1. Finish any workout and use REP's backup/export controls to save a backup before an update. Keep it somewhere you can find again.
2. Open the **same saved project**, using the **same Apple Account/Team and four identifiers**. No fresh ZIP is needed just to renew signing.
3. Connect/unlock the phone, keep the Watch nearby and unlocked, and confirm **Automatic App Install OFF**.
4. Repeat **step 7**, installing over the existing phone app, and confirm it opens. Use the wired phone Bluetooth workaround if needed.
5. Restore phone Bluetooth and repeat **step 8**, installing directly over the existing Watch app. Verify Watch opening **after the phone installation and trust checks**.
6. Unplug the cable and check both apps again. An early rebuild can reuse a still-valid signing permission; it does not guarantee a fresh seven days.

**Do not delete the app first.** Installing over the same app normally retains storage; deleting it can delete local records. A different Team or identifier can create a separate copy. Keep your personal signing values in your own downloaded project.

For a source update, save your backup and note your Team and identifiers before replacing files. New downloads contain the repository's signing settings; reapply your own values before running. The repository does not contain your live plan or history.

## Optional: signing helper for Terminal users

**Skip this if you followed step 5.** This is an alternative to filling in the identifiers manually, not an extra requirement.

Close Xcode. With Python 3 available, run the following from the downloaded REP folder, substituting your own 10-character Team ID from Xcode's account/signing details and your unique iPhone identifier:

```sh
python3 scripts/configure-signing.py --team YOURTEAMID --bundle-id com.yourname.rep --dry-run
python3 scripts/configure-signing.py --team YOURTEAMID --bundle-id com.yourname.rep
```

The first previews values; the second updates your downloaded Xcode project and Watch Info.plist. Reopen Xcode and verify your Team and automatic signing for both targets. The helper does not install apps or read workout data. Do not contribute personal signing changes upstream.

Apple references: [download Xcode](https://developer.apple.com/xcode/resources/), [run on physical devices](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html), [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device), [Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account), and [Bluetooth controls](https://support.apple.com/en-us/102412). Author-reported connection workarounds above are project experience, not Apple guarantees.
