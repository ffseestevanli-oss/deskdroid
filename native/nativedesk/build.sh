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
  # lose the version. And Android has its own libinput, libdrm, libexpat...,
  # which ours would shadow (app_process itself then fails to link), so
  # libraries other than Qt's, KDE's and KWin's get a libdd_ prefix. Both
  # renames apply to the files, their sonames and what the libraries ask for.
  if [ -e "$DESKDROID_QT_ANDROID/lib/libkwin_wayland.so" ]; then
    echo "== native desktop test: KWin"
    command -v patchelf >/dev/null || { echo "patchelf is needed to bundle KWin"; exit 1; }
    sysroot="$NDK/toolchains/llvm/prebuilt/$host/sysroot/usr/lib/aarch64-linux-android"
    unversioned() { echo "${1%%.so*}.so"; }
    bundlename() {
      local n; n="$(unversioned "$1")"
      case "$n" in libQt6*|libKF6*|libkwin*|libkdecorations*|libKWayland*|libplasmashell*) echo "$n" ;; *) echo "libdd_${n#lib}" ;; esac
    }
    install -m 755 "$DESKDROID_QT_ANDROID/lib/libkwin_wayland.so" "$OUT/libkwin_wayland.so"
    # The Qt libraries already copied count too: some need non-Qt libraries
    # (QtDBus needs libdbus-1).
    bundled=("$OUT/libkwin_wayland.so" "$OUT/libnativedesk_qt.so" "$OUT"/libQt6*.so)
    # Stage 4: plasmashell, a library started by QtHost like KWin.
    if [ -e "$DESKDROID_QT_ANDROID/lib/libplasmashell.so" ]; then
      install -m 755 "$DESKDROID_QT_ANDROID/lib/libplasmashell.so" "$OUT/libplasmashell.so"
      bundled+=("$OUT/libplasmashell.so")
    fi
    # Stage 5: apps, built as libraries too (native/plasma/apps/as-library.py),
    # each started by its command bin/<app>, a link to libdd_qtapp.so (qtapp.sh).
    apps=()
    for app in dolphin kioworker; do
      [ -e "$DESKDROID_QT_ANDROID/lib/lib$app.so" ] || continue
      install -m 755 "$DESKDROID_QT_ANDROID/lib/lib$app.so" "$OUT/libdd_$app.so"
      bundled+=("$OUT/libdd_$app.so"); apps+=("$app")
    done
    printf '%s\n' "${apps[@]}" > "$WORK/apps.txt"
    if [ ${#apps[@]} -gt 0 ]; then
      install -m 755 "$HERE/qtapp.sh" "$OUT/libdd_qtapp.so"
      # Open with Android app: bin/android-open (android-open.sh).
      install -m 755 "$HERE/android-open.sh" "$OUT/libdd_android-open.so"
      echo "   apps: ${apps[*]}"
    fi
    # Plugins (Qt's Wayland client, KDE's and KWin's), also flat in the
    # library folder: Qt and KDE on Android look there for files named
    # libplugins_<plugin folder, / as _>_<name>.so. Qt's Android build names
    # its plugins that way already. Android's own platform plugin stays out.
    # The D-Bus session bus, a program shipped under a library's name.
    if [ -e "$DESKDROID_QT_ANDROID/bin/dbus-daemon" ]; then
      install -m 755 "$DESKDROID_QT_ANDROID/bin/dbus-daemon" "$OUT/libdd_dbus-daemon.so"
      bundled+=("$OUT/libdd_dbus-daemon.so")
    fi
    plugins=0
    : > "$WORK/plugins.txt" # flat name, then the path under plugins/ (KDE looks there by namespace)
    if [ -d "$DESKDROID_QT_ANDROID/plugins" ]; then
      while IFS= read -r rel; do
        dir="$(dirname "$rel")"; base="$(basename "$rel")"
        case "$base" in
          libplugins_*) name="$base" ;;
          *) name="libplugins_${dir//\//_}_${base#lib}" ;;
        esac
        # KDE plugins installed flat (kcoreaddons_add_plugin's Android
        # naming) go back into their namespace folder, where KDE looks.
        linkrel="$rel"
        if [ "$dir" = . ]; then
          for ns in kf6/packagestructure kf6/urifilters kf6/kiod kf6/kio_dnd kf6/kio kf6/kded kf6/parts kf6/thumbcreator \
                    kwin/effects/plugins kwin/plugins plasma/applets plasma/containmentactions plasma5support/dataengine org.kde.kdecoration3; do
            flatns="libplugins_${ns//\//_}_"
            case "$base" in "$flatns"*) linkrel="$ns/${base#"$flatns"}"; break ;; esac
          done
        fi
        case "$rel" in platforms/*) case "$base" in *wayland*) ;; *) continue ;; esac ;; esac
        install -m 644 "$DESKDROID_QT_ANDROID/plugins/$rel" "$OUT/$name"
        bundled+=("$OUT/$name"); plugins=$((plugins + 1))
        printf '%s\t%s\n' "$name" "$linkrel" >> "$WORK/plugins.txt"
      done < <(cd "$DESKDROID_QT_ANDROID/plugins" && find . -name '*.so' | sed 's|^\./||' | sort)
      echo "   $plugins plugins"
    fi
    # QML modules (Qt's, KDE's), for plasmashell: their plugins flat in the
    # library folder like the others (libqml_<path, / as _>.so), the rest
    # (qmldir, .qml files) in the data; the app links each plugin back under
    # its own name next to its qmldir, where Qt looks for it.
    : > "$WORK/qml.txt"
    # Qt's modules are in <prefix>/qml, KDE's may be in <prefix>/lib/qml.
    qmlroots=()
    for d in "$DESKDROID_QT_ANDROID" "$DESKDROID_QT_ANDROID/lib"; do [ -d "$d/qml" ] && qmlroots+=("$d"); done
    if [ -e "$OUT/libplasmashell.so" ] && [ ${#qmlroots[@]} -gt 0 ]; then
      qmlskip='^(QtTest|QtWayland|Qt3D|QtQuick3D|QtMultimedia|QtQuick/VirtualKeyboard|QtQuick/Scene[23]D|QtQuick/Controls/(Imagine|FluentWinUI3|iOS|macOS|Windows))(/|$)'
      qmlplugins=0
      for root in "${qmlroots[@]}"; do
        while IFS= read -r rel; do
          name="libqml_$(echo "${rel%.so}" | tr '/' '_').so"
          install -m 644 "$root/qml/$rel" "$OUT/$name"
          bundled+=("$OUT/$name"); qmlplugins=$((qmlplugins + 1))
          printf '%s\t%s\n' "$name" "$rel" >> "$WORK/qml.txt"
        done < <(cd "$root/qml" && find . -name '*.so' | sed 's|^\./||' | grep -Ev "$qmlskip" | sort)
      done
      echo "   $qmlplugins QML plugins"
    fi
    todo=("${bundled[@]}")
    while [ ${#todo[@]} -gt 0 ]; do
      f="${todo[0]}"; todo=("${todo[@]:1}")
      for lib in $("$BIN/llvm-readelf" -d "$f" | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p'); do
        [ -e "$sysroot/$API/$(unversioned "$lib")" ] || [ -e "$sysroot/$(unversioned "$lib")" ] && continue # Android's own
        name="$(bundlename "$lib")"
        [ -e "$OUT/$name" ] && continue
        src="$DESKDROID_QT_ANDROID/lib/$lib"
        # The NDK's own runtime libraries (libomp, for code built with OpenMP).
        [ -e "$src" ] || src="$(find "$NDK/toolchains/llvm/prebuilt/$host/lib" -path '*aarch64*' -name "$lib" 2>/dev/null | head -1)"
        if [ ! -e "$src" ]; then echo "   ? $lib (not in the prefix)"; continue; fi
        install -m 644 "$src" "$OUT/$name"
        echo "   + $name"
        bundled+=("$OUT/$name")
        todo+=("$src")
      done
    done
    for f in "${bundled[@]}"; do
      args=()
      for lib in $("$BIN/llvm-readelf" -d "$f" | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p'); do
        name="$(bundlename "$lib")"
        [ "$name" != "$lib" ] && [ -e "$OUT/$name" ] && args+=(--replace-needed "$lib" "$name")
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
    (cd "$DESKDROID_QT_ANDROID" && zip -qr -X "$OUT/libkwin_data.so" share/X11/xkb \
      $(ls -d share/kwin* share/icons/breeze_cursors share/color-schemes 2>/dev/null))
    (cd "$WORK" && zip -q -X "$OUT/libkwin_data.so" plugins.txt)
    if [ -e "$OUT/libplasmashell.so" ]; then
      # plasmashell's: Plasma's themes and packages, DeskDroid's first shell
      # (native/plasma/shell), and the QML modules' files.
      (cd "$DESKDROID_QT_ANDROID" && zip -qr -X "$OUT/libkwin_data.so" $(ls -d share/plasma share/kf6 2>/dev/null))
      rm -rf "$WORK/shell" && mkdir -p "$WORK/shell/share/plasma"
      cp -r "$HERE/../plasma/shell/shells" "$HERE/../plasma/shell/plasmoids" "$HERE/../plasma/shell/wallpapers" "$WORK/shell/share/plasma/"
      (cd "$WORK/shell" && zip -qr -X "$OUT/libkwin_data.so" share)
      for root in "${qmlroots[@]}"; do
        (cd "$root" && find qml -type f ! -name '*.so' ! -name '*.qmltypes' ! -name '*.metainfo' \
          | grep -Ev "^qml/${qmlskip#^}" | zip -q -X "$OUT/libkwin_data.so" -@)
      done
      (cd "$WORK" && zip -q -X "$OUT/libkwin_data.so" qml.txt apps.txt)
      # The apps' menu entries, window layouts (kxmlgui) and own data.
      (cd "$DESKDROID_QT_ANDROID" && zip -qr -X "$OUT/libkwin_data.so" \
        $(ls -d share/applications share/mime share/kxmlgui5 share/config.kcfg share/icons/breeze share/icons/hicolor $(for a in $(cat "$WORK/apps.txt"); do echo "share/$a"; done) 2>/dev/null))
    fi
    echo "   data: $(du -h "$OUT/libkwin_data.so" | cut -f1)"
  fi
else
  echo "== native desktop test: no DESKDROID_QT_ANDROID, skipping the Qt demo"
fi
