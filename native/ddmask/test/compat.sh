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
"$CC" -O2 -Wall "$HERE/sigsys-probe.c" -o "$T/app/bin/sigsys-probe" -lpthread
"$CC" -O2 -Wall "$HERE/shm-probe.c" -o "$T/app/bin/shm-probe"
"$CC" -O2 -Wall "$HERE/link-probe.c" -o "$T/app/bin/link-probe"
"$CC" -O2 -Wall "$HERE/sysv-probe.c" -o "$T/app/bin/sysv-probe"
"$CC" -O2 -Wall -shared -fPIC "$HERE/android-deny.c" -o "$T/android-deny.so" -ldl
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
for i in 1 2 3 4 5 6; do run "$T/app/bin/probe" execv "$T/app/bin/notes" >/dev/null || true; done
expect "...a failure repeated over and over only three times in a row (Chromium restarting a helper)" \
  "$(tail -n 4 "$J" | grep -c 'notes: no execute bit')" "^3$"

# -- the desktop's environment
H="QT_PLUGIN_PATH=$T/lib/plugins DDMASK_HOST_QT_PLUGIN_PATH=$T/lib/plugins"
H="$H QT_QUICK_CONTROLS_STYLE=Fusion DDMASK_HOST_QT_QUICK_CONTROLS_STYLE=org.kde.desktop"
out="$(run env $H /bin/sh -c "exec $T/lib/libdd_ld-glibc.so /usr/bin/env")"
refute "a glibc program started from the desktop doesn't get its plugin path" "$out" "^QT_PLUGIN_PATH="
expect "...but keeps a value set for it, and the desktop's for later" "$out" "^QT_QUICK_CONTROLS_STYLE=Fusion$" "^DDMASK_HOST_QT_PLUGIN_PATH=$T/lib/plugins$"
# The desktop's look for Linux programs (DDMASK_LINUX_<VAR>), unless set.
LK="QT_QPA_PLATFORMTHEME=deskdroid DDMASK_HOST_QT_QPA_PLATFORMTHEME=deskdroid DDMASK_LINUX_QT_QPA_PLATFORMTHEME=kde"
LK="$LK DDMASK_LINUX_GTK_THEME=DD-Party DDMASK_LINUX_XDG_CURRENT_DESKTOP=KDE XDG_CURRENT_DESKTOP=GNOME"
out="$(run env $LK /bin/sh -c "exec $T/lib/libdd_ld-glibc.so /usr/bin/env")"
expect "a glibc program gets the desktop's look: KDE's platform theme, the GTK theme" "$out" "^QT_QPA_PLATFORMTHEME=kde$" "^GTK_THEME=DD-Party$"
expect "...but not over what's set already" "$out" "^XDG_CURRENT_DESKTOP=GNOME$"
out="$(run env $LK /bin/sh -c "exec /usr/bin/env")"
expect "...and bionic programs keep the desktop's own" "$out" "^QT_QPA_PLATFORMTHEME=deskdroid$"
refute "...without the Linux one" "$out" "^GTK_THEME="
out="$(run env $H /bin/sh -c "exec /usr/bin/env")"
expect "bionic to bionic: as it was" "$out" "^QT_PLUGIN_PATH=$T/lib/plugins$"
out="$(env LD_PRELOAD="$T/glib/libddmask_glibc.so" DDMASK_ALLOW="$ALLOW" QT_PLUGIN_PATH=/app/lib/plugins \
  DDMASK_HOST_QT_PLUGIN_PATH="$T/lib/plugins" /bin/sh -c "exec /usr/bin/env")"
expect "a bionic program started from a glibc one gets the desktop's back" "$out" "^QT_PLUGIN_PATH=$T/lib/plugins$"

# -- blocked system calls
out="$(env LD_PRELOAD="$T/glib/libddmask_glibc.so" DDMASK_JOURNAL="$J" DDMASK_SIGSYS_LOG="$T/sigsys.log" "$T/app/bin/sigsys-probe" 2>&1)"
expect "blocked calls with an allowed twin are made with it" "$out" "^faccessat2=0/ok$" "^epoll_pwait2=0/ok$" "^accept=-1/Resource temporarily unavailable$" \
  "^close_range=0/ok closed=both$"
expect "set*id calls that change nothing succeed, others get EPERM" "$out" "^setresgid-same=0/ok$" "^setresgid-other=-1/Operation not permitted$"
expect "...the rest fail with ENOSYS" "$out" "^getcpu=-1/Function not implemented$"
expect "...noted in the journal" "$(cat "$J")" "Android blocks system call [0-9]+, made as faccessat" "Android blocks system call [0-9]+, failed with ENOSYS"
expect "...and in sigsys.log, by number" "$(sort -un "$T/sigsys.log" | tr '\n' ' ')" "^[0-9]+ [0-9]+ [0-9]+ [0-9]+ [0-9]+ [0-9]+ $"
out="$(env LD_PRELOAD="$T/glib/libddmask_glibc.so" DDMASK_JOURNAL="$J" "$T/app/bin/sigsys-probe" own 2>&1)"
expect "a program with its own SIGSYS handler still gets ENOSYS, from any thread" "$out" "^own-thread-getcpu=-1/Function not implemented$"
expect "...sees its handler as set, and gets the SIGSYS it sends itself" "$out" "^own-handler-kept=yes$" "^own-kill-reached=1$"
out="$(env LD_PRELOAD="$T/glib/libddmask_glibc.so" DDMASK_JOURNAL="$J" "$T/app/bin/sigsys-probe" sandbox 2>&1)"
expect "a program's own seccomp sandbox (Firefox's) answers the calls it traps" "$out" "^sandbox-trapped=42 data=5$"
expect "...while Android's still get ddmask's answer" "$out" "^sandbox-android-blocked=-1/Function not implemented$"

# -- shared memory, with Android's refusals (android-deny.c)
mkdir -p "$T/tmp"
out="$(env LD_PRELOAD="$T/glib/libddmask_glibc.so:$T/android-deny.so" TMPDIR="$T/tmp" "$T/app/bin/shm-probe" 2>&1)"
expect "a memfd's read-only copy through /proc/self/fd, which Android refuses" "$out" "^memfd-reopen=ok$" "^memfd-shared=shared$" "^memfd-cloexec=yes$"
expect "...that sealing makes read-only" "$out" "^memfd-sealed=yes copy-writable=no$"
expect "...while other files stay refused" "$out" "^other-reopen=Permission denied$"
expect "shm_open without /dev/shm: made, opened again, exclusive, unlinked" "$out" "^shm-again=ok$" "^shm-excl=File exists$" "^shm_unlink=ok$" \
  "^shm-shared=shared$" "^shm-gone=No such file or directory$"
expect "...in \$TMPDIR/ddmask-shm, left empty" "dir:$(ls -A "$T/tmp/ddmask-shm" 2>&1)" "^dir:$"
out="$(env LD_PRELOAD="$T/glib/libddmask_glibc.so" "$T/app/bin/shm-probe" 2>&1)"
expect "...and where there is a /dev/shm, as before" "$out" "^memfd-reopen=ok$" "^shm-shared=shared$" "^shm-gone=No such file or directory$"
out="$(env LD_PRELOAD="$T/android-deny.so" TMPDIR="$T/tmp" "$T/app/bin/shm-probe" 2>&1)"
expect "(without ddmask the memfd copy fails there)" "$out" "^memfd-reopen=Permission denied$"

# -- System V shared memory and semaphores, which Android's seccomp blocks
mkdir -p "$T/sv"
out="$(env LD_PRELOAD="$T/glib/libddmask_glibc.so:$T/android-deny.so" DDMASK_SHM="$T/sv" "$T/app/bin/sysv-probe" 2>&1)"
expect "Xorg's MIT-SHM check: an invalid id is EINVAL" "$out" "^probe=Invalid argument$"
expect "a private segment shared with a child by id, read-only, kept while attached after IPC_RMID" "$out" \
  "^child-sees=from-parent$" "^child-nattch=[23]$" "^child-after-rmid=changed$" "^size=100000 mode=600 dest=yes$" \
  "^shmdt=ok$" "^gone=Invalid argument$" "^shmdt-again=Invalid argument$"
expect "...a keyed segment: found again, IPC_EXCL, too small, gone after IPC_RMID" "$out" "^key=ok$" "^key-same=yes$" \
  "^key-excl=File exists$" "^key-bigger=Invalid argument$" "^key-after-rmid=No such file or directory$"
expect "...semaphores: IPC_NOWAIT, a child waiting until another op gives, a timeout, removal" "$out" "^semget=ok$" \
  "^nowait=Resource temporarily unavailable$" "^ncnt=1$" "^child-took=ok$" "^vals=0,5$" \
  "^timed=Resource temporarily unavailable$" "^sem-rmid=ok$" "^sem-gone=Invalid argument$"
expect "...in \$DDMASK_SHM/sysv, left empty" "dir:$(ls -A "$T/sv/sysv" 2>&1)" "^dir:$"
out="$(env LD_PRELOAD="$T/android-deny.so" "$T/app/bin/sysv-probe" 2>&1 || true)"
expect "(without ddmask they fail there)" "$out" "^shmget=Function not implemented$"

# -- hard links, which Android refuses (android-deny.c)
mkdir -p "$T/l1" "$T/l2"
out="$(env LD_PRELOAD="$T/glib/libddmask_glibc.so:$T/android-deny.so" "$T/app/bin/link-probe" "$T/l1" 2>&1)"
expect "an X server's lock file by hard link: made as a copy, EEXIST once it's there" "$out" "^lock=ok$" "^lock-again=File exists$" \
  "^lock-text= +4242$" "^lock-mode=444$"
expect "...other links still fail as they would" "$out" "^link-dir=Permission denied$" "^link-missing=No such file or directory$"
out="$(env LD_PRELOAD="$T/android-deny.so" "$T/app/bin/link-probe" "$T/l2" 2>&1)"
expect "(without ddmask the lock file fails there)" "$out" "^lock=Permission denied$"

[ "$fails" -eq 0 ] && echo "all compatibility tests passed" || { echo "$fails failed"; exit 1; }
