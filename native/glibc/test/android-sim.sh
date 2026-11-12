#!/usr/bin/env bash
# Runs Discover's Flathub steps through DeskDroid's flatpak command on a
# desktop machine (x86_64, root) standing in for the phone:
#   - android-sim (android-sim.c): Android's seccomp policy for apps and
#     SELinux's "no hard links in app data";
#   - the app's layout: /data/data/io.deskdroid.app/files (glibc's prefix),
#     the APK's library folder, its zips unpacked without file modes (as the
#     app's Java unzip does), /system/bin/sh;
#   - ddmask's glibc build starting programs through glibc's loader.
# Needs DeskDroid's glibc and flatpak command built for x86_64 into <apk>:
#   DESKDROID_GLIBC_ARCH=x86_64 CROSS= native/glibc/build.sh <apk>
#   DESKDROID_FLATPAK_DEBARCH=amd64 CROSS= native/flatpak/build.sh <apk>
# and bionic's seccomp lists (libc/SYSCALLS.TXT, SECCOMP_*.TXT) in <bionic>.
#
#   native/glibc/test/android-sim.sh <apk> <bionic> [app id, default org.kde.kcalc]
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# The APK's library folder where Android puts it (not under /tmp, which
# ddflatpak maps to Flatpak's temporary folder).
L=/data/app/io.deskdroid.app/lib/x86_64
rm -rf "$L" && mkdir -p "$L" && cp -a "$1"/. "$L"/
BIONIC="$2"
APP="${3:-org.kde.kcalc}"
F=/data/data/io.deskdroid.app/files
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

# ddflatpak and ddmask (glibc side), from this checkout.
gcc -O2 -Wall -shared -fPIC "$HERE/../../ddmask/ddflatpak.c" -ldl -o "$L/libddflatpak.so"
gcc -O2 -Wall -shared -fPIC -DDDMASK_GLIBC "$HERE/../../ddmask/ddmask.c" -o "$L/libddmask_glibc.so"
install -m 755 "$HERE/../../flatpak/flatpak.sh" "$L/libdd_flatpak.so"
install -m 755 "$HERE/../../flatpak/nobwrap.sh" "$L/libdd_nobwrap.so"
python3 "$HERE/android-policy.py" "$BIONIC" /usr/include/x86_64-linux-gnu/asm/unistd_64.h \
  "${GLIBC_SRC:?set GLIBC_SRC to a glibc source tree}/sysdeps/unix/sysv/linux/aarch64/arch-syscall.h" > "$W/android-policy.h"
gcc -O2 -Wall -I"$W" "$HERE/android-sim.c" -o "$L/android-sim"
# Starts a program with SIGSYS blocked, as gpgme starts gpgconf and gpg.
cat > "$W/blocked.c" <<'EOC'
#include <signal.h>
#include <unistd.h>
int main(int c, char **v) { sigset_t s; sigemptyset(&s); sigaddset(&s, SIGSYS); sigprocmask(SIG_BLOCK, &s, 0); (void)c; execv(v[1], v + 1); return 127; }
EOC
gcc -O2 -Wall "$W/blocked.c" -o "$W/blocked"

# The app's files: zips unpacked like the app does (no modes), etc/ as
# NativeDesk.kt writes it. Flatpak's own data is kept between runs unless
# DDSIM_FRESH=1.
[ "${DDSIM_FRESH:-0}" = 1 ] && rm -rf "$F"
rm -rf "$F/glibc" "$F/flatpak-cli"
unzipnomode() { python3 -c 'import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$1" "$2"; }
unzipnomode "$L/libdd_glibc.so" "$F/glibc"
unzipnomode "$L/libdd_flatpakcli.so" "$F/flatpak-cli"
uid="$(id -u)"
mkdir -p "$F/home" "$F/glibc/etc"
printf 'root:x:0:0:root:/:/system/bin/sh\ndeskdroid:x:%s:%s:DeskDroid:%s/home:/system/bin/sh\n' "$uid" "$uid" "$F" > "$F/glibc/etc/passwd"
printf 'root:x:0:\ndeskdroid:x:%s:\n' "$uid" > "$F/glibc/etc/group"
grep '^nameserver' /etc/resolv.conf > "$F/glibc/etc/resolv.conf" || echo 'nameserver 8.8.8.8' > "$F/glibc/etc/resolv.conf"
# This machine's HTTPS proxy, if any, signs with its own CA.
[ -n "${SSL_CERT_FILE:-}" ] && cat "$SSL_CERT_FILE" >> "$F/flatpak-cli/etc/ssl/certs/ca-certificates.crt"
# Android's shell; here this machine's, which ddmask starts on DeskDroid's
# glibc. A copy, not a link: a link into /bin would resolve to Flatpak's /bin
# (ddflatpak maps it), where Android's /system/bin/sh doesn't go.
mkdir -p /system/bin && rm -f /system/bin/sh && cp /bin/dash /system/bin/sh

fp() {
  env -i PATH=/usr/bin:/bin HOME="$F/home" TMPDIR="$F/flatpak-tmp" \
    ${HTTPS_PROXY:+HTTPS_PROXY=$HTTPS_PROXY https_proxy=$HTTPS_PROXY} \
    DESKDROID_FILES="$F" DESKDROID_LIBS="$L" DESKDROID_FLATPAK_ARCH=x86_64 \
    DESKDROID_GLIBC_RUN="$L/android-sim $L/libdd_ld-glibc.so" QT_QPA_PLATFORM=offscreen \
    /bin/sh "$L/libdd_flatpak.so" "$@"
}
export -f fp
export F L APP
fails=0
step() {
  local name="$1"; shift
  local out rc
  out="$(timeout "${DDSIM_TIMEOUT:-1800}" bash -c '"$@"' step "$@" 2>&1)"; rc=$?
  if [ $rc -eq 0 ]; then echo "ok   $name"; else echo "FAIL $name (exit $rc)"; fails=$((fails + 1)); fi
  printf '%s\n' "$out" | tail -n "${DDSIM_LINES:-6}" | sed 's/^/     /'
  [ -s "$F/glibc/sigsys.log" ] && echo "     blocked calls caught: $(sort -un "$F/glibc/sigsys.log" | tr '\n' ' ')"
  return 0
}
step "a program started with SIGSYS blocked survives Android's blocked calls" \
  "$W/blocked" "$L/android-sim" "$L/libdd_ld-glibc.so" /bin/true
step "add Flathub" fp remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
step "fetch Flathub's catalog" fp update --user --appstream flathub
[ -e "$F/flatpak/appstream/flathub/x86_64/active/appstream.xml.gz" ] && echo "ok   catalog is where Discover reads it" || { echo "FAIL catalog missing"; fails=$((fails + 1)); }
# A remote left without its signing key (remote-add stopped partway on an
# earlier build): adding it again must repair it, as Discover does each start.
rm -f "$F/flatpak/repo/flathub.trustedkeys.gpg"
step "repair Flathub left without its key" fp remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
step "fetch the catalog again" fp update --user --appstream flathub
step "install $APP" fp install --user -y flathub "$APP"
step "list installed apps" fp list --user --app --columns=application,version
step "list updates" fp remote-ls --user --updates --app --columns=application
# A GUI app on Qt's offscreen platform: it counts as started if it's still
# running after a few seconds.
# (Its own process group, so stopping it stops the app, not just the shell.)
run_app() {
  setsid bash -c 'fp run "$APP"' & local p=$!
  sleep "${DDSIM_RUN_SECS:-15}"
  if kill -0 $p 2>/dev/null; then kill -- -$p; wait $p 2>/dev/null; return 0; fi
  wait $p
}
export -f run_app
step "run $APP" run_app
step "update $APP" fp update --user -y "$APP"
step "remove $APP" fp uninstall --user -y "$APP"
[ $fails -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
