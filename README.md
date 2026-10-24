# DeskDroid

A full KDE Plasma desktop on non-rooted Android phones: one app, tap to start, works on the phone screen and on external monitors. Licensed GPL-3.0. Distributed through GitHub Releases and F-Droid (not Google Play).

Architecture and roadmap: see [docs/plan.md](docs/plan.md).

## Status: Phase 1, "Tap to desktop" (in progress, not yet tested on a device)

What's in it:
- `app/`: the Android app (Kotlin, plain views). Setup flow and Home screen in the approved "party" design, installer service, session service, and the desktop window with its overlay drawer.
- `external/termux-x11/`: Termux:X11 as a git submodule. Its `lorie` library (X server, input, clipboard) is built into the APK, so users don't install a second app.
- `native/`: proot, talloc and the installer helper `ddtool` (zstd + minisign), compiled from source with the NDK during the Gradle build. No prebuilt binaries anywhere, as F-Droid requires. See [native/README.md](native/README.md).
- `rootfs/`: builds the Debian trixie arm64 images (`.tar.zst`) with `mmdebstrap`, one per edition: Light (Plasma + Discover), Full (Plasma + apps) and Ultra-lite (MATE).
- `.github/workflows/`: CI that builds the APK and publishes signed images plus `deskdroid-images.json` as the `rootfs-latest` release.

How the pieces fit at run time:
1. The installer reads `deskdroid-images.json`, downloads the chosen edition (resumable, in parts if over 2 GB), checks its minisign signature, and unpacks it into app-private storage.
2. "Start desktop" runs the X server (lorie's `CmdEntryPoint`, as a child process), opens `DesktopActivity`, then boots Debian under proot: system D-Bus, PulseAudio, then Plasma.
3. Sound: PulseAudio writes into a FIFO that the app plays with `AudioTrack`.

GPU acceleration on Mali and PowerVR (Pixel 10): in progress, through Venus Vulkan forwarding (the app's Venus server runs Linux apps' Vulkan on Android's GPU driver) with Zink for OpenGL. It replaced an earlier virgl attempt that crashed KWin. Checklist: [docs/gpu-venus-checklist.md](docs/gpu-venus-checklist.md).

Steam (Light and Full): runs Valve's x86 client under FEX-Emu, which `fex/build.sh` builds in CI (Actions → FEX-Emu, release `fex-latest`). FEX, its x86 rootfs and Steam's bootstrap download on Steam's first start. Checklist: [docs/steam-checklist.md](docs/steam-checklist.md).

Not done yet in Phase 1: Turnip/kgsl Mesa build for Adreno, the Android 12-13 one-tap phantom-process fix over Wireless debugging, and device testing ([docs/phase1-checklist.md](docs/phase1-checklist.md)).

## Build

Clone with submodules:

    git clone --recurse-submodules <repo>
    # or, in an existing clone:
    git submodule update --init --recursive

Needs JDK 17, the Android SDK, the NDK version pinned in `app/build.gradle.kts`, and `python3` + `bison` (Termux:X11's X server build). Then:

    ./gradlew assembleDebug

CI does the same on every push (Actions → Android APK, artifact `deskdroid-debug-apk`).

System images: Actions → **Rootfs images** → Run workflow. Publishes all three editions to the `rootfs-latest` release.

## Signing key for system images

The app only installs images signed with DeskDroid's minisign key (debug builds without a key fall back to SHA-256).

1. `minisign -G -W -p deskdroid.pub -s deskdroid.key` (no password; the key lives only in GitHub's encrypted secrets).
2. Repo Settings → Secrets → Actions: `MINISIGN_SECRET_KEY` = contents of `deskdroid.key`.
3. Repo Settings → Variables → Actions: `MINISIGN_PUBLIC_KEY` = the second line of `deskdroid.pub`. The APK workflow bakes it in; for local builds set `deskdroidImagePublicKey` in `gradle.properties`.
