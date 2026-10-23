# Native tools built from source

F-Droid builds every APK from source, so DeskDroid ships no prebuilt binaries.
`build.sh` compiles these with the Android NDK during the Gradle build
(task `:app:buildNativeTools`) and installs them as `lib*.so` files in the APK's
`nativeLibraryDir`, the only place an app targeting API 29+ may exec from.

| Directory | Upstream | Version | License |
|---|---|---|---|
| `proot/` | https://github.com/termux/proot (`src/` and `COPYING`) | commit `e2d843ee6dab076ea0ed1ffd5d0ea12232185499` | GPL-2.0-or-later |
| `zstd/` | https://github.com/facebook/zstd (`lib/common`, `lib/decompress`, headers, `LICENSE`; no threading/pool, no x86 asm) | tag `v1.5.7` | BSD-3-Clause (dual GPL-2.0) |
| `monocypher/` | https://github.com/LoupVaillant/Monocypher (`src/` + `src/optional/` Ed25519) | tag `4.0.2` | BSD-2-Clause or CC0 |
| `talloc/` | Samba `lib/talloc` (https://github.com/samba-team/samba) | tag `talloc-2.4.3` (`talloc.c`, `talloc.h`, `LICENSE`) | LGPL-3.0-or-later |
| `virgl/` (downloaded, not vendored) | virglrenderer https://gitlab.freedesktop.org/virgl/virglrenderer | `1.3.0` (SHA-256 pinned in `virgl/build.sh`) | MIT |
| `virgl/` (downloaded, not vendored) | libepoxy https://github.com/anholt/libepoxy | `1.5.10` (SHA-256 pinned) | MIT |
| `virgl/patches/` | Termux's `virglrenderer-android` patches (https://github.com/termux/termux-packages, `packages/virglrenderer-android`) | as of 2026-10-23 | MIT (DXTn decoder: see `virgl/COPYING-gl4es`) |

`ddtool/ddtool.c` is ours: the installer's helper, `ddtool zstdcat <file>`
(stream-decompress the system image) and `ddtool verify <pubkey> <file> <sig>`
(check its minisign signature, prehashed `ED` format only).

`gpureport/gpureport.c` is ours: prints the phone's OpenGL ES, ANGLE and
Vulkan driver details for Settings → GPU report, including the Vulkan
extensions GPU forwarding (Venus) depends on.

`virgl/build.sh` builds virglrenderer's vtest server for Android with meson
and the NDK (needs `meson`, `ninja`, `pkg-config`, `python3`). It downloads the
two source tarballs once into `~/.cache/deskdroid` and checks their SHA-256.
Linux apps reach it through Mesa's virgl driver (`GALLIUM_DRIVER=virpipe`) on
`/tmp/.virgl_test`; it renders with the vendor's OpenGL ES or the system's ANGLE.
The patches make it build and run on Android (EGL without GBM, ashmem instead
of memfd, ANGLE loading, DXTn texture decoding). Our change to Termux's 0007:
ANGLE is loaded from `angle/` relative to the server's working directory
(`VirglServer.kt` links that to the system's ANGLE) and the default socket is
`/tmp/.virgl_test`.

`talloc/shim/replace.h` is ours: a small stand-in for Samba's `lib/replace`, so
talloc builds without Samba's waf configure step.

Local changes to vendored sources (keep them when updating):
- `proot/src/extension/ashmem_memfd/ashmem_memfd.c`: adds `#include <string.h>`,
  which NDK clang requires.

Outputs (`app/build/generated/nativeTools/lib/arm64-v8a/`):
- `libproot.so`: the proot executable
- `libproot-loader.so`: proot's loader (found through `PROOT_LOADER`)
- `libtalloc.so`: talloc shared library proot links against
- `libddtool.so`: the installer helper above
- `libgpureport.so`: the GPU report tool (NDK builds only)
- `libvirgl_test_server.so`: the virgl server (NDK builds only)

To update a vendored source, replace the files from the new upstream version
and change the table above. Local build without the NDK uses the host
compiler and only proves the sources compile: `native/build.sh /tmp/out`.
