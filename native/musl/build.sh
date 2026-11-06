#!/usr/bin/env bash
# Builds musl for DeskDroid, so ddmask can run musl programs (Alpine's...)
# without proot. See README.md.
#
#   native/musl/build.sh <outdir> [--cache-dir]
#
# (--cache-dir: only build, and print the cached build's folder.)
# Needs an aarch64 cross compiler (Debian/Ubuntu: gcc-aarch64-linux-gnu; any
# aarch64 gcc builds musl), python3 and git. Installs into <outdir>:
#   libdd_ld-musl.so   musl (its loader and C library in one file), which ddmask
#                      runs musl programs through
#   libddmask_musl.so  ddmask built against musl, preloaded into them
# A finished musl build is kept in $DESKDROID_MUSL_CACHE (default
# ~/.cache/deskdroid/musl), keyed by this folder's scripts.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
VERSION=1.2.5
COMMIT=0784374d561435f7c787a555aeab8ede699ed298 # tag v1.2.5
REPO=https://github.com/kraj/musl # mirror of git.musl-libc.org/git/musl
PREFIX=/data/data/io.deskdroid.app/files/musl
CROSS="${CROSS:-aarch64-linux-gnu-}"
command -v "${CROSS}gcc" >/dev/null || { echo "musl: no ${CROSS}gcc, skipped" >&2; exit 0; }

key="$(cat "$HERE/build.sh" "$HERE/patch.py" | sha256sum | cut -c1-16)"
CACHE="${DESKDROID_MUSL_CACHE:-$HOME/.cache/deskdroid/musl}/$key"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ ! -e "$CACHE/.done" ]; then (
  exec >&2
  echo "== musl $VERSION"
  git -c advice.detachedHead=false clone -q --depth 1 --branch "v$VERSION" "$REPO" "$WORK/src"
  [ "$(git -C "$WORK/src" rev-parse HEAD)" = "$COMMIT" ] || { echo "musl: tag v$VERSION isn't $COMMIT" >&2; exit 1; }
  python3 "$HERE/patch.py" "$WORK/src" "$PREFIX"
  (cd "$WORK/src" && CROSS_COMPILE="$CROSS" ./configure --target=aarch64-linux-gnu \
    --prefix="$PREFIX" --syslibdir="$PREFIX/lib" > "$WORK/configure.log" \
    && make -j"$(nproc)" > "$WORK/make.log" 2>&1 \
    && make install DESTDIR="$WORK/stage" > "$WORK/install.log" 2>&1) || { tail -40 "$WORK"/*.log; exit 1; }
  rm -rf "$CACHE" && mkdir -p "$CACHE" && cp -a "$WORK/stage$PREFIX/." "$CACHE/"
  touch "$CACHE/.done"
) fi
[ "${2:-}" = --cache-dir ] && { echo "$CACHE"; exit 0; }

# A compiler for musl programs, from the cached headers and libraries (musl's
# own musl-gcc points at the phone's folder); used for ddmask and test/run.sh.
# Programs it builds ask for /lib/ld-musl-aarch64.so.1, as Alpine's do.
sed -e "s|$PREFIX/include|$CACHE/include|g" -e "s|$PREFIX/lib/ld-musl|/lib/ld-musl|g" \
  -e "s|$PREFIX/lib|$CACHE/lib|g" "$CACHE/lib/musl-gcc.specs" > "$CACHE/deskdroid-gcc.specs"
MUSLCC=("${CROSS}gcc" -specs "$CACHE/deskdroid-gcc.specs")

# musl's libc.so is its loader too: Android runs it from the APK, it loads the program.
install -m 755 "$CACHE/lib/libc.so" "$OUT/libdd_ld-musl.so"
"${CROSS}strip" --strip-unneeded "$OUT/libdd_ld-musl.so"

# ddmask for musl programs (DDMASK_MUSL: Android's folders, musl's variables).
"${MUSLCC[@]}" -O2 -Wall -Wextra -shared -fPIC -DDDMASK_MUSL -ffile-prefix-map="$HERE/..=." \
  "$HERE/../ddmask/ddmask.c" -Wl,-soname,libddmask_musl.so -Wl,--build-id=none -Wl,-z,noexecstack \
  -o "$OUT/libddmask_musl.so"
"${CROSS}strip" --strip-unneeded "$OUT/libddmask_musl.so"
echo "   musl: loader and ddmask"
