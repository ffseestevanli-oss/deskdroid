#!/usr/bin/env bash
# Tests the ddmask module (../module.sh) on a desktop machine: the package it
# makes, and that ddmask and the launch scripts use an installed module's
# copies, falling back to the APK's when there's none or it doesn't fit.
set -euo pipefail
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
# An APK's library folder, as the build lays it out.
A="$T/apk-libs"; mkdir -p "$A"
cc -O2 -shared -fPIC "$HERE/../ddmask.c" -o "$A/libddmask.so" -ldl
cc -O2 -shared -fPIC -DDDMASK_GLIBC "$HERE/../ddmask.c" -o "$A/libddmask_glibc.so" -ldl
cc -O2 -shared -fPIC "$HERE/../ddflatpak.c" -o "$A/libddflatpak.so" -ldl
cp "$HERE/../../flatpak/adpk-run.sh" "$A/libdd_adpk_run.so"
cp "$HERE/../../flatpak/flatpak.sh" "$A/libdd_flatpak.so"
cp "$HERE/../../flatpak/fex-run.sh" "$A/libdd_flatpak_fex.so"
bash "$HERE/../module.sh" "$A" "$T/ddmask.adpk" test-1 >/dev/null
list="$(unzip -Z1 "$T/ddmask.adpk")"
expect "the package has its manifest, api marker, libraries and scripts" "$list" \
  "^app.json$" "^app.txt$" "^program/api-1$" "^program/lib/libddmask_glibc.so$" "^program/lib/libddflatpak.so$" \
  "^program/scripts/adpk-run.sh$" "^program/scripts/flatpak.sh$" "^program/scripts/fex-run.sh$"
expect "...and says what it is" "$(unzip -p "$T/ddmask.adpk" app.json)" '"id":"ddmask"' '"version":"test-1"' '"kind":"runtime"'

# Installed as Software would: store/apps/ddmask/program.
F="$T/files"; M="$F/store/apps/ddmask/program"
mkdir -p "$F/store/apps/ddmask" && (cd "$F/store/apps/ddmask" && unzip -q "$T/ddmask.adpk" 'program/*')
# The module's scripts say which copy ran.
for s in "$M"/scripts/*.sh; do sed -i '2i echo "running: $0" >&2' "$s"; done

# ddmask (bionic, from the APK) gives glibc programs the module's glibc build.
cat > "$T/probe.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
int main(int c, char **v) {
    if (c > 1) { execl("/usr/bin/env", "env", (char *)0); return 1; }
    return 0;
}
C
cc -O2 "$T/probe.c" -o "$T/probe"
glibc_preload() { # [env...]
  env LD_PRELOAD="$A/libddmask.so" DDMASK_LIBS="$A" "$@" "$T/probe" x 2>/dev/null | sed -n 's/^DDMASK_GLIBC_LD_PRELOAD=//p'
}
# (ddmask hands the glibc build to glibc programs it starts; here every
# program is glibc, so the variable it sets is the sign.)
out="$(glibc_preload DDMASK_MODULE="$M")"
expect "ddmask hands glibc programs the module's glibc build" "x$out" "$M/lib/libddmask_glibc.so"
out="$(glibc_preload DDMASK_MODULE="$T/none")"
expect "...and the APK's when no module is installed" "x$out" "$A/libddmask_glibc.so"
mv "$M/api-1" "$M/api-0"
out="$(glibc_preload DDMASK_MODULE="$M")"
expect "...or when the module doesn't fit this APK (no api-1)" "x$out" "$A/libddmask_glibc.so"
mv "$M/api-0" "$M/api-1"

# The APK's scripts hand over to the module's.
out="$(env -i PATH=/usr/bin:/bin DDMASK_MODULE="$M" DESKDROID_SH=/bin/sh DESKDROID_FILES="$F" DESKDROID_LIBS="$A" \
  FEXRUN_ID=x FEXRUN_APP=/a FEXRUN_RT=/r DESKDROID_FEX=/nofex sh "$A/libdd_flatpak_fex.so" tool 2>&1 || true)"
expect "the APK's fex-run.sh runs the module's copy" "$out" "^running: $M/scripts/fex-run.sh$" "Steam Installation Assistant"
out="$(env -i PATH=/usr/bin:/bin DDMASK_MODULE="$T/none" DESKDROID_SH=/bin/sh DESKDROID_FILES="$F" DESKDROID_LIBS="$A" \
  FEXRUN_ID=x FEXRUN_APP=/a FEXRUN_RT=/r DESKDROID_FEX=/nofex sh "$A/libdd_flatpak_fex.so" tool 2>&1 || true)"
expect "...and its own without a module" "running:none|$out" "^running:none\|" "Steam Installation Assistant"
if grep -q "^running:" <<<"$out"; then echo "FAIL ...but it ran a module copy"; fails=$((fails+1)); fi
mkdir -p "$F/glibc/lib" && : > "$F/glibc/lib/libc.so.6" && : > "$A/libdd_ld-glibc.so"
mkdir -p "$F/store/apps/app/program/files" "$F/store/apps/runtime-kde-6.11/program/files" "$F/store/apps/runtime-mesa-25.08/program"
for d in app runtime-kde-6.11 runtime-mesa-25.08; do : > "$F/store/apps/$d/app.txt"; : > "$F/store/apps/$d/program/.ddsetup-done"; done
printf '[Application]\nname=org.example.App\nruntime=org.kde.Platform/aarch64/6.11\ncommand=app\n' > "$F/store/apps/app/program/metadata"
printf '[Runtime]\nruntime=org.kde.Platform/aarch64/6.11\n' > "$F/store/apps/runtime-kde-6.11/program/metadata"
printf '#!/bin/sh\nenv\n' > "$T/loader"; chmod +x "$T/loader"
out="$(env -i PATH=/usr/bin:/bin HOME="$T/home" XDG_RUNTIME_DIR="$T/run" DDMASK_MODULE="$M" DESKDROID_SH=/bin/sh DESKDROID_FILES="$F" \
  DESKDROID_LIBS="$A" DESKDROID_GLIBC_RUN="$T/loader" DESKDROID_CRASH_DIALOG=0 DDAPP_PROGRAM="$F/store/apps/app/program" \
  sh "$A/libdd_adpk_run.so" 2>&1; cat "$F/store/apps/app/run.log")"
expect "the APK's adpk-run.sh runs the module's copy, with the module's libraries" "$out" \
  "^running: $M/scripts/adpk-run.sh$" "^DDMASK_GLIBC_LD_PRELOAD=$M/lib/libddflatpak.so:$M/lib/libddmask_glibc.so$"

[ "$fails" -eq 0 ] && echo "all module tests passed" || { echo "$fails failed"; exit 1; }
