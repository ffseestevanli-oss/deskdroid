#!/usr/bin/env bash
# Fetches proot (+ its loader and libtalloc) built for Android by Termux and
# places them in app/src/main/jniLibs/arm64-v8a as lib*.so files, so Android
# installs them into the app's executable nativeLibraryDir.
#
# Needs: curl, dpkg-deb, patchelf, readelf. Runs in CI (see .github/workflows/android.yml).
set -euo pipefail

REPO=https://packages.termux.dev/apt/termux-main
ARCH=aarch64
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$ROOT/prebuilts-cache"
OUT="$ROOT/app/src/main/jniLibs/arm64-v8a"
mkdir -p "$CACHE" "$OUT"

curl -fsSL "$REPO/dists/stable/main/binary-$ARCH/Packages" -o "$CACHE/Packages"

deb_path() { # print the pool path of package $1
  awk -v pkg="$1" '$1=="Package:"{p=$2} p==pkg && $1=="Filename:"{print $2; exit}' "$CACHE/Packages"
}

for pkg in proot libtalloc; do
  path="$(deb_path "$pkg")"
  [ -n "$path" ] || { echo "package $pkg not found" >&2; exit 1; }
  echo "fetching $path"
  curl -fsSL "$REPO/$path" -o "$CACHE/$pkg.deb"
  rm -rf "$CACHE/$pkg"; dpkg-deb -x "$CACHE/$pkg.deb" "$CACHE/$pkg"
done

P="$CACHE/proot/data/data/com.termux/files/usr"
T="$CACHE/libtalloc/data/data/com.termux/files/usr"
install -m 755 "$P/bin/proot" "$OUT/libproot.so"
install -m 755 "$P/libexec/proot/loader" "$OUT/libproot-loader.so"
install -m 644 "$(ls "$T"/lib/libtalloc.so.2* | head -1)" "$OUT/libtalloc.so"

# Android only extracts lib*.so; point proot at the renamed talloc and drop Termux's RUNPATH.
patchelf --replace-needed libtalloc.so.2 libtalloc.so "$OUT/libproot.so"
patchelf --set-soname libtalloc.so "$OUT/libtalloc.so"
patchelf --remove-rpath "$OUT/libproot.so"

# Fail loudly if proot gained a dependency we don't ship.
allowed='libtalloc.so|libc.so|libdl.so|libm.so|liblog.so'
extra="$(readelf -d "$OUT/libproot.so" | awk '/NEEDED/{gsub(/[\[\]]/,"",$5); print $5}' | grep -Ev "^($allowed)$" || true)"
if [ -n "$extra" ]; then echo "proot needs libraries we don't ship: $extra" >&2; exit 1; fi

ls -l "$OUT"
