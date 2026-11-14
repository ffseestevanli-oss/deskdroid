#!/usr/bin/env bash
# Builds ViPER FX for DeskDroid (aarch64, Flathub's KDE runtime 6.11) into
# <out>/app: the Flatpak-style /app tree tools/flathub-adpk packs.
#   native/viperfx/build.sh <out dir>
# Needs clang, lld, qemu-aarch64 (for Qt's moc and rcc from the SDK) and
# org.kde.Sdk//6.11 for aarch64 in a flatpak user dir ($FLATPAK_USER_DIR,
# default ~/.cache/deskdroid/flathub-adpk, the same as flathub-adpk's).
# VIPERFX_HOST=1 builds dsptest for this machine instead and runs it.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC=(engine/ViperDsp.cpp $(cd "$HERE" && ls engine/viperfx_re/viper/*.cpp engine/viperfx_re/viper/*/*.cpp))
INC=(-I"$HERE/engine" -I"$HERE/engine/viperfx_re" -I"$HERE/engine/viperfx_re/include" -I"$HERE/engine/viperfx_re/viper")
if [ "${VIPERFX_HOST:-}" = 1 ]; then
  clang++ -std=c++20 -O2 -w "${INC[@]}" "${SRC[@]/#/$HERE/}" "$HERE/tests/dsptest.cpp" -o "${1:-/tmp}/dsptest"
  exec "${1:-/tmp}/dsptest"
fi
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
FU="${FLATPAK_USER_DIR:-$HOME/.cache/deskdroid/flathub-adpk}"
SDK="$FU/runtime/org.kde.Sdk/aarch64/6.11/active/files"
[ -e "$SDK/include/pipewire-0.3/pipewire/pipewire.h" ] || {
  echo "needs org.kde.Sdk//6.11 for aarch64: flatpak install --user --arch=aarch64 flathub runtime/org.kde.Sdk/aarch64/6.11" >&2; exit 1; }
W="$OUT/.work"; mkdir -p "$W/obj" "$W/sysroot"
ln -sfn "$SDK" "$W/sysroot/usr"; ln -sfn usr/lib "$W/sysroot/lib"
SR="$W/sysroot"
QEMU="qemu-aarch64 -L $SR"
T=aarch64-unknown-linux-gnu
CXX=(clang++ --target=$T --sysroot="$SR" -std=c++20 -O2 -fPIC -ffunction-sections -fdata-sections)
QI="$SR/usr/include"
QT=(-I"$QI/QtCore" -I"$QI/QtGui" -I"$QI/QtQml" -I"$QI/QtQuick" -I"$QI/QtQuickControls2" -I"$QI/QtNetwork" -I"$QI"
    -I"$QI/pipewire-0.3" -I"$QI/spa-0.2" -DQT_NO_DEBUG -DVIPERFX_VERSION="\"${VIPERFX_VERSION:-0.1}\"")
$QEMU "$SDK/lib/libexec/moc" "${QT[@]}" "$HERE/src/Backend.h" -o "$W/moc_Backend.cpp"
(cd "$HERE" && $QEMU "$SDK/lib/libexec/rcc" -name viperfx viperfx.qrc -o "$W/qrc_viperfx.cpp")
pids=()
for f in "${SRC[@]}"; do
  o="$W/obj/$(echo "$f" | tr / _).o"
  [ "$o" -nt "$HERE/$f" ] && continue
  "${CXX[@]}" -w "${INC[@]}" -c "$HERE/$f" -o "$o" & pids+=($!)
  [ ${#pids[@]} -ge 4 ] && { wait "${pids[0]}"; pids=("${pids[@]:1}"); }
done
for f in src/main.cpp src/Backend.cpp src/PwEngine.cpp; do
  "${CXX[@]}" -Wall -Wno-vla-cxx-extension "${INC[@]}" "${QT[@]}" -c "$HERE/$f" -o "$W/obj/$(basename "$f").o" & pids+=($!)
done
"${CXX[@]}" "${QT[@]}" -c "$W/moc_Backend.cpp" -o "$W/obj/moc.o" & pids+=($!)
"${CXX[@]}" "${QT[@]}" -c "$W/qrc_viperfx.cpp" -o "$W/obj/qrc.o" & pids+=($!)
for p in "${pids[@]}"; do wait "$p"; done
A="$OUT/app"; rm -rf "$A"; mkdir -p "$A/bin" "$A/share/applications" "$A/share/metainfo" "$A/share/icons/hicolor/scalable/apps" \
  "$A/share/icons/hicolor/128x128/apps" "$A/share/licenses/viperfx"
"${CXX[@]}" -fuse-ld=lld -Wl,--gc-sections -Wl,--as-needed -Wl,-O1 -s "$W"/obj/*.o -o "$A/bin/viperfx" \
  -L"$SR/usr/lib/$(echo aarch64-linux-gnu)" -lQt6Quick -lQt6QuickControls2 -lQt6Qml -lQt6Network -lQt6Gui -lQt6Core -lpipewire-0.3 -lpthread
cp "$HERE/data/org.deskdroid.ViperFX.desktop" "$A/share/applications/"
cp "$HERE/data/org.deskdroid.ViperFX.metainfo.xml" "$A/share/metainfo/"
cp "$HERE/data/viperfx.svg" "$A/share/icons/hicolor/scalable/apps/org.deskdroid.ViperFX.svg"
rsvg-convert -w 128 -h 128 "$HERE/data/viperfx.svg" -o "$A/share/icons/hicolor/128x128/apps/org.deskdroid.ViperFX.png"
cp "$HERE/data/fonts/"*-OFL.txt "$HERE/README.md" "$A/share/licenses/viperfx/" 2>/dev/null || true
cat > "$OUT/metadata" <<META
[Application]
name=org.deskdroid.ViperFX
runtime=org.kde.Platform/aarch64/6.11
sdk=org.kde.Sdk/aarch64/6.11
command=viperfx

[Context]
shared=ipc;
sockets=wayland;fallback-x11;pulseaudio;
filesystems=xdg-run/pipewire-0;home;
META
echo "built $A/bin/viperfx"
