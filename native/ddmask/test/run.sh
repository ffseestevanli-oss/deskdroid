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

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
