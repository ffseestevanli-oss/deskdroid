# Phase 1 device checklist (Pixel 10 Pro first)

Exit criterion: a non-technical tester gets from installing the APK to a working Plasma desktop in under 10 minutes, with no terminal.

## Setup flow
- [ ] Welcome → "Let's go" → loadout picker shows Full/Light, "…or there's this" reveals Ultra-lite; free space shown
- [ ] Install Light: progress ring moves through Download → Verify → Unpack → Create your account
- [ ] Turn on airplane mode mid-download: "Connection lost, retrying", then resumes when back online
- [ ] Swipe the app away mid-download, reopen: the download continues from where it was
- [ ] Notification shows progress and a working Cancel; "Your desktop is ready" when done
- [ ] Keep it running: Developer options button lands in the right place; status flips to "Fixed" after toggling "Disable child process restrictions"
- [ ] Battery row: asks to turn optimization off, then says "All set"

## Desktop on the phone
- [ ] Start desktop: the desktop window opens, Plasma appears with the DeskDroid wallpaper (no Termux:X11 app installed)
- [ ] Text is readable without zoom (Plasma scale from screen density)
- [ ] Touchpad mode: tap = click, two-finger tap = right click, two-finger drag = scroll
- [ ] Direct touch mode from the drawer
- [ ] Drawer: opens from the right-edge handle; Keyboard, Extra keys, Zoom, Stop work
- [ ] Bluetooth/USB keyboard and mouse
- [ ] Sound: play a video in Firefox (Full) or `paplay /usr/share/sounds/...`; note the delay
- [ ] Clipboard: copy in Android, paste in Kate, and back
- [ ] Discover installs an app (Light), `sudo apt update` in Konsole works
- [ ] Session survives 10 minutes of use and 5 minutes screen-off
- [ ] "To monitor" moves the desktop to a USB-C monitor and back

## Options
- [ ] Lock my desktop: fingerprint/PIN asked when opening the app and the desktop
- [ ] Start on phone boot: after reboot and unlock, notification says the desktop is running; tapping it opens it

## Logs to send back
Settings → Log (selectable text), plus `adb logcat -s DeskDroid LorieNative CmdEntryPoint` if something fails.
