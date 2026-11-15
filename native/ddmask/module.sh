#!/usr/bin/env bash
# Packs the ddmask module: ddmask's libraries and the scripts that start Linux
# and Flathub apps, as a package (.adpk) Software installs like any other, so
# a ddmask fix reaches the phone without a new APK. Temporary: once ddmask
# settles it only ships in the APK again.
#
#   native/ddmask/module.sh <app.apk | its lib/arm64-v8a folder> <out.adpk> [version]
#
# Takes the files from an APK build (CI's), so the module and that APK carry
# the same ddmask. Installed, it's store/apps/ddmask/program:
#
#   api-1               this module fits APKs that know module api 1
#   lib/libddmask.so          Android (bionic) programs, if Android's linker
#                             takes it from app files (NativeDesk.kt checks)
#   lib/libddmask_glibc.so, libddmask_musl.so    glibc and musl programs
#   lib/libddflatpak.so, libddflatpak_audit.so   Flatpak's paths
#   scripts/adpk-run.sh, flatpak.sh, fex-run.sh, bwrap.sh, xwayland.sh  how apps start
#
# What stays in the APK, always: the loaders and runners ddmask execs
# (libdd_ld-glibc.so, libdd_ld-musl.so...), since Android only runs programs
# from the APK's library folder; and the APK's own copies of everything
# above, used whenever the module isn't installed or doesn't fit.
set -euo pipefail
src="${1:?an APK or its lib/arm64-v8a folder}" out="${2:?the .adpk to write}"
version="${3:-$(git -C "$(dirname "$0")" describe --always --dirty 2>/dev/null || date +%Y%m%d)}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
if [ -d "$src" ]; then libs="$src"
else
  mkdir -p "$T/apk" && unzip -q -o "$src" 'lib/arm64-v8a/*' -d "$T/apk"
  libs="$T/apk/lib/arm64-v8a"
fi
P="$T/pkg/program"
mkdir -p "$P/lib" "$P/scripts"
for f in libddmask.so libddmask_glibc.so libddmask_musl.so libddflatpak.so libddflatpak_audit.so; do
  [ -e "$libs/$f" ] && cp "$libs/$f" "$P/lib/"
done
[ -e "$P/lib/libddmask_glibc.so" ] || { echo "module.sh: no libddmask_glibc.so in $src" >&2; exit 1; }
cp "$libs/libdd_adpk_run.so" "$P/scripts/adpk-run.sh"
cp "$libs/libdd_flatpak.so" "$P/scripts/flatpak.sh"
[ -e "$libs/libdd_flatpak_fex.so" ] && cp "$libs/libdd_flatpak_fex.so" "$P/scripts/fex-run.sh"
[ -e "$libs/libdd_bwrap.so" ] && cp "$libs/libdd_bwrap.so" "$P/scripts/bwrap.sh"
[ -e "$libs/libdd_xwayland.so" ] && cp "$libs/libdd_xwayland.so" "$P/scripts/xwayland.sh"
: > "$P/api-1"
echo "$version" > "$P/version.txt"
cd "$T/pkg"
echo ddmask > app.txt
printf '{"id":"ddmask","name":"ddmask","summary":"DeskDroid'"'"'s compatibility layer for Linux apps, updated apart from the app","version":"%s","kind":"runtime"}\n' "$version" > app.json
# Nothing to open: Software then doesn't give it a command of its own.
echo true > open.txt
rm -f "$out"
zip -q -r -X "$(cd "$OLDPWD" && realpath -m "$out")" app.txt app.json open.txt program
echo "ddmask module $version: $out ($(ls "$P/lib" | tr '\n' ' '))"
