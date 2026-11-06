#!/usr/bin/env bash
# Builds the x86 system FEX runs programs in on DeskDroid's native desktop
# (no proot): FEX's own Ubuntu 24.04 image, unpacked, made ready to use
# without FEX's FUSE mount, with Xwayland added (Steam's window is X11 and
# the native desktop has no X server), packed as a .tar.zst the app unpacks.
# Run on x86-64 Ubuntu or Debian as root (it chroots into the image to
# install packages; CI uses GitHub's ubuntu-24.04 runner).
# Usage: fex/rootfs.sh [outdir]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/out}"
NAME=deskdroid-x86-rootfs
# FEX's image (from https://rootfs.fex-emu.gg/RootFS_links.json) and its
# XXH3-64 hash from that list, which FEXRootFSFetcher checks too.
IMAGE_URL=https://rootfs.fex-emu.gg/Ubuntu_24_04/2026-08-11/Ubuntu_24_04.sqsh
IMAGE_XXH3=3517e0e5ea25a473
# Added to FEX's image: Xwayland for X11 programs (Steam), and what Steam's
# launcher uses that the image may lack.
PACKAGES="xwayland x11-utils x11-xserver-utils xauth xdg-utils fonts-dejavu-core fonts-liberation"
WORK="$(mktemp -d)"
ROOT="$WORK/root"
cleanup() {
  for m in dev/pts dev proc sys; do umountpoint "$ROOT/$m"; done
  rm -rf "$WORK"
}
umountpoint() { mountpoint -q "$1" 2>/dev/null && umount -l "$1" || true; }
trap cleanup EXIT
mkdir -p "$OUT"

apt-get update -q
apt-get install -y -q --no-install-recommends ca-certificates curl squashfs-tools xxhash zstd

echo "downloading $IMAGE_URL"
curl -fL --retry 3 -o "$WORK/image.sqsh" "$IMAGE_URL"
hash=$(xxhsum -H3 "$WORK/image.sqsh")
echo "xxh3: $hash"
case "$hash" in
  *"$IMAGE_XXH3"*) ;;
  *) echo "the image doesn't match FEX's hash $IMAGE_XXH3"; exit 1 ;;
esac
unsquashfs -q -no-progress -d "$ROOT" "$WORK/image.sqsh"
rm "$WORK/image.sqsh"

# FEX's images keep the files that should come from the host (passwd, hosts,
# resolv.conf, /tmp, /home...) in /chroot ("broken" for FEX's overlay of the
# host). On Android the host has none of them, so they go back in place; the
# app writes passwd, group, hosts and resolv.conf for the phone at each start.
if [ -d "$ROOT/chroot" ]; then
  cp -a "$ROOT/chroot/." "$ROOT/"
  rm -rf "$ROOT/chroot"
fi
# FEX's own files in the image (a server socket config for its chroot tool).
rm -rf "$ROOT/usr/share/fex-emu" "$ROOT/fex"

# Install the extra packages in a chroot (this machine is x86-64).
mkdir -p "$ROOT/dev" "$ROOT/proc" "$ROOT/sys" "$ROOT/tmp"
chmod 1777 "$ROOT/tmp"
mount --bind /dev "$ROOT/dev"
mount --bind /dev/pts "$ROOT/dev/pts"
mount -t proc proc "$ROOT/proc"
mount -t sysfs sys "$ROOT/sys"
rm -f "$ROOT/etc/resolv.conf"
cp /etc/resolv.conf "$ROOT/etc/resolv.conf"
chroot "$ROOT" /usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin DEBIAN_FRONTEND=noninteractive HOME=/root \
  sh -c "apt-get update -q && apt-get install -y -q --no-install-recommends $PACKAGES && apt-get clean"
for m in dev/pts dev proc sys; do umountpoint "$ROOT/$m"; done
# FEX passes /dev, /proc and /sys through from the host only when the image
# has none of its own.
rm -rf "$ROOT/dev" "$ROOT/proc" "$ROOT/sys"
rm -rf "$ROOT/var/lib/apt/lists/"* "$ROOT/var/cache/apt" "$ROOT/tmp/"* "$ROOT/root/.cache"
# The base account files, which the app adds the phone's user to.
for f in passwd group; do cp "$ROOT/etc/$f" "$ROOT/etc/$f.deskdroid-base"; done
rm -f "$ROOT/etc/resolv.conf" "$ROOT/etc/hosts" "$ROOT/etc/machine-id" "$ROOT/var/lib/dbus/machine-id"
date -u +%Y-%m-%d > "$ROOT/etc/deskdroid-x86-version"
[ -x "$ROOT/usr/bin/Xwayland" ] || { echo "Xwayland didn't install"; exit 1; }
du -sh "$ROOT"

# Numeric owners don't matter on Android (every file is the app's); modes and
# symlinks do.
tar -C "$ROOT" --numeric-owner --owner=0 --group=0 -cf - . | zstd -T0 -15 -q -o "$OUT/$NAME.tar.zst"
( cd "$OUT" && sha256sum "$NAME.tar.zst" > "$NAME.tar.zst.sha256" && date -u +%Y-%m-%d > "$NAME.version" )
# Entries in the archive, for the app's progress bar while it unpacks.
find "$ROOT" | wc -l > "$OUT/$NAME.files"
ls -lh "$OUT"
