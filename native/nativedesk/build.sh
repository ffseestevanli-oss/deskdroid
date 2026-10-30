#!/usr/bin/env bash
# Builds the native desktop test (compositor.c as the JNI library
# libnativedesk.so, testclient.c as the executable libnativedesk_client.so)
# into <outdir>. Android-only: it links the NDK's EGL, GLES and
# AHardwareBuffer libraries.
# With DESKDROID_QT_ANDROID (Qt for Android, arm64) and DESKDROID_QT_HOST (the
# matching desktop Qt) set, also builds the Qt demo (qt/) as
# libnativedesk_qt.so and copies the Qt libraries it needs next to it.
#   native/nativedesk/build.sh <outdir> <ndk-dir> [api-level]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
NDK="$2"
API="${3:-29}"
host="$(uname -s | tr A-Z a-z)-x86_64"
BIN="$NDK/toolchains/llvm/prebuilt/$host/bin"
CC="$BIN/aarch64-linux-android$API-clang"
FLAGS=(-O2 -Wall -Wextra -Wno-unused-result "-ffile-prefix-map=$HERE=." -Wl,--build-id=none -Wl,-z,noexecstack)

"$CC" "${FLAGS[@]}" -shared -fPIC "$HERE/compositor.c" -o "$OUT/libnativedesk.so" \
  -landroid -lnativewindow -lEGL -lGLESv2 -llog
"$CC" "${FLAGS[@]}" -fPIE -pie "$HERE/testclient.c" -o "$OUT/libnativedesk_client.so" \
  -lnativewindow -lEGL -lGLESv2 -lm
"$BIN/llvm-strip" --strip-unneeded "$OUT/libnativedesk.so" "$OUT/libnativedesk_client.so"

if [ -n "${DESKDROID_QT_ANDROID:-}" ]; then
  echo "== native desktop test: Qt demo ($DESKDROID_QT_ANDROID)"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  cmake -S "$HERE/qt" -B "$WORK" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$DESKDROID_QT_ANDROID/lib/cmake/Qt6/qt.toolchain.cmake" \
    -DQT_HOST_PATH="$DESKDROID_QT_HOST" -DANDROID_NDK_ROOT="$NDK" -DANDROID_SDK_ROOT="${ANDROID_HOME:-}"
  cmake --build "$WORK"
  install -m 755 "$WORK/nativedesk_qt" "$OUT/libnativedesk_qt.so"
  "$BIN/llvm-strip" --strip-unneeded "$OUT/libnativedesk_qt.so"
  for lib in Core Gui OpenGL; do
    install -m 644 "$DESKDROID_QT_ANDROID/lib/libQt6${lib}_arm64-v8a.so" "$OUT/"
  done
  install -m 644 "$NDK/toolchains/llvm/prebuilt/$host/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" "$OUT/"
else
  echo "== native desktop test: no DESKDROID_QT_ANDROID, skipping the Qt demo"
fi
