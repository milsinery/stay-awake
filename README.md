# Stay Awake

A macOS menu bar app that keeps your Mac awake — even with the lid closed — on weekdays from 8 AM to 8 PM while it's on Wi-Fi. At night, on weekends and off Wi-Fi the Mac sleeps as usual, so it won't run hot in a bag.

## Menu

- **Allow Sleep** — the Mac sleeps whenever macOS decides to.
- **Stay Awake** — the Mac doesn't sleep on weekdays 8 AM – 8 PM while connected to Wi-Fi; otherwise it sleeps as usual.
- **By Rule** — your own rule, set right in the menu once this mode is selected: days of the week, hours (all day or a range, overnight too), and whether to require Wi-Fi and the power adapter. By default it is every day, all day with no conditions, so the Mac never sleeps.

**⌃⌥⌘S** switches between Allow Sleep and Stay Awake from any app. The rule is re-checked every 10 seconds, so the Mac goes back to staying awake by itself in the morning or once Wi-Fi reconnects.

The icon shows the current state: ☀️ the Mac stays awake, 📅 it stays awake by your rule, 🌙 it sleeps as usual. When the schedule pauses Stay Awake, the icon's tooltip says why.

The app follows the system language: English and Russian.

## How it works

Closing the lid puts a Mac to sleep regardless of power assertions like `caffeinate`. The only switch that overrides it is `pmset -a disablesleep`, which needs root.

Stay Awake does not ask for an admin password and does not install a sudoers rule. The app registers a helper with `SMAppService.daemon`. The helper is the only process that runs `/usr/bin/pmset -a disablesleep 0` or `1`, and it accepts that request only over XPC from this app, checked with a code-signing requirement (bundle id `com.milsinery.stay-awake`, team `CA23Z5CN46`).

The helper allows sleep again when the app quits, when the last connection drops, when it is unregistered, when `pmset` fails while trying to keep the Mac awake, and whenever the helper itself starts — including after a crash, because launchd restarts it and startup sets `disablesleep` back to `0`.

The power adapter is checked through IOKit. Wi-Fi is checked through CoreWLAN rather than `NWPathMonitor`, which reports Wi-Fi as unavailable while a VPN is active.

## First launch

On launch the app registers two separate items:

1. **The app itself**, with `SMAppService.mainApp`, so it opens again after you log in. There is no menu switch for this. Turn it off only in System Settings.
2. **The helper**, which needs its own one-time approval under **System Settings → General → Login Items & Extensions**. When macOS reports that the helper still needs approval, the app asks and can open that pane (`SMAppService.openSystemSettingsLoginItems`). Until the helper is allowed, the menu cannot change sleep.

Approving the app in Gatekeeper does not approve the helper. They are separate.

## Build

Requires macOS 13+ and Xcode.

Logic that does not need root or a Mac UI is covered by `swift test` (the schedule, the `pmset` arguments, and checks that the sources do not call out to an admin shell). Those tests were run on Linux. This environment cannot compile, sign, or notarize the Mac app; that still has to happen on a Mac.

```bash
swift test
./build.sh          # Debug, Apple Development signing, copied to ~/Applications
./build.sh Release  # Developer ID signing
open ~/Applications/"Stay Awake.app"
```

`build.sh` is an `xcodebuild` wrapper around `StayAwake.xcodeproj`. The icon is drawn by `make-icon.swift` during the Xcode build.

Bundle ids: `com.milsinery.stay-awake` and `com.milsinery.stay-awake.daemon`. Team `CA23Z5CN46`. Release builds use Developer ID Application, the hardened runtime, and a timestamp.

## Remove an old sudoers rule

Builds before this one could install `/etc/sudoers.d/stay-awake` (see `stay-awake.sudoers`, which the app no longer reads). Remove it:

```bash
sudo rm -f /etc/sudoers.d/stay-awake
```

## Uninstall

From the installed app:

```bash
"/Applications/Stay Awake.app/Contents/MacOS/StayAwake" --uninstall
```

That asks the helper to set `disablesleep` to `0`, unregisters the helper (which sets `disablesleep` to `0` again as it exits), and unregisters the app's session start. Then delete `Stay Awake.app`.

Confirm sleep is allowed:

```bash
pmset -g | grep SleepDisabled
```

No `SleepDisabled` line, or a line ending in `0`, means the Mac can sleep. If a `1` remains and the helper is already gone, set it back once with an admin `pmset -a disablesleep 0` and remove the old sudoers file if it is still there.

## Gatekeeper

A Release build is signed for Developer ID distribution. Gatekeeper on another Mac still rejects it until the app and the disk image are notarized and stapled. Signing alone is not enough. A right-click → Open is only a local bypass, not the way to ship the app.

`scripts/package-for-distribution.sh` archives with the Release configuration, exports with `Distribution/ExportOptions.plist`, notarizes with `notarytool`, staples, and builds a disk image that opens onto the app and an Applications shortcut. Store the notary profile once as `stay-awake-notary` (team `CA23Z5CN46`); the script does not take a password on its command line.

After notarizing, check the app with `spctl --assess --type execute` and the disk image with `spctl --assess --type open`. The helper still needs the separate Login Items approval above.
