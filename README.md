# DeskDroid

A full KDE Plasma desktop on non-rooted Android phones: one app, tap to start, works on the phone screen and on external monitors. Licensed GPL-3.0.

Architecture and roadmap: see [docs/plan.md](docs/plan.md).

## Status: Phase 0 feasibility spike

This build answers one question: does the architecture work on real phones (Pixel 10 Pro first)?

What's in it:
- `app/`: a minimal Android launcher (Kotlin, no AndroidX). Downloads and unpacks the rootfs, starts the X server and Plasma under proot from a foreground service, and shows the desktop on the phone screen or an external display.
- `rootfs/`: builds the Debian trixie arm64 images with `mmdebstrap`, one per edition: Light (Plasma + Discover), Full (Plasma + apps) and Ultra-lite (MATE).
- `scripts/fetch-prebuilts.sh`: pulls Termux's Android build of proot into `jniLibs` (so it is executable under Android's W^X rule).
- `.github/workflows/`: CI that builds the APK and publishes the rootfs as the `rootfs-latest` release.

Phase 0 shortcuts (all replaced in Phase 1):
- The display server is the separately installed **Termux:X11** app, run the same way Termux runs it. Phase 1 embeds it.
- No audio yet.
- GPU: software rendering (llvmpipe) by default. VirGL and Turnip modes are wired in the session script but need Android-side pieces that come next.

## First build

1. Create the GitHub repo and push this folder to `main`.
2. Actions → **Rootfs images** → Run workflow. Publishes all three editions to the `rootfs-latest` release.
3. Actions → **Android APK** runs on push. Download the `deskdroid-debug-apk` artifact.
4. On the phone: install Termux:X11 from https://github.com/termux/termux-x11/releases and the DeskDroid APK.
5. Follow `docs/spike-checklist.md`.

Local build (needs Android SDK, JDK 17, patchelf): `scripts/fetch-prebuilts.sh && ./gradlew assembleDebug`.
