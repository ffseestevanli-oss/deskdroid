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
| Display server | **Termux:X11** for the MVP, then **DeskDroid's own Wayland host** (Phase 2) | Termux:X11 is mature and gets us a desktop fastest. Wayland is the destination because Plasma 6.8+ is Wayland-only (section 6). |
| Desktop session | Plasma **X11 session** for MVP, **Plasma Wayland** (KWin nested on our host) from Phase 2 | X11 apps keep working through Xwayland in both. |
| GPU (Adreno) | **Turnip** (Mesa Vulkan) via `/dev/kgsl`, **Zink** for OpenGL | `/dev/kgsl` is reachable from unprivileged apps; this is how Winlator/Mobox get real GPU speed. |
| GPU (Mali/other) | **Venus** Vulkan forwarding + Zink (dma-buf, or AHardwareBuffer memory where the driver lacks dma-buf export); llvmpipe fallback | No unprivileged path to Panfrost/Mali or PowerVR DRM drivers. Vortek is closed-source, so Venus is the open equivalent. Decided with Steven 2026-10-23: virgl first. First Pixel 10 Pro test: virgl crashed KWin and Firefox tabs. Steven then chose to replace virgl with Venus (opt-in, Automatic stays on llvmpipe until proven), borrowing ideas from GameNative's Vortek: KWin stays on software by default, and zero-copy presentation into AHardwareBuffers is a later step. |
| x86 translation | **FEX-Emu** for Steam and 32-bit x86, **Box64** + **Wine** (WoW64) for standalone Windows apps | FEX runs 32-bit and 64-bit x86 without needing 32-bit ARM, which the Pixel 10 Pro and most 2023+ chips lack; it is what Valve uses for Steam on ARM (Steam Frame) and what Ubuntu's arm64 Steam snap uses. Box64 stays as a fast alternative for Wine apps. |
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
│  • small helpers (busybox-style tar, Venus server)       │
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
- **Study (do not copy blindly):** Winlator (bundling, kgsl/Turnip setup, gamepad shim, Wine prefix management), Mobox, termux-desktop scripts, XoDos, AndroidIDE (how to ship Termux-style userland with a modern targetSdk).

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

## 3a. Editions (chosen at install)

The installer offers two main choices, with a third tucked under "...or there's this":

| Edition | Desktop | What's included | x86 / Windows | Size (estimate: download / on disk) |
|---|---|---|---|---|
| **Light** | KDE Plasma | Base desktop only: Dolphin, Konsole, Kate, Ark, System Settings and **Discover** to add anything else. | Added later from Discover (DeskDroid repo) | ~1.2 GB / ~4 GB |
| **Full** | KDE Plasma | Light plus Firefox, LibreOffice, GIMP, VLC, Okular, Gwenview, and from Phase 3 **Steam**, Box64 + Wine and FEX. | Preinstalled | ~3.5 GB / ~10–12 GB (incl. Steam client) |
| **Ultra-lite** (under "...or there's this") | **MATE** | Basic native ARM apps: Caja, MATE Terminal, Pluma, Eye of MATE, Atril, Engrampa, Firefox ESR. | None, ARM only | ~0.6 GB / ~2 GB |

- One image per edition, built by CI from shared package lists (`rootfs/packages/{base,plasma,full,ultralite}.txt`) and published together. The installer downloads only the chosen one.
- Editions are upgradeable in place: Light → Full is just installing the Full package set (a "Get the Full apps" button in the launcher). Ultra-lite → Light/Full swaps the desktop, so it goes through a fresh image with `/home` kept.
- Discover talks to apt through PackageKit, which needs the system D-Bus. The rootfs now boots through `deskdroid-boot`, which runs under proot's fake root (so sudo, apt and Discover can install software), starts system D-Bus, then drops to the `deskdroid` user. Flathub is enabled in Discover too (section 5b).
- Ultra-lite stays on X11 permanently (MATE is X11-only). After the Wayland switch it runs inside rootful Xwayland on the DeskDroid Wayland host, so we never maintain two display stacks.
- Open question: Light has no web browser. Firefox is one click away in Discover; say if you'd rather Light include it.

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
| **No DRM/KMS, no Wayland compositor on hardware** | KWin can't drive the screen directly | KWin runs nested: its Wayland backend draws into a window provided by our Android-side Wayland host (section 6). |
| **W^X: apps targeting API 29+ can't exec files from app data** | Breaks naive "exec binaries from rootfs" with a modern targetSdk | Ship proot and its loader as `lib*.so` in `jniLibs` (executable `nativeLibraryDir`); proot loads rootfs ELF files via its loader (mmap, not execve), as Winlator/AndroidIDE-style apps do. Must validate on Android 15/16 early (Phase 0). Fallback, now open to us since we're not on Play: target API 28 like Termux, which allows exec from app storage. |
| **Mali/PowerVR GPUs** | No Turnip | Vulkan forwarding to the Android driver (Vortek-style), with Zink on top for OpenGL. **Pulled into Phase 1** because the primary dev device is a Pixel (Tensor: Mali, PowerVR on G5). llvmpipe as last-resort fallback. |
| **No `/dev/input`, no uinput** | Gamepads/joysticks need a bridge | Userspace bridge (section 4). |
| **Storage** | Rootfs lives in app-private storage (deleted on uninstall) | Plain folder, see section 5b. Shared storage bound inside Linux (`~/Phone`, and the XDG home folders are the phone's own); backup/export built in; `hasFragileUserData` gives the "keep app data" choice on uninstall. |
| **OEM breakage** (e.g. reports of Termux breaking on ColorOS/OxygenOS 15) | Some vendors restrict exec/ptrace | Device test matrix; known-issues list per OEM. |

---

## 5b. Flatpak, storage, login and the terminal (decided 2026-10-18)

**Flatpak (must have).** Flathub is enabled in Discover next to apt. Flatpak normally sandboxes every app with bubblewrap, which needs Linux user namespaces that Android doesn't give apps. Plan:
- First check whether unprivileged user namespaces happen to work on the Pixel 10 Pro; if they do, use real bubblewrap.
- Otherwise ship a **bubblewrap stand-in** (`/usr/bin/bwrap` shim) that translates bubblewrap's arguments (`--bind`, `--ro-bind`, `--symlink`, `--dev`, `--proc`, `--tmpfs`, `--setenv`, `--args FD`, …) into proot bind mounts and ignores the namespace and seccomp flags. Apps run without Flatpak's sandbox, like everything else in DeskDroid, which is already isolated from Android by the app sandbox.
- Use per-user installs (`flatpak --user`) by default so no system helper or polkit is needed. Done: the app adds Flathub as a user remote and makes Flatpak Discover's default source at each start (`Flatpak.kt`, `assets/linux/deskdroid-flatpak`). Many Flathub apps have aarch64 builds; x86_64-only ones can run under FEX later.
- The same shim also runs Steam's game containers (section 6b), so it is one piece of work for two features. Prove it in Phase 1 with a few popular Flathub apps.

**Where the system lives: a plain folder, not an image file.**
- The rootfs is a normal folder in the app's private storage (`/data/data/io.deskdroid.app/files/rootfs`). It already grows and shrinks with what's installed, like qcow2, with no fixed size.
- Not `/sdcard/.DeskDroid`: shared storage has no symlinks, no Unix permissions and no exec, so Linux can't run from it, and other apps could read it.
- Not a qcow2/ext4 image file: mounting one needs root (loop devices) or FUSE, neither available to apps.
- Shared storage appears inside Linux at its own path (`/storage/emulated/0`, also `/sdcard` and `~/Phone`), and `~/Documents`, `~/Downloads`, `~/Pictures`, `~/Music` and `~/Videos` are the phone's Documents, Download, Pictures, Music and Movies, so files show up on both sides. Android's own `Android/` folder is hidden (a `.hidden` file, so "Show hidden files" reveals it). Needs All files access; without it the home folders stay Linux-only. (Implemented 2026-10-25, `Storage.kt`.)
- Backup/export writes the system (or just `/home`) to one compressed archive on shared storage, and restore reads it back. That covers the "single file you can move around" need.
- `android:hasFragileUserData="true"` so Android asks whether to keep app data when DeskDroid is uninstalled.

**Login screen (optional).** Real SDDM expects to own the machine (systemd-logind, virtual terminals, starting the X server as root), which proot can't provide. Plasma's lock screen is off by default, and forced off while the deskdroid user has no Linux password, since it would have nothing to unlock with (ScreenLock.kt); users who set one with `passwd` can turn it on in System Settings. The app's "Lock my desktop" setting is the default lock instead: fingerprint, face or the phone's PIN before the desktop opens. Data at rest is already protected by Android's file-based encryption of app storage.

**Start on boot (optional setup toggle).** When on, a `BOOT_COMPLETED` receiver starts the session foreground service, so the desktop is already running when the user opens it.
- `BOOT_COMPLETED` arrives after the first unlock, which is when Android decrypts app storage and the rootfs becomes readable. `LOCKED_BOOT_COMPLETED` is too early.
- Android 15 bans starting some foreground service types from a boot receiver (dataSync, camera, mediaPlayback, phoneCall, mediaProjection, microphone). The session uses `specialUse`, which isn't on that list. If audio later needs the microphone type, it's added only when the user opens the desktop, not at boot.
- Android won't let a background app open a window, so the boot start runs headless. The desktop appears when the user taps the notification or "Start desktop".
- Needs unrestricted battery (requested when the toggle is turned on) and the phantom-process fix. The app must have been opened once after install, because Android doesn't deliver broadcasts to apps that were never launched.
- Cost: an idle Plasma session holds roughly 1–1.5 GB of RAM (estimate), so the setup screen says so and the toggle is off by default.

**What the terminal can and can't do.** Most things work: apt and sudo, compilers, git, Python/Node, SSH client, networking, editing system files. What doesn't: systemd/`systemctl` (shim for common cases), `mount`, kernel modules, Docker/Podman and KVM, iptables/firewall, binding ports below 1024, raw sockets, and direct hardware access. Syscall-heavy work (big builds, package installs) is slower because of proot.

## 6. Biggest risks

1. **Plasma is now Wayland-only.** Plasma 6.8 dropped the X11 session; 6.7 is the last X11 series, supported into early 2027 ([Phoronix](https://www.phoronix.com/news/KDE-Plasma-68-Wayland-Exclusive)). X11 *apps* keep working through Xwayland. Debian trixie's Plasma 6.3 X11 session is fine for the MVP, but we must be on Wayland before moving the image to Debian 14 (forky). Plan:
   - **Step A (Phase 2 start, cheap):** run `kwin_wayland` nested inside Termux:X11 using KWin's X11 backend. Proves Plasma Wayland under proot with zero new display code. Costs one extra frame copy. Implemented as the experimental Wayland session option; device checklist in [wayland-checklist.md](wayland-checklist.md).
   - **Step B (Phase 2 deliverable):** replace Termux:X11 with a **DeskDroid Wayland host** in the APK: a small Android-side compositor that shows one full-screen surface per Android display and implements just what nested KWin needs (`xdg-shell`, `wl_seat`, `wl_shm`, `linux-dmabuf` backed by AHardwareBuffer, relative-pointer and pointer-constraints for games). KWin runs with its Wayland backend on top, Plasma does all real window management, and Xwayland covers X11 and Wine apps. Rotation, monitor hot-plug and any aspect ratio become simple output-size changes.
   - **Prior art:** [tawc](https://github.com/wmww/tawc), a new rootless Android Wayland compositor with Xwayland, which reaches the GPU through libhybris (Android's own drivers loaded into glibc apps). Experimental and license unchecked, but it proves the approach, and libhybris is a candidate GPU path for the Pixel alongside Vulkan forwarding.
2. **F-Droid inclusion rules.** F-Droid builds everything from source, so prebuilt binaries in the APK are not allowed (section 7b). Getting into the main F-Droid repo takes time, so our own F-Droid repo and GitHub Releases come first.
3. **Performance expectations.** Plasma + Firefox is fine on recent Snapdragons; Windows games depend heavily on Turnip versions and device. Ship per-device profiles and set expectations clearly.
4. **Maintenance load** of forks (Termux:X11, proot, Mesa). Keep forks thin and upstream fixes.

---

## 6b. Steam, preinstalled

Steam ships in the image as a desktop and menu icon, ready on first click. Valve does not officially support Steam on ARM Linux, so it runs as the x86 client under FEX, the same approach as Valve's Steam Frame and [Ubuntu's arm64 Steam snap](https://phoronix.com/news/Steam-Snap-ARM64-FEX).

**What it needs:**
- **FEX-Emu** (arm64), with its x86 rootfs (x86_64 + i386 glibc, 32-bit libraries the Steam client needs). Not in Debian, so we build it in CI (`fex/build.sh`, release `fex-latest`). Done as a first-launch download for now, with FEX's own Ubuntu 24.04 x86 rootfs unpacked to `~/.fex-emu` (proot has no FUSE to mount it): [steam-checklist.md](steam-checklist.md).
- **FEX thunks** so x86 games call our arm64 Mesa (Vulkan/OpenGL) directly instead of emulated x86 drivers.
- **Steam launcher** (Valve's small bootstrap). The full client (~1 GB) downloads and updates itself on first launch, which also keeps us from redistributing Valve's binaries. The user accepts Steam's license in Valve's own first-run dialog.
- **Proton** for Windows games, downloaded by Steam as usual and run under FEX.
- Launcher shim instead of binfmt_misc (no root): `deskdroid-steam` → `FEX /bin/bash ~/.local/share/Steam/steam.sh`, and `deskdroid-fex PROGRAM` for other x86 apps. Written by the app at session start (`Steam.kt`).

**Size impact (estimates, to measure in Phase 3):** FEX x86 rootfs about +1.5 to 2 GB on disk (+0.5 to 0.8 GB to the compressed download). Steam client +1 GB on first launch. Each Proton version +1 GB. Total free space recommended goes from ~6 GB to ~10 GB. Phase 1 images can leave the FEX rootfs as a first-click download if the base download size hurts.

**Other launchers (gaming focus for now: Steam, Lutris and similar).**
- **Lutris** ships in Full next to Steam, from Debian. It manages Wine/Proton, emulators and GOG/Humble installs; its Wine runners go through FEX or Box64, and it uses the same bwrap shim where needed.
- **Heroic Games Launcher** (Epic and GOG, has arm64 builds) is the candidate for Epic games until Epic ships its own Linux client; offered through Flathub in Discover.
- **Watch item: Epic Games Store for Linux.** Epic's reported upcoming Linux port of the Epic Games Store (not yet verified by us). Evaluate when it ships; it would likely be x86-only and run under FEX like Steam.

**Hard parts:**
- **Steam Linux Runtime containers.** Steam runs games (and Proton) inside its pressure-vessel container, which uses bubblewrap and needs user namespaces that Android apps don't get. Fix: a `bwrap` shim that turns bubblewrap's bind-mount arguments into a nested proot, or force games to run outside the container. This is the first thing to prove.
- **Steam UI speed.** The Steam UI is an emulated Chromium (steamwebhelper). Expect sluggishness on the desktop client; Big Picture mode and launching games directly are the smoother path.
- **Anti-cheat** games stay unsupported, same as on Steam Deck without vendor opt-in.

## 6c. Branding and look

- **Product design:** Steven approved the "party" mockup design (2026-10-18). Mockups and the source assets live in `/mnt/project-files/ui/`. The launcher app follows it.
- **Default KDE wallpaper:** the gradient background from that mockup. It ships in the rootfs as the `DeskDroid` wallpaper package (`/usr/share/wallpapers/DeskDroid/`, one PNG per common resolution and orientation, including ultrawide and portrait) and is set as the default by a Plasma first-start script (`deskdroid-wallpaper.js`). Users can change it as usual.
- **Next:** match the Plasma color scheme, splash screen and panel accents to the same palette (a DeskDroid Global Theme), so the app and the desktop feel like one product.

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
| Steam client | Proprietary (Valve) | Ship only Valve's launcher/bootstrap; the client downloads itself from Valve and the user accepts Valve's agreement. |
| FEX-Emu | MIT | No issue. |
| Microsoft fonts/DLLs, Windows components | Proprietary | **Never bundle.** Offer optional user-initiated install (e.g. winetricks) with the user accepting the EULA. |
| "KDE", "Debian", "Termux" names/logos | Trademarks | Don't use their logos as our branding; "powered by KDE Plasma" wording is fine. |

**Recommendation:** make DeskDroid fully open source under GPL-3.0 from day one. It matches the components, earns community trust, and avoids any proprietary-bundling problems.

---

## 7b. Distribution: F-Droid and GitHub only (decided 2026-10-18)

DeskDroid will not be on Google Play. What that changes:
- **Freed from Play rules:** "All files access" (`MANAGE_EXTERNAL_STORAGE`) for a full `~/Android` view of shared storage, the battery-optimization exemption request, downloading the system image, and a low targetSdk are all fine. We keep a current targetSdk (35+) with proot in `jniLibs`. Targeting API 28 like Termux stays a fallback if the `jniLibs` route fails on the Pixel in Phase 0.
- **F-Droid builds from source:** no prebuilt binaries in the APK. `scripts/fetch-prebuilts.sh` (Termux's proot .deb) is a Phase 0 shortcut only. In Phase 1, proot, talloc and later the X server, PulseAudio and the Wayland host are compiled from source with the NDK as part of the Gradle build, so F-Droid's build server can reproduce them.
- **Reproducible builds:** aim for bit-identical APKs so F-Droid can publish our own signed APK. Then GitHub, our F-Droid repo and the main F-Droid repo all ship the same signature, and users can switch between them without reinstalling.
- **The downloaded system image is fine for F-Droid** as long as it's free software from public sources and built openly in CI. The rootfs uses Debian `main` only (non-free components dropped). Full's Steam download will give the F-Droid listing the "Non-Free Add-ons" anti-feature label; acceptable, and Light/Ultra-lite have none.
- **Channels:** (1) GitHub Releases with Obtainium support from day one; (2) our own F-Droid repo (fdroidserver on GitHub Pages) for quick updates; (3) main F-Droid repo submission once builds are from source and reproducible.
- **Updates:** no self-updating APK code; F-Droid and Obtainium handle app updates. The system image updates through apt and the A/B images (section 3).

## 8. Phased roadmap (MVP first)

### Phase 0: Feasibility spike
- Minimal app: embedded Termux:X11 + proot from `jniLibs` + a stock Debian arm64 rootfs, targetSdk current (API 28 as fallback).
- Prove: exec works under W^X on Android 14/15/16, Xfce-or-Plasma starts, Turnip on `/dev/kgsl` runs `vkcube`, audio plays.
- Test on 3 devices: Steven's Pixel 10 Pro (primary dev device, PowerVR), a Snapdragon flagship, one other Mali/MediaTek.
- Prove Vulkan forwarding on the Pixel renders a composited Plasma desktop smoothly.
- **Exit:** a written go/no-go on the architecture above.

### Phase 1: MVP "Tap to desktop"
- proot and talloc built from source with the NDK in the Gradle build (replaces the Phase 0 prebuilt download; required for F-Droid).
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
- Plasma Wayland: nested KWin on Termux:X11 first (Step A), then the DeskDroid Wayland host replaces Termux:X11 (Step B, section 6).

### Phase 3: Windows and x86 apps
- Box64/Box86 + Wine WoW64 preinstalled, `.exe` double-click in Dolphin "just works".
- Wine prefix manager (per-app prefixes, DXVK/VKD3D/WineD3D choice), device performance profiles.
- x86_64 Linux apps via FEX/Box64 launcher shims (no binfmt_misc without root).
- **Steam and Lutris preinstalled** (section 6b): FEX + x86 rootfs + thunks in our apt repo, bwrap shim for Steam's runtime containers, Proton games launching from Steam.

### Phase 4: Gaming and peripherals
- Gamepad bridge (Wine XInput + SDL virtual joystick), on-screen controls for touch-only use.
- Per-game profiles, FPS overlay, Turnip version picker.
- Forwarding-path performance work for games on Mali/PowerVR.

### Phase 5: Distribution and polish
- Releases on GitHub (+ Obtainium) and our own F-Droid repo, then submit to the main F-Droid repo (section 7b). No Google Play.
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
