# DeskDroid

**A real KDE Plasma desktop on Android.** One app, no root: tap it and your phone becomes a computer, with a panel, windows, a file manager, System Settings and a keyboard and mouse, on the phone screen or an external monitor. It runs KDE apps natively, Flathub apps, and x86-64 Linux software through Box64 and FEX.

Website: **https://ffseestevanli-oss.github.io/deskdroid/** · License: GPL-3.0 · Current build: **1109** (app version 0.1.3)

## What it is

DeskDroid runs Plasma as Android code. KWin, plasmashell and the KDE apps are built with the Android NDK and draw with the phone's own GPU driver. There is no proot, no Linux image for the desktop itself, and no GPU forwarding. Under it sits **ddmask**, DeskDroid's loader, which lets ordinary Linux (glibc) programs and Flatpaks run inside an Android app, and hands x86-64 programs to Box64 or FEX.

You can use it like Samsung DeX, as a desktop for your Android apps, or like an actual Linux computer running actual desktop software. Both live on the same desktop.

## Features

**The desktop**
- KWin with a DeskDroid backend and plasmashell: panel, Kickoff (plus Application Menu and Start 7 Plus), system tray, Folder View desktop, notifications, End Session screen and panel editing, the way Plasma works on a PC.
- System Settings with DeskDroid's own pages: About This Phone, power profiles (Power Save, Balanced, Performance), Gestures, Cursors, Wallpaper, Sounds, Splash Screen, Shortcuts and Accessibility.
- KWin with X11 support: Xwayland starts on demand, so X11-only apps become normal windows next to Wayland ones.
- PipeWire and WirePlumber for sound, with EasyEffects and ViPER FX available.

**External displays and peripherals**
- Plug in a monitor and the desktop moves to it, with its own scale. The phone becomes a touchpad, with a MENU button and edge swipes. Android's own desktop mode and DeX are kept off the monitor.
- Keyboard and mouse work like on a PC. On the phone screen you get direct touch or touchpad mode, a three-finger tap, edge swipes, and the phone's keyboard (swipe typing and suggestions included) whenever a text field has focus.

**Android integration**
- **Launcher mode:** DeskDroid can be your home app. Your Android apps are in Kickoff and in a phone app drawer with a Private Space section.
- Files open in Android apps through Open With, Android widgets can sit on the desktop, and Restart or Power Off opens Android's power menu.

**Installing software**
- **Agora**, DeskDroid's store: apps built for Android (KDE apps, GIMP, Sasha and more) plus ready-made `.adpk` packages, installed or removed in seconds.
- **Flathub inside Agora:** browse all of Flathub by category and install with `flatpak`. ARM64 apps run natively; x86-64 apps run through FEX. LibreOffice, Krita, Inkscape, Kdenlive, Audacity, Okular, Prism Launcher and many more have been tested.
- **Etherium**, DeskDroid's browser: Firefox rebuilt with nothing phoning home and uBlock Origin included, installed from Agora.

**DD Party**
DeskDroid's own look: near-black surfaces, #990045 magenta, rainbow accents, chamfered corners and its own icon set. It covers Plasma, window decorations, Qt and GTK apps, the splash screen and Etherium. It also works as a theme on any Plasma 6 desktop ([theme/dd-party](theme/dd-party/README.md)). Breeze and the other Plasma themes remain in System Settings.

## Coming next

- **Steam:** Steam on FEX already starts from the Steam Installation Assistant. Getting games running well on the phone's GPU is the work in progress.
- **Sober flavor:** a DeskDroid flavor with Sober set up for playing Roblox from the desktop.
- More Agora apps, a public download host for builds and store packages, and a refreshed website.

## Downloads

Builds are numbered (currently 1109) and install over each other, since every build is signed with the same key. Public download links are being moved to a new host and will be listed on the [website](https://ffseestevanli-oss.github.io/deskdroid/) when they're ready. The old 0.1.0 alpha on the Releases page predates the native desktop and is out of date.

## Repository layout

- `app/`: the Android app (Kotlin): setup, DDHome, the native desktop host (`NativeDesk.kt`, `QtHost.kt`), external display handling, gestures, Agora and the Flathub catalog.
- `native/plasma/`: builds Qt 6, KDE Frameworks, KWin, plasmashell, System Settings and the KDE apps for Android with the NDK.
- `native/nativedesk/`: KWin's DeskDroid backend and the compositor glue.
- `native/ddmask/`: the loader that runs glibc programs, Flatpaks and x86-64 programs (Box64, FEX) inside the app.
- `native/flatpak/`, `native/glibc/`, `native/sound/`: Flatpak tooling, glibc for ddmask, and the PipeWire sound server.
- `native/firefox/`: the Etherium browser build. `native/store/`: Agora's package builder.
- `fex/`: FEX-Emu for Android. `theme/dd-party/`: the DD Party theme.
- `tools/cloud-build.sh`: the full APK build in one script. `tools/flathub-adpk/`: turns Flathub apps into `.adpk` packages.
- `docs/`: design notes ([docs/native-plasma.md](docs/native-plasma.md) explains how the native desktop works).

## Build

Needs Linux x86_64, JDK 17, the Android SDK, the NDK pinned in `app/build.gradle.kts`, and the usual build tools.

    git clone --recurse-submodules https://github.com/ffseestevanli-oss/deskdroid
    cd deskdroid
    tools/cloud-build.sh

The first run builds Qt, KDE Frameworks, KWin and Plasma from source, which takes a few hours. The script keeps that prefix, so later APK builds take about ten minutes. Everything is compiled from source, with no prebuilt binaries.

The GitHub Actions workflows in `.github/workflows/` are kept for reference and only run when started by hand.

## Older docs

The first DeskDroid desktop ran Plasma on Debian under proot through Termux:X11. It has been replaced by the native desktop. Its notes are still here for reference: [README.txt](README.txt), [docs/plan.md](docs/plan.md), [docs/steam-checklist.md](docs/steam-checklist.md) and [docs/gpu-venus-checklist.md](docs/gpu-venus-checklist.md).
