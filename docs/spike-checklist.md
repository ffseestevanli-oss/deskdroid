# Phase 0 spike checklist (Pixel 10 Pro)

Record results for each step (works / fails + log excerpt from the app screen).

## Setup
- [ ] DeskDroid and Termux:X11 installed
- [ ] "Fix background limits": battery set to unrestricted, Developer options → "Disable child process restrictions" on

## Install
- [ ] "Download and install" finishes; status says Installed (note time taken and storage used)
- [ ] Re-running install after airplane-mode interruption resumes the download

## Desktop on the phone screen
- [ ] "Start desktop" with GPU = Software: Termux:X11 opens and Plasma appears
- [ ] Log shows proot started without `execve` / permission errors (W^X check)
- [ ] Dolphin, Konsole, Kate, System Settings open (Light image first: smallest Plasma)
- [ ] Firefox ESR opens a website (Full / Ultra-lite) (network + DNS work)
- [ ] `sudo apt update` works in Konsole, and Discover can install an app (Light)
- [ ] Ultra-lite image starts a MATE desktop
- [ ] Touch and Bluetooth/USB mouse + keyboard work
- [ ] Session survives 10 minutes of use and 5 minutes screen-off
- [ ] "Software, compositing off" feels faster than compositing on

## External monitor
- [ ] With a USB-C monitor connected, the display picker lists it
- [ ] Desktop opens on the monitor at its native resolution
- [ ] Try a non-16:9 monitor or Android desktop-mode freeform window, and note what happens on resize

## GPU (exploratory)
- [ ] Konsole: `glxinfo -B` and `vulkaninfo --summary` output saved
- [ ] Note whether `/dev/dri` or any GPU node is visible (`ls -l /dev/dri /dev/kgsl* /dev/pvr*`)

## Go / no-go
Write up: what worked, what failed, and whether the architecture in the plan holds.
