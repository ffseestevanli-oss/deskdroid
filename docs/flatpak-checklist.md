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
- [x] `native/ddmask/test/flatpak.sh`: path rewriting and starting programs,
      with a pretend app and runtime.

## Left for Android

- [ ] **glibc.** The KDE 6.11 runtime ships glibc 2.42; DeskDroid's (patched
      for Android's seccomp filter, `native/glibc`) is 2.41. Plan: build
      DeskDroid's glibc at the runtime's version and use its loader and libc
      in place of the runtime's (the runtime's loader is in app data, which
      Android won't exec, and its glibc isn't patched for seccomp).
- [ ] **ddmask rule**: a program under `flatpak/app/*` or `flatpak/runtime/*`
      starts through DeskDroid's glibc with the Flatpak library path and
      `ddflatpak` preloaded (in place of `test/ddflatpak-run.sh`).
- [ ] Try KCalc's aarch64 build on a phone.
- [ ] **GPU**: Flathub's Mesa doesn't know Android's GPU, so apps draw on the
      CPU at first; later, route them through virgl/Venus.
- [ ] Build libflatpak and OSTree for Android, then port Discover with its
      Flatpak backend, its Launch button starting apps through ddmask.
- Known gaps: programs that make raw system calls (static Go) and glibc's
  own internal reads (gconv) see the real paths; `LOCPATH` covers locales.
