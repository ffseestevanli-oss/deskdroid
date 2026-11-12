#!/usr/bin/env bash
# Builds the store packages (.adpk) in apps.txt from Flathub's ARM64 builds:
#   tools/flathub-adpk/build.sh <out dir> [store id...]
# Needs flatpak (any architecture: it only downloads), readelf, rsvg-convert
# and the Android NDK ($ANDROID_NDK_HOME) for ddapp.c. Flathub's files are
# kept in $FLATPAK_USER_DIR (default ~/.cache/deskdroid/flathub-adpk).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"; shift
want=" $* "
export FLATPAK_USER_DIR="${FLATPAK_USER_DIR:-$HOME/.cache/deskdroid/flathub-adpk}"
CC="$(ls -d "${ANDROID_NDK_HOME:?}"/toolchains/llvm/prebuilt/linux-x86_64/bin)/aarch64-linux-android26-clang"
export DDAPP_BIN="$OUT/.ddapp"
"$CC" -O2 -Wall -fPIE -pie -s -o "$DDAPP_BIN" "$HERE/ddapp.c"
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
I="flatpak install --user --arch=aarch64 --noninteractive -y --no-related flathub"
P="python3 $HERE/flathub-adpk.py"
pick() { [ "$want" = "  " ] || [[ "$want" == *" $1 "* ]]; }

$I runtime/org.freedesktop.Platform/aarch64/25.08 runtime/org.kde.Platform/aarch64/6.11 runtime/org.gnome.Platform/aarch64/50 \
   runtime/org.freedesktop.Platform.GL.default/aarch64/25.08 runtime/org.freedesktop.Platform.codecs-extra/aarch64/25.08-extra
pick runtime-mesa-25.08 && $P mesa "$FLATPAK_USER_DIR" 25.08 runtime-mesa-25.08 "$OUT/runtime-mesa-25.08.adpk"
pick runtime-freedesktop-25.08 && $P runtime "$FLATPAK_USER_DIR" org.freedesktop.Platform/aarch64/25.08 runtime-freedesktop-25.08 \
  "$OUT/runtime-freedesktop-25.08.adpk" --name "Freedesktop runtime 25.08" --summary "Shared libraries for Flathub apps"
pick runtime-kde-6.11 && $P runtime "$FLATPAK_USER_DIR" org.kde.Platform/aarch64/6.11 runtime-kde-6.11 \
  "$OUT/runtime-kde-6.11.adpk" --name "KDE runtime 6.11" --summary "Qt 6 and KDE Frameworks for Flathub apps"
pick runtime-gnome-50 && $P runtime "$FLATPAK_USER_DIR" org.gnome.Platform/aarch64/50 runtime-gnome-50 \
  "$OUT/runtime-gnome-50.adpk" --name "GNOME runtime 50" --summary "GTK and GNOME libraries for Flathub apps"

grep -v '^#' "$HERE/apps.txt" | while read -r fpid sid rt commit; do
  [ -n "$fpid" ] && pick "$sid" || continue
  if [ -n "${commit:-}" ]; then
    # Pinned: a newer build moved to a runtime this set doesn't carry.
    $I --no-deps "$fpid" || true
    flatpak update --user --arch=aarch64 --noninteractive -y --no-related --no-deps --commit="$commit" "$fpid"
  else
    $I "$fpid"
  fi
  $P app "$FLATPAK_USER_DIR" "$fpid" "$sid" "$rt" "$OUT/$sid.adpk"
done
rm -f "$DDAPP_BIN"
