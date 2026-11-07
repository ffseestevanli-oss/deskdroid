#!/usr/bin/env bash
# Packs fex/build.sh's output (and fex/rootfs.sh's, when it's in the same
# folder) into one .zip that the Steam Installation Assistant installs from
# ("Install from a .zip", X86.kt): FEX-Emu without a download host.
# Stored, not deflated: the files inside are zstd already.
# Usage: fex/zip.sh <folder with deskdroid-fex-arm64.*> [out.zip] [--no-rootfs]
set -euo pipefail
DIR="$(cd "$1" && pwd)"
version="$(cat "$DIR/deskdroid-fex-arm64.version")"
files=(deskdroid-fex-arm64.tar.zst deskdroid-fex-arm64.tar.zst.sha256 deskdroid-fex-arm64.version)
suffix=""
if [ "${3:-}" != --no-rootfs ] && [ -e "$DIR/deskdroid-x86-rootfs.tar.zst" ]; then
  for f in "$DIR"/deskdroid-x86-rootfs.*; do files+=("$(basename "$f")"); done
  suffix="-with-x86-system"
fi
OUT="${2:-$DIR/deskdroid-fex-$version$suffix.zip}"
rm -f "$OUT"
(cd "$DIR" && zip -0 -q -X "$OUT" "${files[@]}")
ls -lh "$OUT"
