# Steam and FEX-Emu: device test checklist

Plan section 6b: Valve's x86 Steam client running under FEX-Emu. Untested on a
device so far.

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
  a Konsole window that installs FEX, the rootfs and Valve's bootstrap
  (`steam.deb` → `~/.local/share/Steam`), then starts Steam, which downloads
  its own client and shows Valve's license. Later starts go straight to
  `steam.sh` under FEX with `-no-cef-sandbox -cef-disable-gpu
  -cef-disable-gpu-compositing`. Extra arguments: `~/.config/deskdroid-steam-args`.
  Log: `~/.local/share/deskdroid-steam/steam.log`.

Needs about 5 GB free for the first setup, plus Steam's client (~1 GB) and games.

## Before testing

- [ ] Run Actions → FEX-Emu once (or merge to main) so the `fex-latest`
      release exists.

## On the device

- [ ] Steam shows in the app menu (Games) after an app update, without
      reinstalling the system.
- [ ] First click opens "Setting up Steam" and finishes: FEX, x86 system,
      bootstrap. Note how long each step takes.
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
  some 64-bit x86 programs may fail to map memory. 32-bit ones (most of the
  Steam client) are fine. Check `steam.log` if Steam exits early.
- No FEX thunks yet, so games use the emulated x86 Mesa (slower).
- The Steam UI is an emulated Chromium and will be slow; Big Picture (menu
  entry action) is lighter.
