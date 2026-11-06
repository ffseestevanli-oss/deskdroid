# musl for ddmask

DeskDroid's own build of musl 1.2.5, so ddmask can run ARM64 musl programs
(Alpine Linux's packages, and other programs built against musl) on Android
without proot. It is the same idea as `../glibc`; read that README first.

`patch.py` makes the same three changes to upstream musl:

- **Its own folder**, `/data/data/io.deskdroid.app/files/musl`: `/etc`,
  `/var` and `/tmp` paths move under it, the loader looks for libraries in
  its `lib` and `usr/lib` (and reads `etc/ld-musl-aarch64.path` there), and
  the shell is `/system/bin/sh`. The app writes `etc/passwd`, `etc/group`,
  `etc/resolv.conf` and `etc/hosts` at every start (`NativeDesk.kt`).
- **Its own variables**: `DDMASK_MUSL_LD_PRELOAD` and
  `DDMASK_MUSL_LD_LIBRARY_PATH` instead of Android's `LD_*`.
- **Blocked system calls fail with `ENOSYS`** instead of killing the process
  (a `SIGSYS` handler, set just before the program starts).

musl's C library is also its loader, so `build.sh` outputs just two files
for the APK's library folder:

| File | What it is |
|---|---|
| `libdd_ld-musl.so` | musl: loader and C library. ddmask maps `PT_INTERP` `/lib/ld-musl-aarch64.so.1` to it, and programs asking for `libc.musl-aarch64.so.1` or `libc.so` get it too. |
| `libddmask_musl.so` | ddmask built against musl, preloaded into musl programs. |

ddmask starts musl programs as `libdd_ld-musl.so --argv0 <argv[0]> <program>`
(musl calls constructors without arguments, so ddmask can't fix `argv[0]`
itself the way it does for bionic programs).

The build is cached in `~/.cache/deskdroid/musl` (CI caches it on
`build.sh` and `patch.py`). Without an aarch64 cross compiler it's skipped.

## Testing

`test/run.sh <build.sh's outdir>` runs under `qemu-aarch64`: a program
through the loader, the app's `/etc/passwd`, `ENOSYS` for a blocked call, a
library from musl's `lib` folder, `LD_PRELOAD` ignored, `libddmask_musl.so`
giving the program its name and path, and a static musl program through
ddmask's `ddload` (`../ddmask/ddload.c`). CI runs it on every APK build.

## Limits

Those of `../glibc`: the folder is fixed to Android's first user, musl
programs bring musl builds of their libraries (into `files/musl/lib`), and
there's no GPU for them yet. Also `/dev/shm` (`shm_open`, named semaphores)
doesn't exist on Android.
