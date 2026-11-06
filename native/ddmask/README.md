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
| a file without an exec bit | refused with `EACCES`, as before |
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
