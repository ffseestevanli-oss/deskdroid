# Steam and FEX-Emu: device test checklist

Plan section 6b. Steam runs Valve's native ARM64 client; x86 Linux programs
run under FEX-Emu. First device test (Pixel 10 Pro): the x86 client under FEX
got as far as steam.sh's check for user namespaces, which proot can't pass, so
Steam moved to the ARM64 client, started directly without steam.sh (the
approach [steamclienttermux](https://github.com/huntergdavis/steamclienttermux)
proved under proot).

## Native desktop (no proot): Steam through FEX, experimental

The native desktop has no Debian system and no proot, so Steam runs the way
x86 Linux programs run on ARM64 PCs: Valve's x86 client under FEX-Emu, in
an x86 system of its own.

- **FEX** (`fex/build.sh`, patched by `fex/patches`) is an ARM64 glibc
  program. ddmask starts it through DeskDroid's glibc, and hands it every
  x86 program the desktop starts (`DDMASK_X86_64`, `DDMASK_I386`); FEX's own
  execs go back through ddmask (`native/ddmask/README.md`, "x86 programs").
- **The x86 system** (`fex/rootfs.sh`) is FEX's Ubuntu 24.04 image, unpacked
  (no FUSE on Android), with the files FEX normally takes from the host put
  back, and Xwayland added. The app writes its `passwd`, `group`, `hosts` and
  `resolv.conf` for the phone at each desktop start.
- Both are in the `fex-latest` release (Actions, FEX-Emu: built for pull
  requests, published from main and the native desktop's branch, or by
  hand). The app (`X86.kt`) downloads them the first time Steam starts:
  about 1.2 GB, 4 GB unpacked, into `files/x86`.
- **Steam (experimental)** in the menu runs `files/x86/bin/deskdroid-steam`
  (`assets/x86`). The first time, it opens a Konsole window that asks the app
  for FEX and the x86 system and shows its progress, then downloads Valve's
  bootstrap (`steam_latest.deb`) into `~/.local/share/Steam`. After that it
  runs `steam-x86.sh` with FEX's x86 bash: it starts Xwayland as one window
  on the desktop (the native desktop has no X server, and Steam's windows
  are X11), then `steam.sh -no-cef-sandbox -cef-disable-gpu
  -cef-disable-gpu-compositing` in it. OpenGL is llvmpipe (software).
- Settings: `~/.config/deskdroid-steam-geometry` (Xwayland's size,
  `1280x800` by default, or `fullscreen`), `~/.config/deskdroid-steam-args`
  (more Steam arguments), `~/.config/deskdroid-steam-env` (more variables,
  `NAME=value` lines). Logs: `files/x86/install.log`,
  `files/x86/steam.log`. `deskdroid-steam --reinstall` downloads FEX again
  (and the x86 system, when there's a newer one).

### On the device (native)

- [ ] Steam (experimental) shows in the menu (Games).
- [ ] First click: Konsole shows the downloads and unpacking, then Valve's
      bootstrap. Note how long each step takes.
- [ ] In Konsole: `files/x86/fex/bin/FEXInterpreter /bin/uname -m` prints
      `x86_64` (with `DDMASK_DEBUG=1` to see ddmask's choices).
- [ ] An Xwayland window opens and Steam's updater shows in it.
- [ ] Steam updates itself and shows the login window.
- [ ] If anything stops: `files/x86/steam.log` and
      `~/.local/share/Steam/logs/`.

### What may stop it (native)

- Steam's current client (`steamrt64/steam`, Steam Runtime 3) may want user
  namespaces for its containers, which Android doesn't give apps. The
  fallback is the older 32-bit client: a line
  `STEAM_FORCE_CLIENT=ubuntu12_32` in `~/.config/deskdroid-steam-env`.
- A system call Android's seccomp filter blocks fails with `ENOSYS` (the
  patched glibc's handler) until an x86 program installs its own `SIGSYS`
  handler; then that program gets the signal.
- Phones with a 39-bit address space leave FEX less room for 64-bit
  programs.
- Everything draws on the CPU: no x86 GPU driver for Android's GPUs yet.

## How it works (proot desktop)

The app writes two scripts and a Steam menu entry into the rootfs at every
session start (`Steam.kt`), so existing installs get Steam with an app update.
Light and Full only; Ultra-lite has no x86 support.

- `deskdroid-fex` installs FEX and its x86 rootfs the first time it's needed,
  then runs an x86 program: `deskdroid-fex ./game.x86_64` or
  `deskdroid-fex /bin/bash` for an x86 shell.
  - FEX comes from the `fex-latest` release, built by `fex/build.sh` (Actions →
    FEX-Emu) for Debian trixie arm64, baseline ARMv8.0, no thunks yet. It
    unpacks into `/usr/local` with sudo.
  - The x86 rootfs is FEX's Ubuntu 24.04 image from rootfs.fex-emu.gg
    (downloaded and hash-checked by `FEXRootFSFetcher`). FEX normally mounts it
    with FUSE, which proot lacks, so it's unpacked into
    `~/.fex-emu/RootFS/Ubuntu_24_04` (about 3 GB).
  - It turns the session's GPU variables into x86 ones: with Venus it points
    `VK_ICD_FILENAMES` at the rootfs's x86 Venus driver (same server socket);
    otherwise x86 apps get llvmpipe.
- `deskdroid-steam` is what the Steam menu entry runs. The first time, it opens
  a Konsole window that installs the Debian libraries the client needs (apt)
  and Valve's ARM64 client seed: it reads `bins_linuxarm64_linuxarm64` from
  `client-update.steamstatic.com/steam_client_linuxarm64` (falling back to a
  pinned seed known to work) and unzips it into `~/.local/share/Steam`. Then
  it runs `steamrtarm64/steam -no-cef-sandbox -cef-disable-gpu
  -chromeosnopreallocate -noverifyfiles` directly; steam.sh is skipped because
  it requires user namespaces for its containers. Steam downloads the rest of
  itself and shows Valve's license. Extra arguments:
  `~/.config/deskdroid-steam-args`. Log: `~/.local/share/deskdroid-steam/steam.log`.

Steam needs about 1.5 GB for its client, plus games. FEX's x86 system (about
5 GB during setup) is only installed when `deskdroid-fex` is first used.

## Before testing

- [x] The `fex-latest` release exists (only needed for `deskdroid-fex`).

## On the device

- [ ] Steam shows in the app menu (Games) after an app update, without
      reinstalling the system.
- [ ] First click opens "Setting up Steam" and finishes: libraries, ARM64
      client seed. Note how long each step takes.
- [ ] `deskdroid-fex /bin/uname -m` in Konsole prints `x86_64`.
- [ ] Steam updates itself, shows the license, then the login window.
- [ ] Logging in works; the store and library pages draw (steamwebhelper).
- [ ] A native Linux game without the Steam Linux Runtime starts.
- [ ] A Proton game: expected to fail until the bwrap shim exists (below).

## Known limits and next steps

- The ARM64 client checks its threads' robust futex lists (`get_robust_list`),
  which Android blocks; proot answers those calls itself (native/README.md).

- Games that run in Steam's pressure-vessel container (Proton, newer native
  games) need bubblewrap and user namespaces, which proot can't give. Next:
  the `bwrap` shim from plan section 6b.
- Android kernels often have a 39-bit address space; FEX expects 48-bit, so
  some 64-bit x86 programs may fail to map memory. Check `steam.log` if
  Steam exits early.
- No FEX thunks yet, so games use the emulated x86 Mesa (slower).
- The Steam UI is Chromium drawing in software; Big Picture (menu entry
  action) may be lighter.
