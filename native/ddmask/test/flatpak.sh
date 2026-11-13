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
"$CC" -O2 -Wall "$HERE/flatpak-probe.c" -o "$APP/bin/probe" -ldl
echo app-data > "$APP/share/probe/data"
echo runtime-data > "$RT/share/probe/data"
echo runtime-etc > "$RT/etc/xdg/proberc"
cp "$APP/bin/probe" "$RT/bin/rtprobe"
cp "$(readlink -f /bin/sh)" "$RT/bin/sh" # the runtime's sh, for #!/bin/sh
printf '#!/bin/sh\nexec /app/bin/probe from-script "$@"\n' > "$APP/bin/script"
printf '#!/bin/sh\necho zypak itself ran\n' > "$APP/bin/zypak-wrapper.sh"
chmod 755 "$APP/bin/script" "$APP/bin/zypak-wrapper.sh"
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
ALL='open=yes stat=yes opendir=yes realpath=yes xstat=yes'

out="$(run "$APP/bin/probe" /app/share/probe/data /usr/share/probe/data /etc/xdg/proberc)"
expect "/app reaches the app's files" "$out" "/app/share/probe/data fopen=app-data $ALL"
expect "/usr reaches the runtime's files" "$out" "/usr/share/probe/data fopen=runtime-data $ALL"
expect "/etc reaches the runtime's /etc" "$out" "/etc/xdg/proberc fopen=runtime-etc $ALL"

out="$(run "$APP/bin/probe" /etc/hostname)"
expect "/etc the runtime lacks stays the system's" "$out" "/etc/hostname fopen=[^n]"

out="$(run "$APP/bin/probe" "exec:/usr/bin/rtprobe" /app/share/probe/data)"
expect "a program at /usr/bin starts through the loader" "$out" \
  "argv0=child exe=$RT/bin/rtprobe" "/app/share/probe/data fopen=app-data"

# Chromium overwrites the environment's old memory with its process title.
out="$(run "$APP/bin/probe" clobber-env "exec:/usr/bin/rtprobe" /app/share/probe/data)"
expect "programs started after the environment's memory is overwritten still go through the loader" "$out" \
  "argv0=child exe=$RT/bin/rtprobe" "/app/share/probe/data fopen=app-data"

# Chromium (Electron) finds its files next to /proc/self/exe and execs it.
out="$(run "$LOADER" "$APP/bin/probe")"
expect "/proc/self/exe names the program, not the loader" "$out" "exe=$APP/bin/probe"

out="$(run sh -c 'exec probe /usr/share/probe/data' 2>&1 || true)"
expect "PATH's /app/bin finds the app's program" "$out" "fopen=runtime-data"

out="$(run "$APP/bin/probe" "exec:/app/bin/script" /usr/share/probe/data)"
expect "a #!/bin/sh script runs with the runtime's sh" "$out" "argv0=/app/bin/probe exe=$APP/bin/probe" \
  "/usr/share/probe/data fopen=runtime-data"

out="$(run "$APP/bin/probe" "exec:/app/bin/zypak-wrapper.sh" /app/bin/probe /app/share/probe/data)"
expect "zypak-wrapper starts the program itself with --no-sandbox" "$out" \
  "argv0=/app/bin/probe exe=$APP/bin/probe" "--no-sandbox fopen=no" "/app/share/probe/data fopen=app-data"

# Library folders named by absolute path (RUNPATH), which glibc's loader opens
# itself: ddflatpak-audit maps them.
mkdir -p "$APP/lib/sub" "$RT/lib/plug"
printf 'int sub_value(void) { return 42; }\n' > "$T/sub.c"
printf 'int plug_value(void) { return 7; }\n' > "$T/plug.c"
printf '#include <stdio.h>\nint sub_value(void); int plug_value(void);\nint main(void) { printf("libs=%%d,%%d\\n", sub_value(), plug_value()); return 0; }\n' > "$T/rp.c"
"$CC" -shared -fPIC "$T/sub.c" -o "$APP/lib/sub/libsub.so"
"$CC" -shared -fPIC "$T/plug.c" -o "$RT/lib/plug/libplug.so"
"$CC" "$T/rp.c" -o "$APP/bin/rpprobe" -L"$APP/lib/sub" -L"$RT/lib/plug" -lsub -lplug \
  -Wl,--enable-new-dtags -Wl,-rpath,/app/lib/sub:/usr/lib/plug
"$CC" -O2 -Wall -shared -fPIC -nostdlib -fno-builtin -fno-stack-protector "$HERE/../ddflatpak-audit.c" \
  -o "$T/libddflatpak_audit.so"
out="$(run "$APP/bin/rpprobe" || true)"
expect "without the audit library, absolute RUNPATHs point at nothing" "$out" "cannot open shared object"
out="$(run env LD_AUDIT="$T/libddflatpak_audit.so" "$APP/bin/rpprobe")"
expect "the audit library maps RUNPATH /app/lib/<x> and /usr/lib/<x>" "$out" "^libs=42,7$"
out="$(run env LD_AUDIT="$T/libddflatpak_audit.so" "$APP/bin/probe" "exec:/app/bin/rpprobe")"
expect "...in programs the app starts too" "$out" "^libs=42,7$"

mkdir -p "$T/shm"
out="$(run env DDFLATPAK_MOUNTS="/dev/shm=$T/shm;/run/ddtest-shm=$T/shm" "$APP/bin/probe" temp:/run/ddtest-shm/.org.chromium.Chromium.XXXXXX)"
expect "mkostemp and unlink under a mounted path (Chromium's /dev/shm)" "$out" "^temp fd=yes named=yes removed=yes$"

echo
[ "$fails" = 0 ] && echo "all ddflatpak tests passed" || { echo "$fails failed"; exit 1; }
