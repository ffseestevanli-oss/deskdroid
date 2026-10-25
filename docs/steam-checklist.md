# Steam and FEX-Emu: device test checklist

Plan section 6b. Steam runs Valve's native ARM64 client; x86 Linux programs
run under FEX-Emu. First device test (Pixel 10 Pro): the x86 client under FEX
got as far as steam.sh's check for user namespaces, which proot can't pass, so
Steam moved to the ARM64 client, started directly without steam.sh (the
approach [steamclienttermux](https://github.com/huntergdavis/steamclienttermux)
proved under proot).

## How it works

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

- Games that run in Steam's pressure-vessel container (Proton, newer native
  games) need bubblewrap and user namespaces, which proot can't give. Next:
  the `bwrap` shim from plan section 6b.
- Android kernels often have a 39-bit address space; FEX expects 48-bit, so
  some 64-bit x86 programs may fail to map memory. Check `steam.log` if
  Steam exits early.
- No FEX thunks yet, so games use the emulated x86 Mesa (slower).
- The Steam UI is Chromium drawing in software; Big Picture (menu entry
  action) may be lighter.
