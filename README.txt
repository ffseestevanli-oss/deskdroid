===============================================================================
                                   DESKDROID
                  Your computer in your pocket: KDE Plasma on Android
===============================================================================

Last updated: 2026-10-26 (APK build 77 era)
License: GPL-3.0 (free and open source)
Source: https://github.com/ffseestevanli-oss/deskdroid


-------------------------------------------------------------------------------
CONTENTS
-------------------------------------------------------------------------------

  1.  What DeskDroid is
  2.  Download and install
  3.  First-time setup (step by step)
  4.  Editions: Full, Light, Ultra-lite
  5.  Using the desktop
  6.  Features in detail
        6.1  Splash screen
        6.2  Touch, keyboard, mouse and the side drawer
        6.3  External monitors
        6.4  Graphics: software, Venus GPU, Turnip
        6.5  Plasma Wayland session (experimental)
        6.6  Apps: Discover, Flathub and apt
        6.7  Phone files and the Linux home folder
        6.8  Web browsers
        6.9  Steam and x86 apps (FEX-Emu)
        6.10 Lock screen and "Lock my desktop"
        6.11 Start on phone boot
        6.12 Sound and clipboard
  7.  Settings reference
  8.  Architecture (how it works)
  9.  What the Linux terminal can and can't do
  10. Known issues and current status
  11. Troubleshooting
  12. Logs: where to find them and what to send
  13. Building from source
  14. Roadmap
  15. Licensing and credits


===============================================================================
1. WHAT DESKDROID IS
===============================================================================

DeskDroid is one Android app that installs and runs a full KDE Plasma 6
desktop (Debian 13 "trixie", arm64) on an ordinary, NON-ROOTED Android phone.
Install the APK, pick an edition, tap "Start desktop", and you get a real
Linux desktop:

  * KDE Plasma with Dolphin, Konsole, Kate, System Settings and Discover.
  * Native ARM64 Linux software, installed with apt or from Flathub.
  * x86 Linux programs through FEX-Emu, and Steam through Valve's native ARM64
    client. Box64 + Wine for Windows apps is planned (see Roadmap).
  * External monitors over USB-C, Bluetooth/USB keyboard and mouse, sound and
    a shared clipboard, so the phone works like a real computer.
  * Your phone's storage shows up on the desktop like a USB drive, while the
    Linux home folder stays separate.

It needs no root, no Termux and no second app: the X server (from Termux:X11),
proot and every other native piece are built into the APK.

Primary test device: Google Pixel 10 Pro (Tensor G5, PowerVR GPU, Android 16+
with USB-C display output). Other phones should work but are less tested.

Requirements:
  * Android 10 or newer (API 29). Android 14 or newer is recommended, because
    it has a switch for the "child process" limit (see section 3).
  * 64-bit ARM (arm64) phone.
  * Free storage: about 2 GB (Ultra-lite) to 10-12 GB (Full), more for Steam
    and games.
  * Memory: an idle Plasma desktop uses roughly 1-1.5 GB of RAM.
  * Wi-Fi recommended for the first download.


===============================================================================
2. DOWNLOAD AND INSTALL
===============================================================================

DeskDroid is distributed through GitHub Releases (and later F-Droid). It is
NOT on Google Play.

Newest APK (always the latest build of the main branch):

  https://github.com/ffseestevanli-oss/deskdroid/releases/tag/apk-latest

The release holds a single file named deskdroid-build-NN.apk, where NN is the
build number (for example deskdroid-build-77.apk). Only the newest build is
kept on the release, so older direct links stop working; use the release page
above to always get the current one.

To install:
  1. Open the link on the phone and download the .apk file.
  2. Tap it. If Android asks, allow your browser or Files app to "install
     unknown apps".
  3. Open DeskDroid and follow the setup (section 3).

To update: install the newer APK over the old one. Your Linux system and home
folder are kept. Many fixes (splash screen, Steam scripts, storage, lock
screen, Flathub) are applied by the app at every desktop start, so they reach
an existing install with just an app update. Some changes (for example the
Wayland packages) need a fresh system image: Settings > Reinstall the system.

System images (the Linux part) are downloaded by the app from the
"rootfs-latest" release; you normally never touch them by hand.


===============================================================================
3. FIRST-TIME SETUP (STEP BY STEP)
===============================================================================

Welcome
  "Welcome to DeskDroid!" > tap "Let's go".

Step 1 / 3: Pick your loadout
  Choose Full (recommended) or Light. Tap "...or there's this" to reveal
  Ultra-lite. The screen shows the download size and free space. There is also
  "Install from a file instead" for a .tar.zst image you built or trust (these
  can't be checked for tampering).

Step 2 / 3: Install
  The progress ring moves through:
    Download    resumes by itself if the connection drops or the app is closed
    Verify      checks the image's minisign signature (that it's genuine)
    Unpack      sets up Debian and Plasma
    Create your account   uses your phone's language and time zone
  A notification shows progress with a Cancel button and says "Your desktop is
  ready" when done. You can leave the app while it runs.

Step 3 / 3: "Don't let Android kill the party"
  A desktop runs many programs, which Android normally stops. Fix these once:

  * Child process limit
      Android 14+: tap "Open Developer options" and turn on
        "Disable child process restrictions".
        (If Developer options are hidden: Settings > About phone, tap
        "Build number" 7 times.)
      Android 12-13: there is no switch. Tap "Copy the fix command" and run
        that ADB command once from a computer.
      Android 10-11: not needed.
  * Background + notifications: turn battery optimization off for DeskDroid
    and allow its status notification.
  * Share files with the desktop: grants "All files access" so your phone's
    storage appears on the desktop as a drive called Phone.
  * Optional: "Start on phone boot" and "Lock my desktop".

Then you land on the Home screen: choose "Play on: This phone / Monitor" and
tap START DESKTOP.


===============================================================================
4. EDITIONS
===============================================================================

  Edition      Desktop      What's included                        Approx. size
  -----------  -----------  -------------------------------------  ------------
  Full         KDE Plasma   Light + Floorp browser, LibreOffice     ~3.5 GB dl
  (recommended)             (Writer, Calc, Impress), GIMP, VLC,     ~10-12 GB
                            Okular, Gwenview, Steam menu entry      on disk
  Light        KDE Plasma   Desktop only: Dolphin, Konsole, Kate,   ~1.2 GB dl
                            Ark, System Settings, Discover +        ~4 GB disk
                            Flathub. Add everything else yourself.
  Ultra-lite   MATE         Caja, MATE Terminal, Pluma, Eye of      ~0.6 GB dl
                            MATE, Atril, Engrampa, Floorp. ARM      ~2 GB disk
                            apps only, no x86/Steam, X11 only.
                            For older or low-storage phones.

Sizes are estimates. Light has no web browser by default; get one from
Discover. Steam and FEX are available on Light and Full only.


===============================================================================
5. USING THE DESKTOP
===============================================================================

* Start: Home > START DESKTOP. While Linux boots you see DeskDroid's splash
  screen; the desktop appears once Plasma's panel is up.
* Re-open: if the desktop is already running the button says OPEN DESKTOP, or
  tap the DeskDroid notification.
* Side drawer (CONTROLS): swipe in or tap the handle on the right edge. It has
  Touchpad / Direct touch, Keyboard, Extra keys, Zoom, To monitor / To phone,
  and STOP DESKTOP.
* Stop: drawer > STOP DESKTOP ("Unsaved work in Linux apps will be lost").
* Administrator: the Linux user is "deskdroid" with passwordless sudo, so
  `sudo apt install ...` works in Konsole without a password.


===============================================================================
6. FEATURES IN DETAIL
===============================================================================

6.1 Splash screen
-----------------
The desktop window shows a DeskDroid splash screen until the desktop shell
(plasmashell, or mate-panel on Ultra-lite) is running, then a few seconds
more so it can draw. Plasma's own splash is turned off. A "Show the desktop
now" link appears if you want to skip it. If no shell shows up within 3
minutes, the splash hides anyway and the log says so.
(Files: Splash.kt, assets/linux/deskdroid-splash, ready flag
/tmp/deskdroid/ready inside Linux.)

6.2 Touch, keyboard, mouse and the side drawer
----------------------------------------------
* Touchpad mode (default): the screen is a trackpad. Tap = click, two-finger
  tap = right click, two-finger drag = scroll, tap and hold = drag.
* Direct touch mode: your finger is the pointer.
* Keyboard: opens Android's keyboard. Extra keys: Esc, Tab, Ctrl, Alt, Meta,
  arrows and F-keys.
* Zoom: enlarges the desktop for small text.
* Bluetooth and USB keyboards and mice work directly.
* Desktop scale (Settings) sets Plasma's scale for the next start; it is
  picked from the screen density by default.

6.3 External monitors
---------------------
Plug a monitor into USB-C (the Pixel 10 Pro has display output). Choose
"Play on: Monitor" on Home, or use "To monitor" in the drawer to move a
running desktop to the monitor and "To phone" to bring it back. The desktop
uses the monitor's native resolution at any aspect ratio (16:9, 21:9, 32:9,
portrait...). Home shows "Monitor connected - W x H" or "No monitor
connected. Plug one in with USB-C."
Today it runs full screen on the monitor. Phone-as-touchpad while on the
monitor and DeX/Android-desktop-mode freeform windows are coming next.

6.4 Graphics: software, Venus GPU, Turnip
-----------------------------------------
Settings > Graphics:
  Automatic                     Turnip on Adreno phones, software elsewhere.
  GPU via Venus (experimental)  Linux apps' Vulkan is forwarded to Android's
                                own GPU driver (Mesa's Venus driver talks to a
                                Venus server built into the APK, over
                                /tmp/.virgl_test). OpenGL apps go through Zink
                                (OpenGL on Vulkan). Meant for Mali and PowerVR
                                (Pixel) GPUs.
  Software (llvmpipe)           CPU rendering. Most reliable.
  Software, effects off         Fastest software option.
  Adreno (Turnip + Zink)        Snapdragon phones.

Venus options:
  * Venus GPU memory: Automatic / dma-buf / AHardwareBuffer. Automatic asks
    the driver. If apps crash or draw garbage, try the other mode.
  * Desktop effects on the GPU: off by default, so KWin and the Plasma panel
    stay on software rendering and a GPU problem can't leave the desktop
    black. Apps get the GPU either way.
  * Before the desktop starts, the app checks that the Venus device answers
    (vulkaninfo, 20 s). If not, the session falls back to software and the
    log shows "[venus-test]" lines explaining why.
  * Settings > GPU report shows your GPU, drivers and the Vulkan extensions
    Venus needs. Share it when reporting graphics problems.

Check from Konsole:
  vulkaninfo --summary   expect "Virtio-GPU Venus (...)"
  glxinfo -B             expect "zink Vulkan 1.x (Virtio-GPU Venus ...)"
  If either shows llvmpipe, you are on software rendering.

History: an earlier virgl approach crashed KWin on the Pixel 10 Pro and was
replaced by Venus on 2026-10-23.

6.5 Plasma Wayland session (experimental)
-----------------------------------------
Settings > Desktop session > "Wayland (experimental)" runs Plasma's Wayland
session (KWin nested inside the built-in X server) instead of Plasma X11. X11
apps run through Xwayland. KWin draws in software (QPainter); apps follow the
Graphics setting. Rotation and monitor changes resize the desktop within
about a second, and the panel and maximized windows re-layout after a resize
or zoom. Images built before Wayland support lack the packages: the log says
"missing (reinstall the system for Wayland)" and X11 starts instead. Use
Settings > Reinstall the system to get them. Ultra-lite (MATE) is X11 only.
This matters long-term because Plasma 6.8+ drops the X11 session.

6.6 Apps: Discover, Flathub and apt
-----------------------------------
* Discover is the app store. Flathub (Flatpak) is the DEFAULT source, added
  per-user (flatpak --user) by the app at every start, so no admin password
  is needed. Debian packages (apt, through PackageKit) are available too.
* Many Flathub apps have arm64 builds. Flatpak's sandbox can't run without
  root on Android, so apps run unsandboxed (DeskDroid itself is still
  isolated from Android by the app sandbox).
* Terminal: `sudo apt update && sudo apt install <package>` in Konsole.
* Reinstalling the system keeps your home folder but removes apps you
  installed with apt.

6.7 Phone files and the Linux home folder
-----------------------------------------
With "All files access" granted (setup step 3, or Home > Phone files):
  * Your phone's shared storage appears like a USB drive at
      /media/deskdroid/Phone        (also at /sdcard)
  * Dolphin's sidebar (Places) lists: Home, Desktop, Documents, Downloads,
    Music, Pictures, Videos, then Phone and Camera (Camera = DCIM/Camera).
  * Files saved to Phone show up in Android's Files app, and photos taken on
    the phone show up in Camera.
  * Phone files are presented to Linux as owned by your desktop user, so
    Dolphin can copy, rename and delete them. Android still decides what is
    really allowed.
  * Android's own "Android/" folder is hidden; turn on "Show hidden files" in
    Dolphin to see it.

The Linux home folder (/home/deskdroid) is SEPARATE and Linux-only: a file in
~/Downloads on the desktop does NOT appear on Android. Copy files to Phone to
share them. Without the permission the desktop still starts, just without the
Phone drive. The home folder lives in the app's private storage and is kept
across app updates and system reinstalls (it's deleted if you uninstall the
app and choose not to keep its data).

6.8 Web browsers
----------------
* Floorp (a Firefox-based browser) is the default browser on Full and
  Ultra-lite. It's installed from Floorp's own arm64 builds and updated with
  new DeskDroid images (its own updater is off).
* Firefox/Floorp: their sandbox is off (it can't work under proot), and
  proot routes their shared memory through /dev/shm so tabs don't crash.
* Chromium-based browsers (Chromium, Chrome, Brave, Vivaldi, Edge) get
  --no-sandbox automatically.

6.9 Steam and x86 apps (FEX-Emu)
--------------------------------
Steam (Light and Full) is in the app menu under Games.
  * It runs Valve's NATIVE ARM64 Steam client, not the x86 one.
  * First click opens a "Setting up Steam" Konsole window that installs the
    libraries Steam needs and Valve's ARM64 client seed into
    ~/.local/share/Steam. Steam then downloads the rest of itself (~1.5 GB)
    and shows Valve's license and login.
  * Extra Steam arguments: ~/.config/deskdroid-steam-args
  * Steam log: ~/.local/share/deskdroid-steam/steam.log
  * Steam's own logs: ~/.local/share/Steam/logs/
  * Big Picture mode is available as a menu entry action and may be lighter.

x86 Linux programs run through FEX-Emu with the `deskdroid-fex` command:
  deskdroid-fex ./game.x86_64
  deskdroid-fex /bin/bash          (an x86 shell)
  deskdroid-fex /bin/uname -m      (prints x86_64 when it works)
The first use downloads FEX (from the "fex-latest" release) and FEX's
Ubuntu 24.04 x86 system into ~/.fex-emu (about 3 GB; ~5 GB during setup).

6.10 Lock screen and "Lock my desktop"
--------------------------------------
* Plasma's own lock screen is OFF by default, and forced off while the
  deskdroid user has no Linux password (it would have nothing to unlock
  with). If you set a password with `passwd`, you can turn it on again in
  System Settings.
* Instead, the app's "Lock my desktop" option asks for your fingerprint,
  face or phone PIN before DeskDroid or the desktop opens.
* App data is already encrypted by Android's file-based encryption.

6.11 Start on phone boot
------------------------
Optional. After the phone restarts and you unlock it, the desktop starts in
the background; the notification says it's running and tapping it opens it.
Uses some battery and about 1 GB of memory. Needs unrestricted battery and
the child-process fix, and the app must have been opened once after install.

6.12 Sound and clipboard
------------------------
Sound: Linux apps play through PulseAudio, which the app plays on Android.
Expect a small delay. Clipboard: copy on Android and paste in Linux apps,
and back.


===============================================================================
7. SETTINGS REFERENCE (gear icon on the Home screen)
===============================================================================

  Touch mode              Touchpad / Direct touch
  Desktop scale           Plasma scale, applies at next start
  Desktop session         Plasma X11 / Wayland (experimental)
  Graphics                Automatic / GPU via Venus / Software (llvmpipe) /
                          Software, effects off / Adreno (Turnip + Zink)
  Venus GPU memory        Automatic / dma-buf / AHardwareBuffer
  Desktop effects on GPU  Venus only; off keeps KWin on software
  GPU report              GPU and driver details, with Share/Copy
  Start on phone boot     on/off
  Lock my desktop         on/off (fingerprint, face or PIN)
  Phone files             All files access, Phone drive info
  Background limits       re-opens the "Don't let Android kill" checks
  Reinstall the system    fresh image; home folder kept, apt apps removed
  Save log to Downloads   writes Downloads/deskdroid-log-YYYYMMDD-HHMMSS.txt
  (bottom)                DeskDroid version and build


===============================================================================
8. ARCHITECTURE (HOW IT WORKS)
===============================================================================

  +---------------------------- DeskDroid APK -----------------------------+
  | Kotlin app: setup/installer, Home and Settings, session service,       |
  |   desktop window with splash and side drawer, display handling        |
  | Built-in X server (Termux:X11's "lorie", compiled into the APK)        |
  | Native tools (built from source with the NDK, shipped as lib*.so):    |
  |   proot + talloc, ddtool (zstd + minisign), gpureport, Venus server   |
  +-----------------------------------------------------------------------+
            | proot (binds X/sound sockets, /sdcard, /tmp)
  +--------------------------- Debian rootfs ------------------------------+
  | deskdroid-boot (fake root: system D-Bus, then drops to user deskdroid) |
  |   -> deskdroid-session -> startplasma-x11 or startplasma-wayland       |
  | KDE Plasma 6, Discover + Flatpak, Mesa (Venus, Zink, Turnip, llvmpipe) |
  | Steam (ARM64 client), FEX-Emu on demand                                |
  +-----------------------------------------------------------------------+

Key decisions:
  * proot (user-space, ptrace) instead of chroot: works without root.
  * Debian 13 trixie arm64: official port, stable, Plasma 6 packaged.
  * Display: built-in Termux:X11 X server now; a DeskDroid Wayland host later.
  * Native binaries live in the APK's nativeLibraryDir because Android 10+
    won't run programs from app data (W^X).
  * The system lives in a plain folder in app-private storage
    (/data/data/io.deskdroid.app/files/rootfs), not an image file, so it
    grows and shrinks with what you install.
  * No prebuilt binaries in the APK (F-Droid rule): everything is compiled
    from source in the Gradle build or in CI.

Boot sequence when you tap Start:
  1. Session foreground service starts (with its notification).
  2. App writes its helper scripts into the rootfs (splash watcher, Steam,
     FEX, Flatpak setup, browser flags, Places, lock screen setting).
  3. X server starts; the desktop window opens with the splash screen.
  4. Optional Venus server and self-test.
  5. proot runs deskdroid-boot: system D-Bus, PulseAudio, then Plasma.
  6. Splash hides once the panel is up.

Install sequence:
  The app reads deskdroid-images.json from the rootfs-latest release,
  downloads the edition (resumable, in parts if over 2 GB), verifies its
  minisign signature, unpacks it (zstd + tar), and creates the account.

Source layout:
  app/                     Android app (Kotlin)
  external/termux-x11/     Termux:X11 (git submodule), X server built in
  native/                  proot, talloc, ddtool, gpureport, Venus build
  rootfs/                  Debian image build (mmdebstrap), package lists,
                           overlay files (deskdroid-boot, -session, wallpaper)
  fex/                     FEX-Emu build for the fex-latest release
  docs/                    plan.md and device test checklists
  .github/workflows/       CI: Android APK, Rootfs images, FEX-Emu

Releases:
  apk-latest      newest APK from main (deskdroid-build-NN.apk)
  rootfs-latest   signed system images + deskdroid-images.json
  fex-latest      FEX-Emu build for Debian trixie arm64


===============================================================================
9. WHAT THE LINUX TERMINAL CAN AND CAN'T DO
===============================================================================

Works: apt and sudo, compilers, git, Python, Node, SSH client, networking,
editing system files, Flatpak apps.

Doesn't work (Android without root doesn't allow it): systemd / systemctl,
mount, kernel modules, Docker/Podman, KVM/virtual machines, iptables,
listening on ports below 1024, raw sockets, direct hardware access, user
namespaces (bubblewrap sandboxes).

Slower than native: syscall-heavy work such as big builds and package
installs, because proot intercepts every system call.


===============================================================================
10. KNOWN ISSUES AND CURRENT STATUS (as of 2026-10-26)
===============================================================================

Project status: Phase 1 ("Tap to desktop") is built and being tested on a
Pixel 10 Pro. These are debug builds.

Working on the Pixel 10 Pro:
  * Install, Plasma desktop, splash screen, touch, keyboard, Discover.
  * Plasma Wayland session (llvmpipe and Venus), including rotation.

Open issues:
  * Steam: the ARM64 client now installs, updates and stays running (proot
    fixes in PR #28). It then shows "Unexpected Transport Error": its web UI
    (steamwebhelper) fails to start. Being investigated; the next step needs
    the files in ~/.local/share/Steam/logs/.
  * Steam games in Steam's container (Proton and newer native games) need
    bubblewrap / user namespaces. A bwrap stand-in is planned; until then
    they are expected to fail.
  * FEX: Android kernels often have a 39-bit address space while FEX
    expects 48-bit, so some 64-bit x86 programs may fail to map memory. No
    FEX thunks yet, so x86 games use emulated (slower) graphics drivers.
  * Venus GPU: on build 31 the desktop went black after the splash. Since
    then the panel and KWin stay on software rendering and a self-test falls
    back to software. Still waiting for a device log to confirm the cause.
    Use Software (llvmpipe) if you see a black screen.
  * Floorp tabs crashing: fixed in proot (shared memory through /dev/shm,
    build 49+). Not yet confirmed on the phone.
  * Phone drive: the ownership fix (PR #27) should make Phone read-write in
    Dolphin; waiting for confirmation on the phone.
  * Wayland: KWin draws in software with one extra copy per frame, so it is
    slower than X11. Old images lack the Wayland packages (reinstall).
  * External monitor: full screen only; no phone-touchpad mode or DeX-style
    freeform windows yet. Multi-monitor isn't supported.
  * Box64 + Wine (Windows apps) are not in the images yet (Phase 3), even
    though the Full card mentions them.
  * Android 12-13 need a one-time ADB command for the child process limit;
    a one-tap fix over Wireless debugging is planned.
  * Turnip (Adreno) Mesa build isn't finished.
  * Gamepads aren't bridged yet (Phase 4).
  * Anti-cheat games are unsupported.


===============================================================================
11. TROUBLESHOOTING
===============================================================================

The desktop closes or dies after a while
  - Setup step 3 / Settings > Background limits: turn on "Disable child
    process restrictions" (Android 14+) or run the copied ADB command
    (Android 12-13), and turn battery optimization off.
  - Allow the notification; the session runs as a foreground service.

Black screen after the splash
  - Settings > Graphics > Software (llvmpipe) and start again.
  - If you were using Venus, keep "Desktop effects on the GPU" off, or try
    the other Venus GPU memory mode.
  - Save the log (section 12) and look for [venus], [venus-test] and
    [session] lines.

Splash never goes away
  - After 3 minutes it hides by itself; or tap "Show the desktop now".
  - Save the log; the shell (plasmashell) probably didn't start.

Apps crash or draw garbage with Venus
  - Settings > Venus GPU memory: switch between dma-buf and AHardwareBuffer.
  - Settings > GPU report > Share, and include it with the log.

No Phone drive in Dolphin / Phone looks empty or read-only
  - Home > Phone files, or setup step 3: allow All files access.
  - Install the newest APK (ownership fix).
  - The log line "storage check: ... writable" shows whether it works.
  - The Android/ folder is hidden: Dolphin > Show hidden files.

My file isn't on Android
  - The Linux home folder is separate. Save or copy it into Phone.

Wayland option does nothing / starts X11
  - Log says "missing (reinstall the system for Wayland)": use Settings >
    Reinstall the system, then pick Wayland again.

Desktop doesn't fit after rotating (Wayland)
  - It should resize within a second; check the log for
    "deskdroid-kwin-wayland: screen W H ..." lines.

Browser tabs crash
  - Update to the newest APK (build 49 or later).

Steam doesn't start / exits
  - Check ~/.local/share/deskdroid-steam/steam.log and
    ~/.local/share/Steam/logs/ (webhelper.txt, cef_log.txt,
    console_log.txt). To zip them:
      cd ~/.local/share/Steam && zip -r ~/steam-logs.zip logs
    then copy steam-logs.zip into Phone to share it.

Discover can't install
  - Try in Konsole: sudo apt update. Flathub is the default source; Debian
    packages need the system D-Bus, which deskdroid-boot starts.

Something else
  - Settings > Reinstall the system gives a fresh image (home kept).
  - Save the log and report it with your phone model and Android version.


===============================================================================
12. LOGS: WHERE TO FIND THEM AND WHAT TO SEND
===============================================================================

App / session log (most important)
  * Settings > "Save log to Downloads". It is saved on the phone as
      Downloads/deskdroid-log-YYYYMMDD-HHMMSS.txt
    with the app version, Android version and phone model at the top. Attach
    that file anywhere (chat, email, issue).
  * Internally: /data/data/io.deskdroid.app/files/session.log (up to 2000
    lines). It survives the app being killed or restarted: after a crash or
    black screen, reopen DeskDroid and save the log; lines from before the
    restart are marked "== Log from before the app last restarted ==".
  * Useful prefixes: [session], [venus], [venus-test], deskdroid-session:,
    deskdroid-kwin-wayland:, deskdroid-splash:, storage check:.

GPU report
  * Settings > GPU report > Share or Copy.

Steam
  * ~/.local/share/deskdroid-steam/steam.log
  * ~/.local/share/Steam/logs/

FEX x86 system
  * ~/.fex-emu/

Android-side logs (with a computer and ADB)
  adb logcat -s DeskDroid LorieNative CmdEntryPoint

Advanced: PROOT_SYSVIPC_LOG=1 makes proot log the semaphore and robust-list
calls it emulates (Steam debugging).


===============================================================================
13. BUILDING FROM SOURCE
===============================================================================

  git clone --recurse-submodules https://github.com/ffseestevanli-oss/deskdroid
  # or in an existing clone: git submodule update --init --recursive

Needs JDK 17, the Android SDK, the NDK version pinned in
app/build.gradle.kts, python3 and bison (for the X server), and meson,
ninja and pkg-config (for the Venus server). Then:

  ./gradlew assembleDebug

CI does the same on every push (Actions > Android APK); builds of main are
published to the apk-latest release.

System images: Actions > Rootfs images > Run workflow. Publishes all three
editions to rootfs-latest. Locally: rootfs/build-rootfs.sh (mmdebstrap on
arm64).

FEX-Emu: Actions > FEX-Emu (fex/build.sh) publishes fex-latest.

Image signing (minisign):
  1. minisign -G -W -p deskdroid.pub -s deskdroid.key
  2. Repo secret MINISIGN_SECRET_KEY = contents of deskdroid.key
  3. Repo variable MINISIGN_PUBLIC_KEY = second line of deskdroid.pub
     (local builds: deskdroidImagePublicKey in gradle.properties)
  Debug builds without a key fall back to a SHA-256 check.

App details: package io.deskdroid.app, minSdk 29, targetSdk 35.


===============================================================================
14. ROADMAP
===============================================================================

Phase 1 - Tap to desktop (now): installer, Plasma on the phone, touch,
  keyboard/mouse, sound, clipboard, GPU (Venus/Turnip/software), splash,
  Flathub, phone files, Steam groundwork. Goal: a non-technical tester gets
  a working desktop in under 10 minutes with no terminal.
Phase 2 - Real computer mode: external display modes (full screen, DeX-style
  windows), phone as touchpad, pointer capture, open-in-Android and
  notifications, backup/restore of /home, A/B system images with rollback,
  and a DeskDroid Wayland host replacing the X server.
Phase 3 - Windows and x86 apps: Box64 + Wine preinstalled, .exe double-click
  in Dolphin, Wine prefix manager, FEX thunks, Steam games via a bwrap
  stand-in, Proton, Lutris.
Phase 4 - Gaming and peripherals: gamepad bridge, on-screen controls,
  per-game profiles, performance work on Mali/PowerVR.
Phase 5 - Distribution and polish: GitHub Releases + Obtainium, DeskDroid's
  own F-Droid repo, then the main F-Droid repo; delta updates; docs site.

Full plan: docs/plan.md. Device test checklists: docs/*-checklist.md.


===============================================================================
15. LICENSING AND CREDITS
===============================================================================

DeskDroid is licensed under GPL-3.0. It includes or builds on:
  Termux:X11 (GPL-3.0), proot (GPL-2.0-or-later, Termux fork), talloc
  (LGPL-3.0+), zstd (BSD-3-Clause), Monocypher (BSD-2/CC0), virglrenderer
  and libepoxy (MIT) with Termux's Android patches, FEX-Emu (MIT), Debian
  and KDE Plasma packages (mostly GPL/LGPL/MIT), Floorp, and Chakra Petch
  and Orbitron fonts (OFL). Steam fixes for proot are adapted from
  steamclienttermux (GPL-2.0-or-later).

Steam is Valve's proprietary software: DeskDroid only downloads Valve's
client seed, and you accept Valve's license in Steam itself. Windows
components and Microsoft fonts are never bundled. "KDE", "Debian" and
"Termux" are trademarks of their owners; DeskDroid is an independent
project, powered by KDE Plasma.

===============================================================================
