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
    # Apps in DeskDroid's app store instead of the APK: packaged below.
    # The ones from other repositories (native/store/apps.json) are built into
    # the prefix by native/store/build-apps.sh first.
    store_apps=(gwenview kate kcalc konsole $(jq -r '.apps[].id' "$HERE/../store/apps.json" 2>/dev/null))
    for app in dolphin kioworker ksmserver-logout-greeter kwrite; do
      [ -e "$DESKDROID_QT_ANDROID/lib/lib$app.so" ] || continue
      install -m 755 "$DESKDROID_QT_ANDROID/lib/lib$app.so" "$OUT/libdd_$app.so"
      bundled+=("$OUT/libdd_$app.so"); apps+=("$app")
    done
    printf '%s\n' "${apps[@]}" > "$WORK/apps.txt"
    # Stage 6: GTK programs (towards Floorp), plain executables named like
    # libraries (the APK's library folder is where Android lets apps run
    # programs from), started as bin/<name> (gtkapps.txt).
    : > "$WORK/gtkapps.txt"
    if [ -e "$DESKDROID_QT_ANDROID/lib/pkgconfig/gtk+-3.0.pc" ]; then
      gtkflags="$(PKG_CONFIG_LIBDIR="$DESKDROID_QT_ANDROID/lib/pkgconfig:$DESKDROID_QT_ANDROID/share/pkgconfig" \
        PKG_CONFIG_SYSROOT_DIR= pkg-config --cflags --libs gtk+-3.0)"
      "$BIN/aarch64-linux-android$API-clang" -O2 -fPIE -pie -o "$OUT/libdd_gtktest.so" "$HERE/gtktest.c" \
        -L"$DESKDROID_QT_ANDROID/lib" $gtkflags
      bundled+=("$OUT/libdd_gtktest.so"); echo gtktest >> "$WORK/gtkapps.txt"
      mkdir -p "$WORK/gtkshare/share/applications"
      printf '[Desktop Entry]\nType=Application\nName=GTK Test\nComment=A GTK 3 window, natively on Android\nIcon=applications-development\nExec=gtktest\nCategories=Development;\n' \
        > "$WORK/gtkshare/share/applications/org.deskdroid.gtktest.desktop"
      echo "   gtk: gtktest"
    fi
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
    # Floorp (native/floorp, published by floorp.yml): its programs and
    # libraries go in the library folder like everything else (Android runs
    # programs only from there), its other files (omni.ja...) in the data;
    # the app links the first into data/floorp next to the second, where
    # Floorp looks for them (floorp.txt), and bin/floorp starts it (floorp.sh).
    : > "$WORK/floorp.txt"
    if [ -n "${DESKDROID_FLOORP:-}" ] && [ -e "$DESKDROID_FLOORP" ]; then
      rm -rf "$WORK/ff" && mkdir -p "$WORK/ff" && tar xf "$DESKDROID_FLOORP" -C "$WORK/ff"
      ffroot="$(ls "$WORK/ff" | head -1)"
      mkdir -p "$WORK/ffdata/floorp"
      while IFS= read -r rel; do
        f="$WORK/ff/$ffroot/$rel"
        if [ "$(head -c 4 "$f" | od -An -c | tr -d ' ')" = '177ELF' ]; then
          # Its own libraries under their own names (NSS opens libsoftokn3.so
          # and libfreeblpriv3.so by name, next to itself), its programs and
          # the libraries in subfolders by their path.
          case "$rel" in
            */*) name="libdd_ff_$(echo "${rel%.so}" | tr '/' '_').so" ;;
            *.so) name="$rel" ;;
            *) name="libdd_ff_$rel.so" ;;
          esac
          install -m 755 "$f" "$OUT/$name"; bundled+=("$OUT/$name")
          printf '%s\t%s\n' "$name" "$rel" >> "$WORK/floorp.txt"
        else
          mkdir -p "$WORK/ffdata/floorp/$(dirname "$rel")" && cp -p "$f" "$WORK/ffdata/floorp/$rel"
        fi
      done < <(cd "$WORK/ff/$ffroot" && find . -type f | sed 's|^\./||' | sort)
      echo "$ffroot" > "$WORK/ffdata/floorp/program.txt"
      install -m 755 "$HERE/floorp.sh" "$OUT/libdd_floorp-run.so"
      mkdir -p "$WORK/ffdata/share/applications"
      printf '[Desktop Entry]\nType=Application\nName=Floorp\nGenericName=Web Browser\nComment=Browse the web\nIcon=internet-web-browser\nExec=floorp %%u\nCategories=Network;WebBrowser;\nMimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;\n' \
        > "$WORK/ffdata/share/applications/org.deskdroid.floorp.desktop"
      echo "   floorp: $ffroot, $(wc -l < "$WORK/floorp.txt") programs and libraries"
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
    # The app store's packages (StoreActivity.kt installs them): one zip per
    # app with its library, the libraries it needs that the APK doesn't have
    # (lib/), its menu entry, icons and data (share/), and its catalog entry.
    # They go next to the APK's libraries' folder; CI publishes them.
    STORE_OUT="$(dirname "$(dirname "$OUT")")/store"
    rm -rf "$STORE_OUT" && mkdir -p "$STORE_OUT"
    store_entries=()
    for app in "${store_apps[@]}"; do
      [ -e "$DESKDROID_QT_ANDROID/lib/lib$app.so" ] || continue
      pkg="$WORK/store/$app"; rm -rf "$pkg"; mkdir -p "$pkg/lib" "$pkg/share"
      install -m 644 "$DESKDROID_QT_ANDROID/lib/lib$app.so" "$pkg/lib/libdd_$app.so"
      todo=("$pkg/lib/libdd_$app.so"); own=("$pkg/lib/libdd_$app.so")
      while [ ${#todo[@]} -gt 0 ]; do
        f="${todo[0]}"; todo=("${todo[@]:1}")
        for lib in $("$BIN/llvm-readelf" -d "$f" | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p'); do
          [ -e "$sysroot/$API/$(unversioned "$lib")" ] || [ -e "$sysroot/$(unversioned "$lib")" ] && continue
          name="$(bundlename "$lib")"
          [ -e "$OUT/$name" ] || [ -e "$pkg/lib/$name" ] && continue
          src="$DESKDROID_QT_ANDROID/lib/$lib"
          if [ ! -e "$src" ]; then echo "   ? $lib (for $app, not in the prefix)"; continue; fi
          install -m 644 "$src" "$pkg/lib/$name"
          own+=("$pkg/lib/$name"); todo+=("$src")
        done
      done
      for f in "${own[@]}"; do
        args=()
        for lib in $("$BIN/llvm-readelf" -d "$f" | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p'); do
          name="$(bundlename "$lib")"
          [ "$name" != "$lib" ] && { [ -e "$OUT/$name" ] || [ -e "$pkg/lib/$name" ]; } && args+=(--replace-needed "$lib" "$name")
        done
        soname="$("$BIN/llvm-readelf" -d "$f" | sed -n 's/.*Library soname: \[\([^]]*\)\].*/\1/p')"
        [ -n "$soname" ] && [ "$soname" != "$(basename "$f")" ] && args+=(--set-soname "$(basename "$f")")
        [ ${#args[@]} -gt 0 ] && patchelf --page-size 16384 "${args[@]}" "$f"
        "$BIN/llvm-strip" --strip-unneeded "$f"
      done
      (cd "$DESKDROID_QT_ANDROID" && for d in share/applications/*"$app"*.desktop share/"$app" share/kxmlgui5/"$app" \
          share/icons/hicolor/*/apps/"$app".* share/config.kcfg/"$app"* share/metainfo/*"$app"*; do
        [ -e "$d" ] && mkdir -p "$pkg/$(dirname "$d")" && cp -r "$d" "$pkg/$d"
      done; true)
      desktop="$(ls "$pkg"/share/applications/*.desktop 2>/dev/null | head -1)"
      title="$(sed -n 's/^Name=//p' "$desktop" | head -1)"; summary="$(sed -n 's/^GenericName=//p' "$desktop" | head -1)"
      version="$(sed -n 's/.*<release version="\([^"]*\)".*/\1/p' "$pkg"/share/metainfo/*"$app"* 2>/dev/null | head -1)"
      echo "$app" > "$pkg/app.txt"
      rm -f "$STORE_OUT/$app.zip"; (cd "$pkg" && zip -qr -X "$STORE_OUT/$app.zip" .)
      size="$(stat -c %s "$STORE_OUT/$app.zip")"; sha="$(sha256sum "$STORE_OUT/$app.zip" | cut -d' ' -f1)"
      cp "$(ls "$pkg"/share/icons/hicolor/128x128/apps/"$app".png "$pkg"/share/icons/hicolor/*/apps/"$app".png 2>/dev/null | head -1)" "$STORE_OUT/$app.png" 2>/dev/null || true
      # Built from another repository: which commit (store-watch.yml compares it with upstream).
      source=""
      if [ -s "$DESKDROID_QT_ANDROID/share/deskdroid-store/$app.source" ]; then
        read -r srcrepo srcsha < "$DESKDROID_QT_ANDROID/share/deskdroid-store/$app.source"
        source="$(printf ',"repo":"%s","commit":"%s"' "$srcrepo" "$srcsha")"
      fi
      store_entries+=("$(printf '{"id":"%s","name":"%s","summary":"%s","version":"%s","size":%s,"sha256":"%s","file":"%s.zip","icon":"%s.png"%s}' \
        "$app" "${title:-$app}" "$summary" "${version:-}" "$size" "$sha" "$app" "$app" "$source")")
      echo "   store: $app ($(du -h "$STORE_OUT/$app.zip" | cut -f1), ${#own[@]} libraries)"
    done
    (IFS=,; echo "{\"version\":1,\"apps\":[${store_entries[*]}]}") > "$STORE_OUT/index.json"
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
      (cd "$WORK" && zip -q -X "$OUT/libkwin_data.so" qml.txt apps.txt gtkapps.txt floorp.txt)
      [ -d "$WORK/ffdata" ] && (cd "$WORK/ffdata" && zip -qr -X "$OUT/libkwin_data.so" floorp share)
      [ -d "$WORK/gtkshare" ] && (cd "$WORK/gtkshare" && zip -qr -X "$OUT/libkwin_data.so" share)
      # The apps' menu entries, window layouts (kxmlgui) and own data.
      (cd "$DESKDROID_QT_ANDROID" && zip -qr -X "$OUT/libkwin_data.so" \
        $(ls -d share/applications share/mime share/kxmlgui5 share/config.kcfg share/themes share/icons/breeze share/icons/breeze-dark share/icons/hicolor $(for a in $(cat "$WORK/apps.txt"); do echo "share/$a"; done) 2>/dev/null) \
        -x $(for a in "${store_apps[@]}"; do echo "share/applications/*$a*"; done))
    fi
    echo "   data: $(du -h "$OUT/libkwin_data.so" | cut -f1)"
  fi
else
  echo "== native desktop test: no DESKDROID_QT_ANDROID, skipping the Qt demo"
fi
