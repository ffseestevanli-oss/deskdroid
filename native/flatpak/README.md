# Flatpak without proot

Flathub apps on the native (no-proot) desktop, with no hosting of our own:
Flathub serves the apps and Debian serves the `flatpak` command.

## How it fits together

| Piece | What it does |
|---|---|
| `libdd_flatpak.so` (`flatpak.sh`), linked as `bin/flatpak` | The `flatpak` command. `flatpak run` starts the app itself (below); everything else (`remote-add`, `install`, `update`, `uninstall`, `list`...) goes to Flatpak's own program. |
| `libdd_flatpakcli.so` | A zip of Debian trixie's arm64 `flatpak`, OSTree, `gpg` and the libraries they need (95 packages, `build.sh` and `debs.py`), unpacked into `files/flatpak-cli` once per app version (`NativeDesk.kt`). They run on DeskDroid's glibc (`../glibc`). |
| `libddflatpak.so` (`../ddmask/ddflatpak.c`) | Preloaded into Flatpak's programs and into the apps: maps the paths they expect (`/usr`, `/app`, `/etc/...`) to the folders they're really in, as bubblewrap's mounts would. |
| `libdd_nobwrap.so` (`nobwrap.sh`) | Stands in for bubblewrap, which needs user namespaces Android doesn't give apps. Flatpak only uses it for its install triggers here. |

Installs are per-user, in `files/flatpak` (`FLATPAK_USER_DIR`), so no
system helper or polkit is needed. Flatpak exports the apps' menu entries
and icons to `files/flatpak/exports/share`, which is in the desktop's
`XDG_DATA_DIRS`, and `flatpak.sh` points their `Exec=/usr/bin/flatpak` at
`flatpak`, so the apps show up in the menu and start from it.

## Starting an app

`flatpak run <app>` reads the app's metadata (its runtime, command and
`[Environment]`), then starts the command with the runtime's `/bin/sh`
through ddmask, with:

- `DDMASK_GLIBC_LD_LIBRARY_PATH`: DeskDroid's glibc first (it's patched for
  Android: paths, variables, seccomp; the runtime's own glibc isn't, and its
  loader is in app data, which Android won't exec), then the app's
  libraries, the runtime's, and the GL driver extension's.
- `DDMASK_GLIBC_LD_PRELOAD`: `libddflatpak.so` before `libddmask_glibc.so`,
  so a path like `/app/bin/kcalc` is real by the time ddmask starts it.
- `DDFLATPAK_APP`, `DDFLATPAK_RUNTIME`, `DDFLATPAK_MOUNTS` (the GL driver
  extension where Flatpak mounts it, `/dev/shm`), and the environment
  `flatpak run` sets inside its sandbox (`PATH=/app/bin:/usr/bin`,
  `XDG_DATA_DIRS`, `~/.var/app/<app>`).
- The desktop's own Qt and KDE variables unset (they name bionic plugins).

Electron apps start through `zypak-wrapper`, which needs Flatpak's portal:
ddflatpak starts them directly with `--no-sandbox`, and on Wayland with
`--ozone-platform-hint=auto` (`../ddmask/ddflatpak.c`).

## Use

In Konsole:

    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak install --user flathub org.kde.kcalc
    flatpak run org.kde.kcalc

## Tests

Desktop Linux (x86_64): `../ddmask/test/flatpak.sh` (ddflatpak's rules),
and Flathub's x86_64 KCalc and ytDownloader with
`../ddmask/test/ddflatpak-run.sh`.

arm64 under qemu-aarch64, laid out like the phone (2026-11-07): this
`flatpak.sh`, with `DESKDROID_GLIBC_RUN` and `DDFLATPAK_LOADER` set to a
script that runs `qemu-aarch64 libdd_ld-glibc.so` (ddmask's job on the
phone), added Flathub, installed KCalc with its runtime and GL driver from
Flathub (aarch64), and ran it on DeskDroid's glibc 2.42.

Android's rules for apps, on x86_64 (`../glibc/test/android-sim.sh`): the
app's seccomp policy (from bionic's lists) and SELinux's "no hard links in
app data", the APK's library folder and app files where Android puts them,
the zips unpacked without file modes. It runs every step Discover takes:
add Flathub, fetch its catalog (where Discover reads it), install KCalc,
list installed apps and updates, run KCalc, update, remove. All passed
(2026-11-07), install triggers included.

What Android changes, and how it's handled:

| Android | Effect | Handled by |
|---|---|---|
| No hard links in app data (`EACCES`) | OSTree creates files as `O_TMPFILE` and links them in; checkout hard-links from the repo | ddflatpak: `O_TMPFILE` fails with `EOPNOTSUPP` (OSTree then writes named temp files), `link`/`linkat` `EACCES` becomes `EPERM` (OSTree copies instead) |
| seccomp kills on calls it blocks (set_robust_list, rseq...) | "Bad system call" | glibc: `SIGSYS` returns `ENOSYS`; no clone3/rseq; set_robust_list only where it worked (`../glibc`) |
| Can't exec files in app data | gpg, the triggers, flatpak itself | ddmask (glibc build) runs them through the APK's loader; `flatpak.sh` too, when started without ddmask (Discover) |
| Zips unpack without modes | the shell won't start them | `flatpak.sh` sets them (globs, not `find`) |
| No user namespaces | no bubblewrap | `nobwrap.sh` for triggers, ddflatpak for `flatpak run` |

## Limits

- Programs that make raw system calls (static Go), and glibc's own
  internal reads, see the real paths, not the mapped ones.
- GPU: Flathub's Mesa doesn't know Android's GPU, so apps draw on the CPU
  (llvmpipe, or SwiftShader in Electron) for now.
- Without hard links, each app and runtime is stored twice (OSTree's repo
  and the checkout): KCalc with its KDE runtime takes about 6 GB.
- Portals (file chooser, notifications through Flatpak) aren't there; apps
  fall back to their own dialogs.
