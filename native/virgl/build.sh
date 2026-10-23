#!/usr/bin/env bash
# Builds virglrenderer's vtest server and render server (libepoxy linked in
# statically) for Android with the NDK, and installs them as lib*.so files in
# <outdir> so they can be exec'd from nativeLibraryDir.
#
# Linux apps in the rootfs use Mesa's Venus Vulkan driver (VN_DEBUG=vtest),
# with Zink for OpenGL, which sends Vulkan commands over /tmp/.virgl_test to
# this server; it runs them on Android's Vulkan driver (see native/README.md).
#
#   native/virgl/build.sh <outdir> <ndk-dir> [api-level]
# Needs meson, ninja, pkg-config and python3. Sources are downloaded once
# (pinned by SHA-256) into $DESKDROID_SRC_CACHE, default ~/.cache/deskdroid.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
NDK="$2"
API="${3:-29}"

VIRGL_VERSION=1.3.0
VIRGL_URL="https://gitlab.freedesktop.org/virgl/virglrenderer/-/archive/virglrenderer-$VIRGL_VERSION/virglrenderer-virglrenderer-$VIRGL_VERSION.tar.gz"
VIRGL_SHA256=56170f8caa1bb642a2624b649e3bcca095ec2834814e5c308efc8a85a709e4ce
EPOXY_VERSION=1.5.10
EPOXY_URL="https://github.com/anholt/libepoxy/archive/refs/tags/$EPOXY_VERSION.tar.gz"
EPOXY_SHA256=a7ced37f4102b745ac86d6a70a9da399cc139ff168ba6b8002b4d8d43c900c15

for tool in meson ninja pkg-config python3; do
  command -v "$tool" >/dev/null || { echo "virgl: $tool not found (pip install meson ninja)" >&2; exit 1; }
done

CACHE="${DESKDROID_SRC_CACHE:-$HOME/.cache/deskdroid}"
mkdir -p "$CACHE"
fetch() { # url sha256 file
  local f="$CACHE/$3"
  if ! echo "$2  $f" | sha256sum -c --status 2>/dev/null; then
    curl -fL --retry 4 -o "$f.part" "$1"
    echo "$2  $f.part" | sha256sum -c --status || { echo "virgl: checksum mismatch for $1" >&2; exit 1; }
    mv "$f.part" "$f"
  fi
  echo "$f"
}
virgl_tar="$(fetch "$VIRGL_URL" "$VIRGL_SHA256" "virglrenderer-$VIRGL_VERSION.tar.gz")"
epoxy_tar="$(fetch "$EPOXY_URL" "$EPOXY_SHA256" "libepoxy-$EPOXY_VERSION.tar.gz")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SRC="$WORK/src"
mkdir -p "$SRC/libepoxy"
tar -xzf "$virgl_tar" -C "$SRC" --strip-components=1
tar -xzf "$epoxy_tar" -C "$SRC/libepoxy" --strip-components=1
# The patches expect libepoxy inside the virglrenderer tree, as in Termux.
for p in "$HERE"/patches/*.patch; do
  echo "== patch $(basename "$p")"
  patch -d "$SRC" -p1 --forward --quiet < "$p"
done

host="$(uname -s | tr A-Z a-z)-x86_64"
BIN="$NDK/toolchains/llvm/prebuilt/$host/bin"
PREFIX="$WORK/prefix"
cat > "$WORK/cross.ini" <<EOF
[binaries]
c = '$BIN/aarch64-linux-android$API-clang'
cpp = '$BIN/aarch64-linux-android$API-clang++'
ar = '$BIN/llvm-ar'
strip = '$BIN/llvm-strip'
pkg-config = 'pkg-config'

[built-in options]
c_args = ['-ffile-prefix-map=$WORK=.']
c_link_args = ['-Wl,--build-id=none', '-Wl,-z,noexecstack']

[properties]
pkg_config_libdir = '$PREFIX/lib/pkgconfig'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8-a'
endian = 'little'
EOF
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" PKG_CONFIG_PATH=

echo "== libepoxy"
meson setup "$WORK/epoxy-build" "$SRC/libepoxy" --cross-file "$WORK/cross.ini" \
  --prefix="$PREFIX" --libdir=lib --buildtype=release -Ddefault_library=static \
  -Degl=yes -Dglx=no -Dx11=false -Dtests=false
ninja -C "$WORK/epoxy-build" install

# Venus runs inside virglrenderer's render server, which the vtest server
# execs from <prefix>/libexec. Android only lets us exec from nativeLibraryDir,
# whose path isn't known at build time, so the prefix is /proc/self/cwd: the
# server's working directory (VenusServer.kt) holds libexec/virgl_render_server
# as a link to the right lib*.so.
# Two builds: "dmabuf" is upstream Venus (needs VK_EXT_external_memory_dma_buf,
# e.g. PowerVR on the Pixel 10); "ahb" adds patch 0011 for drivers that can only
# share memory as AHardwareBuffers (common on Mali).
for variant in dmabuf ahb; do
  echo "== virglrenderer ($variant)"
  extra=()
  [ "$variant" = ahb ] && extra=(-Dc_args="-ffile-prefix-map=$WORK=. -DDESKDROID_VENUS_AHB")
  meson setup "$WORK/virgl-$variant" "$SRC" --cross-file "$WORK/cross.ini" \
    --prefix=/proc/self/cwd --libdir=lib --buildtype=release -Ddefault_library=static \
    -Dplatforms=egl -Dvenus=true -Dtests=false "${extra[@]}"
  ninja -C "$WORK/virgl-$variant"
  suffix=""; [ "$variant" = ahb ] && suffix="_ahb"
  install -m 755 "$WORK/virgl-$variant/vtest/virgl_test_server" "$OUT/libvirgl_test_server$suffix.so"
  rs="$WORK/virgl-$variant/server/virgl_render_server"
  if [ -f "$rs" ]; then
    install -m 755 "$rs" "$OUT/libvirgl_render_server$suffix.so"
  fi
done
"$BIN/llvm-strip" --strip-unneeded "$OUT"/libvirgl_*.so
ls -l "$OUT"/libvirgl_*.so
