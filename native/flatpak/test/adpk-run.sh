#!/bin/bash
# Tests adpk-run.sh (libdd_adpk_run.so) on a desktop machine: what it reads
# from a Flathub package and what it hands glibc's loader, with a stand-in
# loader that prints its environment and arguments.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
expect() { # name text regex...
  local name="$1" text="$2"; shift 2
  for re in "$@"; do
    grep -Eq -- "$re" <<<"$text" || { echo "FAIL $name: no /$re/ in:"; sed 's/^/     /' <<<"$text"; fails=$((fails+1)); return; }
  done
  echo "ok   $name"
}
F="$T/files" S="$T/files/store/apps" L="$T/libs"
mkdir -p "$F/glibc/lib" "$L" && : > "$F/glibc/lib/libc.so.6" && : > "$L/libdd_ld-glibc.so"
pkg() { # id metadata [app.json]
  mkdir -p "$S/$1/program/files"; : > "$S/$1/app.txt"; : > "$S/$1/program/.ddsetup-done"
  printf '%s\n' "$2" > "$S/$1/program/metadata"
  printf '%s\n' "${3:-{\"id\": \"$1\"\}}" > "$S/$1/app.json"
}
pkg runtime-kde-6.11 '[Runtime]
name = org.kde.Platform

[Environment]
QT_PLUGIN_PATH = /app/lib/plugins:/usr/share/runtime/lib/plugins
KDE_FORK_SLAVES = 1'
pkg runtime-mesa-25.08 ''
pkg kid3 '[Application]
name=org.kde.kid3
command=kid3

[Environment]
TMPDIR=/var/tmp
LD_LIBRARY_PATH=/app/lib/extra' '{ "id": "kid3", "needs": [
  "runtime-kde-6.11",
  "runtime-mesa-25.08" ] }'
cat > "$T/loader" <<'L'
#!/bin/sh
echo "args: $*"
env | sort
L
chmod +x "$T/loader"
run() {
  env -i HOME="$T/home" PATH=/usr/bin:/bin QT_PLUGIN_PATH=/desktop/plugins DDAPP_PROGRAM="$S/$1/program" \
    DESKDROID_FILES="$F" DESKDROID_LIBS="$L" DESKDROID_GLIBC_RUN="$T/loader" sh "$HERE/../adpk-run.sh" "${@:2}"
}
out="$(run kid3 --dd-command=kid3-cli a b)"
log="$(cat "$S/kid3/run.log")"
expect "reads the app, its command and its runtime from the package" "$log" \
  "^kid3: starting /app/bin/kid3-cli a b \(org.kde.kid3, runtime-kde-6.11\)$"
expect "starts it with the runtime's sh, through the loader" "$out" "^args: $S/runtime-kde-6.11/program/files/bin/sh -c exec \"\\\$0\" \"\\\$@\" /app/bin/kid3-cli a b$"
expect "the runtime's [Environment] replaces the desktop's Qt settings" "$out" \
  "^QT_PLUGIN_PATH=/app/lib/plugins:/usr/share/runtime/lib/plugins$" "^KDE_FORK_SLAVES=1$" "^TMPDIR=/var/tmp$"
expect "the app's own paths" "$out" "^PATH=/app/bin:/usr/bin$" "^FLATPAK_ID=org.kde.kid3$" "^ELECTRON_OZONE_PLATFORM_HINT=wayland$" \
  "^DDMASK_GLIBC_LD_LIBRARY_PATH=.*$S/kid3/program/files/lib/extra" "^DDFLATPAK_RUNTIME=$S/runtime-kde-6.11/program/files$"
expect "makes its data folders" "$(ls "$T/home/.var/app/org.kde.kid3")" "^config$" "^data$"
if [ -r /proc/version ]; then
  expect "a readable /proc/version is left alone" "$out" "^DDFLATPAK_MOUNTS=[^ ]*/dev/shm=$F/flatpak-tmp(;/proc/sys[^;]*)?$"
fi
rm "$S/runtime-kde-6.11/app.txt"
run kid3 >/dev/null || true
expect "a missing runtime says so" "$(cat "$S/kid3/run.log")" "^kid3: needs runtime-kde-6.11.adpk installed first"
expect "...and opens Software" "$(cat "$F"/open-requests/*.req)" "^deskdroid:store$"
[ "$fails" -eq 0 ] && echo "all adpk-run tests passed" || { echo "$fails failed"; exit 1; }
