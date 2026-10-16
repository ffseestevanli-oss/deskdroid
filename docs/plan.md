# DeskDroid: Architecture and Roadmap

_Draft 1 · 2026-10-16_

**Vision.** Turn Android phones from toys into real computers, limitations be damned. Every non-root limit below is an engineering problem with a planned way through it, not a reason to scale back.

**Goal.** One Android app, for non-rooted devices, that installs and launches a full KDE Plasma desktop with zero manual setup. Install the APK, tap "Start", get a desktop. It runs Linux ARM64 software natively, x86/x86_64 Linux and Windows software through Box64 + Wine, and works with external displays, keyboard, mouse and gamepads like a real computer.

**Not in scope yet.** Requiring root for anything, replacing the Android launcher, running Android apps inside Plasma. Where root would normally be needed (chroot, KVM, DRM/KMS, uinput), we build a user-space path instead.

---

## 1. Key decisions

| Decision | Choice | Why |
|---|---|---|
| Device requirement | Non-root only | Rooted devices are rare; painless install is the product. |
| Container | **proot** (ptrace-based, user space) | The only general way to run a full glibc distro without root. |
| Distro | **Debian 13 "trixie" arm64** | Official arm64 port, stable base, Plasma 6.3 packaged, huge package set, Box64/Wine/Mesa well tested on it by the Termux and Winlator communities. Arch Linux ARM is unofficial, rolling (breaks a prebuilt image often), and harder to ship as a pinned, reproducible rootfs. |
| Display server | **Termux:X11**, embedded in our APK | Mature, fast X server for Android (renders into an Android Surface, supports pointer capture, IME, DeX, secondary displays). |
| Desktop session | Plasma 6 **X11 session** for MVP | Works inside Termux:X11 today. See section 6 for the Wayland-only Plasma risk. |
| GPU (Adreno) | **Turnip** (Mesa Vulkan) via `/dev/kgsl`, **Zink** for OpenGL | `/dev/kgsl` is reachable from unprivileged apps; this is how Winlator/Mobox get real GPU speed. |
| GPU (Mali/other) | **llvmpipe** at first, then a Vulkan forwarding layer (Vortek-style) or virgl over Android GLES | No unprivileged path to Panfrost/Mali DRM nodes. |
| x86 translation | **Box64** (x86_64) + **Box86**/Box64-WOW64 (32-bit) + **Wine** (WoW64 build) | De facto standard on ARM Linux. |
| Audio | **PulseAudio** server on the Android side with an AAudio sink | Proven in Termux; PipeWire-pulse client inside the rootfs can come later. |
| How we get binaries | Native pieces built with the NDK under **our own package prefix**; rootfs is plain Debian built in CI | Avoids depending on the Termux app or its `com.termux` hardcoded paths. |

---

## 2. Components

```
┌──────────────────────────── DeskDroid APK ────────────────────────────┐
│ Kotlin app                                                            │
│  • Launcher UI (install, start/stop, settings, display picker)        │
│  • Bootstrap/installer service (download, verify, extract rootfs)     │
│  • Session foreground service (owns all child processes)              │
│  • Embedded Termux:X11 activity + X server (libXlorie)                │
│  • Input bridge (keyboard, mouse, touch→pointer, gamepad)             │
│  • Display manager (internal / external / DeX mode)                   │
│ Native (jniLibs, so they are executable under W^X)                    │
│  • libproot.so + loader     • libpulseaudio-server.so (AAudio sink)   │
│  • small helpers (busybox-style tar, virgl/vortek server later)       │
└───────────────────────────────────────────────────────────────────────┘
             │ proot (bind /dev/kgsl, /sdcard, X/pulse sockets)
┌──────────────────────────── Debian rootfs ────────────────────────────┐
│ systemd-less init script → dbus → startplasma-x11                     │
│ KDE Plasma 6, Dolphin, Konsole, Discover (apt), Firefox ESR           │
│ Mesa (Turnip + Zink + llvmpipe), Box64/Box86, Wine (WoW64), DXVK/VKD3D │
│ deskdroid-integration package (clipboard, open-in-Android, notifs)    │
└───────────────────────────────────────────────────────────────────────┘
```

**Reuse vs. build:**
- **Reuse:** Termux:X11 (fork as a module), proot (Termux fork), Box64, Wine, Mesa, DXVK, Debian packages.
- **Build ourselves:** the launcher/installer app, the rootfs build pipeline, the session init scripts, the input/display bridges, the integration package.
- **Study (do not copy blindly):** Winlator (bundling, kgsl/Turnip setup, gamepad shim, Wine prefix management), Mobox, termux-desktop scripts, XoDos, AndroidIDE (how to ship Termux-style userland inside a Play-distributable app).

---

## 3. Bootstrap: how the app gets a desktop on the device

1. **APK install** (~60–120 MB): app, native libs, Termux:X11, PulseAudio, proot.
2. **First launch** shows a single screen: storage needed (~4–6 GB), Wi-Fi recommended, "Install".
3. **Download** a prebuilt, versioned rootfs (`deskdroid-rootfs-<ver>-arm64.tar.zst`, ~1.5–2.5 GB) from a CDN/GitHub Releases, resumable, in a foreground service. Verify SHA-256 and a signature (minisign) before extraction.
4. **Extract** in our own code (zstd + tar), handling hardlinks as copies/symlinks (Android app storage forbids hardlinks in some places; proot's `--link2symlink` covers the rest at runtime). Fix permissions, write `/etc/resolv.conf`, `/etc/hosts`, locale, timezone from Android settings.
5. **Create the user** (`deskdroid` with passwordless sudo, matching UID mapping in proot) and a default Wine prefix lazily on first Windows app launch, not at install.
6. **Start session**: foreground service spawns `libpulseaudio-server.so`, the X server, then `proot … /usr/local/bin/deskdroid-session` which starts dbus, sets `DISPLAY`, `PULSE_SERVER`, `MESA_LOADER_DRIVER_OVERRIDE=zink` / `TU_DEBUG` etc. per device profile, then `startplasma-x11`.
7. **Updates**: app updates via the store; rootfs updates normally via `apt` inside Debian (Discover), plus an occasional "rebase" image from us with migration of `/home`.

**Rootfs build pipeline (CI):** `mmdebstrap` on a native arm64 runner (GitHub has arm64 runners), install a pinned package list, add our apt repo (Box64, our Mesa build if Debian's lags, deskdroid-integration), strip docs/locales, pack with zstd. Reproducible and testable in CI with proot itself.

**Immutable-style base (Bazzite/Silverblue ideas, our own implementation).** Fedora Atomic distros (Silverblue, Kinoite, Bazzite) can't be used directly: rpm-ostree/bootc deploy through the bootloader and kernel, which proot never touches, and Bazzite is x86_64-only. Their Flatpak/Distrobox model also needs user namespaces, which app sandboxes don't get. We copy the model instead:
- `/usr` comes from a versioned, read-only base image we build (proot bind-mounts it read-only). We keep `/etc` (3-way merged on upgrade like ostree), `/var` and `/home` in a separate writable layer.
- Upgrades download the new image next to the old one and switch with one atomic directory rename. If the next boot fails, the launcher rolls back to the previous image automatically, and the user can pick an older image by hand.
- User-installed apt packages go into a writable overlay (proot bind order or a `/opt`+`~/.local` prefix) that gets replayed onto new images, so "install anything" still works.
- Phase 1 ships a plain mutable rootfs. Phase 2 adds A/B images and rollback, Phase 5 adds delta downloads.

**Why prebuilt and not "apt install on device":** on-device install of Plasma takes 20–60 minutes, fails on flaky networks and is the biggest source of pain in today's Termux guides.

---

## 4. Display and input pipeline

**Display path:** X clients in proot → Unix socket (`/tmp/.X11-unix` bound into proot) → embedded Termux:X11 server → Android `Surface` (AHardwareBuffer) → SurfaceFlinger → screen.
GPU apps render with Turnip on `/dev/kgsl`; frames are copied into the X server's buffer (DRI3-less path today, the main performance cost). Later optimization: shared AHardwareBuffer/dmabuf path between Mesa and the X server.

**Phone screen mode (Winlator/GameNative style):**
- Full-screen immersive landscape (portrait allowed; RandR resizes on rotation). Plasma scale 1.5–2x by default.
- Two touch modes, switchable from the overlay: **Touchpad** (relative cursor; tap = click, two-finger tap = right click, two-finger drag = scroll, tap-and-hold = drag) and **Direct touch** (finger is the pointer). Pinch zooms a viewport over the desktop for small text.
- **Overlay drawer** from an edge swipe or a floating button: Android keyboard, extra-keys row (Esc, Tab, Ctrl, Alt, Meta, arrows, F-keys), touch mode, resolution/scale, per-app on-screen gamepad layouts, "move to external display", stop session.

**External displays and DeX-style mode:**
- **Aspect-ratio agnostic:** the X screen is always created at the Android window's exact pixel size via a RandR mode generated on the fly, so 16:9, 16:10, 21:9, 32:9, 4:3 and portrait monitors all get native resolution with no letterboxing. Scale comes from the display's DPI and can be overridden.
- **Hot-plug without restarting:** the X server and Plasma keep running; the X11 activity moves to the new display and the screen resizes live. Unplugging moves the desktop back to the phone.
- **Games at fixed resolutions:** optional per-app render resolution, scaled up to the native screen (fit, integer, or stretch) by the X server, so a 1080p game fills an ultrawide sensibly.
- Detect displays with `DisplayManager`; launch the X11 activity on the chosen display with `ActivityOptions.setLaunchDisplayId()`.
- **Mode A: "Desktop on external display"**: Plasma full screen on the monitor; the phone becomes a touchpad/keyboard (or stays a normal phone).
- **Mode B: "DeX style"**: the X11 activity is a resizable freeform window inside Samsung DeX or Android 16 desktop windowing; Plasma follows the window size (RandR resize).
- Resolution/DPI: set via RandR on window resize; Plasma scale factor picked from display DPI.
- Multi-monitor (phone + external as two Plasma screens) is a stretch goal: needs two Android windows mapped to two RandR outputs on one X server.

**Input:**
- Keyboard: hardware keys mapped to X keycodes (Termux:X11 already does this); capture Meta/Alt-Tab where Android allows (`requestPointerCapture`, `onKeyShortcut` interception, DeX "Meta key passthrough").
- Mouse: pointer capture for relative motion (games), absolute mode for desktop use; right/middle click, scroll wheel, touchpad gestures.
- Touch: phone screen as trackpad when external display is used; direct touch on phone-only mode.
- Gamepads: no `/dev/input` or `uinput` without root. Android `InputDevice` events go into our bridge, which feeds (a) a Wine XInput/DInput shim (Winlator's approach) and (b) for native Linux games, an SDL virtual joystick via a preload library. Phase 4.
- Clipboard and IME: Termux:X11 clipboard sync, Android IME for touch typing.

**Audio:** apps → PulseAudio client in rootfs → socket → PulseAudio server on Android side → AAudio. Microphone input via the same server (needs RECORD_AUDIO permission, asked on first use).

---

## 5. Non-root limits and mitigations

| Limit | Impact | Mitigation |
|---|---|---|
| **Phantom process killer** (Android 12+ kills when an app has >32 child processes, and kills CPU-heavy background children) | Plasma + Wine easily exceed 32 processes; session dies randomly | Android 14+: guide user to Developer options → "Disable child process restrictions" with a one-tap deep link and in-app check. Android 12–13: offer a one-time fix via Wireless debugging (built-in ADB pairing over loopback, like Shizuku/LADB do) to set `settings_enable_monitor_phantom_procs=false`. Also trim the session (no baloo, no akonadi, fewer kded modules). |
| **Battery optimization / OEM killers** | Session killed when screen off or app backgrounded | Foreground service with persistent notification, request ignore-battery-optimizations, per-OEM guidance (dontkillmyapp.com data). |
| **No KVM / no real VM** | Can't run x86 VMs; no Docker | Box64/Wine for x86 apps; document clearly. (Android's AVF "Linux Terminal" VM is not open to third-party apps.) |
| **proot overhead** (ptrace on every syscall) | 10–30% slower syscall-heavy work (compiles, package installs) | Use proot's seccomp acceleration, keep hot paths (rendering, audio) outside ptrace (sockets, shared memory). |
| **No systemd** | Some services expect it | Simple init script with dbus-launch; systemctl shim for common cases. |
| **No DRM/KMS, no Wayland compositor on hardware** | X11 only; no real KWin Wayland | X11 session now; nested `kwin_wayland --x11-display` later (see risks). |
| **W^X: apps targeting API 29+ can't exec files from app data** | Breaks naive "exec binaries from rootfs" for Play-distributed builds | Ship proot and its loader as `lib*.so` in `jniLibs` (executable `nativeLibraryDir`); proot loads rootfs ELF files via its loader (mmap, not execve), as Winlator/AndroidIDE-style apps do. Must validate on Android 15/16 early (Phase 0). |
| **Mali/PowerVR GPUs** | No Turnip | Vulkan forwarding to the Android driver (Vortek-style), with Zink on top for OpenGL. **Pulled into Phase 1** because the primary dev device is a Pixel (Tensor: Mali, PowerVR on G5). llvmpipe as last-resort fallback. |
| **No `/dev/input`, no uinput** | Gamepads/joysticks need a bridge | Userspace bridge (section 4). |
| **Storage** | Rootfs lives in app-private storage (deleted on uninstall) | Bind `/sdcard` (with All Files Access or SAF) as `~/Android`; backup/export of `/home` built in. |
| **OEM breakage** (e.g. reports of Termux breaking on ColorOS/OxygenOS 15) | Some vendors restrict exec/ptrace | Device test matrix; known-issues list per OEM. |

---

## 6. Biggest risks

1. **KDE is moving to Wayland-only Plasma** (announced for Plasma 6.8). Debian trixie's Plasma 6.3 has the X11 session, which covers us for the life of trixie. Long-term path: run `kwin_wayland` nested on the X11 backend inside Termux:X11, with Xwayland for X apps. Prototype this in Phase 2 so we are not surprised.
2. **Play Store policy.** Downloading executable code, W^X, and "all files access" can block Play listing. Plan for GitHub Releases + F-Droid/Obtainium first, Play second.
3. **Performance expectations.** Plasma + Firefox is fine on recent Snapdragons; Windows games depend heavily on Turnip versions and device. Ship per-device profiles and set expectations clearly.
4. **Maintenance load** of forks (Termux:X11, proot, Mesa). Keep forks thin and upstream fixes.

---

## 7. Licensing when bundling

| Component | License | What it means for us |
|---|---|---|
| Termux:X11 | GPL-3.0 | Embedding it makes the APK a combined GPLv3 work. **Simplest: license DeskDroid GPL-3.0** and publish all source. |
| Termux app code (if reused) | GPL-3.0 (some parts Apache-2.0) | Same as above. |
| proot | GPL-2.0-or-later | Compatible with GPLv3 distribution; provide source. |
| PulseAudio | LGPL-2.1 | Fine; provide source/relinking ability. |
| Box64 / Box86 | MIT | No issue; keep notice. |
| Wine | LGPL-2.1 | Ship source offer for our builds. |
| Mesa (Turnip, Zink) | MIT | No issue. |
| DXVK / VKD3D-Proton | zlib / LGPL-2.1 | Fine. |
| KDE Plasma, Debian packages | Mostly GPL/LGPL/MIT | Distributing a rootfs image means we distribute those binaries: must provide corresponding source (point to Debian's archive snapshot for unmodified packages; host source for anything we patch). |
| Winlator | Check before copying code | Treat as reference; if we reuse code, check its license file and keep notices. |
| Microsoft fonts/DLLs, Windows components | Proprietary | **Never bundle.** Offer optional user-initiated install (e.g. winetricks) with the user accepting the EULA. |
| "KDE", "Debian", "Termux" names/logos | Trademarks | Don't use their logos as our branding; "powered by KDE Plasma" wording is fine. |

**Recommendation:** make DeskDroid fully open source under GPL-3.0 from day one. It matches the components, earns community trust, and avoids any proprietary-bundling problems.

---

## 8. Phased roadmap (MVP first)

### Phase 0: Feasibility spike
- Minimal app: embedded Termux:X11 + proot from `jniLibs` + a stock Debian arm64 rootfs, targetSdk current.
- Prove: exec works under W^X on Android 14/15/16, Xfce-or-Plasma starts, Turnip on `/dev/kgsl` runs `vkcube`, audio plays.
- Test on 3 devices: Steven's Pixel 10 Pro (primary dev device, PowerVR), a Snapdragon flagship, one other Mali/MediaTek.
- Prove Vulkan forwarding on the Pixel renders a composited Plasma desktop smoothly.
- **Exit:** a written go/no-go on the architecture above.

### Phase 1: MVP "Tap to desktop"
- Installer flow (download, verify, extract, progress, resume).
- CI-built Debian + Plasma rootfs.
- Session service, phantom-process check and fix flow, battery-optimization prompt.
- Plasma on the phone screen with touch, Bluetooth/USB keyboard and mouse, audio, clipboard.
- Vulkan forwarding + Zink on Pixel/Mali/PowerVR, Turnip+Zink on Adreno, llvmpipe fallback.
- Phone screen mode with touchpad/direct-touch and the overlay drawer.
- **Exit:** a non-technical tester gets to a working Plasma desktop in under 10 minutes with no terminal.

### Phase 2: Real computer mode
- External display support, Mode A and Mode B (DeX / Android desktop windowing), auto resolution and scaling.
- Pointer capture toggle, Meta/Alt-Tab capture, phone-as-touchpad.
- Shared storage (`~/Android`), "open with Android app" and Android notifications from Linux.
- Backup/restore of `/home`; immutable A/B base images with automatic rollback (section 3).
- Nested KWin Wayland prototype.

### Phase 3: Windows and x86 apps
- Box64/Box86 + Wine WoW64 preinstalled, `.exe` double-click in Dolphin "just works".
- Wine prefix manager (per-app prefixes, DXVK/VKD3D/WineD3D choice), device performance profiles.
- x86_64 Linux apps via Box64 binfmt-style wrapper (no binfmt_misc without root, so a launcher shim).

### Phase 4: Gaming and peripherals
- Gamepad bridge (Wine XInput + SDL virtual joystick), on-screen controls for touch-only use.
- Per-game profiles, FPS overlay, Turnip version picker.
- Forwarding-path performance work for games on Mali/PowerVR.

### Phase 5: Distribution and polish
- Releases on GitHub + F-Droid/Obtainium; evaluate Play Store.
- Delta rootfs updates, crash reporting (opt-in), OEM known-issues list, docs site.
- Optional: second distro image (Arch) if users ask.

---

## 9. Open questions for Steven
- App/brand name final? Package id (e.g. `io.deskdroid.app`)?
- ~~OK with GPL-3.0 for the whole project?~~ Yes, GPL-3.0 confirmed by Steven (2026-10-16).
- Minimum Android version: suggest **Android 10+** (API 29), recommend 14+ because of the phantom-process toggle.
- ~~Target devices?~~ Steven's Pixel 10 Pro (Tensor G5, PowerVR GPU, USB-C display out + Android 16 desktop mode) is the primary dev device.

---

### References
- Termux:X11 README: https://github.com/termux/termux-x11
- termux-desktop (setup scripts, good reference for package lists and Turnip setup): https://github.com/sabamdarif/termux-desktop
- XoDos (all-in-one Termux desktop + Wine): https://github.com/xodiosx/XoDos
- Winlator CMOD (Winlator fork): https://github.com/Stredohori/Winlator-CMOD
- Termux breakage on OxygenOS/ColorOS 15: https://oxygenupdater.com/article/484/
- Android 16 desktop mode: https://heise.de/-10391884
- Android Linux Terminal (AVF, Debian VM): https://linux.slashdot.org/story/25/03/08/0158226/google-introduces-debian-linux-terminal-app-for-android
