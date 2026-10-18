# Native tools built from source

F-Droid builds every APK from source, so DeskDroid ships no prebuilt binaries.
`build.sh` compiles these with the Android NDK during the Gradle build
(task `:app:buildNativeTools`) and installs them as `lib*.so` files in the APK's
`nativeLibraryDir`, the only place an app targeting API 29+ may exec from.

| Directory | Upstream | Version | License |
|---|---|---|---|
| `proot/` | https://github.com/termux/proot (`src/` and `COPYING`) | commit `e2d843ee6dab076ea0ed1ffd5d0ea12232185499` | GPL-2.0-or-later |
| `talloc/` | Samba `lib/talloc` (https://github.com/samba-team/samba) | tag `talloc-2.4.3` (`talloc.c`, `talloc.h`, `LICENSE`) | LGPL-3.0-or-later |

`talloc/shim/replace.h` is ours: a small stand-in for Samba's `lib/replace`, so
talloc builds without Samba's waf configure step.

Outputs (`app/build/generated/nativeTools/lib/arm64-v8a/`):
- `libproot.so`: the proot executable
- `libproot-loader.so`: proot's loader (found through `PROOT_LOADER`)
- `libtalloc.so`: talloc shared library proot links against

To update a vendored source, replace the files from the new upstream version
and change the table above. Local build without the NDK uses the host
compiler and only proves the sources compile: `native/build.sh /tmp/out`.
