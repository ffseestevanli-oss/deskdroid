#!/usr/bin/env bash
# Builds FEX-Emu (x86 and x86-64 emulation for Steam and other x86 Linux apps)
# for DeskDroid's Debian trixie arm64 rootfs and packs it as a .tar.zst that
# unpacks at / (everything under /usr/local). Debian doesn't package FEX.
# Run on arm64 Debian trixie (CI uses a debian:trixie container on GitHub's
# ubuntu-24.04-arm runner), as root so it can install the build tools.
# Usage: fex/build.sh [outdir]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/out}"
TAG="$(cat "$HERE/VERSION")"
NAME=deskdroid-fex-arm64
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

apt-get update -q
apt-get install -y -q --no-install-recommends \
  ca-certificates git cmake ninja-build clang clang-tools lld llvm python3 pkg-config zstd file

git clone -q --depth 1 -b "$TAG" https://github.com/FEX-Emu/FEX.git "$WORK/src"
git -C "$WORK/src" submodule update -q --init --depth 1

# TUNE_CPU=none builds for baseline ARMv8.0 (+crc), so one build runs on every
# phone; FEX's JIT picks the newer CPU features it finds at run time.
# No thunks or FEXConfig (Qt) for now: games use the x86 Mesa in FEX's rootfs.
cmake -S "$WORK/src" -B "$WORK/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DUSE_LINKER=lld \
  -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_INSTALL_LIBDIR=lib \
  -DTUNE_CPU=none -DCMAKE_CXX_SCAN_FOR_MODULES=OFF \
  -DENABLE_LTO=True -DENABLE_ASSERTIONS=False -DENABLE_CCACHE=False \
  -DBUILD_TESTING=False -DBUILD_THUNKS=False -DBUILD_FEXCONFIG=False
cmake --build "$WORK/build"
DESTDIR="$WORK/root" cmake --install "$WORK/build"

# Without root there's no binfmt_misc; the launchers run FEX directly.
rm -rf "$WORK/root/usr/local/share/binfmts" "$WORK/root/usr/local/share/man"
mkdir -p "$WORK/root/usr/local/share/deskdroid-fex"
echo "$TAG" > "$WORK/root/usr/local/share/deskdroid-fex/version"
file "$WORK/root/usr/local/bin/FEX"
"$WORK/root/usr/local/bin/FEX" --version || true
find "$WORK/root" -not -type d | sort

tar -C "$WORK/root" --owner=0 --group=0 -cf - usr | zstd -T0 -19 -q -o "$OUT/$NAME.tar.zst"
( cd "$OUT" && sha256sum "$NAME.tar.zst" > "$NAME.tar.zst.sha256" && echo "$TAG" > "$NAME.version" )
ls -lh "$OUT"
