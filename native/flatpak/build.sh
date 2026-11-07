#!/usr/bin/env bash
# Builds the flatpak command for DeskDroid from Debian's arm64 packages, so
# Flathub apps install without proot (README.md).
#
#   native/flatpak/build.sh <outdir>
#
# Installs into <outdir>:
#   libdd_flatpakcli.so  a zip of flatpak, OSTree, gpg and their libraries
#                        (Debian trixie, arm64), which the app unpacks into
#                        files/flatpak-cli; they run on DeskDroid's glibc
#   libdd_flatpak.so     the flatpak command (flatpak.sh): installs and
#                        updates with flatpak itself, runs apps with ddflatpak
#   libdd_nobwrap.so     stands in for bubblewrap, which Android can't run
#   libddflatpak.so      ddflatpak.c built against glibc (aarch64)
# The packages are cached in $DESKDROID_FLATPAK_CACHE (default
# ~/.cache/deskdroid/flatpak), keyed by this folder's contents.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
MIRROR=https://deb.debian.org/debian
SUITE=trixie
ROOTS="flatpak gpg gpgconf libgcc-s1 libstdc++6 ca-certificates"
CROSS="${CROSS:-aarch64-linux-gnu-}"
command -v "${CROSS}gcc" >/dev/null || { echo "flatpak: no ${CROSS}gcc, skipped" >&2; exit 0; }
command -v dpkg-deb >/dev/null || { echo "flatpak: no dpkg-deb, skipped" >&2; exit 0; }

key="$(cat "$HERE/build.sh" "$HERE/debs.py" "$HERE/unlink.py" | sha256sum | cut -c1-16)"
CACHE="${DESKDROID_FLATPAK_CACHE:-$HOME/.cache/deskdroid/flatpak}/$key"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ ! -e "$CACHE/.done" ]; then
  echo "== flatpak (Debian $SUITE arm64)"
  curl -sSfL -o "$WORK/Packages.xz" "$MIRROR/dists/$SUITE/main/binary-arm64/Packages.xz"
  xz -d "$WORK/Packages.xz"
  python3 -I "$HERE/debs.py" "$WORK/Packages" "$MIRROR" $ROOTS > "$WORK/list"
  mkdir -p "$WORK/debs" "$WORK/root"
  while read -r url sum; do
    f="$WORK/debs/${url##*/}"
    curl -sSfL --retry 3 -o "$f" "$url"
    echo "$sum  $f" | sha256sum -c --quiet - || { echo "flatpak: $url: bad checksum" >&2; exit 1; }
    dpkg-deb -x "$f" "$WORK/root"
  done < "$WORK/list"
  R="$WORK/root"
  # Only what runs: no documentation, translations or headers.
  rm -rf "$R/usr/share/doc" "$R/usr/share/man" "$R/usr/share/info" "$R/usr/share/locale" \
    "$R/usr/share/lintian" "$R/usr/share/bash-completion" "$R/usr/share/zsh" "$R/usr/share/fish" \
    "$R/usr/include" "$R/usr/lib/systemd" "$R/usr/lib/sysusers.d" "$R/usr/lib/tmpfiles.d" "$R/etc/profile.d"
  # update-ca-certificates' bundle (a package script makes it on Debian).
  mkdir -p "$R/etc/ssl/certs"
  find "$R/usr/share/ca-certificates" -name '*.crt' | sort | xargs cat > "$R/etc/ssl/certs/ca-certificates.crt"
  # Java's unzip (the app's) can't make symlinks: each link becomes the file it
  # points at (moved, not copied, when only one link points at it).
  python3 -I "$HERE/unlink.py" "$R"
  find "$R" -name '*.a' -delete
  awk '{print $1}' "$WORK/list" | sed 's|.*/||' > "$R/usr/share/deskdroid-flatpak-packages.txt"
  rm -rf "$CACHE" && mkdir -p "$CACHE" && cp -a "$R/." "$CACHE/" && touch "$CACHE/.done"
fi

rm -f "$OUT/libdd_flatpakcli.so"
(cd "$CACHE" && zip -qr -X "$OUT/libdd_flatpakcli.so" usr etc)
install -m 755 "$HERE/flatpak.sh" "$OUT/libdd_flatpak.so"
install -m 755 "$HERE/nobwrap.sh" "$OUT/libdd_nobwrap.so"
"${CROSS}gcc" -O2 -Wall -Wextra -shared -fPIC -ffile-prefix-map="$HERE/..=." "$HERE/../ddmask/ddflatpak.c" -ldl \
  -Wl,-soname,libddflatpak.so -Wl,--build-id=none -Wl,-z,noexecstack -o "$OUT/libddflatpak.so"
"${CROSS}strip" --strip-unneeded "$OUT/libddflatpak.so"
echo "   flatpak: $(du -h "$OUT/libdd_flatpakcli.so" | cut -f1) ($(wc -l < "$CACHE/usr/share/deskdroid-flatpak-packages.txt") Debian packages)"
