#!/usr/bin/env bash
# Packs a build.sh output into a DeskDroid store package with
# tools/flathub-adpk (the program kind, on the KDE 6.11 runtime package):
#   native/viperfx/adpk.sh <build out dir> <out.adpk>
# Needs ddapp for Android: $DDAPP_BIN, or $ANDROID_NDK_HOME to build it.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$HERE/../../tools/flathub-adpk"
B="$(cd "$1" && pwd)"; OUT="$2"
FP="$B/.flatpak"; ID=org.deskdroid.ViperFX
D="$FP/app/$ID/aarch64/stable/active"
rm -rf "$FP"; mkdir -p "$D"
ln -s "$B/app" "$D/files"
cp "$B/metadata" "$D/metadata"
if [ -z "${DDAPP_BIN:-}" ]; then
  CC="$(ls -d "${ANDROID_NDK_HOME:?set DDAPP_BIN or ANDROID_NDK_HOME}"/toolchains/llvm/prebuilt/linux-x86_64/bin)/aarch64-linux-android26-clang"
  export DDAPP_BIN="$B/.ddapp"
  "$CC" -O2 -Wall -fPIE -pie -s -o "$DDAPP_BIN" "$TOOLS/ddapp.c"
fi
python3 "$TOOLS/flathub-adpk.py" app "$FP" "$ID" viperfx runtime-kde-6.11 "$OUT" \
  --name "ViPER FX" --summary "ViPER4Android's sound effects for the desktop's sound"
# flatpak info has no version for a local build: the store shows app.json's.
python3 - "$OUT" "${VIPERFX_VERSION:-0.1}" <<'PY'
import json, sys, zipfile, shutil, os
src, ver = sys.argv[1], sys.argv[2]
tmp = src + ".tmp"
with zipfile.ZipFile(src) as zi, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zo:
    for e in zi.infolist():
        data = zi.read(e)
        if e.filename == "app.json":
            j = json.loads(data); j["version"] = ver; data = json.dumps(j, indent=1).encode()
        zo.writestr(e, data)
os.replace(tmp, src)
PY
echo "made $OUT"
