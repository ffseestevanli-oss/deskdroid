# Flathub apps without proot (ddmask + Flatpak)

Goal: Discover installs apps from Flathub on the native (no-proot) desktop,
and ddmask runs them, so the store needs no hosting of its own.

## How

- **Installing** needs no sandbox: `flatpak --user install` (libflatpak and
  OSTree) downloads and unpacks the app and its runtime into
  `~/.local/share/flatpak`. Discover's Flatpak backend does the same.
- **Running** normally goes through bubblewrap, which needs user namespaces
  Android doesn't give apps. Instead, `native/ddmask/ddflatpak.c` is
  preloaded into the app and rewrites the paths it asks the C library for:
  `/app` to the app's folder, `/usr` (and `/lib`, `/bin`) to the runtime's,
  and `/etc/<x>` to the runtime's when it has one. Programs the app starts
  go through the runtime's loader. The app gets the same environment
  `flatpak run` gives it (`PATH=/app/bin:/usr/bin`, `XDG_DATA_DIRS`, ...),
  `native/ddmask/test/ddflatpak-run.sh`.

## Test on desktop Linux (done, 2026-11-07)

- [x] KCalc and the KDE runtime 6.11 (x86_64) installed from Flathub with
      `flatpak --user install`, no bubblewrap: 25 s.
- [x] KCalc starts with the runtime's own loader and `ddflatpak.c`, without
      `flatpak run` or bubblewrap, with the Breeze style, icons and fonts
      from the runtime (`flatpak-kcalc-test.png`, on Xvfb).
- [x] ytDownloader 4.0.0 (Electron 30.5.1, freedesktop runtime 25.08 with
      its GL driver extension) runs the same way (`flatpak-ytdownloader-test.png`).
      What Electron needed:
      - **zypak**: Flathub's Electron apps start through `zypak-wrapper`, which
        asks Flatpak's portal to start Chromium's sandboxed helpers. ddflatpak
        skips it and starts the program with `--no-sandbox` instead.
      - **/proc/self/exe**: started through the loader, it names the loader;
        Chromium finds its files next to it and execs it for its helpers, so
        ddflatpak answers with the program (the loader's `AT_EXECFN`).
      - **old stat functions**: Electron is built against an old glibc and
        calls `__xstat64` and friends, so its own fontconfig saw no fonts and
        the page crashed in Blink (`FontCache::CrashWithFontInfo`, found with
        Electron's debug symbols). ddflatpak maps those too.
      - **extensions**: the GL driver (Mesa) goes where Flatpak mounts it,
        `DDFLATPAK_MOUNTS`.
      - `#!` scripts (the app's `run.sh`) start with the runtime's `/bin/sh`.
- [x] `native/ddmask/test/flatpak.sh`: path rewriting, scripts, zypak,
      `/proc/self/exe` and the old stat functions, with a pretend app and
      runtime.

## Left for Android

- [x] **glibc 2.42** (2026-11-07). Flathub's 25.08 runtimes need it (their
      programs ask for `GLIBC_2.42`); `native/glibc` builds it with
      DeskDroid's patches (paths, variables, seccomp) and its tests pass. On
      qemu-aarch64, the arm64 freedesktop 25.08 runtime's `stty` (which needs
      2.42), bash and Python 3.13 (with ssl and sqlite3) run on DeskDroid's
      loader and libc in place of the runtime's own: put DeskDroid's
      `glibc/lib` first in `DDMASK_GLIBC_LD_LIBRARY_PATH`, then the runtime's.
      Runtimes on a newer glibc will need the next bump.
- [x] **The flatpak command on the phone** (`native/flatpak`): Debian's arm64
      flatpak, OSTree and gpg on DeskDroid's glibc for installing, and
      `flatpak run` through ddmask with ddflatpak preloaded first. Under
      qemu-aarch64, laid out like the phone, it added Flathub, installed
      KCalc (aarch64) with its runtime and GL driver, and ran it
      (`flatpak-kcalc-arm64-test.png`).
- [x] Desktop wiring: `bin/flatpak`, `files/flatpak-cli` unpacked with
      glibc, Flatpak's exported menu entries in `XDG_DATA_DIRS`.
- [ ] Try KCalc's and ytDownloader's aarch64 builds on a phone (APK).
- [ ] Extensions in general: read them from the runtime's and app's metadata
      (`[Extension ...]`, `merge-dirs`) instead of the launcher's one GL case.
- [ ] **GPU**: Flathub's Mesa doesn't know Android's GPU, so apps draw on the
      CPU at first; later, route them through virgl/Venus.
- [ ] Discover: port it with its Flatpak backend (libflatpak can come from
      the same Debian packages only for glibc programs; Discover is bionic,
      so either build libflatpak for Android or run Discover itself on glibc
      from a Flathub/Debian build), its Launch button calling `flatpak run`.
- Known gaps: programs that make raw system calls (static Go) and glibc's
  own internal reads (gconv) see the real paths; `LOCPATH` covers locales.
