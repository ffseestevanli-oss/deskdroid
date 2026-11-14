# ddmask

ddmask lets DeskDroid's desktop start programs that Android won't exec.

Android (targetSdk 29+) only execs files from the APK's library folder and
the system's folders. Programs an app installs itself, like the app store's
GIMP and its plug-ins, are refused with `EACCES`. Android still lets the app
map those files as code, so they can run through Android's own linker:
`/system/bin/linker64 <program> <args>` loads the program the way it loads a
library.

`libddmask.so` is preloaded (`LD_PRELOAD`) into KWin and plasmashell
(`NativeDesk.kt`), and so into every program they start. It wraps the exec
family (`execve`, `execv`, `execvp`, `execvpe`, `execl`, `execlp`, `execle`,
`execveat`, `fexecve`, `posix_spawn`, `posix_spawnp`). For a program outside
the folders Android allows, it runs:

| The file is | It starts as |
|---|---|
| an ARM64 Android (bionic) program | `/system/bin/linker64 <program> <args>` (its own `PT_INTERP`) |
| a `#!` script | its interpreter (`/bin/sh` and `/usr/bin/env` map to `/system/bin`), then these same rules for the interpreter |
| a file without an exec bit | run by these same rules when it is an ELF program or `#!` script (zips drop file modes; see "Compatibility layer"), else refused with `EACCES` |
| an ARM64 glibc (ordinary Linux) program | DeskDroid's glibc loader, `libdd_ld-glibc.so --argv0 <argv[0]> <program> <args>` (`/lib/ld-linux-aarch64.so.1` maps to it; see `../glibc/README.md`) |
| an ARM64 musl program (Alpine's) | DeskDroid's musl, `libdd_ld-musl.so --argv0 <argv[0]> <program> <args>` (`/lib/ld-musl-aarch64.so.1` maps to it; see `../musl/README.md`) |
| a static ARM64 program (Go, Rust, static musl or glibc) | ddmask's own loader, `libdd_static.so <program> <argv[0]> <args>` (`ddload.c`, below) |
| an AppImage | `libdd_appimage.so <appimage> <argv[0]> <args>` (`appimage.sh`, below) |
| an x86-64 or i386 program | FEX-Emu, `$DDMASK_X86_64 <program> <args>` (`$DDMASK_I386` for i386), once the app has downloaded it (`X86.kt`; refused with `EACCES` before). FEX is a glibc program, so it starts by the glibc rule; see "x86 programs" below |

A program started through the linker still sees its own `argv[0]`, has its
own process name, and reads its own path from `/proc/self/exe`. Every exec
puts `libddmask.so` back into `LD_PRELOAD` (and its glibc and musl builds,
`libddmask_glibc.so` and `libddmask_musl.so`, into `DDMASK_GLIBC_LD_PRELOAD`
and `DDMASK_MUSL_LD_PRELOAD`, which those loaders read instead), so bionic,
glibc and musl programs can start each other, and a program that clears its
environment still starts its children through ddmask.

Programs inside allowed folders (`/system`, `/vendor`, `/apex`, the APK's
library folder) are exec'd as before. ddmask follows symlinks first, so
`bin/<app>` links into the APK run as before too.

A file named `ddmask-off` in the app's files folder turns it off.

## Compatibility layer

Starting a program is only the first thing that goes wrong for Linux
programs on Android. ddmask also handles the problems that kept coming back
app after app, so each new app needs less of its own troubleshooting:

| Problem | What ddmask does |
|---|---|
| Zips (the store's packages, Flatpak's files as the app unpacks them) and shared storage drop execute bits, so scripts and programs were refused with `EACCES` | An ELF program or `#!` script in the app's files runs without its execute bit, `access(X_OK)` agrees (shells' `PATH` search, `[ -x ]`), and the file gets its bits back where the folder keeps them. A file that is neither still gets `EACCES`. `DDMASK_STRICT_EXEC=1` restores the old rule. |
| The desktop's own Qt and KDE settings (the APK's plugin folder in `QT_PLUGIN_PATH`, the `org.kde.desktop` style, the `deskdroid-ahb` buffer plugin) leaked into Linux programs, whose Qt then looked for plugins and styles it doesn't have | `NativeDesk.kt` copies each of those settings into `DDMASK_HOST_<name>`. When a bionic program starts a glibc or musl one, a setting that still has the desktop's value is left out; a launcher that set its own value (Flatpak's `QT_PLUGIN_PATH=/app/lib/plugins`) keeps it. When a Linux program starts a bionic one again (`xdg-open`, a link that opens the desktop's browser), the desktop's values come back. |
| Android's seccomp filter blocks newer system calls that some programs make without a fallback | The glibc and musl builds catch `SIGSYS` once the program's libraries are loaded. Calls with an allowed twin are made with it: `accept` (`accept4`), `epoll_pwait2` (`epoll_pwait`), `faccessat2` and `fchmodat2` without flags (`faccessat`, `fchmodat`), `close_range` (`close` or `fcntl` on each). The rest fail with `ENOSYS`, as glibc's loader already does (`../glibc/README.md`). Each number goes to `files/glibc/sigsys.log` as before (`DDMASK_SIGSYS_LOG`); `DDMASK_SIGSYS=0` leaves glibc's handler alone. |
| Library folders written into programs as absolute paths (`RUNPATH /app/lib/kid3`, `/usr/lib/<triple>/pulseaudio`) are opened by glibc's loader itself, which ddflatpak's preload never sees | `ddflatpak-audit.c` (`libddflatpak_audit.so`) is an audit library for glibc's loader (`rtld-audit(7)`): the loader asks it about every folder a program or library names, and it answers with ddflatpak's mapping. `flatpak.sh` and the store's Flathub launchers load it with `DDMASK_GLIBC_LD_AUDIT`. It has no C library, so the loader doesn't search for one along the program's `RUNPATH` before asking it. |
| Shared memory fails (Firefox: `MOZ_RELEASE_ASSERT(mHandle.IsValid() && mMapping.IsValid())`) | glibc and musl builds. Android's SELinux policy refuses opening an app's own memfd again through `/proc/self/fd/N`, which Firefox and Chromium do for a read-only copy: ddmask hands back a copy of the descriptor instead (Firefox seals the memfd against writes first). And Android has no `/dev/shm`, which glibc's and musl's `shm_open` open inside libc where no path mapping reaches: ddmask's `shm_open` and `shm_unlink` open it through `open()`, so ddflatpak's `/dev/shm` mount applies, and otherwise use `$DDMASK_SHM` or `$TMPDIR/ddmask-shm`. |
| Linux apps in Breeze Light instead of the desktop's look | Going from a desktop (bionic) program to a glibc or musl one, ddmask fills in `DDMASK_LINUX_<VAR>` where the program has no value of its own: NativeDesk sets KDE's platform theme (`QT_QPA_PLATFORMTHEME=kde`, so `kdeglobals`' DD Party colours, icons and fonts apply), `XDG_CURRENT_DESKTOP=KDE` and the GTK theme from `gtk-3.0/settings.ini`. Flathub and store apps also get the desktop's colour scheme as the default for KDE apps that pick their own (`adpk-run.sh`). |
| A program that didn't open left nothing behind | The journal, `$DDMASK_JOURNAL` (`files/ddmask.log` on the desktop): one timestamped line for each program started another way (how, and through what), each one that can't start and why (no loader, an x86 program before FEX is installed, not a program at all), and each blocked system call (once per process). Settings' **Save log** adds it, the programs Flatpak couldn't start (`files/glibc/exec.log`), a count of blocked system calls and each store app's own launcher log (`store/apps/<app>/run.log`). It is kept under 256 KiB, the one before as `ddmask.log.old`. |

`test/compat.sh` tests all of these on desktop Linux, the blocked system
calls with a seccomp filter that traps them the way Android's does;
`test/flatpak.sh` tests the audit library.

## Static programs: ddload

A static program has no interpreter, so there is no loader to start it
through. `ddload.c` (`libdd_static.so`) is one: a small freestanding program
(no C library) that does the kernel's exec in user space. It maps the
program's segments (static or static PIE), points the auxiliary vector at
them, sets the process name, and jumps to the program's entry on the same
stack, so the program gets its `argv[0]`, arguments and environment. It also
catches `SIGSYS`, as the patched glibc and musl do, so a system call
Android's seccomp filter blocks fails with `ENOSYS` instead of killing the
program.

Limits: `/proc/self/exe` names `libdd_static.so` (nothing can be preloaded
into a static program to fix it), and a static program's own execs don't
pass through ddmask, so one that starts other programs from the app's files
fails as before.

## AppImages

An AppImage mounts itself with FUSE, which Android apps can't use.
`appimage.sh` (`libdd_appimage.so`) unpacks it instead, with the AppImage's
own `--appimage-extract`, into `$DDMASK_APPIMAGE_CACHE` (default
`~/.cache/ddmask-appimage`), once per file, then starts its `AppRun` with
`APPIMAGE`, `APPDIR`, `ARGV0` and `OWD` set. Both the AppImage and its
`AppRun` start through ddmask, so their programs run by the rules above
(an ARM64 AppImage's programs are usually glibc ones). `DDMASK_APPIMAGE_RAW=1`
makes ddmask run an AppImage as a plain program.

## x86 programs: FEX-Emu

x86 Linux programs (Steam, its games) run under FEX-Emu, which the app
downloads the first time Steam starts (`X86.kt`, `docs/steam-checklist.md`):
FEX into `files/x86/fex`, and the x86 system the programs see as `/` (FEX's
Ubuntu 24.04 image with Xwayland, `fex/rootfs.sh`) into `files/x86/rootfs`.
FEX is an ARM64 glibc program, built by `fex/build.sh` with its own
`libstdc++` and `libgcc_s` next to it (found through `RPATH`), so it runs on
DeskDroid's glibc. Its patch (`fex/patches`) makes its own execs (an x86
program starting another, or FEX starting itself again) call the C library's
`execveat`, which ddmask wraps, instead of the raw system call, and starts FEX
by its real path rather than `/proc/self/exe` (the glibc loader). It also
drops the Android `LD_PRELOAD` and `LD_LIBRARY_PATH` before the x86 program
sees them.

## Settings

All optional; the defaults are right for DeskDroid.

| Variable | Meaning |
|---|---|
| `DDMASK_ALLOW` | Folders exec works in, `:`-separated. Default on Android: the system's folders and `libddmask.so`'s own folder. Elsewhere: everything (ddmask does nothing). |
| `DDMASK_MAP` | Interpreters to replace, `from=to:from=to`, for `#!` lines and `PT_INTERP`. |
| `DDMASK_DEBUG=1` | Logs each decision to stderr. |
| `DDMASK_JOURNAL` | The journal file (above). The desktop sets `files/ddmask.log`. |
| `DDMASK_LOG` | A file for programs that couldn't start, without times (`flatpak.sh` reads it back for its messages). |
| `DDMASK_HOST_<name>` | The desktop's own value of `<name>` (above). |
| `DDMASK_STRICT_EXEC=1` | Files without an execute bit are refused. |
| `DDMASK_SIGSYS=0`, `DDMASK_SIGSYS_LOG` | Leave blocked system calls to glibc's loader; where their numbers go. |
| `DDMASK_X86_64`, `DDMASK_I386` | The emulator for x86-64 and i386 programs. The app sets both to FEX's `FEXInterpreter` once it's installed. |
| `DDMASK_FALLBACK` | A last resort (proot...) for anything else the linker can't run. Unused. |

## Testing

`test/run.sh` builds ddmask and a probe program with the host compiler and
runs them on desktop Linux, where glibc's loader stands in for linker64: a
folder outside `DDMASK_ALLOW` plays the app's own files. It covers exec by
path, `PATH` search, `execvp`, `execle` with a cleaned environment,
`posix_spawnp`, `#!` scripts, the program's own `argv[0]`,
`/proc/self/exe` and process name, static and static PIE programs through
ddload, and a pretend AppImage (`fake-appimage.c`) unpacked and started. CI
runs it on every APK build. `../glibc/test/run.sh` and `../musl/test/run.sh`
test the glibc and musl loaders, and ddload for ARM64, under qemu.

## The ddmask module (for now)

While ddmask changes often, it also ships apart from the APK, as a package
Software installs like a dependency (`module.sh` packs one from an APK
build, `test/module.sh` tests it). Installed, it's
`files/store/apps/ddmask/program`, and with `api-1` in it (it fits this APK):

- the bionic ddmask (`libddmask.so`) is the module's when Android's linker
  will preload it from app files (`NativeDesk.kt` checks at desktop start
  and sets `DDMASK_MODULE_BIONIC=1`); otherwise the APK's;
- ddmask hands glibc and musl programs the module's builds
  (`libddmask_glibc.so`, `libddmask_musl.so`), and the launch scripts preload
  the module's `libddflatpak.so` and audit library;
- the APK's `adpk-run.sh`, `flatpak.sh` and `fex-run.sh` run the module's
  copies instead.

The loaders and runners ddmask execs stay in the APK (`DDMASK_LIBS`), since
Android runs programs only from there; so does a copy of everything above,
used whenever the module isn't installed or doesn't fit. Removing the
module in Software goes back to the APK's ddmask. Once ddmask settles, the
module goes away and the APK's copy is the only one again.
