#!/usr/bin/env bash
# Tests ddmask's compatibility layer (README.md, "Compatibility layer") on a
# desktop Linux machine, set up as test/run.sh does: programs without execute
# bits, access(X_OK), the journal, the desktop's environment between bionic
# and glibc programs, and blocked system calls.
#   native/ddmask/test/compat.sh [cc]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CC="${1:-${CC:-cc}}"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/lib" "$T/app/bin" "$T/glib"
"$CC" -O2 -Wall -shared -fPIC "$HERE/../ddmask.c" -o "$T/lib/libddmask.so" -ldl
# Its glibc build, in a folder of its own so the bionic one isn't its partner.
"$CC" -O2 -Wall -shared -fPIC -DDDMASK_GLIBC "$HERE/../ddmask.c" -o "$T/glib/libddmask_glibc.so" -ldl
"$CC" -O2 -Wall "$HERE/probe.c" -o "$T/app/bin/probe"
"$CC" -O2 -Wall "$HERE/sigsys-probe.c" -o "$T/app/bin/sigsys-probe"
cp "$T/app/bin/probe" "$T/app/bin/nox"
printf '#!/bin/sh\necho "nox-script $*"\n' > "$T/app/bin/noxscript"
echo "just text" > "$T/app/bin/notes"
chmod 644 "$T/app/bin/nox" "$T/app/bin/noxscript" "$T/app/bin/notes"
# This machine's loader stands in for DeskDroid's glibc loader in the APK.
LD="$(readelf -l "$T/app/bin/probe" | sed -n 's/.*interpreter: \(.*\)]/\1/p')"
cp "$LD" "$T/lib/libdd_ld-glibc.so"

ALLOW="/usr:/bin:/lib:/lib32:/lib64:/sbin:/etc:$T/lib:$T/glib"
J="$T/journal.log"
run() { env LD_PRELOAD="$T/lib/libddmask.so" DDMASK_ALLOW="$ALLOW" DDMASK_JOURNAL="$J" PATH="$T/app/bin:/usr/bin:/bin" "$@" 2>&1; }
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
refute() { # <name> <output> <pattern>
  if grep -qE -- "$3" <<<"$2"; then echo "FAIL $1: /$3/ in:"; sed 's/^/    /' <<<"$2"; fails=$((fails + 1)); else echo "ok   $1"; fi
}

# -- execute bits
out="$(run /bin/sh -c "[ -x $T/app/bin/nox ] && echo x-ok; [ -x $T/app/bin/notes ] || echo notes-not-x")"
expect "[ -x ] on a program without its execute bit" "$out" "^x-ok$" "^notes-not-x$"
chmod 644 "$T/app/bin/nox"
out="$(run "$T/app/bin/probe" execv "$T/app/bin/nox")"
expect "a program without its execute bit runs" "$out" "argv0=$T/app/bin/nox exe=$T/app/bin/nox"
[ -x "$T/app/bin/nox" ] && echo "ok   ...and gets its execute bits back" || { echo "FAIL nox still not executable"; fails=$((fails + 1)); }
chmod 644 "$T/app/bin/nox"
out="$(run /bin/sh -c "nox from-path")"
expect "a shell finds it on PATH" "$out" "argv0=nox .*arg=from-path"
out="$(run "$T/app/bin/probe" execvp noxscript)"
expect "a #! script without its execute bit" "$out" "^nox-script child$"
out="$(run "$T/app/bin/probe" execv "$T/app/bin/notes" || true)"
expect "a text file without x stays refused" "$out" "execv: Permission denied"
chmod 644 "$T/app/bin/nox"
out="$(run env DDMASK_STRICT_EXEC=1 "$T/app/bin/probe" execv "$T/app/bin/nox" || true)"
expect "DDMASK_STRICT_EXEC=1 refuses it as before" "$out" "execv: Permission denied"

# -- the journal
out="$(cat "$J")"
expect "the journal names programs started another way" "$out" \
  "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8} ddmask\[[0-9]+\]: $T/app/bin/nox: no execute bit, glibc, through "
expect "...and why one can't start" "$out" "notes: no execute bit, and not a program or script"
expect "...and refusals under DDMASK_STRICT_EXEC" "$out" "nox: no execute bit, and not a program or script|nox: .*mode"

# -- the desktop's environment
H="QT_PLUGIN_PATH=$T/lib/plugins DDMASK_HOST_QT_PLUGIN_PATH=$T/lib/plugins"
H="$H QT_QUICK_CONTROLS_STYLE=Fusion DDMASK_HOST_QT_QUICK_CONTROLS_STYLE=org.kde.desktop"
out="$(run env $H /bin/sh -c "exec $T/lib/libdd_ld-glibc.so /usr/bin/env")"
refute "a glibc program started from the desktop doesn't get its plugin path" "$out" "^QT_PLUGIN_PATH="
expect "...but keeps a value set for it, and the desktop's for later" "$out" "^QT_QUICK_CONTROLS_STYLE=Fusion$" "^DDMASK_HOST_QT_PLUGIN_PATH=$T/lib/plugins$"
out="$(run env $H /bin/sh -c "exec /usr/bin/env")"
expect "bionic to bionic: as it was" "$out" "^QT_PLUGIN_PATH=$T/lib/plugins$"
out="$(env LD_PRELOAD="$T/glib/libddmask_glibc.so" DDMASK_ALLOW="$ALLOW" QT_PLUGIN_PATH=/app/lib/plugins \
  DDMASK_HOST_QT_PLUGIN_PATH="$T/lib/plugins" /bin/sh -c "exec /usr/bin/env")"
expect "a bionic program started from a glibc one gets the desktop's back" "$out" "^QT_PLUGIN_PATH=$T/lib/plugins$"

# -- blocked system calls
out="$(env LD_PRELOAD="$T/glib/libddmask_glibc.so" DDMASK_JOURNAL="$J" DDMASK_SIGSYS_LOG="$T/sigsys.log" "$T/app/bin/sigsys-probe" 2>&1)"
expect "blocked calls with an allowed twin are made with it" "$out" "^faccessat2=0/ok$" "^epoll_pwait2=0/ok$" "^accept=-1/Resource temporarily unavailable$" \
  "^close_range=0/ok closed=both$"
expect "...the rest fail with ENOSYS" "$out" "^getcpu=-1/Function not implemented$"
expect "...noted in the journal" "$(cat "$J")" "Android blocks system call [0-9]+, made as faccessat" "Android blocks system call [0-9]+, failed with ENOSYS"
expect "...and in sigsys.log, by number" "$(sort -un "$T/sigsys.log" | tr '\n' ' ')" "^[0-9]+ [0-9]+ [0-9]+ [0-9]+ [0-9]+ $"

[ "$fails" -eq 0 ] && echo "all compatibility tests passed" || { echo "$fails failed"; exit 1; }
