# Native Plasma (experiment)

Goal: run KDE Plasma as Android code, the way GDroid runs Garry's Mod: built
with the NDK against Android's libc, drawing with the phone's own GPU driver.
No proot, no Debian rootfs for the desktop itself, no GPU forwarding.

The current desktop (proot + Debian + Termux:X11, Venus on non-Adreno GPUs)
stays as it is. Its last known-good state is the `gold-backup` branch.

## Design

- **Compositor:** KWin with a new Android backend. It renders into the
  activity's `Surface` (`ANativeWindow`) with Android's EGL/GLES, and maps each
  connected display to its own surface (Presentation API for external
  monitors). Input comes from Android `MotionEvent`/`KeyEvent` instead of
  libinput.
- **Buffers:** apps render into `AHardwareBuffer`s and hand them to the
  compositor over a unix socket together with a native fence; the compositor
  samples them as EGLImages and its GPU waits on the fence. Nothing is copied,
  forwarded or read back. For Wayland apps this becomes a small protocol
  extension that carries AHardwareBuffers.
- **Apps:** Qt 6 and KDE Frameworks built for Android (Qt already supports
  it), with a Qt platform plugin that speaks the buffer protocol. KDE's
  dependencies on udev, logind, polkit and glibc get stubbed or patched.
- **Linux apps:** Debian apps and FEX games keep running in the existing proot
  system and show up as windows on the native desktop.

## Stages

1. **Buffer path test (this branch).** `native/nativedesk/`: a minimal
   compositor and a stand-in app, both native, measuring frame rate and CPU
   time per frame on the Pixel 10 Pro. Settings → Native desktop test.
2. Qt 6 for Android with a platform plugin that uses the same buffer protocol
   (one real Qt window on the test compositor).
3. KWin built for Android with the Android backend replacing the test
   compositor.
4. plasmashell and the KDE apps; then bridge proot apps in as windows.

## What to look for in stage 1

- Both test windows at the panel's refresh rate (120 Hz on the Pixel 10 Pro)
  while dragging windows.
- Compositor CPU time per frame well under 1 ms.
- The heavy app (1024 spinning squares) not slowing down the light one.
