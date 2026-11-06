# glibc for ddmask

DeskDroid's own build of glibc 2.41, so ddmask can run ordinary ARM64 Linux
(glibc) programs on Android without proot.

Android has no glibc, and a stock glibc wouldn't work there anyway: it looks
for its loader at `/lib/ld-linux-aarch64.so.1` and its settings in `/etc`,
it reads the same `LD_PRELOAD` as Android's linker, and Android's seccomp
filter kills a process that makes a system call it blocks. `patch.py`
changes upstream glibc so it fits:

- **Its own folder.** glibc is built for `/data/data/io.deskdroid.app/files/glibc`,
  and its fixed paths (`/etc/...`, `/var/...`, `/tmp`) move under that folder.
  The app unpacks the libraries there and writes `etc/passwd`, `etc/group`
  (the app's user) and `etc/resolv.conf` (DNS from Android's network) at
  every start (`NativeDesk.kt`). `/bin/sh` is `/system/bin/sh`.
- **Its own variables.** glibc's loader reads `DDMASK_GLIBC_LD_PRELOAD`,
  `DDMASK_GLIBC_LD_LIBRARY_PATH` and so on instead of `LD_*`, so the bionic
  libraries in Android's `LD_PRELOAD` and `LD_LIBRARY_PATH` don't get loaded
  into glibc programs, and the other way round.
- **Blocked system calls fail instead of killing.** The loader catches
  `SIGSYS` before the program starts, and a system call seccomp blocks
  returns `ENOSYS`, which programs already handle. (A program that installs
  its own `SIGSYS` handler replaces it.)

`build.sh` builds it with an aarch64 glibc cross compiler and outputs three
files for the APK's library folder:

| File | What it is |
|---|---|
| `libdd_ld-glibc.so` | glibc's loader. Android lets the app run it (it's in the APK), and it loads the program, as `linker64` does for bionic programs. ddmask maps `PT_INTERP` `/lib/ld-linux-aarch64.so.1` to it. |
| `libddmask_glibc.so` | ddmask built against glibc, preloaded into glibc programs, so their children start through ddmask too. |
| `libdd_glibc.so` | A zip of glibc's shared libraries, gconv modules and settings, unpacked into `files/glibc` once per app version. |

The glibc build is cached in `~/.cache/deskdroid/glibc` (CI caches it on
`build.sh` and `patch.py`), so it only rebuilds when those change. Without
a cross compiler, `build.sh` skips it and the APK has no glibc support.

## Testing

`test/run.sh <build.sh's outdir>` runs a probe program under
`qemu-aarch64`, with a folder laid out like the phone: it checks that the
program runs through the loader, reads the app's `/etc/passwd`, gets
`ENOSYS` for a blocked system call, ignores `LD_PRELOAD`, and that
`libddmask_glibc.so` loads and gives it its own name and `/proc/self/exe`.
CI runs it on every APK build.

## Limits

- The folder is fixed. Android's first user has the app's files at
  `/data/data/io.deskdroid.app/files` (`/data/user/0/...`); a second user or
  work profile has another folder, where glibc programs won't find their
  libraries.
- A glibc program needs glibc builds of its libraries (GTK, Qt...): it can't
  use the desktop's bionic ones. Those come with the program, the way an
  AppImage or a Flatpak runtime brings them.
- No GPU yet: Android's GPU drivers are bionic libraries. glibc programs get
  software rendering until there is a bridge.
