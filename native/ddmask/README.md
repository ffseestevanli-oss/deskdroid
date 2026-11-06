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
| anything else (static, glibc, x86) | refused with `EACCES`; not a goal for now (DeskDroid ports are native Android builds) |

A program started through the linker still sees its own `argv[0]`, has its
own process name, and reads its own path from `/proc/self/exe`. Every exec
puts `libddmask.so` back into `LD_PRELOAD`, so a program that clears its
environment still starts its children through ddmask.

Programs inside allowed folders (`/system`, `/vendor`, `/apex`, the APK's
library folder) are exec'd as before. ddmask follows symlinks first, so
`bin/<app>` links into the APK run as before too.

A file named `ddmask-off` in the app's files folder turns it off.

## Settings

All optional; the defaults are right for DeskDroid.

| Variable | Meaning |
|---|---|
| `DDMASK_ALLOW` | Folders exec works in, `:`-separated. Default on Android: the system's folders and `libddmask.so`'s own folder. Elsewhere: everything (ddmask does nothing). |
| `DDMASK_MAP` | Interpreters to replace, `from=to:from=to`, for `#!` lines and `PT_INTERP`. |
| `DDMASK_DEBUG=1` | Logs each decision to stderr. |
| `DDMASK_X86_64`, `DDMASK_I386`, `DDMASK_FALLBACK` | Hooks for an emulator (Box64, FEX) or proot to run what the linker can't. Unused for now. |

## Testing

`test/run.sh` builds ddmask and a probe program with the host compiler and
runs them on desktop Linux, where glibc's loader stands in for linker64: a
folder outside `DDMASK_ALLOW` plays the app's own files. It covers exec by
path, `PATH` search, `execvp`, `execle` with a cleaned environment,
`posix_spawnp`, `#!` scripts, and the program's own `argv[0]`,
`/proc/self/exe` and process name. CI runs it on every APK build.
