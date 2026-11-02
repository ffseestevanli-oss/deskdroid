# DeskDroid

A real KDE Plasma desktop on non-rooted Android phones: one app, tap to start, with a panel, windows, a file manager and a keyboard and mouse, on the phone screen or an external monitor. Licensed GPL-3.0. Distributed through GitHub Releases and F-Droid (not Google Play).

**Try it:** the first alpha, [0.1.0 alpha](https://github.com/ffseestevanli-oss/deskdroid/releases/tag/v0.1.0-alpha), is on the Releases page. It is an early test build, so expect rough edges.

## Plasma, running natively on Android

DeskDroid now runs Plasma as Android code. KWin, plasmashell and the KDE apps are built with the Android NDK against Android's own libc and draw with the phone's own GPU driver. There is no proot, no Linux system image to download, and no GPU forwarding for the desktop itself.

What works today:
- **The desktop:** KWin with a DeskDroid backend, plasmashell with a panel, the Kickoff application menu and a Folder View desktop that shows the phone's Desktop folder, over the phone's wallpaper.
- **Apps:** Dolphin, KWrite and Gwenview, in Breeze Dark with Breeze Dark icons.
- **Plasma as you know it:** panel editing (edit mode, panel settings, widget explorer), rotation that follows the phone, scale that changes instantly (automatic by default), and End Session with KDE's logout screen.
- **Input:** touchpad or direct touch, keyboard and mouse, and the phone's keyboard pops up when a text field has focus. Back opens DeskDroid's side menu.
- **Android integration:** DeskDroid can be your home app (launcher mode). Kickoff has an Android Apps folder with your phone's apps, files open in Android apps through Open With, and Restart or Power Off on the logout screen opens Android's power menu.
- **App store:** a DeskDroid store inside the app. Each app is built for Android in CI and published as a GitHub release (`store-latest`), then installed or removed in seconds.

How the native desktop is built: [docs/native-plasma.md](docs/native-plasma.md). Until it is merged, the native desktop's code lives in [pull request #31](https://github.com/ffseestevanli-oss/deskdroid/pull/31).

## Installing software

- **The DeskDroid store.** KDE and other apps we build for Android, installed from the App Store in the desktop menu or Kickoff. They run at native speed with the phone's GPU.
- **Android apps** are in Kickoff's Android Apps folder.
- **No Flatpak.** It needs glibc and a sandbox feature Android doesn't allow for apps.
- **No Debian apt for now.** The Debian container that could have run other Linux software has been removed with the old desktop (see below).

## Roadmap

- **Floorp** as the desktop browser, ported natively. The GTK 3 libraries it needs already build for Android.
- **FEX-Emu and Steam:** FEX built natively and shipped through the store, running x86 programs such as Steam from a one-time x86 system download, without proot. Getting games onto the phone's GPU through Vulkan is the hard part.
- More apps in the store, Private Space and Work profile apps in Kickoff, and full external monitor support.

## Removed for now: the Debian (proot) desktop

The earlier desktop, Plasma on a Debian trixie system under proot shown through Termux:X11, has been removed from the app for now, along with all of its legacy settings, to keep DeskDroid fast and focused on the native desktop. That includes the Debian container and apt. Its old docs are still here for reference: [docs/plan.md](docs/plan.md), [docs/steam-checklist.md](docs/steam-checklist.md) and [docs/gpu-venus-checklist.md](docs/gpu-venus-checklist.md).

## Repository layout

- `app/`: the Android app (Kotlin, plain views): setup and Home screens, the native desktop (`NativeDesk.kt`, `QtHost.kt`), and the store.
- `native/nativedesk/`: the native compositor, KWin's DeskDroid backend glue and the store package builder.
- `native/plasma/`: builds Qt 6, KDE Frameworks, KWin, plasmashell and the KDE apps for Android with the NDK.
- `fex/`: builds FEX-Emu (for the FEX and Steam roadmap item).
- `.github/workflows/`: CI that builds the KDE stack and the APK, and publishes the store and the APK as releases.

Everything is compiled from source during the build, with no prebuilt binaries, as F-Droid requires. Code left over from the removed Debian desktop (proot, Termux:X11, the rootfs images) is being taken out.

## Build

Clone with submodules:

    git clone --recurse-submodules <repo>
    # or, in an existing clone:
    git submodule update --init --recursive

Needs JDK 17, the Android SDK, the NDK version pinned in `app/build.gradle.kts`, and `python3` + `bison` (Termux:X11's X server build). Then:

    ./gradlew assembleDebug

CI does the same on every push (Actions → Android APK, artifact `deskdroid-debug-apk`). Pushes to main publish the APK as `apk-latest` and the store as `store-latest`; pull requests get `apk-pr-N` and `store-pr-N` test releases.
