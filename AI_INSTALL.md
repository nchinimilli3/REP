# Copy this into an AI assistant to install REP

**Yes—an assistant can do the computer work for you if it can run commands on your Mac.** You still plug in the phone, enter your own passwords in Apple's windows, and tap Apple's device confirmations. The assistant should explain each of those actions when it is time.

## Do this first

1. Download/unzip [REP](https://github.com/nchinimilli3/REP) on your **Mac** if you have not already. Keep the whole folder.
2. If you do not have a local assistant, follow [OpenAI's desktop app download/setup instructions](https://learn.chatgpt.com/docs/app). Choose the Mac download, install/open the app as instructed there, and sign into your **ChatGPT account**. This is separate from the Apple Account you will use in Xcode.
3. Choose **Codex** in the desktop app's mode selector (or open your existing local coding assistant). Open/add your downloaded **REP-main folder** as its project and start a new chat there. Choose **This computer / Local** if offered, and allow the folder/command permissions needed for this task. For the exact current interface, see [local projects](https://learn.chatgpt.com/docs/projects) and [local versus cloud environments](https://learn.chatgpt.com/docs/environments/modes). If your account cannot use a local assistant, use the manual guide or the chat-only route below.
4. Plug the **iPhone into the Mac with a data-capable USB cable**. Keep your paired Watch nearby and unlocked. You can start the chat before Xcode is installed—the assistant will guide that part.
5. Copy the entire box below into the assistant and send it. The copy button at the top right of the code box on GitHub copies the prompt.

**Using ordinary ChatGPT or another chat-only AI?** Paste the same prompt there. It should explain the next clicks, but cannot install anything unless its actual tools have access to your Mac and devices. Uploading a ZIP or connecting GitHub alone does not provide that access. A cloud computer cannot reach your plugged-in devices by default. The prompt requires the assistant to check rather than pretend it has installed anything.

## Copy everything in this box

```text
Help me install REP on my own iPhone and paired Apple Watch. I have no coding,
Xcode, Terminal, or software-development experience. Handle the computer work
you can do and give me one short, specific instruction at a time when I must
click, plug in, unlock, sign in, or confirm something. Continue after my reply.

Repository: https://github.com/nchinimilli3/REP
Installation instructions: docs/INSTALL.md
Portable installation helper: scripts/install-personal.py
Signing helper: scripts/configure-signing.py

First check your ACTUAL tools and where they run. Can you read my downloaded
REP folder and run commands on MY LOCAL MAC with Xcode and physical devices?
Do not confuse a cloud/Linux environment, uploaded ZIP, GitHub connection, or
Simulator with access to my Mac. If you lack local execution, say that plainly
and help me open this folder in a local assistant, or guide me through
docs/INSTALL.md one step at a time. Do not claim to run anything you did not run.
If you cannot read those files, fetch their actual contents from the repository
or ask me to attach the installation guide; do not invent the missing steps.

If you have local Mac access, I authorize the necessary local signing setup,
building, and in-place installation on the specific personal devices I select.
Read README.md, docs/INSTALL.md, this file, and both helpers before acting.
Follow applicable repository instructions if present. Do not change app logic,
publish my settings, commit/push changes, or install on an unconfirmed device.

Work through this sequence:

1. Find my REP folder and inspect Xcode/tool availability. Guide me through
   downloading Xcode, opening it, accepting its license, installing requested
   iOS/watchOS support, and signing into MY Apple Account if needed. Use the
   official Apple download. Never request my password, 2FA code, or private
   signing key in chat; I enter those directly in Apple's windows. Do not
   purchase a developer membership. If tools point at Command Line Tools
   rather than full Xcode, use the installed Xcode's DEVELOPER_DIR for your
   commands instead of making an unexplained system-wide change.

2. Guide USB connection, Finder/phone Trust, device pairing with Xcode, and
   Developer Mode on BOTH phone and Watch, including restarts/confirmations.
   Check actual macOS/Xcode/device compatibility. Discover physical devices
   with `python3 scripts/install-personal.py --list-devices`; inspect installed
   devicectl help if a connection needs investigation. Show me the detected
   device names and ask which are mine when ambiguous. Use their exact current
   CoreDevice identifiers, never identifiers copied from the app author's setup.

3. Identify my actual Apple signing Team. On a FIRST install, choose my own
   unique bundle identifier and use configure-signing.py --dry-run, then the
   real command with my Team and bundle ID, with Xcode closed. Verify all four
   related values described in INSTALL step 5. For an EXISTING installation,
   preserve its original Team and identifiers; do not reset them to repository
   defaults or invent new ones. The repository author's signing values are
   not my account. Keep HealthKit enabled on both targets. If Python 3 is
   unavailable, explain that and use the Xcode walkthrough rather than claim
   the Python helpers ran.

4. Before installing, ask me to confirm: no workout is active; any existing
   data I need is backed up; the selected devices are unlocked/ready; and
   iPhone Watch app > My Watch > General > Automatic App Install is OFF.
   Explain this setting once: it also affects automatic install of other new
   Watch apps. Do not pass the helper's --ready flag before I confirm these.
   Run only one installer/build at a time. Use --dry-run first to inspect the
   commands without contacting devices or building.

5. Install the PHONE stage with scripts/install-personal.py using my actual
   --device, --team, and --bundle-id, plus --stage phone and --ready. Keep the
   cable connected. If the wired phone installation stalls or repeatedly
   cannot connect, use this AUTHOR-REPORTED workaround: iPhone Settings >
   Bluetooth OFF; Mac Bluetooth ON; Watch Bluetooth ON; Wi-Fi left ON; iPhone
   still plugged into the Mac. Use phone Settings, not Control Center.
   Do not present this workaround as guaranteed or switch off Mac/Watch
   Bluetooth. Ask me to change the phone setting if you cannot do so.
   If it worsens connectivity, restore phone Bluetooth and recheck USB trust.

6. STOP after phone installation for me to tap REP and confirm it opens.
   Resolve any own-account Trust/Verify prompt in iPhone Settings > General >
   VPN & Device Management if present. Restore iPhone Bluetooth ON before
   Watch installation. Confirm the phone works and Automatic App Install is
   still OFF. Phone trust must be settled BEFORE the final direct Watch install.

7. Install the WATCH stage with scripts/install-personal.py using my actual
   Watch --device, same --team and iPhone --bundle-id, --stage watch, --ready,
   and --phone-open-confirmed. Only use that last flag after my confirmation
   in step 6. This builds/signs the watchOS app and installs it DIRECTLY via
   Apple's devicectl, not through the iPhone Watch app's Install button.
   Do not toggle REP's Show App on Apple Watch setting. If a placeholder or
   “Unable to install REP” appears, check auto-install OFF and phone trust
   before one direct Watch retry. Use INSTALL's bounded reconnection steps;
   do not run endless retries or unbounded startup diagnosis.

8. Keep build, signing, installation, automated launch, and my manual opening
   confirmations separate. If automated launch fails but I can open the app,
   report that distinction and do not rebuild repeatedly. The helper prints a
   private temporary log/build directory; inspect the relevant log for a
   failure without uploading my profile, keys, device logs, or health records.
   If signing/capability/account restrictions remain, explain the exact blocker
   in plain language; do not remove HealthKit, bypass security, or claim success.

9. Ask me to open REP on the Watch, complete Health permissions, unplug the
   phone from the Mac, and manually reopen REP on BOTH devices. Explain how
   to customize Plan and check initial sync. Do not start a workout yourself.
   Offer the short real-workout check in INSTALL step 9 and explain that it
   records a real workout. Installation/opening alone do not prove Health
   saving, phone receipt, or workout reliability.

10. Finish with what actually succeeded for each device, anything still
    unresolved, the actual profile expiry reported by the helper, and simple
    renewal instructions. Free Personal Team profiles expire seven days after
    issuance; an early rebuild may reuse the existing expiry. Keep this project
    and the same signing values. Never delete REP, reset/unpair the Watch, erase
    app storage, or change an existing app identifier as a troubleshooting fix.

Start by checking whether you have access to my local Mac and REP folder.
```

## What the helper does

The assistant can run `python3 scripts/install-personal.py --help`. It needs **Python 3, full Xcode, a configured Apple signing account, and reachable physical devices**. Xcode must have completed first-launch setup. It has no default device IDs and does not modify signing settings or device radio settings.

It checks your configured identifiers, identifies the selected physical device, builds with two jobs, verifies the signature and HealthKit provisioning, prints profile expiry, installs directly in place, and attempts launch. **Phone and Watch are separate invocations**, so Apple trust and Bluetooth steps can happen between them. Failed steps stop with a nonzero exit and local logs. A preview validates configuration and prints commands without building or contacting devices.

These are command templates **for the assistant to fill in**, not commands you need to understand or copy unchanged:

```sh
python3 scripts/install-personal.py --list-devices
python3 scripts/install-personal.py --stage phone --device PHONE_ID --team YOURTEAMID --bundle-id com.yourname.rep --dry-run
python3 scripts/install-personal.py --stage phone --device PHONE_ID --team YOURTEAMID --bundle-id com.yourname.rep --ready
# Pause for actual phone opening/trust and restore phone Bluetooth ON.
python3 scripts/install-personal.py --stage watch --device WATCH_ID --team YOURTEAMID --bundle-id com.yourname.rep --dry-run
python3 scripts/install-personal.py --stage watch --device WATCH_ID --team YOURTEAMID --bundle-id com.yourname.rep --ready --phone-open-confirmed
```

For renewal, paste the same prompt into the local assistant and add: **“REP is already installed. Renew it using my existing Team and identifiers; preserve my data.”**

## Validation and limits

This portable helper is based on the project's direct-device deployment approach. Its [automated fixture checks](scripts/test-personal-installer.py) exercise signing validation, device selection, stage ordering, failure stops, preview behavior, and process timeouts without building or installing an app. Run them with `python3 scripts/test-personal-installer.py`.

These checks are not proof of a successful installation on a new person's devices. Apple account support, device connection, actual signing/build/install/launch, and the user's unplugged opening checks still need to succeed on that Mac. If an assistant cannot run the helper, the [manual beginner guide](docs/INSTALL.md) remains available.
