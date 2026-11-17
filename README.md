# Stay Awake

A macOS menu bar app that keeps your Mac awake — even with the lid closed — on weekdays from 8 AM to 8 PM while it's on Wi-Fi. At night, on weekends and off Wi-Fi the Mac sleeps as usual, so it won't run hot in a bag.

## Menu

- **Allow Sleep** — the Mac sleeps whenever macOS decides to.
- **Stay Awake** — the Mac doesn't sleep on weekdays 8 AM – 8 PM while connected to Wi-Fi; otherwise it sleeps as usual.
- **By Rule** — your own rule, set right in the menu once this mode is selected: days of the week, hours (all day or a range, overnight too), and whether to require Wi-Fi and the power adapter. By default it is every day, all day with no conditions, so the Mac never sleeps.

**⌃⌥⌘S** switches between Allow Sleep and Stay Awake from any app. The rule is re-checked every 10 seconds, so the Mac goes back to staying awake by itself in the morning or once Wi-Fi reconnects.

The icon shows the current state: ☀️ the Mac stays awake, 📅 it stays awake by your rule, 🌙 it sleeps as usual. When the schedule pauses Stay Awake, the icon's tooltip says why.

The app adds itself to Login Items on launch, so it keeps working after a restart. It follows the system language: English and Russian.

## How it works

Closing the lid puts a Mac to sleep regardless of power assertions like `caffeinate`. The only switch that overrides it is `pmset disablesleep`, which needs root. Stay Awake sets it with `sudo -n /usr/bin/pmset -a disablesleep 0|1`; without a sudoers rule it falls back to the standard admin password dialog.

The power adapter is checked through IOKit. Wi-Fi is checked through CoreWLAN rather than `NWPathMonitor`, which reports Wi-Fi as unavailable while a VPN is active.

## Build

Requires macOS 13+ and the Xcode command line tools.

```bash
./build.sh
open ~/Applications/"Stay Awake.app"
```

The app is ad-hoc signed and built into `~/Applications`. The icon is drawn by `make-icon.swift` at build time.

## Switching without a password

Install a sudoers rule that allows exactly `pmset -a disablesleep 0` and `1` and nothing else:

```bash
sed "s/YOUR_USERNAME/$(whoami)/" stay-awake.sudoers > /tmp/stay-awake.sudoers \
  && sudo visudo -cf /tmp/stay-awake.sudoers \
  && sudo install -m 440 -o root -g wheel /tmp/stay-awake.sudoers /etc/sudoers.d/stay-awake
```

Remove it with `sudo rm /etc/sudoers.d/stay-awake`.

## Uninstall

1. Quit the app from its menu.
2. Restore normal sleep: `sudo pmset -a disablesleep 0`.
3. Delete `~/Applications/Stay Awake.app` and, if installed, the sudoers rule.
