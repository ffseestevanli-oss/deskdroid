#!/usr/bin/env bash
# Tests libddmask.so on a desktop Linux machine, where glibc's loader
# (ld-linux, the programs' own PT_INTERP) stands in for Android's linker64:
# a folder outside DDMASK_ALLOW is treated like an Android app's own files,
# so its programs must start through the loader.
#   native/ddmask/test/run.sh [cc]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CC="${1:-${CC:-cc}}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/lib" "$T/app/bin"
"$CC" -O2 -Wall -shared -fPIC "$HERE/../ddmask.c" -o "$T/lib/libddmask.so" -ldl
"$CC" -O2 -Wall "$HERE/probe.c" -o "$T/app/bin/probe"
printf '#!%s/app/bin/probe from-script\n' "$T" > "$T/app/bin/script"
printf '#!/bin/sh\necho "sh-script $0 $*"\n' > "$T/app/bin/shscript"
cp "$T/app/bin/probe" "$T/app/bin/noexec"
chmod 755 "$T/app/bin/script" "$T/app/bin/shscript"
chmod 644 "$T/app/bin/noexec"
# Static programs: through ddload (libdd_static.so), built for this machine.
"$CC" -O2 -Wall -fPIE -static-pie -nostdlib -ffreestanding -fno-builtin -fno-stack-protector \
  -fno-asynchronous-unwind-tables "$HERE/../ddload.c" -o "$T/lib/libdd_static.so"
"$CC" -O2 -static "$HERE/probe.c" -o "$T/app/bin/sprobe"
"$CC" -O2 -static-pie "$HERE/probe.c" -o "$T/app/bin/spieprobe"
# AppImages: the runner (with this machine's shell), and a pretend AppImage, a
# static program with AppImage's mark that unpacks an AppRun script.
sed '1s|.*|#!/bin/sh|' "$HERE/../appimage.sh" > "$T/lib/libdd_appimage.so"
chmod 755 "$T/lib/libdd_appimage.so"
"$CC" -O2 -static "$HERE/fake-appimage.c" -o "$T/app/bin/Fake.AppImage"
printf 'AI\002' | dd of="$T/app/bin/Fake.AppImage" bs=1 seek=8 conv=notrunc status=none

ALLOW="/usr:/bin:/lib:/lib32:/lib64:/sbin:/etc:$T/lib"
run() { env LD_PRELOAD="$T/lib/libddmask.so" DDMASK_ALLOW="$ALLOW" PATH="$T/app/bin:/usr/bin:/bin" "$@" 2>&1; }
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
P="$T/app/bin/probe"
LOADER='cmd0=[^ ]*ld-linux'

out="$(run /bin/sh -c "exec $P one")"
expect "a shell starts a program by path" "$out" "argv0=$P " "exe=$P " "comm=probe " "$LOADER" "arg=one"

out="$(run /bin/sh -c "exec probe two")"
expect "a shell finds it on PATH" "$out" "argv0=probe " "exe=$P " "$LOADER" "arg=two"

out="$(run /bin/sh -c "exec probe execvp probe")"
expect "execvp from a loaded program" "$out" "argv0=probe exe=$P comm=probe cmd0=[^ ]*ld-linux[^ ]* arg=child"

out="$(run /bin/sh -c "exec probe execle $P DDMASK_ALLOW=$ALLOW")"
expect "a cleaned environment keeps ddmask" "$out" "argv0=child exe=$P comm=probe cmd0=[^ ]*ld-linux"

out="$(run /bin/sh -c "exec probe spawnp probe")"
expect "posix_spawnp" "$out" "argv0=probe exe=$P comm=probe cmd0=[^ ]*ld-linux[^ ]* arg=spawned"

out="$(run /bin/sh -c "exec script a b")"
expect "#! script whose interpreter is masked too" "$out" "argv0=$P exe=$P .*arg=from-script arg=$T/app/bin/script arg=a arg=b"

out="$(run /bin/sh -c "exec shscript x")"
expect "#! script for /bin/sh" "$out" "sh-script $T/app/bin/shscript x"

out="$(run "$P" execv "$T/app/bin/noexec" || true)"
expect "a file without x stays refused" "$out" "execv: Permission denied"

out="$(env LD_PRELOAD="$T/lib/libddmask.so" DDMASK_ALLOW="$ALLOW" /bin/sh -c "exec /bin/true && echo unreached; echo" ; echo "status=$?")"
expect "allowed programs run as before" "$out" "status=0"

out="$(env LD_PRELOAD="$T/lib/libddmask.so" DDMASK_ALLOW="$ALLOW:$T/app" /bin/sh -c "exec $P")"
expect "inside DDMASK_ALLOW: plain exec" "$out" "cmd0=$P"

S="$T/app/bin/sprobe"
out="$(run /bin/sh -c "exec $S one")"
expect "a static program runs through ddload" "$out" "argv0=$S " "comm=sprobe " "cmd0=[^ ]*libdd_static.so" "arg=one"

out="$(run /bin/sh -c "exec spieprobe two")"
expect "a static PIE program, found on PATH" "$out" "argv0=spieprobe " "comm=spieprobe " "cmd0=[^ ]*libdd_static.so" "arg=two"

out="$(run "$P" execvp sprobe)"
expect "a loaded program starts a static one" "$out" "argv0=sprobe exe=[^ ]*libdd_static.so comm=sprobe .* arg=child"

export DDMASK_APPIMAGE_CACHE="$T/cache"
out="$(run /bin/sh -c "exec Fake.AppImage x y")"
expect "an AppImage unpacks and its AppRun starts" "$out" "apprun appimage=$T/app/bin/Fake.AppImage argv0=Fake.AppImage appdir=$T/cache/Fake.AppImage-[^ ]* args=x y" "^unpacked$"
out="$(run /bin/sh -c "exec Fake.AppImage again")"
expect "the second start uses the unpacked copy" "$out" "apprun .* args=again"
if grep -q "^unpacked" <<<"$out"; then echo "FAIL it unpacked again"; fails=$((fails + 1)); fi

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
