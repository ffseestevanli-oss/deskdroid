#!/usr/bin/env bash
# Builds a DeskDroid Debian arm64 rootfs as a .tar.xz plus .sha256.
# Run as root on an arm64 machine (CI uses GitHub's ubuntu-24.04-arm runner).
# Usage: sudo rootfs/build-rootfs.sh <light|full|ultralite> [outdir]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
EDITION="${1:?usage: build-rootfs.sh <light|full|ultralite> [outdir]}"
OUT="${2:-$HERE/out}"
SUITE=trixie
NAME=deskdroid-rootfs-$EDITION-arm64
mkdir -p "$OUT"

case "$EDITION" in
  ultralite) LISTS="base ultralite" ;;
  light)     LISTS="base plasma" ;;
  full)      LISTS="base plasma full" ;;
  *) echo "unknown edition: $EDITION" >&2; exit 1 ;;
esac
PKGS="$(for l in $LISTS; do cat "$HERE/packages/$l.txt"; done | grep -Ev '^\s*(#|$)' | paste -sd, -)"

mmdebstrap \
  --arch=arm64 \
  --variant=apt \
  --components=main \
  --aptopt='APT::Install-Recommends "false"' \
  --include="$PKGS" \
  --customize-hook='chroot "$1" useradd -m -u 1000 -s /bin/bash -G sudo deskdroid' \
  --customize-hook='echo "deskdroid ALL=(ALL) NOPASSWD:ALL" > "$1/etc/sudoers.d/deskdroid"' \
  --customize-hook='chmod 440 "$1/etc/sudoers.d/deskdroid"' \
  --customize-hook='echo deskdroid > "$1/etc/hostname"' \
  --customize-hook="mkdir -p \"\$1/etc/deskdroid\" && echo $EDITION > \"\$1/etc/deskdroid/edition\"" \
  --customize-hook="sync-in $HERE/overlay /" \
  --customize-hook='rm -f "$1/usr/share/wallpapers/DeskDroid/contents/images/README.md"' \
  --customize-hook='chmod 755 "$1"/usr/local/bin/deskdroid-*' \
  --customize-hook='echo "en_US.UTF-8 UTF-8" > "$1/etc/locale.gen" && chroot "$1" locale-gen' \
  --customize-hook='mkdir -p "$1/home/deskdroid/.config" && printf "[Basic Settings]\nIndexing-Enabled=false\n" > "$1/home/deskdroid/.config/baloofilerc"' \
  --customize-hook='printf "[General]\nsystemdBoot=false\n" > "$1/home/deskdroid/.config/startkderc"' \
  --customize-hook='chroot "$1" chown -R deskdroid:deskdroid /home/deskdroid' \
  --customize-hook='rm -rf "$1"/var/cache/apt/archives/*.deb "$1"/var/lib/apt/lists/* "$1"/usr/share/doc/* "$1"/usr/share/man/*' \
  "$SUITE" "$OUT/$NAME.tar"

xz -T0 -6 -f "$OUT/$NAME.tar"
( cd "$OUT" && sha256sum "$NAME.tar.xz" > "$NAME.tar.xz.sha256" )
ls -lh "$OUT"
