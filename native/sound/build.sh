#!/usr/bin/env bash
# Builds DeskDroid's sound server (README.md) from Debian's arm64 packages:
#   libdd_soundsrv.so   a zip of PipeWire, WirePlumber, PulseAudio's tools and
#                       only the libraries and modules they use, unpacked into
#                       files/sound by the app
#   libdd_sound.so      sound.sh, which runs it on DeskDroid's glibc
# The packages are cached in $DESKDROID_SOUND_CACHE (default
# ~/.cache/deskdroid/sound), keyed by this folder's contents.
#   native/sound/build.sh <outdir>
# DESKDROID_SOUND_DEBARCH=amd64 builds it for a desktop machine (test.sh).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
MIRROR=https://deb.debian.org/debian
SUITE=trixie
DEBARCH="${DESKDROID_SOUND_DEBARCH:-arm64}"
case "$DEBARCH" in arm64) TRIPLE=aarch64-linux-gnu ;; amd64) TRIPLE=x86_64-linux-gnu ;; *) echo "sound: $DEBARCH?" >&2; exit 1 ;; esac
command -v dpkg-deb >/dev/null || { echo "sound: no dpkg-deb, skipped" >&2; exit 0; }
command -v readelf >/dev/null || { echo "sound: no readelf, skipped" >&2; exit 0; }

key="$( { cat "$HERE/build.sh" "$HERE/closure.py" "$HERE/../flatpak/debs.py"; echo "$DEBARCH"; } | sha256sum | cut -c1-16)"
CACHE="${DESKDROID_SOUND_CACHE:-$HOME/.cache/deskdroid/sound}/$key"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ ! -e "$CACHE/.done" ]; then
  echo "== sound (Debian $SUITE $DEBARCH PipeWire)"
  curl -sSfL -o "$WORK/Packages.xz" "$MIRROR/dists/$SUITE/main/binary-$DEBARCH/Packages.xz"
  xz -d "$WORK/Packages.xz"
  python3 -I "$HERE/../flatpak/debs.py" "$WORK/Packages" "$MIRROR" \
    pipewire-bin pipewire-pulse wireplumber libpipewire-0.3-modules libspa-0.2-modules pulseaudio-utils > "$WORK/list"
  mkdir -p "$WORK/debs" "$WORK/all"
  while read -r url sum; do
    f="$WORK/debs/${url##*/}"
    curl -sSfL --retry 3 -o "$f" "$url"
    echo "$sum  $f" | sha256sum -c --quiet - || { echo "sound: $url: bad checksum" >&2; exit 1; }
    dpkg-deb -x "$f" "$WORK/all"
  done < "$WORK/list"
  # The packages pull in much more (FFADO, ROC, AVB, X11, ALSA for modules
  # DeskDroid doesn't load): keep only what the server, WirePlumber, the tools
  # and the modules below need, each library under the name it's asked for
  # (the app's unzip can't make symlinks).
  U="usr/lib/$TRIPLE"
  ( cd "$WORK/all"
    echo usr/bin/pipewire usr/bin/wireplumber usr/bin/wpctl usr/bin/pw-cli usr/bin/pw-dump usr/bin/pw-top \
      usr/bin/pw-link usr/bin/pw-metadata usr/bin/pw-cat usr/bin/pactl usr/bin/pacat
    for m in protocol-native profiler access metadata spa-node-factory spa-device-factory spa-node spa-device \
             client-node client-device adapter link-factory session-manager pipe-tunnel protocol-pulse \
             loopback filter-chain combine-stream echo-cancel parametric-equalizer fallback-sink; do
      echo "$U/pipewire-0.3/libpipewire-module-$m.so"
    done
    ls "$U"/wireplumber-0.5/*.so
    ls "$U"/spa-0.2/support/libspa-support.so "$U"/spa-0.2/audioconvert/*.so "$U"/spa-0.2/audiomixer/*.so \
       "$U"/spa-0.2/control/*.so "$U"/spa-0.2/aec/libspa-aec-null.so "$U"/spa-0.2/filter-graph/libspa-filter-graph.so \
       "$U"/spa-0.2/filter-graph/libspa-filter-graph-plugin-builtin.so ) > "$WORK/starts"
  CLOSURE_DIRS="$U/pulseaudio:$U/pipewire-0.3:$U/spa-0.2" python3 -I "$HERE/closure.py" "$WORK/all" "$TRIPLE" \
    $(cat "$WORK/starts") > "$WORK/keep"
  # Configuration and WirePlumber's scripts.
  (cd "$WORK/all" && find usr/share/wireplumber usr/share/pipewire/client.conf usr/share/pipewire/pipewire.conf -type f) >> "$WORK/keep"
  R="$WORK/root"
  while read -r f; do
    mkdir -p "$R/$(dirname "$f")"
    cp -L "$WORK/all/$f" "$R/$f"
  done < "$WORK/keep"
  awk '{print $1}' "$WORK/list" | sed 's|.*/||' > "$R/usr/debian-packages.txt"
  rm -rf "$CACHE" && mkdir -p "$CACHE" && cp -a "$R/." "$CACHE/" && touch "$CACHE/.done"
fi

rm -f "$OUT/libdd_soundsrv.so"
(cd "$CACHE" && zip -qr -X "$OUT/libdd_soundsrv.so" usr)
install -m 755 "$HERE/sound.sh" "$OUT/libdd_sound.so"
echo "   sound: $(du -h "$OUT/libdd_soundsrv.so" | cut -f1) PipeWire ($(wc -l < "$CACHE/usr/debian-packages.txt") Debian packages, $(find "$CACHE/usr" -type f | wc -l) files kept)"
