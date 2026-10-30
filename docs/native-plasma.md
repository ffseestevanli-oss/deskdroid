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

## Results so far (Pixel 10 Pro, PowerVR D-Series DXT-48-1536)

- Stage 1: the compositor holds 120 fps at about 1.8 ms of CPU per frame.
- Stage 2: Qt 6.8.3 windows run on the compositor through the `deskdroid`
  platform plugin, with Android's own fonts. With four windows on screen at
  once (both test apps at 120 fps), the Qt raster window runs at 84-101 fps
  and the Qt OpenGL window (QPainter on the GPU) at 82-94 fps; the two Qt
  windows share one thread.
- Stage 2b: a Qt Quick (QML) window runs next to them on Qt Quick's scene
  graph over OpenGL ES, with clicks, hover, typing and scrolling all working.
  QML modules resolve from the types Qt's libraries register, so no QML
  plugins or qmldir files are installed. Lessons: the platform plugin must
  report `RhiBasedRendering` (or Qt Quick falls back to software), use
  `QUnixEventDispatcherQPA` (or input never reaches Qt), and bundle
  `Qt6AndroidQuick.jar` (libQt6Quick registers natives on load). Qt's 16 ms
  animation timer capped QML at 60 fps; the demo ticks it every 8 ms.
- Pacing that got there: the compositor queues up to two commits per app and
  shows one per refresh, so each app has a frame of slack (protocol.h, FRAME).
- Qt for Android calls into Java throughout QtCore (app version,
  QStandardPaths during QCoreApplication's constructor, OS version, time
  zones). Without a Java VM every one of those crashes, so Qt apps run in an
  app_process with Qt6Android.jar (`QtHost.kt`). There is no Activity, so Qt
  has no Android Context. A native Plasma would either keep this host process
  per app or patch those calls out of a Qt built from source.

## What to look for in stage 1

- Both test windows at the panel's refresh rate (120 Hz on the Pixel 10 Pro)
  while dragging windows.
- Compositor CPU time per frame well under 1 ms.
- The heavy app (1024 spinning squares) not slowing down the light one.
