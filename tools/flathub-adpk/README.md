# Flathub apps as store packages (.adpk)

`build.sh` turns Flathub's ARM64 builds into DeskDroid store packages that
install from a file (Software, "Install from a file") and run without the
`flatpak` command, Flathub, or signature checks on the phone. The apps are
listed in `apps.txt`.

## What a package holds

Every package is the store's "program" kind (`Store.kt`), so the current
APK installs it as it is:

| Entry | What it is |
|---|---|
| `program.txt` | `bin/ddapp`, the package's main program (`ddapp.c`) |
| `program.env` | `DDAPP_RUN=@PROGRAM@/run.sh`, `DDAPP_PROGRAM=@PROGRAM@` |
| `program/bin/ddapp` | A small bionic program: the store marks only ELF files executable and starts the main program through Android's linker, so a script can't be the main program. It starts `run.sh` with `/system/bin/sh`, and lays out each package on its first start (below). |
| `program/run.sh` | `run.sh.in`: `flatpak run` without Flatpak, as `native/flatpak/flatpak.sh`'s `run()` does, with the app, runtime and Mesa in store packages. |
| `program/files/` | The app's `/app` (or a runtime's `/usr`). |
| `program/layout.txt` | What a zip unpacked by the store can't carry: symbolic links (and hard links, which OSTree uses for identical files and SELinux forbids in app data), the execute bits of scripts, empty folders. Absolute link targets (`/app/...`, `/usr/...`) are made relative, to where those folders really are. |
| `program/libdirs.txt` | `RUNPATH` folders under `/app` or `/usr`: glibc's loader opens those itself, where ddflatpak can't map them, so `run.sh` puts the real folders on the library path. |
| `share/` | The app's menu entries (`Exec=<store id>`, `DBusActivatable` dropped), icons and metainfo. |

Runtimes are packages of their own, shared by the apps:

| Package | Flathub |
|---|---|
| `runtime-mesa-25.08` | `org.freedesktop.Platform.GL.default` 25.08 (without OpenCL and the Vulkan drivers for other GPUs) and `codecs-extra` |
| `runtime-freedesktop-25.08` | `org.freedesktop.Platform` 25.08 |
| `runtime-kde-6.11` | `org.kde.Platform` 6.11 |
| `runtime-gnome-50` | `org.gnome.Platform` 50 |

Flathub extensions an app needs and wouldn't work without (EasyEffects' LV2
plugins: LSP, Calf, ZamPlugins, MDA) go inside the app's package at the place
Flatpak mounts them (`--ext`), with the folder Flatpak merges (`lv2`) as links
and only the folders the app uses (`--ext-keep lv2,lib`).

An app's `app.json` lists what it needs (`needs`); `run.sh` says so in
`store/apps/<id>/run.log` when one is missing. Software doesn't install
them by itself yet.

## Building

    ANDROID_NDK_HOME=... tools/flathub-adpk/build.sh <out dir> [store id...]

## Testing on a desktop machine

`test/` installs packages the way `Store.kt` does (`store-install.py`) into
`/data/data/io.deskdroid.app/files` (glibc's fixed prefix), with the APK's
`libdd_ld-glibc.so`, `libddflatpak.so`, `libddmask_glibc.so`,
`libdd_glibc.so` (unpacked into `files/glibc`) and `libdd_store-program.so`
in `/data/app/io.deskdroid.app/lib/arm64`, `/system/bin/sh` a copy of dash,
and `qemu-loader.sh` there running `qemu-aarch64 libdd_ld-glibc.so "$@"`.
`launch.sh <id>` then starts an app as `store-program.sh` would, with qemu
standing in for ddmask; `try.sh <id> <display> <seconds>` does it on its
own Xvfb and takes a screenshot.
