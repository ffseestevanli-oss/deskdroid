#!/usr/bin/env bash
# Tests ddflatpak.c on a desktop Linux machine with a pretend Flatpak app and
# runtime: the app's own paths (/app, /usr, /etc) must reach their folders,
# and programs it starts must go through the runtime's loader.
#   native/ddmask/test/flatpak.sh [cc]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CC="${1:-${CC:-cc}}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
APP="$T/app/files" RT="$T/runtime/files"
mkdir -p "$APP/bin" "$APP/share/probe" "$RT/share/probe" "$RT/etc/xdg" "$RT/bin"
"$CC" -O2 -Wall -shared -fPIC "$HERE/../ddflatpak.c" -o "$T/libddflatpak.so" -ldl
"$CC" -O2 -Wall "$HERE/flatpak-probe.c" -o "$APP/bin/probe"
echo app-data > "$APP/share/probe/data"
echo runtime-data > "$RT/share/probe/data"
echo runtime-etc > "$RT/etc/xdg/proberc"
cp "$APP/bin/probe" "$RT/bin/rtprobe"
# This machine's loader stands in for the runtime's.
LOADER="$(readelf -l "$APP/bin/probe" | sed -n 's/.*interpreter: \(.*\)]/\1/p')"

run() {
  env LD_PRELOAD="$T/libddflatpak.so" DDFLATPAK_APP="$APP" DDFLATPAK_RUNTIME="$RT" \
    DDFLATPAK_LOADER="$LOADER" PATH=/app/bin:/usr/bin "$@" 2>&1
}
fails=0
expect() { # <name> <output> <pattern>...
  local name="$1" out="$2"; shift 2
  for p in "$@"; do
    if ! grep -qE -- "$p" <<<"$out"; then
      echo "FAIL $name: no /$p/ in:"; sed 's/^/    /' <<<"$out"; fails=$((fails + 1)); return
    fi
  done
  echo "ok   $name"
}
ALL='open=yes stat=yes opendir=yes realpath=yes'

out="$(run "$APP/bin/probe" /app/share/probe/data /usr/share/probe/data /etc/xdg/proberc)"
expect "/app reaches the app's files" "$out" "/app/share/probe/data fopen=app-data $ALL"
expect "/usr reaches the runtime's files" "$out" "/usr/share/probe/data fopen=runtime-data $ALL"
expect "/etc reaches the runtime's /etc" "$out" "/etc/xdg/proberc fopen=runtime-etc $ALL"

out="$(run "$APP/bin/probe" /etc/hostname)"
expect "/etc the runtime lacks stays the system's" "$out" "/etc/hostname fopen=[^n]"

out="$(run "$APP/bin/probe" "exec:/usr/bin/rtprobe" /app/share/probe/data)"
expect "a program at /usr/bin starts through the loader" "$out" \
  "argv0=child exe=[^ ]*ld-linux" "/app/share/probe/data fopen=app-data"

out="$(run sh -c 'exec probe /usr/share/probe/data' 2>&1 || true)"
expect "PATH's /app/bin finds the app's program" "$out" "fopen=runtime-data"

echo
[ "$fails" = 0 ] && echo "all ddflatpak tests passed" || { echo "$fails failed"; exit 1; }
