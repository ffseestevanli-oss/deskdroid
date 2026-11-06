#!/usr/bin/env bash
# Tests DeskDroid's musl (native/musl/build.sh's output) under qemu-aarch64,
# with qemu's -L folder standing in for the phone: the APK's libraries at /apk,
# musl's folder at /data/data/io.deskdroid.app/files/musl.
#   native/musl/test/run.sh <build.sh's outdir>
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(cd "$1" && pwd)"
CROSS="${CROSS:-aarch64-linux-gnu-}"
command -v qemu-aarch64 >/dev/null || { echo "musl test: no qemu-aarch64, skipped"; exit 0; }
[ -e "$OUT/libdd_ld-musl.so" ] || { echo "musl test: no build in $OUT, skipped"; exit 0; }
CACHE="$("$HERE/../build.sh" "$OUT" --cache-dir)"
R="$(mktemp -d)"
trap 'rm -rf "$R"' EXIT
M="$R/data/data/io.deskdroid.app/files/musl"
mkdir -p "$M/etc" "$M/lib" "$R/apk" "$R/app"
cp "$OUT/libdd_ld-musl.so" "$OUT/libddmask_musl.so" "$R/apk/"
echo "deskdroid:x:$(id -u):$(id -g):DeskDroid:/home:/system/bin/sh" > "$M/etc/passwd"
CC=("${CROSS}gcc" -specs "$CACHE/deskdroid-gcc.specs")
"${CC[@]}" -O2 "$HERE/../../ddmask/test/libc-probe.c" -o "$R/app/probe"
# A library from musl's own folder (Alpine packages put theirs in lib/).
printf 'int dd_answer(void) { return 42; }\n' > "$R/lib.c"
printf 'int dd_answer(void);\n#include <stdio.h>\nint main(void) { printf("answer=%%d\\n", dd_answer()); return 0; }\n' > "$R/uselib.c"
"${CC[@]}" -shared -fPIC "$R/lib.c" -o "$M/lib/libddanswer.so"
"${CC[@]}" "$R/uselib.c" -L"$M/lib" -lddanswer -o "$R/app/uselib"
run() { local p="$1"; shift; qemu-aarch64 -L "$R" "$@" "$R/apk/libdd_ld-musl.so" ${ARGV0:+--argv0 "$ARGV0"} "$p" 2>&1; }
fails=0
expect() { # <name> <output> <pattern>...
  local name="$1" out="$2"; shift 2
  for p in "$@"; do
    grep -qE -- "$p" <<<"$out" || { echo "FAIL $name: no /$p/ in:"; sed 's/^/    /' <<<"$out"; fails=$((fails + 1)); return; }
  done
  echo "ok   $name"
}
out="$(run /app/probe)"
expect "a program runs through musl's loader" "$out" "argv0=/app/probe"
expect "/etc/passwd is the app's" "$out" "user=deskdroid"
expect "a blocked system call (SIGSYS) fails with ENOSYS" "$out" "sigsys=-1/Function not implemented"
out="$(run /app/uselib)"
expect "libraries load from musl's lib folder" "$out" "answer=42"
out="$(run /app/probe -E LD_PRELOAD=/nonexistent.so)"
expect "LD_PRELOAD (Android's) is left alone" "$out" "argv0=/app/probe" "preload=unset"
# (ddmask starts musl programs as: libdd_ld-musl.so --argv0 <argv[0]> <program> <args>)
out="$(ARGV0=probe run /app/probe -E DDMASK_MUSL_LD_PRELOAD=/apk/libddmask_musl.so -E DDMASK_EXE=/app/probe)"
expect "ddmask's musl build loads and gives the program its name and path" "$out" "argv0=probe exe=/app/probe "
# Static programs (ddmask's ddload, ../../ddmask/ddload.c), here for ARM64: a static musl one.
"${CROSS}gcc" -O2 -fPIE -static-pie -nostdlib -ffreestanding -fno-builtin -fno-stack-protector \
  -fno-asynchronous-unwind-tables "$HERE/../../ddmask/ddload.c" -o "$R/apk/libdd_static.so"
"${CC[@]}" -O2 -static "$HERE/../../ddmask/test/libc-probe.c" -o "$R/app/sprobe"
out="$(qemu-aarch64 -L "$R" "$R/apk/libdd_static.so" "$R/app/sprobe" sprobe 2>&1)"
expect "a static ARM64 program runs through ddload, blocked calls fail with ENOSYS" "$out" "argv0=sprobe " "user=deskdroid" "sigsys=-1/Function not implemented"
[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
