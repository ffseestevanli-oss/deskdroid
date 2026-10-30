#!/usr/bin/env bash
# Builds the native desktop test (compositor.c as the JNI library
# libnativedesk.so, testclient.c as the executable libnativedesk_client.so)
# into <outdir>. Android-only: it links the NDK's EGL, GLES and
# AHardwareBuffer libraries.
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
