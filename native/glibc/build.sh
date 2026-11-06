#!/usr/bin/env bash
# Builds glibc for DeskDroid, so ddmask can run glibc (ordinary Linux) programs
# without proot. See README.md.
#
#   native/glibc/build.sh <outdir>
#
# Needs a cross compiler for aarch64 glibc (Debian/Ubuntu: gcc-aarch64-linux-gnu;
# glibc builds with GCC only), bison, gawk, python3 and git. Installs into <outdir>:
#   libdd_ld-glibc.so   glibc's loader, which ddmask runs glibc programs through
#   libddmask_glibc.so  ddmask built against glibc, preloaded into them
#   libdd_glibc.so      a zip of glibc's libraries and settings, which the app
#                       unpacks into files/glibc (the prefix glibc is built for)
# A finished glibc build is kept in $DESKDROID_GLIBC_CACHE (default
# ~/.cache/deskdroid/glibc), keyed by this folder's contents.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
VERSION=2.41
COMMIT=74f59e9271cbb4071671e5a474e7d4f1622b186f # tag glibc-2.41
REPO=https://github.com/bminor/glibc # mirror of sourceware.org/git/glibc.git
PREFIX=/data/data/io.deskdroid.app/files/glibc
CROSS="${CROSS:-aarch64-linux-gnu-}"
command -v "${CROSS}gcc" >/dev/null || { echo "glibc: no ${CROSS}gcc, skipped" >&2; exit 0; }

key="$(cat "$HERE/build.sh" "$HERE/patch.py" | sha256sum | cut -c1-16)"
CACHE="${DESKDROID_GLIBC_CACHE:-$HOME/.cache/deskdroid/glibc}/$key"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ ! -e "$CACHE/.done" ]; then
  echo "== glibc $VERSION"
  git -c advice.detachedHead=false clone -q --depth 1 --branch "glibc-$VERSION" "$REPO" "$WORK/src"
  [ "$(git -C "$WORK/src" rev-parse HEAD)" = "$COMMIT" ] || { echo "glibc: tag glibc-$VERSION isn't $COMMIT" >&2; exit 1; }
  python3 "$HERE/patch.py" "$WORK/src" "$PREFIX"
  mkdir -p "$WORK/build"
  (cd "$WORK/build" && "$WORK/src/configure" --host=aarch64-linux-gnu --build="$(uname -m)-linux-gnu" \
    --prefix="$PREFIX" libc_cv_slibdir="$PREFIX/lib" CC="${CROSS}gcc" CXX="${CROSS}g++" \
    --enable-kernel=4.14 --disable-werror --disable-nscd --disable-build-nscd --disable-timezone-tools \
    --disable-profile --without-selinux --disable-sanity-checks > configure.log)
  make -C "$WORK/build" -j"$(nproc)" > "$WORK/make.log" 2>&1 || { tail -60 "$WORK/make.log"; exit 1; }
  make -C "$WORK/build" install DESTDIR="$WORK/stage" > "$WORK/install.log" 2>&1 || { tail -40 "$WORK/install.log"; exit 1; }
  rm -rf "$CACHE" && mkdir -p "$CACHE" && cp -a "$WORK/stage$PREFIX/." "$CACHE/"
  touch "$CACHE/.done"
fi

# Runtime: the shared libraries (not static ones or headers, which only building
# against glibc needs), gconv's modules, and settings for an Android phone.
R="$WORK/runtime"
mkdir -p "$R/lib" "$R/etc" "$R/tmp"
# Only real files: the unversioned names are symlinks or linker scripts for
# building, and the app's unzip (Java's) can't make symlinks.
find "$CACHE/lib" -maxdepth 1 -name '*.so.*' -type f -exec cp {} "$R/lib/" \;
[ -d "$CACHE/lib/gconv" ] && cp -rL "$CACHE/lib/gconv" "$R/lib/"
# nsswitch: files only (the app writes passwd, group and hosts), DNS for host names.
printf 'passwd: files\ngroup: files\nshadow: files\nhosts: files dns\nnetworks: files\nprotocols: files\nservices: files\n' > "$R/etc/nsswitch.conf"
printf '127.0.0.1 localhost\n::1 localhost\n' > "$R/etc/hosts"
for f in "$R"/lib/*.so* "$R"/lib/gconv/*.so; do [ -f "$f" ] && "${CROSS}strip" --strip-unneeded "$f" 2>/dev/null || true; done
rm -f "$OUT/libdd_glibc.so"
(cd "$R" && zip -qr -X "$OUT/libdd_glibc.so" .)

# The loader, in the APK's library folder: Android runs it, it loads the program.
install -m 755 "$CACHE/lib/ld-linux-aarch64.so.1" "$OUT/libdd_ld-glibc.so"
"${CROSS}strip" --strip-unneeded "$OUT/libdd_ld-glibc.so"

# ddmask for glibc programs (DDMASK_GLIBC: Android's folders, glibc's variables).
"${CROSS}gcc" -O2 -Wall -Wextra -shared -fPIC -DDDMASK_GLIBC -ffile-prefix-map="$HERE/..=." \
  "$HERE/../ddmask/ddmask.c" -Wl,-soname,libddmask_glibc.so -Wl,--build-id=none -Wl,-z,noexecstack \
  -o "$OUT/libddmask_glibc.so"
"${CROSS}strip" --strip-unneeded "$OUT/libddmask_glibc.so"
echo "   glibc: $(du -h "$OUT/libdd_glibc.so" | cut -f1) runtime, loader and ddmask"
