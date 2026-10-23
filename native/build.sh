#!/usr/bin/env bash
# Builds libtalloc, proot, proot's loader and ddtool from the vendored sources in
# native/ and installs them as lib*.so files, so Android puts them in the
# app's executable nativeLibraryDir (W^X rule for targetSdk 29+).
#
# Called by the :app Gradle build (task buildNativeTools) with the NDK, and
# usable on its own:
#   native/build.sh <outdir> [ndk-dir] [api-level]
# Without an NDK it builds with the host compiler, which only proves the
# sources and this script work (the result won't run on Android).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
NDK="${2:-}"
API="${3:-29}"
# Scratch space outside OUT: Gradle packages every file under the jniLibs dir.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/talloc" "$WORK/proot"

if [ -n "$NDK" ]; then
  host="$(uname -s | tr A-Z a-z)-x86_64"
  BIN="$NDK/toolchains/llvm/prebuilt/$host/bin"
  CC="$BIN/aarch64-linux-android$API-clang"
  STRIP="$BIN/llvm-strip"; OBJCOPY="$BIN/llvm-objcopy"; OBJDUMP="$BIN/llvm-objdump"
else
  CC="${CC:-clang}"; STRIP=strip; OBJCOPY=objcopy; OBJDUMP=objdump
fi
[ -x "$(command -v "$CC")" ] || { echo "compiler not found: $CC" >&2; exit 1; }

# Reproducible output: no build paths or timestamps in the binaries.
REPRO="-ffile-prefix-map=$HERE=. -ffile-prefix-map=$WORK=."
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"

echo "== talloc"
"$CC" -O2 -fPIC -Wall $REPRO \
  -I"$HERE/talloc/shim" -I"$HERE/talloc" \
  -DTALLOC_BUILD_VERSION_MAJOR=2 -DTALLOC_BUILD_VERSION_MINOR=4 -DTALLOC_BUILD_VERSION_RELEASE=3 \
  -c "$HERE/talloc/talloc.c" -o "$WORK/talloc/talloc.o"
"$CC" -shared -Wl,-soname,libtalloc.so -Wl,--build-id=none -Wl,-z,noexecstack \
  -o "$WORK/talloc/libtalloc.so" "$WORK/talloc/talloc.o"

echo "== proot"
# PROOT_UNBUNDLE_LOADER keeps the loader a separate file; at run time the app
# points PROOT_LOADER at libproot-loader.so in nativeLibraryDir.
# The makefile's out-of-tree mode is broken, so build in a copy of the tree.
cp -r "$HERE/proot/src/." "$WORK/proot/"
# Flags go in the environment, not on the make command line, so the
# makefile's own "CFLAGS +=" lines (e.g. for PROOT_UNBUNDLE_LOADER) still apply.
CPPFLAGS="-D_FILE_OFFSET_BITS=64 -D_GNU_SOURCE -I. -I$HERE/talloc" \
CFLAGS="-Wall -Wextra -O2 $REPRO" \
LDFLAGS="-L$WORK/talloc -ltalloc -Wl,-z,noexecstack -Wl,--build-id=none" \
make -C "$WORK/proot" -j"$(nproc)" \
  CC="$CC" STRIP="$STRIP" OBJCOPY="$OBJCOPY" OBJDUMP="$OBJDUMP" GIT=false \
  PROOT_UNBUNDLE_LOADER=/nonexistent \
  proot loader/loader

echo "== ddtool"
# zstd decoder + minisign check used by the installer (ddtool/ddtool.c).
mkdir -p "$WORK/ddtool"
"$CC" -O2 -Wall $REPRO -DZSTD_DISABLE_ASM -DZSTD_LEGACY_SUPPORT=0 -DDEBUGLEVEL=0 \
  -I"$HERE/zstd" -I"$HERE/zstd/common" -I"$HERE/monocypher" \
  "$HERE/ddtool/ddtool.c" \
  "$HERE"/zstd/common/*.c "$HERE"/zstd/decompress/*.c \
  "$HERE/monocypher/monocypher.c" "$HERE/monocypher/monocypher-ed25519.c" \
  -Wl,--build-id=none -Wl,-z,noexecstack -o "$WORK/ddtool/ddtool"

install -m 755 "$WORK/ddtool/ddtool" "$OUT/libddtool.so"
install -m 755 "$WORK/proot/proot" "$OUT/libproot.so"
install -m 755 "$WORK/proot/loader/loader" "$OUT/libproot-loader.so"
install -m 644 "$WORK/talloc/libtalloc.so" "$OUT/libtalloc.so"
"$STRIP" --strip-unneeded "$OUT/libproot.so" "$OUT/libtalloc.so" "$OUT/libddtool.so"
ls -l "$OUT"
