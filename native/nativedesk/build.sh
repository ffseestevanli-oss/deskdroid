#!/usr/bin/env bash
# Builds the native desktop test (compositor.c as the JNI library
# libnativedesk.so, testclient.c as the executable libnativedesk_client.so)
# into <outdir>. Android-only: it links the NDK's EGL, GLES and
# AHardwareBuffer libraries.
# With DESKDROID_QT_ANDROID (Qt for Android, arm64) and DESKDROID_QT_HOST (the
# matching desktop Qt) set, also builds the Qt demo (qt/) as
# libnativedesk_qt.so and copies the Qt libraries it needs next to it. When
# that Qt is DeskDroid's own build with KWin (native/plasma), bundles KWin too.
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
  install -m 755 "$WORK/libnativedesk_qt.so" "$OUT/libnativedesk_qt.so"
  "$BIN/llvm-strip" --strip-unneeded "$OUT/libnativedesk_qt.so"
  # Every Qt library it needs, directly or through another Qt library.
  todo=("$OUT/libnativedesk_qt.so")
  while [ ${#todo[@]} -gt 0 ]; do
    f="${todo[0]}"; todo=("${todo[@]:1}")
    for lib in $("$BIN/llvm-readelf" -d "$f" | sed -n 's/.*Shared library: \[\(libQt6[^]]*\)\].*/\1/p'); do
      [ -e "$OUT/$lib" ] && continue
      install -m 644 "$DESKDROID_QT_ANDROID/lib/$lib" "$OUT/"
      echo "   + $lib"
      todo+=("$OUT/$lib")
    done
  done
  install -m 644 "$NDK/toolchains/llvm/prebuilt/$host/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" "$OUT/"

  # Stage 3: KWin, when the Qt is DeskDroid's own build (native/plasma), which
  # has it. Everything libkwin_wayland.so needs from that prefix goes next to
  # it. APKs only carry files named lib*.so, so versioned names (libfoo.so.6)
  # lose the version, in the files and in what the libraries ask for.
  if [ -e "$DESKDROID_QT_ANDROID/lib/libkwin_wayland.so" ]; then
    echo "== native desktop test: KWin"
    command -v patchelf >/dev/null || { echo "patchelf is needed to bundle KWin"; exit 1; }
    sysroot="$NDK/toolchains/llvm/prebuilt/$host/sysroot/usr/lib/aarch64-linux-android"
    unversioned() { local n="${1%%.so*}.so"; echo "$n"; }
    install -m 755 "$DESKDROID_QT_ANDROID/lib/libkwin_wayland.so" "$OUT/libkwin_wayland.so"
    # The Qt libraries already copied count too: some need non-Qt libraries
    # (QtDBus needs libdbus-1).
    bundled=("$OUT/libkwin_wayland.so" "$OUT"/libQt6*.so)
    todo=("${bundled[@]}")
    while [ ${#todo[@]} -gt 0 ]; do
      f="${todo[0]}"; todo=("${todo[@]:1}")
      for lib in $("$BIN/llvm-readelf" -d "$f" | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p'); do
        name="$(unversioned "$lib")"
        [ -e "$OUT/$name" ] && continue
        [ -e "$sysroot/$API/$name" ] || [ -e "$sysroot/$name" ] && continue # Android's own
        if [ ! -e "$DESKDROID_QT_ANDROID/lib/$lib" ]; then echo "   ? $lib (not in the prefix)"; continue; fi
        install -m 644 "$DESKDROID_QT_ANDROID/lib/$lib" "$OUT/$name"
        echo "   + $name"
        bundled+=("$OUT/$name")
        todo+=("$DESKDROID_QT_ANDROID/lib/$lib")
      done
    done
    for f in "${bundled[@]}"; do
      args=()
      for lib in $("$BIN/llvm-readelf" -d "$f" | sed -n 's/.*Shared library: \[\([^]]*\.so\.[^]]*\)\].*/\1/p'); do
        args+=(--replace-needed "$lib" "$(unversioned "$lib")")
      done
      soname="$("$BIN/llvm-readelf" -d "$f" | sed -n 's/.*Library soname: \[\([^]]*\)\].*/\1/p')"
      [ -n "$soname" ] && [ "$soname" != "$(basename "$f")" ] && args+=(--set-soname "$(basename "$f")")
      [ ${#args[@]} -gt 0 ] && patchelf --page-size 16384 "${args[@]}" "$f"
      "$BIN/llvm-strip" --strip-unneeded "$f"
    done
    echo "   ${#bundled[@]} libraries, $(du -ch "${bundled[@]}" | tail -1 | cut -f1)"
    # Data KWin reads at run time (keyboard layouts, its own files), as a zip
    # named like a library so it ships the same way; the app unpacks it.
    rm -f "$OUT/libkwin_data.so"
    (cd "$DESKDROID_QT_ANDROID" && zip -qr -X "$OUT/libkwin_data.so" share/X11/xkb $(ls -d share/kwin* 2>/dev/null))
    echo "   data: $(du -h "$OUT/libkwin_data.so" | cut -f1)"
  fi
else
  echo "== native desktop test: no DESKDROID_QT_ANDROID, skipping the Qt demo"
fi
