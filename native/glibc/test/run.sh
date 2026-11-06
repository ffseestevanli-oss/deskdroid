#!/usr/bin/env bash
# Tests DeskDroid's glibc (native/glibc/build.sh's output) under qemu-aarch64,
# with qemu's -L folder standing in for the phone: the runtime unpacked at
# /data/data/io.deskdroid.app/files/glibc, the APK's libraries at /apk.
#   native/glibc/test/run.sh <build.sh's outdir>
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(cd "$1" && pwd)"
CROSS="${CROSS:-aarch64-linux-gnu-}"
command -v qemu-aarch64 >/dev/null || { echo "glibc test: no qemu-aarch64, skipped"; exit 0; }
[ -e "$OUT/libdd_ld-glibc.so" ] || { echo "glibc test: no build in $OUT, skipped"; exit 0; }
R="$(mktemp -d)"
trap 'rm -rf "$R"' EXIT
G="$R/data/data/io.deskdroid.app/files/glibc"
mkdir -p "$G" "$R/apk" "$R/app"
(cd "$G" && unzip -q "$OUT/libdd_glibc.so")
cp "$OUT/libdd_ld-glibc.so" "$OUT/libddmask_glibc.so" "$R/apk/"
echo "deskdroid:x:$(id -u):$(id -g):DeskDroid:/home:/system/bin/sh" > "$G/etc/passwd"
"${CROSS}gcc" -O2 "$HERE/probe.c" -o "$R/app/probe"
run() { qemu-aarch64 -L "$R" "$@" "$R/apk/libdd_ld-glibc.so" /app/probe 2>&1; }
fails=0
expect() { # <name> <output> <pattern>...
  local name="$1" out="$2"; shift 2
  for p in "$@"; do
    grep -qE -- "$p" <<<"$out" || { echo "FAIL $name: no /$p/ in:"; sed 's/^/    /' <<<"$out"; fails=$((fails + 1)); return; }
  done
  echo "ok   $name"
}
out="$(run)"
expect "a program runs through glibc's loader" "$out" "argv0=/app/probe"
expect "/etc/passwd is the app's" "$out" "user=deskdroid"
expect "a blocked system call (SIGSYS) fails with ENOSYS" "$out" "sigsys=-1/Function not implemented"
out="$(run -E LD_PRELOAD=/nonexistent.so)"
expect "LD_PRELOAD (Android's) is left alone" "$out" "argv0=/app/probe" "preload=unset"
if grep -q "nonexistent" <<<"$out"; then echo "FAIL glibc's loader read LD_PRELOAD"; fails=$((fails + 1)); fi
out="$(run -E DDMASK_GLIBC_LD_PRELOAD=/apk/libddmask_glibc.so -E DDMASK_EXE=/app/probe -E DDMASK_ARGV0=probe)"
expect "ddmask's glibc build loads and gives the program its name and path" "$out" "argv0=probe exe=/app/probe "
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
