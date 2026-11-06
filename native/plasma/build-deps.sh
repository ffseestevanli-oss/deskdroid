#!/usr/bin/env bash
# Native Plasma, stage 3a (docs/native-plasma.md): builds the Linux libraries
# KWin needs for Android with the NDK, into <prefix> (include/, lib/,
# lib/pkgconfig/, share/). Host tools some of them need at build time
# (wayland-scanner) go into <prefix>/host.
#
#   native/plasma/build-deps.sh <prefix> <ndk-dir> [package...]
#
# With no packages, builds all of them in order; a package already in
# <prefix> with the same recipe (its stamp in <prefix>/stamps) is skipped, so a cached prefix only
# rebuilds what's new. Qt needs QT_HOST_PATH (see build_qtbase). Needs meson, ninja, cmake, pkg-config, bison, gperf,
# autoconf/automake/libtool and a host C compiler with expat. Sources come
# from their upstream release tarballs or tags.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PREFIX="$(mkdir -p "$1" && cd "$1" && pwd)"
NDK="$2"
shift 2
API=29
HOSTPREFIX="$PREFIX/host"
STAMPS="$PREFIX/stamps"
mkdir -p "$STAMPS" "$HOSTPREFIX"

host="$(uname -s | tr A-Z a-z)-x86_64"
BIN="$NDK/toolchains/llvm/prebuilt/$host/bin"
CC="$BIN/aarch64-linux-android$API-clang"
CXX="$BIN/aarch64-linux-android$API-clang++"
TRIPLE=aarch64-linux-android
JOBS="$(nproc)"

CACHE="${DESKDROID_SRC_CACHE:-$HOME/.cache/deskdroid}/plasma"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$CACHE"

cat > "$WORK/cross.ini" <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$BIN/llvm-ar'
strip = '$BIN/llvm-strip'
ranlib = '$BIN/llvm-ranlib'
pkg-config = 'pkg-config'

[built-in options]
c_args = ['-ffile-prefix-map=$WORK=.']
cpp_args = ['-ffile-prefix-map=$WORK=.']
c_link_args = ['-Wl,-z,noexecstack', '-L$PREFIX/lib']
cpp_link_args = ['-Wl,-z,noexecstack', '-L$PREFIX/lib']

[properties]
pkg_config_libdir = '$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8-a'
endian = 'little'
EOF
cat > "$WORK/native.ini" <<EOF
[built-in options]
pkg_config_path = '$HOSTPREFIX/lib/pkgconfig:$HOSTPREFIX/share/pkgconfig'
EOF
export PATH="$HOSTPREFIX/bin:$PATH"
# Qt's toolchain file otherwise takes the runner's default NDK from these.
export ANDROID_NDK_ROOT="$NDK" ANDROID_NDK_HOME="$NDK" ANDROID_NDK="$NDK"
# Bionic has librt's and libpthread's functions in libc; some builds still
# ask for the libraries by name.
for lib in rt pthread; do
  [ -e "$PREFIX/lib/lib$lib.a" ] || "$BIN/llvm-ar" rc "$PREFIX/lib/lib$lib.a"
done
export PKG_CONFIG_PATH= PKG_CONFIG_LIBDIR=

# fetch <url> <file>: downloads once into the cache, prints the path.
fetch() {
  local f="$CACHE/$2"
  [ -s "$f" ] || { curl -fL --retry 4 -o "$f.part" "$1" && mv "$f.part" "$f"; }
  echo "$f"
}
# unpack <url> <file>: a fresh source tree in $WORK, prints its path.
unpack() {
  local tar d
  tar="$(fetch "$1" "$2")"
  d="$WORK/src/${2%%.tar*}"
  rm -rf "$d" && mkdir -p "$d"
  tar -xf "$tar" -C "$d" --strip-components=1
  if [ -d "$HERE/patches/${2%%-[0-9]*}" ]; then
    for p in "$HERE/patches/${2%%-[0-9]*}"/*.patch; do
      echo "   patch $(basename "$p")" >&2
      patch -d "$d" -p1 --forward --quiet < "$p" >&2
    done
  fi
  echo "$d"
}
meson_cross() { # <src> [options...]
  local src="$1"; shift
  meson setup "$src/_android" "$src" --cross-file "$WORK/cross.ini" --native-file "$WORK/native.ini" \
    --prefix="$PREFIX" --libdir=lib --buildtype=release -Ddefault_library=shared "$@"
  ninja -C "$src/_android" ${NINJA_KEEP_GOING:+-k 0} install
}
cmake_cross() { # <src> [options...]
  local src="$1"; shift
  cmake -S "$src" -B "$src/_android" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$API -DANDROID_STL=c++_shared \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_FIND_ROOT_PATH="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX" "$@"
  cmake --build "$src/_android" -j "$JOBS"
  cmake --install "$src/_android"
}
autotools_cross() { # <src> [configure options...]
  local src="$1"; shift
  (cd "$src" && [ -x configure ] || autoreconf -fi)
  (cd "$src" && CC="$CC" CXX="$CXX" AR="$BIN/llvm-ar" RANLIB="$BIN/llvm-ranlib" \
    PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig" \
    ./configure --host=$TRIPLE --prefix="$PREFIX" --libdir="$PREFIX/lib" "$@" && make -j"$JOBS" && make install)
}

# ---- the packages, in build order ------------------------------------------

build_expat() {
  local s; s="$(unpack https://github.com/libexpat/libexpat/releases/download/R_2_7_1/expat-2.7.1.tar.xz expat-2.7.1.tar.xz)"
  cmake_cross "$s" -DEXPAT_BUILD_TOOLS=OFF -DEXPAT_BUILD_EXAMPLES=OFF -DEXPAT_BUILD_TESTS=OFF -DEXPAT_BUILD_DOCS=OFF
}

build_libffi() {
  local s; s="$(unpack https://github.com/libffi/libffi/releases/download/v3.4.8/libffi-3.4.8.tar.gz libffi-3.4.8.tar.gz)"
  autotools_cross "$s" --disable-static --disable-docs --disable-multi-os-directory
}

# wayland-scanner for the build machine first, then the libraries for Android.
build_wayland() {
  local s; s="$(unpack https://gitlab.freedesktop.org/wayland/wayland/-/releases/1.24.0/downloads/wayland-1.24.0.tar.xz wayland-1.24.0.tar.xz)"
  meson setup "$s/_host" "$s" --prefix="$HOSTPREFIX" --libdir=lib --buildtype=release \
    -Dlibraries=false -Ddocumentation=false -Ddtd_validation=false -Dtests=false
  ninja -C "$s/_host" install
  meson_cross "$s" -Dscanner=false -Ddocumentation=false -Ddtd_validation=false -Dtests=false
  # Builds against the Android prefix look up wayland.xml through wayland-scanner.pc.
  cp "$(find "$HOSTPREFIX" -name wayland-scanner.pc | head -1)" "$PREFIX/lib/pkgconfig/"
}

build_wayland_protocols() {
  local s; s="$(unpack https://gitlab.freedesktop.org/wayland/wayland-protocols/-/releases/1.45/downloads/wayland-protocols-1.45.tar.xz wayland-protocols-1.45.tar.xz)"
  meson_cross "$s" -Dtests=false
}

build_xkbcommon() {
  local s; s="$(unpack https://github.com/xkbcommon/libxkbcommon/archive/refs/tags/xkbcommon-1.11.0.tar.gz libxkbcommon-1.11.0.tar.gz)"
  # Android has no /usr/share/X11/xkb: KWin's keymaps will ship with the app.
  meson_cross "$s" -Denable-x11=false -Denable-wayland=false -Denable-docs=false -Denable-tools=false -Denable-xkbregistry=false \
    -Denable-bash-completion=false -Dxkb-config-root=/system/usr/share/xkb
}

build_dbus() {
  local s; s="$(unpack https://dbus.freedesktop.org/releases/dbus/dbus-1.16.2.tar.xz dbus-1.16.2.tar.xz)"
  # The machine ID file's path is built in (under the CI's prefix), and
  # Android has no /etc/machine-id: the app names one in DBUS_MACHINE_ID_FILE.
  sed -i 's|_dbus_string_init_const (&filename, DBUS_MACHINE_UUID_FILE);|_dbus_string_init_const (\&filename, getenv ("DBUS_MACHINE_ID_FILE") ? getenv ("DBUS_MACHINE_ID_FILE") : DBUS_MACHINE_UUID_FILE);|g' \
    "$s/dbus/dbus-sysdeps-unix.c"
  grep -q 'getenv ("DBUS_MACHINE_ID_FILE")' "$s/dbus/dbus-sysdeps-unix.c"
  meson_cross "$s" -Dmodular_tests=disabled -Ddoxygen_docs=disabled -Dxml_docs=disabled -Dducktype_docs=disabled \
    -Dqt_help=disabled -Dsystemd=disabled -Dselinux=disabled -Dapparmor=disabled -Dlibaudit=disabled \
    -Dx11_autolaunch=disabled -Dinotify=enabled -Dmessage_bus=true -Dtools=true -Duser_session=false
}

build_epoxy() {
  local s; s="$(unpack https://github.com/anholt/libepoxy/archive/refs/tags/1.5.10.tar.gz libepoxy-1.5.10.tar.gz)"
  meson_cross "$s" -Degl=yes -Dglx=no -Dx11=false -Dtests=false
}

build_lcms2() {
  local s; s="$(unpack https://github.com/mm2/Little-CMS/releases/download/lcms2.17/lcms2-2.17.tar.gz lcms2-2.17.tar.gz)"
  meson_cross "$s" -Dutils=false
}

build_libdrm() {
  local s; s="$(unpack https://dri.freedesktop.org/libdrm/libdrm-2.4.125.tar.xz libdrm-2.4.125.tar.xz)"
  meson_cross "$s" -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled -Dvmwgfx=disabled \
    -Domap=disabled -Dexynos=disabled -Dfreedreno=disabled -Dtegra=disabled -Dvc4=disabled -Detnaviv=disabled \
    -Dcairo-tests=disabled -Dman-pages=disabled -Dvalgrind=disabled -Dtests=false -Dudev=false
}

build_libxcvt() {
  local s; s="$(unpack https://www.x.org/releases/individual/lib/libxcvt-0.1.3.tar.xz libxcvt-0.1.3.tar.xz)"
  meson_cross "$s"
}

build_hwdata() {
  local s; s="$(unpack https://github.com/vcrhonek/hwdata/archive/refs/tags/v0.400.tar.gz hwdata-0.400.tar.gz)"
  (cd "$s" && ./configure --prefix="$PREFIX" --datadir="$PREFIX/share" && make install)
}

# The keyboard layouts xkbcommon compiles keymaps from (data only). The app
# ships them and points XKB_CONFIG_ROOT at its copy.
build_xkeyboard_config() {
  local s; s="$(unpack https://xorg.freedesktop.org/archive/individual/data/xkeyboard-config/xkeyboard-config-2.44.tar.xz xkeyboard-config-2.44.tar.xz)"
  meson setup "$s/_build" "$s" --prefix="$PREFIX" -Dxorg-rules-symlinks=false -Dcompat-rules=true
  ninja -C "$s/_build" install
}

# libxcb: KWin includes <xcb/xcb.h> for its types even without X11 support.
XORG=https://xorg.freedesktop.org/archive/individual
build_xorgproto() {
  local s; s="$(unpack $XORG/proto/xorgproto-2024.1.tar.xz xorgproto-2024.1.tar.xz)"
  meson_cross "$s" -Dlegacy=false
}
build_xcb_proto() { # protocol XML and its Python generator, for the build machine
  local s; s="$(unpack $XORG/proto/xcb-proto-1.17.0.tar.xz xcb-proto-1.17.0.tar.xz)"
  (cd "$s" && ./configure --prefix="$PREFIX" && make install)
}
build_libxau() {
  local s; s="$(unpack $XORG/lib/libXau-1.0.12.tar.xz libXau-1.0.12.tar.xz)"
  autotools_cross "$s" --disable-static
}
build_libxcb() {
  local s; s="$(unpack $XORG/lib/libxcb-1.17.0.tar.xz libxcb-1.17.0.tar.xz)"
  autotools_cross "$s" --disable-static --disable-devel-docs --without-doxygen
}

build_libdisplay_info() {
  local s; s="$(unpack https://gitlab.freedesktop.org/emersion/libdisplay-info/-/archive/0.2.0/libdisplay-info-0.2.0.tar.gz libdisplay-info-0.2.0.tar.gz)"
  meson_cross "$s"
}

build_freetype() {
  local s; s="$(unpack https://download.savannah.gnu.org/releases/freetype/freetype-2.13.3.tar.xz freetype-2.13.3.tar.xz)"
  meson_cross "$s" -Dbrotli=disabled -Dbzip2=disabled -Dharfbuzz=disabled -Dpng=disabled -Dzlib=internal -Dtests=disabled
}

build_fontconfig() {
  local s; s="$(unpack https://gitlab.freedesktop.org/api/v4/projects/890/packages/generic/fontconfig/2.16.2/fontconfig-2.16.2.tar.xz fontconfig-2.16.2.tar.xz)"
  meson_cross "$s" -Ddoc=disabled -Dtests=disabled -Dtools=disabled -Dcache-build=disabled -Dnls=disabled \
    -Ddefault-fonts-dirs=/system/fonts
}

build_udev() { # libudev-zero: libudev without systemd
  local s; s="$(unpack https://github.com/illiliti/libudev-zero/archive/refs/tags/1.0.3.tar.gz libudev-zero-1.0.3.tar.gz)"
  make -C "$s" -j"$JOBS" CC="$CC" AR="$BIN/llvm-ar" PREFIX="$PREFIX" LIBDIR="$PREFIX/lib" install-shared install-headers install-pkgconfig 2>/dev/null \
    || make -C "$s" -j"$JOBS" CC="$CC" AR="$BIN/llvm-ar" PREFIX="$PREFIX" LIBDIR="$PREFIX/lib" install
}

build_mtdev() {
  local s; s="$(unpack https://bitmath.org/code/mtdev/mtdev-1.1.7.tar.bz2 mtdev-1.1.7.tar.bz2)"
  autotools_cross "$s" --disable-static
}

build_libevdev() {
  local s; s="$(unpack https://www.freedesktop.org/software/libevdev/libevdev-1.13.4.tar.xz libevdev-1.13.4.tar.xz)"
  # Android's kernel headers are Linux's: use libevdev's Linux copies.
  sed -i "s/host_machine.system()/'linux'/g" "$s/meson.build"
  meson_cross "$s" -Dtests=disabled -Ddocumentation=disabled -Dtools=disabled
}

build_libinput() {
  local s; s="$(unpack https://gitlab.freedesktop.org/libinput/libinput/-/archive/1.28.1/libinput-1.28.1.tar.gz libinput-1.28.1.tar.gz)"
  # Bionic dropped index()/rindex().
  meson_cross "$s" -Dc_args="-Dindex=strchr -Drindex=strrchr" -Dlibwacom=false -Ddebug-gui=false -Dtests=false -Ddocumentation=false -Dinstall-tests=false \
    -Dudev-dir="$PREFIX/lib/udev"
}

# gbm: a stand-in (gbm-stub/), Android has no DRM device to allocate from.
build_gbm() {
  install -D -m 644 "$HERE/gbm-stub/gbm.h" "$PREFIX/include/gbm.h"
  "$CC" -O2 -shared -fPIC -Wall -Wextra "$HERE/gbm-stub/gbm.c" -o "$PREFIX/lib/libgbm.so" -Wl,-soname,libgbm.so
  cat > "$PREFIX/lib/pkgconfig/gbm.pc" <<PC
prefix=$PREFIX
Name: gbm
Description: DeskDroid's gbm stand-in
Version: 25.0.0
Libs: -L\${prefix}/lib -lgbm
Cflags: -I\${prefix}/include
PC
}

# ---- Qt (stage 3b), built from source: the prebuilt Qt for Android has no
# D-Bus and no Wayland client, and KWin needs both. Needs QT_HOST_PATH, a
# desktop Qt of the same version for the build tools (moc, qtwaylandscanner...).

QT_VERSION=6.8.3
qt_src() { # <module>: unpacked source of one Qt module
  unpack "https://download.qt.io/archive/qt/${QT_VERSION%.*}/$QT_VERSION/submodules/$1-everywhere-src-$QT_VERSION.tar.xz" \
    "$1-everywhere-src-$QT_VERSION.tar.xz"
}
# The NDK's toolchain file only searches the sysroot (and CMAKE_FIND_ROOT_PATH
# re-roots absolute paths); let CMake take the include and library paths that
# pkg-config reports for the prefix as they are.
qt_find_args() {
  echo -DCMAKE_FIND_ROOT_PATH="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH
}
qt_module() { # <module> [cmake options...]: one module on top of qtbase
  local s; s="$(qt_src "$1")"; shift
  mkdir -p "$s/_android"
  (cd "$s/_android" && PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig" \
    "$PREFIX/bin/qt-configure-module" "$s" -- $(qt_find_args) "$@")
  cmake --build "$s/_android" -j "$JOBS"
  cmake --install "$s/_android"
}

build_qtbase() {
  : "${QT_HOST_PATH:?set QT_HOST_PATH to a desktop Qt $QT_VERSION}"
  local s; s="$(qt_src qtbase)"
  # Qt only looks for Wayland on Linux; KWin's Qt needs it (QtWaylandClient).
  perl -0pi -e 's/if\(\(LINUX\) OR QT_FIND_ALL_PACKAGES_ALWAYS\)(\s*qt_find_package\(Wayland)/if((LINUX OR ANDROID) OR QT_FIND_ALL_PACKAGES_ALWAYS)$1/' \
    "$s/src/gui/configure.cmake"
  grep -q "LINUX OR ANDROID" "$s/src/gui/configure.cmake"
  # Likewise xkbcommon (only looked for with X11); KWin uses Qt's xkbcommon helpers.
  perl -0pi -e 's/if\(\(X11_SUPPORTED\) OR QT_FIND_ALL_PACKAGES_ALWAYS\)(\s*qt_find_package\(XKB 0)/if((X11_SUPPORTED OR ANDROID) OR QT_FIND_ALL_PACKAGES_ALWAYS)$1/' \
    "$s/src/gui/configure.cmake"
  grep -q "X11_SUPPORTED OR ANDROID" "$s/src/gui/configure.cmake"
  # Standard paths from the XDG variables, as on Linux: Qt for Android's
  # version asks the app's Context (a JNI call) and knows nothing of share/,
  # where KDE software looks for its data, and KWin runs outside an Activity.
  perl -0pi -e 's/(CONDITION ANDROID\s+SOURCES\s+)io\/qstandardpaths_android\.cpp/$1io\/qstandardpaths_unix.cpp/' \
    "$s/src/corelib/CMakeLists.txt"
  grep -q "qstandardpaths_unix.cpp" <(sed -n '/CONDITION ANDROID$/,/)/p' "$s/src/corelib/CMakeLists.txt")
  mkdir -p "$s/_android"
  (cd "$s/_android" && PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig" "$s/configure" \
    -platform android-clang -android-ndk "$NDK" -android-sdk "$ANDROID_HOME" -android-abis arm64-v8a \
    -android-ndk-platform android-$API -qt-host-path "$QT_HOST_PATH" -prefix "$PREFIX" \
    -release -nomake tests -nomake examples -dbus-linked -feature-dbus -feature-wayland -feature-xkbcommon -pkg-config -system-freetype -fontconfig \
    -- $(qt_find_args) -DQT_FEATURE_vulkan=OFF)
  cmake --build "$s/_android" -j "$JOBS"
  cmake --install "$s/_android"
}

build_qtshadertools() { qt_module qtshadertools; }
build_qtdeclarative() { qt_module qtdeclarative; }
build_qtsvg() { qt_module qtsvg; }
build_qt5compat() { qt_module qt5compat; }
build_qtsensors() { qt_module qtsensors; }
# Gwenview plays videos with Qt Multimedia (Android's own media backend).
build_qtmultimedia() { qt_module qtmultimedia -DFEATURE_ffmpeg=OFF -DFEATURE_spatialaudio=OFF -DFEATURE_spatialaudio_quick3d=OFF; }
# Text to speech, which KTextEditor needs (its "Say" actions); Qt Speech
# builds nothing without Qt Multimedia.
build_qtspeech() { qt_module qtspeech; test -e "$PREFIX/lib/libQt6TextToSpeech_arm64-v8a.so" || test -e "$PREFIX/lib/libQt6TextToSpeech.so"; }
build_qtwayland() {
  local s; s="$(qt_src qtwayland)"
  # qtwayland skips Android outright; the client side is plain Linux code.
  sed -i 's/(ANDROID OR NOT LINUX)/(NOT LINUX AND NOT ANDROID)/' "$s/CMakeLists.txt"
  mkdir -p "$s/_android"
  (cd "$s/_android" && PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig" \
    "$PREFIX/bin/qt-configure-module" "$s" -- $(qt_find_args) -DFEATURE_wayland_server=OFF -DFEATURE_wayland_client=ON)
  cmake --build "$s/_android" -j "$JOBS"
  cmake --install "$s/_android"
}
# Qt apps draw on the GPU: Qt Wayland's client side for KWin's
# deskdroid_ahb_v1 (ahb/), standing in for wayland-egl.
build_deskdroid_ahb() {
  local s="$WORK/deskdroid-ahb"
  rm -rf "$s"; mkdir -p "$s"; cp "$HERE"/ahb/* "$s/"
  kde_cmake "$s"
  ls "$PREFIX"/plugins/wayland-graphics-integration-client/ | grep deskdroid-ahb
}
inputs_deskdroid_ahb() { cat "$HERE"/ahb/*; }
# Only for QUiLoader, which KWin's scripting configuration uses.
build_qttools() {
  qt_module qttools -DFEATURE_assistant=OFF -DFEATURE_designer=ON -DFEATURE_linguist=OFF \
    -DFEATURE_pixeltool=OFF -DFEATURE_qtdiag=OFF -DFEATURE_qtplugininfo=OFF -DFEATURE_qdoc=OFF \
    -DFEATURE_distancefieldgenerator=OFF -DFEATURE_qtattributionsscanner=OFF -DFEATURE_qev=OFF
}

# ---- KDE Frameworks and Plasma libraries (stage 3c) ------------------------

KF_VERSION=6.16.0
PLASMA_VERSION=6.4.5
kf_src() { # <name>: a framework's source
  unpack "https://download.kde.org/stable/frameworks/${KF_VERSION%.*}/$1-$KF_VERSION.tar.xz" "$1-$KF_VERSION.tar.xz"
}
# kde_cmake <src> [options...]: a KDE project for Android, through Qt's
# toolchain file, with build tools (kconfig_compiler...) from the host builds.
kde_cmake() {
  local src="$1"; shift
  PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig" \
  cmake -S "$src" -B "$src/_android" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$PREFIX/lib/cmake/Qt6/qt.toolchain.cmake" -DQT_HOST_PATH="$QT_HOST_PATH" \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib $(qt_find_args) \
    -DKF6_HOST_TOOLING="$HOSTPREFIX/lib/cmake" -DKF_IGNORE_PLATFORM_CHECK=ON \
    -DWayland_DATADIR="$HOSTPREFIX/share/wayland" -DWaylandProtocols_DATADIR="$PREFIX/share/wayland-protocols" \
    -DSKIP_APPSTREAM=ON -DBUILD_TESTING=OFF -DBUILD_QCH=OFF -DBUILD_PYTHON_BINDINGS=OFF -DBUILD_DESIGNERPLUGIN=OFF "$@"
  cmake --build "$src/_android" -j "$JOBS" ${KEEP_GOING:+-- -k 0}
  cmake --install "$src/_android"
}
# KDE's Android support is for Android apps (Java UI, Gradle, no D-Bus, no
# Wayland). Here KDE runs like on Linux, so drop those Android branches from
# the build files; C++ code keeps its Q_OS_ANDROID parts.
unandroid() {
  find "$1" -type f \( -name CMakeLists.txt -o -name '*.cmake' \) | xargs sed -i -E \
    -e 's/(AND|OR) NOT ANDROID//g' -e 's/NOT ANDROID AND //g' \
    -e 's/if ?\(ANDROID\)/if(FALSE)/g' -e 's/if ?\(NOT ANDROID\)/if(TRUE)/g' -e 's/\(ANDROID OR /(/g' -e 's/ OR ANDROID//g'
}
kf() { local s; s="$(kf_src "$1")"; shift; unandroid "$s"; kde_cmake "$s" -DWITH_X11=OFF -DUSE_DBUS=ON "$@"; }

build_ecm() {
  local s; s="$(kf_src extra-cmake-modules)"
  cmake -S "$s" -B "$s/_host" -DCMAKE_INSTALL_PREFIX="$PREFIX" -DBUILD_TESTING=OFF -DBUILD_DOC=OFF
  cmake --install "$s/_host"
}

# kconfig's build tools (kconfig_compiler_kf6, kconf_update), for the host.
build_kconfig_host() {
  local s; s="$(kf_src kconfig)"
  cmake -S "$s" -B "$s/_host" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$QT_HOST_PATH;$PREFIX" \
    -DCMAKE_INSTALL_PREFIX="$HOSTPREFIX" -DKDE_INSTALL_LIBDIR=lib -DBUILD_TESTING=OFF -DBUILD_QCH=OFF -DKCONFIG_USE_GUI=OFF -DKCONFIG_USE_QML=OFF
  cmake --build "$s/_host" -j "$JOBS"
  cmake --install "$s/_host"
}

# libintl for ki18n: Android's libc has no gettext.
build_libintl() {
  local s; s="$(unpack https://ftp.gnu.org/pub/gnu/gettext/gettext-0.22.5.tar.xz gettext-0.22.5.tar.xz)"
  autotools_cross "$s/gettext-runtime" --disable-static --disable-java --disable-csharp --disable-libasprintf \
    --with-included-gettext --disable-openmp --without-emacs
  test -e "$PREFIX/lib/libintl.so" && test -e "$PREFIX/include/libintl.h"
  # GNU's own symbols (ki18n needs libintl_bind_textdomain_codeset), not GLib's
  # stand-in, which once replaced this library (see build_glib).
  "$BIN/llvm-nm" -D "$PREFIX/lib/libintl.so" | grep -q " libintl_bind_textdomain_codeset"
}

build_karchive() { kf karchive -DWITH_BZIP2=OFF -DWITH_LIBLZMA=OFF -DWITH_LIBZSTD=OFF -DWITH_OPENSSL=OFF; }
build_kconfig() { kf kconfig; }
# KDE's Android plugin lookup expects every plugin flat in the library folder
# as libplugins_<namespace>_<name>.so, and then takes that whole file name as
# the plugin's ID ("libplugins_org.kde.kdecoration3_org.kde.breeze" instead
# of "org.kde.breeze"), so nothing asked for by ID is found. KCoreAddons uses
# its Linux lookup instead: <plugin path>/<namespace>/<name>.so, which the app
# lays out as links to the flat files the APK carries.
build_kcoreaddons() {
  local s; s="$(kf_src kcoreaddons)"
  sed -i '0,/^#include <unordered_map>/s//#include <unordered_map>\n#undef Q_OS_ANDROID/' "$s/src/lib/plugin/kpluginmetadata.cpp"
  grep -q "^#undef Q_OS_ANDROID" "$s/src/lib/plugin/kpluginmetadata.cpp"
  # A plugin's ID comes from its file name, but QPluginLoader follows the link
  # to the APK's flat file (libplugins_kf6_thumbcreator_imagethumbnail.so), so
  # every plugin found by folder got that as its ID and nothing asked for by
  # name (thumbnailers...) matched. The ID comes from the link's name instead.
  perl -0pi -e 's/(if \(!d->m_fileName\.isEmpty\(\)\) \{\n\s*d->m_pluginId = QFileInfo\()d->m_fileName(\)\.completeBaseName\(\);)/$1pluginFile.startsWith(QLatin1Char(\x27\/\x27)) ? pluginFile : d->m_fileName$2/' "$s/src/lib/plugin/kpluginmetadata.cpp"
  grep -q "QFileInfo(pluginFile.startsWith" "$s/src/lib/plugin/kpluginmetadata.cpp"
  unandroid "$s"
  kde_cmake "$s" -DWITH_X11=OFF -DUSE_DBUS=ON
  # kcoreaddons_add_plugin: plugins in their namespace folders, as on Linux
  # (unandroid takes out its Android branch, which installs them flat).
  ! grep -q 'if(NOT ANDROID)' "$PREFIX/lib/cmake/KF6CoreAddons/KF6CoreAddonsMacros.cmake"
}
build_ki18n() {
  local s; s="$(kf_src ki18n)"
  # Android apps' translations come from APK assets through a function KDE's
  # Android gettext adds; ours come from files like on Linux.
  sed -i 's/^\( *\)loadMessageCatalogFile(domain, moFile);/\1(void)domain;/' "$s/src/i18n/kcatalog.cpp"
  grep -q "(void)domain;" "$s/src/i18n/kcatalog.cpp"
  # The rest of KCatalog's Android code reads catalogs from APK assets through
  # the app's AssetManager (a JNI call on Qt's Context); KWin runs outside an
  # Activity, so catalogs are found in share/locale as on Linux.
  sed -i '0,/^#ifdef Q_OS_ANDROID/s//#undef Q_OS_ANDROID\n#ifdef Q_OS_ANDROID/' "$s/src/i18n/kcatalog.cpp"
  grep -q "^#undef Q_OS_ANDROID" "$s/src/i18n/kcatalog.cpp"
  unandroid "$s"
  kde_cmake "$s" -DWITH_X11=OFF -DUSE_DBUS=ON -DCMAKE_SHARED_LINKER_FLAGS=-landroid -DBUILD_WITH_QML=ON -DLibIntl_INCLUDE_DIRS="$PREFIX/include" -DLibIntl_LIBRARIES="$PREFIX/lib/libintl.so"
}
build_kwidgetsaddons() { kf kwidgetsaddons; }
build_kguiaddons() { kf kguiaddons -DWITH_WAYLAND=ON -DBUILD_GEO_SCHEME_HANDLER=OFF; }
build_kwindowsystem() { kf kwindowsystem -DKWINDOWSYSTEM_WAYLAND=ON -DKWINDOWSYSTEM_X11=OFF; }  # after the Qt fixes
build_kdbusaddons() { kf kdbusaddons; }
build_kcolorscheme() { kf kcolorscheme; }
build_kidletime() { kf kidletime; }
build_kauth() { kf kauth -DKAUTH_BACKEND_NAME=FAKE; }
build_kcrash() { kf kcrash; }
build_kglobalaccel() { kf kglobalaccel; }
# kpackagetool6 only runs at build time to write AppStream files, which nothing
# here needs (SKIP_APPSTREAM), so the host side gets a stand-in target instead
# of a second, host build of KPackage and everything under it.
build_kpackage() {
  kf kpackage
  mkdir -p "$HOSTPREFIX/lib/cmake/KF6Package"
  cat > "$HOSTPREFIX/lib/cmake/KF6Package/KF6PackageToolsTargets.cmake" <<'CMAKE'
if(NOT TARGET KF6::kpackagetool6)
  add_executable(KF6::kpackagetool6 IMPORTED)
  set_target_properties(KF6::kpackagetool6 PROPERTIES IMPORTED_LOCATION /bin/true)
endif()
CMAKE
}
# Icons in the software renderer: Kirigami 6.16 adds an icon's image node
# while the scene is being drawn, which crashes Qt's software renderer.
# patches/kirigami holds upstream's later version of that node.
build_kirigami() {
  local s; s="$(kf_src kirigami)"
  cp "$HERE"/patches/kirigami/softwarerectanglenode.* "$s/src/primitives/scenegraph/"
  unandroid "$s"; kde_cmake "$s" -DWITH_X11=OFF -DUSE_DBUS=ON
}
inputs_kirigami() { cat "$HERE"/patches/kirigami/*; }
build_kservice() { kf kservice; }
build_ksvg() { kf ksvg; }

build_plasma_wayland_protocols() {
  local s; s="$(unpack https://download.kde.org/stable/plasma-wayland-protocols/plasma-wayland-protocols-1.18.0.tar.xz plasma-wayland-protocols-1.18.0.tar.xz)"
  kde_cmake "$s"
}
build_kiconthemes() {
  local s; s="$(kf_src kiconthemes)"
  python3 "$HERE/patches/kiconthemes/icon-theme.py" "$s"
  unandroid "$s"
  kde_cmake "$s" -DWITH_X11=OFF -DUSE_DBUS=ON -DUSE_BreezeIcons=OFF -DKICONTHEMES_USE_QTQUICK=OFF
}
inputs_kiconthemes() { cat "$HERE"/patches/kiconthemes/*; }
# Breeze: KWin's window borders (and the Qt style, colors and cursors). The
# border and style settings pages need KCMUtils, which nothing else here
# does, so they stay out; KDE's Android switch would leave out the borders.
build_breeze() {
  local s; s="$(unpack "https://download.kde.org/stable/plasma/$PLASMA_VERSION/breeze-$PLASMA_VERSION.tar.xz" "breeze-$PLASMA_VERSION.tar.xz")"
  perl -0pi -e 's/find_package\(KF6KCMUtils[^)]*\)\s*set_package_properties\(KF6KCMUtils.*?\)\n//s' "$s/CMakeLists.txt"
  ! grep -q "KF6KCMUtils" "$s/CMakeLists.txt"
  sed -i 's/^add_subdirectory(config)/# add_subdirectory(config)/' "$s/kdecoration/CMakeLists.txt"
  grep -q "^# add_subdirectory(config)" "$s/kdecoration/CMakeLists.txt"
  unandroid "$s"
  kde_cmake "$s" -DBUILD_QT5=OFF -DBUILD_QT6=ON -DWITH_DECORATIONS=ON -DWITH_WALLPAPERS=OFF
  test -e "$PREFIX/plugins/org.kde.kdecoration3/org.kde.breeze.so"
}
build_kdecoration() {
  local s; s="$(unpack "https://download.kde.org/stable/plasma/$PLASMA_VERSION/kdecoration-$PLASMA_VERSION.tar.xz" "kdecoration-$PLASMA_VERSION.tar.xz")"
  kde_cmake "$s"
}

build_kwayland() {
  local s; s="$(unpack "https://download.kde.org/stable/plasma/$PLASMA_VERSION/kwayland-$PLASMA_VERSION.tar.xz" "kwayland-$PLASMA_VERSION.tar.xz")"
  unandroid "$s"
  kde_cmake "$s"
}

# ---- KWin (stage 3d) ---------------------------------------------------------

build_kwin() {
  local s; s="$(unpack "https://download.kde.org/stable/plasma/$PLASMA_VERSION/kwin-$PLASMA_VERSION.tar.xz" "kwin-$PLASMA_VERSION.tar.xz")"
  unandroid "$s"
  # Our backend: KWin's desktop as a window of DeskDroid's Android compositor.
  python3 "$HERE/kwin-nativedesk/add-to-kwin.py" "$s"
  # Android is Linux underneath: /proc/self/exe, the same scheduler and so on.
  grep -rl --include=CMakeLists.txt 'CMAKE_SYSTEM_NAME MATCHES "Linux"' "$s" | xargs sed -i 's/CMAKE_SYSTEM_NAME MATCHES "Linux"/CMAKE_SYSTEM_NAME MATCHES "Linux|Android"/'
  # The "kill this frozen window" helper is X11 only, and the wrapper that
  # restarts kwin_wayland after a crash is the Android app's job here.
  sed -i 's/^add_subdirectory(/# add_subdirectory(/' "$s/src/helpers/CMakeLists.txt"
  # No sound theme to play the system bell with.
  sed -i 's/^find_package(Canberra REQUIRED)/find_package(Canberra)/' "$s/CMakeLists.txt"
  sed -i 's/^add_subdirectory(systembell)/# add_subdirectory(systembell)/' "$s/src/plugins/CMakeLists.txt"
  # The software cursor is painted in screen pixels at its position in logical
  # ones, so at scale 1.5 it showed at two thirds of where the pointer was
  # (the scene's painter maps logical to screen pixels; the cursor's didn't).
  perl -0pi -e 's/(    QPainter painter\(buffer\);\n)/$1    painter.setWindow(m_output->geometry());\n/ or die "cursor patch"' "$s/src/scene/cursordelegate_qpainter.cpp"
  # memfd_create and friends are API 30+; the Pixel has them, so link them weakly.
  # Big build, many fixes to come: keep going past errors so a run shows them all.
  KEEP_GOING=1 kde_cmake "$s" -DCMAKE_CXX_FLAGS="-D__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__ -I$HERE/x11-stubs" -DCMAKE_C_FLAGS=-D__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__ -DKWIN_BUILD_KCMS=OFF -DKWIN_BUILD_NOTIFICATIONS=OFF -DKWIN_BUILD_SCREENLOCKER=OFF \
    -DKWIN_BUILD_X11=OFF -DKWIN_BUILD_RUNNERS=OFF -DKWIN_BUILD_TABBOX=OFF \
    -DKWIN_BUILD_ACTIVITIES=OFF -DKWIN_BUILD_EIS=OFF -DBUILD_DOC=OFF -DNATIVE_PREFIX="$QT_HOST_PATH"
}

# ---- plasmashell's libraries (stage 4a) --------------------------------------

build_kcodecs() { kf kcodecs; }
build_kitemviews() { kf kitemviews; }
build_kcompletion() { kf kcompletion; }
build_kbookmarks() { kf kbookmarks; }
build_kconfigwidgets() { kf kconfigwidgets; }
# No sound theme player (libcanberra) here: notifications are silent for now.
# They go out over D-Bus as on Linux, not through Android's notification API.
build_knotifications() {
  local s f; s="$(kf_src knotifications)"
  sed -i 's/find_package(Canberra REQUIRED)/find_package(Canberra)/' "$s/CMakeLists.txt"
  for f in knotificationpermission.cpp knotificationmanager.cpp knotification.cpp; do
    sed -i '0,/^#include.*/s//&\n#undef Q_OS_ANDROID/' "$s/src/$f"
    grep -q "^#undef Q_OS_ANDROID" "$s/src/$f"
  done
  unandroid "$s"
  kde_cmake "$s" -DWITH_X11=OFF -DUSE_DBUS=ON
}
build_kjobwidgets() { kf kjobwidgets; }
# Solid's Android build has no device backends besides the fake one; its
# Linux ones need libmount and udisks. UPower (the battery) comes later.
build_solid() { local s; s="$(kf_src solid)"; kde_cmake "$s" -DUSE_DBUS=ON; }
# TLS for Qt (KIO needs QSslSocket; so will anything online). OpenSSL, and
# qtbase built again with it as a recipe of its own, so the packages built on
# the first qtbase don't all build again: TLS only adds to Qt's API.
build_openssl() {
  local s; s="$(unpack https://github.com/openssl/openssl/releases/download/openssl-3.5.4/openssl-3.5.4.tar.gz openssl-3.5.4.tar.gz)"
  (cd "$s" && export ANDROID_NDK_ROOT="$NDK" PATH="$BIN:$PATH" && ./Configure android-arm64 -D__ANDROID_API__=$API \
    --prefix="$PREFIX" --libdir=lib shared no-tests no-docs no-apps \
    && make -j"$JOBS" && make install_sw)
  test -e "$PREFIX/lib/libssl.so"
}
build_qtbase_ssl() {
  eval "$(declare -f build_qtbase | sed '1s/build_qtbase/qtbase_with_ssl/; s/ -feature-dbus / -feature-dbus -openssl-linked /')"
  qtbase_with_ssl
  grep -q "define QT_FEATURE_ssl 1" "$PREFIX/include/QtNetwork/qtnetwork-config.h"
}
# Apps start by fork and exec here: there's no systemd to start them in scopes
# (KIO's build leaves that code out on Android, but one #if still uses it).
build_kio() {
  local s; s="$(kf_src kio)"
  sed -i 's/^#if defined(Q_OS_LINUX) && defined(WITH_QTDBUS)$/#if defined(Q_OS_LINUX) \&\& !defined(Q_OS_ANDROID) \&\& defined(WITH_QTDBUS)/' "$s/src/gui/kprocessrunner.cpp"
  grep -q "!defined(Q_OS_ANDROID) && defined(WITH_QTDBUS)" "$s/src/gui/kprocessrunner.cpp"
  # kioworker (KIO's helper program for workers outside the app) as a
  # library QtHost starts, found through PATH as bin/kioworker.
  python3 "$HERE/apps/as-library.py" "$s" src/kioworker/CMakeLists.txt kioworker src/kioworker/kioworker.cpp
  sed -i 's|install(TARGETS kioworker DESTINATION ${KDE_INSTALL_LIBEXECDIR_KF})|install(TARGETS kioworker LIBRARY DESTINATION ${KDE_INSTALL_LIBDIR})|' "$s/src/kioworker/CMakeLists.txt"
  grep -q "kioworker LIBRARY DESTINATION" "$s/src/kioworker/CMakeLists.txt"
  python3 "$HERE/patches/kio/preview-log.py" "$s"
  python3 "$HERE/patches/kio/preview-plugins.py" "$s"
  unandroid "$s"
  kde_cmake "$s" -DWITH_X11=OFF -DUSE_DBUS=ON -DWITH_WAYLAND=ON
}
inputs_kio() { cat "$HERE"/apps/as-library.py "$HERE"/kwin-nativedesk/qthost_entry.cpp "$HERE"/patches/kio/*; }
build_kxmlgui() { kf kxmlgui; }
build_kstatusnotifieritem() { kf kstatusnotifieritem; }
# The library only: its QML imports need Boost, which isn't here yet.
build_plasma_activities() {
  local s; s="$(unpack "https://download.kde.org/stable/plasma/$PLASMA_VERSION/plasma-activities-$PLASMA_VERSION.tar.xz" "plasma-activities-$PLASMA_VERSION.tar.xz")"
  unandroid "$s"
  kde_cmake "$s" -DPLASMA_ACTIVITIES_LIBRARY_ONLY=ON
}
build_libplasma() {
  local s; s="$(unpack "https://download.kde.org/stable/plasma/$PLASMA_VERSION/libplasma-$PLASMA_VERSION.tar.xz" "libplasma-$PLASMA_VERSION.tar.xz")"
  unandroid "$s"
  # KX11Extras and KWindowInfo are X11 only, and libplasma (like plasmashell)
  # uses them, if only when on X11: do-nothing stand-ins (x11-stubs/) for them.
  KEEP_GOING=1 kde_cmake "$s" -DWITHOUT_X11=ON -DCMAKE_CXX_FLAGS="-I$HERE/x11-stubs"
}
inputs_libplasma() { cat "$HERE"/x11-stubs/* "$HERE"/patches/libplasma/*; }
build_layer_shell_qt() {
  local s; s="$(unpack "https://download.kde.org/stable/plasma/$PLASMA_VERSION/layer-shell-qt-$PLASMA_VERSION.tar.xz" "layer-shell-qt-$PLASMA_VERSION.tar.xz")"
  python3 "$HERE/patches/layer-shell-qt/popup-role.py" "$s"
  unandroid "$s"
  kde_cmake "$s"
}
inputs_layer_shell_qt() { cat "$HERE"/patches/layer-shell-qt/*; }

# Global shortcuts: KWin runs kglobalacceld's library in its own process (it
# answers org.kde.kglobalaccel on D-Bus for plasmashell and apps), with its own
# static platform plugin, so no separate daemon is started.
build_kglobalacceld() {
  local s; s="$(unpack "https://download.kde.org/stable/plasma/$PLASMA_VERSION/kglobalacceld-$PLASMA_VERSION.tar.xz" "kglobalacceld-$PLASMA_VERSION.tar.xz")"
  unandroid "$s"
  kde_cmake "$s" -DWITH_X11=OFF
  test -e "$PREFIX/lib/cmake/KGlobalAccelD/KGlobalAccelDConfig.cmake"
}

# QML pieces Plasma's own panel and widgets use: item models, and
# kdeclarative's drag and drop, controls addons and calendar events.
build_kitemmodels() { kf kitemmodels; }
build_kdeclarative() { kf kdeclarative; }
# Settings pages' QML (org.kde.kcmutils): Plasma's widgets import it.
build_kcmutils() { kf kcmutils; }
# Plasma 5's data engines, which the digital clock still reads the time from.
build_plasma5support() {
  local s; s="$(unpack "https://download.kde.org/stable/plasma/$PLASMA_VERSION/plasma5support-$PLASMA_VERSION.tar.xz" "plasma5support-$PLASMA_VERSION.tar.xz")"
  unandroid "$s"
  KEEP_GOING=1 kde_cmake "$s" -DWITH_X11=OFF
  test -e "$PREFIX/lib/cmake/Plasma5Support/Plasma5SupportConfig.cmake"
}

# KDE's look for Qt apps and Plasma's dialogs: the Qt Quick Controls style
# (org.kde.desktop, instead of Android's Material: white windows, big controls)
# and the platform theme (colors, fonts, icons, KDE's file dialog). The theme's
# X11 part is a do-nothing stand-in.
build_qqc2_desktop_style() { kf qqc2-desktop-style; test -e "$PREFIX/lib/qml/org/kde/desktop/qmldir"; }
build_plasma_integration() {
  local s; s="$(unpack "https://download.kde.org/stable/plasma/$PLASMA_VERSION/plasma-integration-$PLASMA_VERSION.tar.xz" "plasma-integration-$PLASMA_VERSION.tar.xz")"
  local t="$s/qt6/src/platformtheme"
  perl -0pi -e 's/find_package\(X11\)\s*set_package_properties\(X11 [^)]*\)/set(X11_FOUND OFF)/' "$t/CMakeLists.txt"
  grep -q "set(X11_FOUND OFF)" "$t/CMakeLists.txt"
  cp "$HERE/patches/plasma-integration/x11integration.cpp" "$t/x11integration.cpp"
  # "Open With" asks xdg-desktop-portal-kde for its app chooser over D-Bus;
  # there's no portal here, so the dialog never appeared. Without that
  # handler KIO shows its own Open With dialog in the app.
  sed -i 's/KIO::JobUiDelegate(flags, window, {new KIOOpenWith(window, nullptr)})/KIO::JobUiDelegate(flags, window, {})/' "$t/kiodelegate.cpp"
  grep -q "KIO::JobUiDelegate(flags, window, {})" "$t/kiodelegate.cpp"
  unandroid "$s"
  kde_cmake "$s" -DBUILD_QT5=OFF -DBUILD_QT6=ON
  test -e "$PREFIX/plugins/platformthemes/KDEPlasmaPlatformTheme6.so" || ls "$PREFIX"/plugins/platformthemes/ | grep -q KDEPlasma
}
inputs_plasma_integration() { cat "$HERE"/patches/plasma-integration/*; }

# ---- Apps' frameworks (stage 5) ----------------------------------------------

# Spell checking: no dictionaries backend yet (Hunspell comes later); the
# trigram data for language guessing needs a host tool, so it's left out.
build_sonnet() { kf sonnet -DSONNET_NO_BACKENDS=ON; }
build_ktextwidgets() { kf ktextwidgets -DWITH_TEXT_TO_SPEECH=OFF; }
build_kparts() { kf kparts; }
build_attica() { kf attica; }
build_syndication() { kf syndication; }
build_knewstuff() { kf knewstuff; }
# File metadata without extractors for now (no taglib, exiv2, poppler).
build_kfilemetadata() { kf kfilemetadata; }

# Breeze's icon theme, as files (KIconThemes here doesn't embed it).
# Its library needs tools it builds for the target (no host variants), so only
# the themes' files are installed. Breeze Dark's symbolic icons are made from
# the light ones by its generate-symbolic-dark, built here for the host; icons
# it doesn't recolor come from Breeze, which Breeze Dark inherits (instead of
# copies of them all).
# Breeze for GTK programs (Floorp...): CSS and images only, made on the
# build machine from the prefix's Plasma color schemes.
build_breeze_gtk() {
  local s; s="$(unpack "https://download.kde.org/stable/plasma/$PLASMA_VERSION/breeze-gtk-$PLASMA_VERSION.tar.xz" "breeze-gtk-$PLASMA_VERSION.tar.xz")"
  command -v sassc >/dev/null && python3 -c "import cairo" 2>/dev/null || sudo apt-get install -y -q sassc python3-cairo >/dev/null
  sed 's|@Python3_EXECUTABLE@|python3|g' "$s/src/build_theme.sh.cmake" > "$s/src/build_theme.sh"
  rm -rf "$PREFIX/share/themes/Breeze" "$PREFIX/share/themes/Breeze-Dark"
  (cd "$s/src" && sh build_theme.sh -c BreezeDark -t "$PREFIX/share/themes/Breeze-Dark" -r "$PREFIX/share/color-schemes" \
    && sh build_theme.sh -c BreezeLight -t "$PREFIX/share/themes/Breeze" -r "$PREFIX/share/color-schemes")
  cp "$s/src/gtk-dark-3.0.css" "$PREFIX/share/themes/Breeze/gtk-3.0/gtk-dark.css"
  cp "$s/src/settings.ini" "$PREFIX/share/themes/Breeze/settings.ini"
  cp "$s/src/settings.ini" "$PREFIX/share/themes/Breeze-Dark/settings.ini"
  test -s "$PREFIX/share/themes/Breeze-Dark/gtk-3.0/gtk.css"
}
build_breeze_icons() {
  local s d; s="$(kf_src breeze-icons)"; d="$(mktemp -d)"
  sed -i -E 's/^add_subdirectory\((autotests|src)\)/# &/' "$s/CMakeLists.txt"
  ! grep -qE '^add_subdirectory\(src\)' "$s/CMakeLists.txt"
  perl -0pi -e 's/install\(EXPORT KF6BreezeIconsTargets.*?\)\n//s or die "breeze-icons export"' "$s/CMakeLists.txt"
  perl -0pi -e 's/\n\s*foreach \(icon_file \$\{BREEZE_LIGHT_ICONS\}\).*?endforeach\(\)//s or die "breeze-dark fallback copies"' "$s/icons-dark/CMakeLists.txt"
  kde_cmake "$s" -DWITH_ICON_GENERATION=OFF
  cat > "$d/CMakeLists.txt" <<EOF2
cmake_minimum_required(VERSION 3.16)
project(breeze_icons_host_tools CXX)
find_package(Qt6 REQUIRED COMPONENTS Core)
add_executable(generate-symbolic-dark "$s/src/tools/generate-symbolic-dark.cpp")
target_link_libraries(generate-symbolic-dark Qt6::Core)
EOF2
  cmake -S "$d" -B "$d/_host" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$QT_HOST_PATH"
  cmake --build "$d/_host"
  "$d/_host/generate-symbolic-dark" "$s/icons" "$d/dark"
  find "$d/dark" -xtype l -delete
  cp -a "$d/dark/." "$PREFIX/share/icons/breeze-dark/"
  test -e "$PREFIX/share/icons/breeze/index.theme"
  test -e "$PREFIX/share/icons/breeze-dark/index.theme"
  test -n "$(find "$PREFIX/share/icons/breeze-dark/places" -name 'folder*.svg' | head -1)"
}
# kcmutils' build tool (desktop files for settings pages), for the host: apps
# with settings pages (Dolphin) run it at build time.
build_kcmutils_host() {
  local s d; s="$(kf_src kcmutils)"; d="$(mktemp -d)"
  cat > "$d/CMakeLists.txt" <<EOF2
cmake_minimum_required(VERSION 3.16)
project(kcmutils_host_tools CXX)
find_package(Qt6 REQUIRED COMPONENTS Core)
add_executable(kcmdesktopfilegenerator "$s/tools/kcmmetadatagenerator.cpp")
target_link_libraries(kcmdesktopfilegenerator Qt6::Core)
install(TARGETS kcmdesktopfilegenerator EXPORT KF6KCMUtilsToolingTargets DESTINATION lib/libexec/kf6)
install(EXPORT KF6KCMUtilsToolingTargets DESTINATION lib/cmake/KF6KCMUtils FILE KF6KCMUtilsToolingTargets.cmake NAMESPACE KF6::)
EOF2
  cmake -S "$d" -B "$d/_host" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$QT_HOST_PATH" -DCMAKE_INSTALL_PREFIX="$HOSTPREFIX"
  cmake --build "$d/_host" && cmake --install "$d/_host"
  test -e "$HOSTPREFIX/lib/cmake/KF6KCMUtils/KF6KCMUtilsToolingTargets.cmake"
}

# ---- Apps (stage 5) -----------------------------------------------------------

GEAR_VERSION=25.08.2
# Dolphin, as a library QtHost starts (apps/as-library.py), like plasmashell.
build_dolphin() {
  local s; s="$(unpack "https://download.kde.org/stable/release-service/$GEAR_VERSION/src/dolphin-$GEAR_VERSION.tar.xz" "dolphin-$GEAR_VERSION.tar.xz")"
  python3 "$HERE/apps/as-library.py" "$s" src/CMakeLists.txt dolphin src/main.cpp
  # Wayland only: Dolphin assumes X11 on any Unix.
  sed -i 's/^    set(HAVE_X11 TRUE)/    set(HAVE_X11 FALSE)/' "$s/CMakeLists.txt"
  grep -q "set(HAVE_X11 FALSE)" "$s/CMakeLists.txt"
  unandroid "$s"
  KEEP_GOING=1 kde_cmake "$s" -DCMAKE_CXX_FLAGS="-D__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__"
  test -e "$PREFIX/lib/libdolphin.so"
}
# Thumbnails (Dolphin, the wallpaper picker): kio-extras' thumbnail worker
# and its thumbnailers only; the rest of kio-extras isn't needed.
build_kio_extras() {
  local s; s="$(unpack "https://download.kde.org/stable/release-service/$GEAR_VERSION/src/kio-extras-$GEAR_VERSION.tar.xz" "kio-extras-$GEAR_VERSION.tar.xz")"
  perl -0pi -e 's/\n    DNSSD\n/\n/ or die "dnssd"; s/find_package\(QCoro6 REQUIRED COMPONENTS Core\)\nqcoro_enable_coroutines\(\)\n// or die "qcoro"; s/^add_subdirectory\(kcms\)\n.*?(?=^if\(BUILD_DOC\)\n    add_subdirectory\(doc\))/add_subdirectory(thumbnail)\n\n/ms or die "subdirs"' "$s/CMakeLists.txt"
  # The worker draws offscreen, a Qt platform this build leaves out on
  # Android: it keeps the app's Wayland one (it makes no windows).
  perl -0pi -e 's/^(    qputenv\("QT_QPA_PLATFORM", "offscreen"\);)$/#ifndef Q_OS_ANDROID\n$1\n#endif/m or die "offscreen"' "$s/thumbnail/thumbnail.cpp"
  # Thumbnailers are asked for by ID (imagethumbnail...); without one in
  # their metadata, KDE takes the file name, which on Android is the APK's
  # flat libplugins_kf6_thumbcreator_<name>. Each gets its ID written in.
  python3 - "$s/thumbnail" <<'PY'
import json, pathlib, sys
for f in pathlib.Path(sys.argv[1]).glob("*thumbnail.json"):
    if f.name == "thumbnail.json":
        continue
    d = json.loads(f.read_text())
    d.setdefault("KPlugin", {})["Id"] = f.stem
    f.write_text(json.dumps(d, indent=4) + "\n")
PY
  grep -q '"Id": "imagethumbnail"' "$s/thumbnail/imagethumbnail.json"
  # Comic books need KArchive's 7-Zip, built without here.
  perl -0pi -e 's/^add_library\(comicbookthumbnail .*?^install\(TARGETS comicbookthumbnail [^\n]*\n//ms or die "comic"' "$s/thumbnail/CMakeLists.txt"
  unandroid "$s"
  KEEP_GOING=1 kde_cmake "$s" -DWITHOUT_X11=ON -DBUILD_DOC=OFF -DUSE_DBUS=ON -DBUILD_ACTIVITIES=OFF
  test -e "$PREFIX/plugins/kf6/kio/thumbnail.so"
  test -e "$PREFIX/plugins/kf6/thumbcreator/imagethumbnail.so"
}
# KWrite: KDE's text editor, from Kate's sources without Kate and its
# plugins. KSyntaxHighlighting builds its indexer for the host itself.
build_syntax_highlighting() {
  local s; s="$(kf_src syntax-highlighting)"
  # The host's rcc compresses with zstd, which this Qt can't read.
  sed -i 's|COMMAND Qt6::rcc --name syntax_data|COMMAND Qt6::rcc --no-zstd --name syntax_data|' "$s/data/CMakeLists.txt"
  grep -q -- "--no-zstd" "$s/data/CMakeLists.txt"
  unandroid "$s"; kde_cmake "$s" -DWITH_X11=OFF -DUSE_DBUS=ON
}
build_ktexteditor() { kf ktexteditor -DENABLE_KAUTH=OFF; }
build_kwrite() {
  local s; s="$(unpack "https://download.kde.org/stable/release-service/$GEAR_VERSION/src/kate-$GEAR_VERSION.tar.xz" "kate-$GEAR_VERSION.tar.xz")"
  sed -i 's|^add_executable(kwrite main.cpp data/kwrite.qrc)|add_executable(kwrite)\ntarget_sources(kwrite PRIVATE main.cpp data/kwrite.qrc)|' "$s/apps/kwrite/CMakeLists.txt"
  python3 "$HERE/apps/as-library.py" "$s" apps/kwrite/CMakeLists.txt kwrite apps/kwrite/main.cpp
  # Kate too (for the app store), without its plugins: same library, tabs,
  # sessions and split views. Its target is kate-bin, named kate.
  perl -0pi -e 's/^add_executable\(kate-bin\n/add_executable(kate-bin)\ntarget_sources(kate-bin PRIVATE\n/m or die "kate-bin"' "$s/apps/kate/CMakeLists.txt"
  python3 "$HERE/apps/as-library.py" "$s" apps/kate/CMakeLists.txt kate-bin apps/kate/main.cpp
  unandroid "$s"
  KEEP_GOING=1 kde_cmake "$s" -DBUILD_addons=OFF -DBUILD_doc=OFF -DENABLE_PCH=OFF -DUSE_DBUS=ON \
    -DCMAKE_CXX_FLAGS="-D__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__"
  test -e "$PREFIX/lib/libkwrite.so"
  test -e "$PREFIX/lib/libkate.so"
}
inputs_kwrite() { inputs_dolphin; }
# Gwenview: KDE's image viewer, with the image libraries it reads
# through (JPEG, PNG, and Exiv2 for metadata).
build_libjpeg_turbo() {
  local s; s="$(unpack https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.1.0/libjpeg-turbo-3.1.0.tar.gz libjpeg-turbo-3.1.0.tar.gz)"
  cmake_cross "$s" -DENABLE_STATIC=OFF -DWITH_TURBOJPEG=OFF
}
build_libpng() {
  local s; s="$(unpack https://github.com/pnggroup/libpng/archive/refs/tags/v1.6.47.tar.gz libpng-1.6.47.tar.gz)"
  cmake_cross "$s" -DPNG_STATIC=OFF -DPNG_TESTS=OFF -DPNG_TOOLS=OFF -DPNG_FRAMEWORK=OFF
}
build_exiv2() {
  local s; s="$(unpack https://github.com/Exiv2/exiv2/archive/refs/tags/v0.28.3.tar.gz exiv2-0.28.3.tar.gz)"
  cmake_cross "$s" -DBUILD_SHARED_LIBS=ON -DEXIV2_ENABLE_INIH=OFF -DEXIV2_ENABLE_BROTLI=OFF -DEXIV2_ENABLE_NLS=OFF \
    -DEXIV2_ENABLE_WEBREADY=OFF -DEXIV2_ENABLE_XMP=ON -DEXIV2_BUILD_EXIV2_COMMAND=OFF -DEXIV2_BUILD_SAMPLES=OFF \
    -DEXIV2_BUILD_UNIT_TESTS=OFF -DEXIV2_BUILD_DOC=OFF -DEXIV2_ENABLE_LENSDATA=ON
}
build_gwenview() {
  local s; s="$(unpack "https://download.kde.org/stable/release-service/$GEAR_VERSION/src/gwenview-$GEAR_VERSION.tar.xz" "gwenview-$GEAR_VERSION.tar.xz")"
  sed -i 's|^add_executable(gwenview ${gwenview_SRCS})|add_executable(gwenview)\ntarget_sources(gwenview PRIVATE ${gwenview_SRCS})|' "$s/app/CMakeLists.txt"
  python3 "$HERE/apps/as-library.py" "$s" app/CMakeLists.txt gwenview app/main.cpp
  unandroid "$s"
  KEEP_GOING=1 kde_cmake "$s" -DWITHOUT_X11=ON -DGWENVIEW_IMAGEANNOTATOR=OFF -DGWENVIEW_NO_WAYLAND_GESTURES=ON \
    -DGWENVIEW_SEMANTICINFO_BACKEND=None -DCMAKE_CXX_FLAGS="-D__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__"
  test -e "$PREFIX/lib/libgwenview.so"
}
inputs_gwenview() { inputs_dolphin; }
# KCalc: KDE's calculator, on GMP, MPFR and MPC for its arbitrary precision.
build_gmp() {
  local s; s="$(unpack https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz gmp-6.3.0.tar.xz)"
  autotools_cross "$s" --disable-static --enable-shared --enable-cxx=no
}
build_mpfr() {
  local s; s="$(unpack https://ftp.gnu.org/gnu/mpfr/mpfr-4.2.2.tar.xz mpfr-4.2.2.tar.xz)"
  autotools_cross "$s" --disable-static --enable-shared --with-gmp="$PREFIX"
}
build_mpc() {
  local s; s="$(unpack https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz mpc-1.3.1.tar.gz)"
  autotools_cross "$s" --disable-static --enable-shared --with-gmp="$PREFIX" --with-mpfr="$PREFIX"
}
build_kcalc() {
  local s; s="$(unpack "https://download.kde.org/stable/release-service/$GEAR_VERSION/src/kcalc-$GEAR_VERSION.tar.xz" "kcalc-$GEAR_VERSION.tar.xz")"
  python3 "$HERE/apps/as-library.py" "$s" CMakeLists.txt kcalc kcalc.cpp
  unandroid "$s"
  KEEP_GOING=1 kde_cmake "$s" -DCMAKE_CXX_FLAGS="-D__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__"
  test -e "$PREFIX/lib/libkcalc.so"
}
inputs_kcalc() { inputs_dolphin; }
# Konsole: KDE's terminal, on KPty and KNotifyConfig. Its right-to-left text
# uses ICU's C API (ubidi, ushape), whose tables are compiled in: only ICU's
# libraries are built, its data left out (libicudata is the stub).
build_icu() {
  local s; s="$(unpack https://github.com/unicode-org/icu/releases/download/release-76-1/icu4c-76_1-src.tgz icu4c-76_1-src.tgz)"
  mkdir -p "$s/_host" "$s/_android"
  # The data tools run on the build machine, from a host build.
  (cd "$s/_host" && ../source/runConfigureICU Linux --disable-tests --disable-samples --disable-extras && make -j"$JOBS")
  (cd "$s/_android" && CC="$CC" CXX="$CXX" AR="$BIN/llvm-ar" RANLIB="$BIN/llvm-ranlib" \
    CXXFLAGS="-O2 -fPIC" LDFLAGS="-lc++_shared" \
    ../source/configure --host=$TRIPLE --prefix="$PREFIX" --libdir="$PREFIX/lib" --with-cross-build="$s/_host" \
      --with-data-packaging=archive --disable-tests --disable-samples --disable-extras --disable-tools --disable-icuio \
      --disable-layoutex --enable-shared --disable-static)
  # Only the libraries: the data build wants an ICU data list the host
  # tools would make, and no data is shipped. stubdata is the empty libicudata.
  mkdir -p "$s/_android/lib" "$s/_android/bin" # made by the top-level make, skipped here
  for d in stubdata common i18n; do make -C "$s/_android/$d" -j"$JOBS" || return 1; make -C "$s/_android/$d" install || return 1; done
  test -e "$PREFIX/lib/libicuuc.so"
}
build_kpty() {
  local s; s="$(kf_src kpty)"
  # Bionic's utmp.h has no updwtmp or getutline, and Android keeps no login
  # records: KPty's login() and logout() do nothing here.
  perl -0pi -e 's/(\nvoid KPty::(?:login\(const char \*user, const char \*remotehost\)|logout\(\))\n\{\n)(.*?)(\n\}\n)/$1#ifndef __ANDROID__ \/\/ no utmp on Android\n$2\n#endif$3/sg; $n = () = /no utmp on Android/g; die "kpty utmp" unless $n == 2' "$s/src/kpty.cpp"
  unandroid "$s"; kde_cmake "$s" -DWITH_X11=OFF -DUSE_DBUS=ON -DCMAKE_DISABLE_FIND_PACKAGE_UTEMPTER=ON
}
build_knotifyconfig() { kf knotifyconfig; }
build_konsole() {
  local s; s="$(unpack "https://download.kde.org/stable/release-service/$GEAR_VERSION/src/konsole-$GEAR_VERSION.tar.xz" "konsole-$GEAR_VERSION.tar.xz")"
  sed -i 's|^add_executable(konsole ${konsole_SRCS} ${ICONS_SOURCES})|add_executable(konsole)\ntarget_sources(konsole PRIVATE ${konsole_SRCS} ${ICONS_SOURCES})|' "$s/src/CMakeLists.txt"
  python3 "$HERE/apps/as-library.py" "$s" src/CMakeLists.txt konsole src/main.cpp
  # Android's shell, when $SHELL isn't set.
  sed -i 's|QStringLiteral("/bin/sh")};|QStringLiteral("/system/bin/sh")};|' "$s/src/session/Session.cpp"
  grep -q '"/system/bin/sh"' "$s/src/session/Session.cpp"
  unandroid "$s"
  KEEP_GOING=1 kde_cmake "$s" -DWITH_X11=OFF -DUSE_DBUS=ON -DENABLE_PLUGIN_SSHMANAGER=OFF -DENABLE_PLUGIN_QUICKCOMMANDS=OFF \
    -DCMAKE_CXX_FLAGS="-D__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__"
  test -e "$PREFIX/lib/libkonsole.so"
}
inputs_konsole() { inputs_dolphin; }
inputs_dolphin() { cat "$HERE"/apps/as-library.py "$HERE"/kwin-nativedesk/qthost_entry.cpp; }

# ---- GTK 3 (for Floorp, stage 6) ----------------------------------------------
# GNOME's toolkit for Android: GLib, Cairo, Pango and GTK 3 with only its
# Wayland backend, shown on KWin like the KDE apps.

build_pcre2() {
  local s; s="$(unpack https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.45/pcre2-10.45.tar.bz2 pcre2-10.45.tar.bz2)"
  cmake_cross "$s" -DBUILD_SHARED_LIBS=ON -DPCRE2_BUILD_PCRE2GREP=OFF -DPCRE2_BUILD_TESTS=OFF -DPCRE2_SUPPORT_JIT=ON
}
# GLib's build tools (glib-compile-resources, -schemas, glib-mkenums...) for
# the build machine first, then GLib for Android.
build_glib() {
  local s; s="$(unpack https://download.gnome.org/sources/glib/2.84/glib-2.84.1.tar.xz glib-2.84.1.tar.xz)"
  local opts=(-Dtests=false -Dintrospection=disabled -Dman-pages=disabled -Ddocumentation=false -Dsysprof=disabled
    -Dselinux=disabled -Dxattr=false -Dlibmount=disabled -Dnls=disabled -Dlibelf=disabled -Dglib_debug=disabled)
  # Static, so the tools don't pick up the runner's older GLib when they run.
  meson setup "$s/_host" "$s" --prefix="$HOSTPREFIX" --libdir=lib --buildtype=release -Ddefault_library=static "${opts[@]}"
  ninja -C "$s/_host" install
  "$HOSTPREFIX/bin/glib-compile-resources" --help >/dev/null
  # GNU gettext's libintl (build_libintl), found with its header's folder (meson checks with the C++ compiler too). Without
  # it GLib builds its own stand-in, installed over it as libintl.so with other
  # symbols, and KDE's i18n no longer loads (KWin died at start in build 210).
  build_libintl # gettext's again, in case an earlier GLib build replaced it
  meson_cross "$s" "${opts[@]}" -Dc_args="-ffile-prefix-map=$WORK=. -I$PREFIX/include" -Dcpp_args="-ffile-prefix-map=$WORK=. -I$PREFIX/include"
  grep -i -E "intl|ngettext|Checking for function|Library .* found|Header" "$s/_android/meson-logs/meson-log.txt" | grep -i -E "intl|ngettext" | tail -38 >&2 || true
  test -e "$PREFIX/lib/libgio-2.0.so" && test -x "$HOSTPREFIX/bin/glib-compile-resources"
  "$BIN/llvm-nm" -D "$PREFIX/lib/libintl.so" | grep -q " libintl_bind_textdomain_codeset"
}
build_pixman() {
  local s; s="$(unpack https://cairographics.org/releases/pixman-0.46.0.tar.gz pixman-0.46.0.tar.gz)"
  meson_cross "$s" -Dtests=disabled -Ddemos=disabled -Dgtk=disabled -Dlibpng=disabled
}
build_fribidi() {
  local s; s="$(unpack https://github.com/fribidi/fribidi/releases/download/v1.0.16/fribidi-1.0.16.tar.xz fribidi-1.0.16.tar.xz)"
  meson_cross "$s" -Ddocs=false -Dtests=false -Dbin=false
}
build_harfbuzz() {
  local s; s="$(unpack https://github.com/harfbuzz/harfbuzz/releases/download/11.2.1/harfbuzz-11.2.1.tar.xz harfbuzz-11.2.1.tar.xz)"
  meson_cross "$s" -Dglib=enabled -Dgobject=enabled -Dfreetype=enabled -Dcairo=disabled -Dicu=disabled \
    -Dtests=disabled -Ddocs=disabled -Dintrospection=disabled -Dutilities=disabled -Dbenchmark=disabled
}
build_cairo() {
  local s; s="$(unpack https://cairographics.org/releases/cairo-1.18.4.tar.xz cairo-1.18.4.tar.xz)"
  meson_cross "$s" -Dxlib=disabled -Dxcb=disabled -Dquartz=disabled -Dtee=disabled -Dpng=enabled \
    -Dfreetype=enabled -Dfontconfig=enabled -Dglib=enabled -Dtests=disabled -Dgtk_doc=false \
    -Dspectre=disabled -Dsymbol-lookup=disabled -Dlzo=disabled
  test -e "$PREFIX/lib/pkgconfig/cairo-gobject.pc"
}
build_pango() {
  : against GNU libintl, 2 # (rebuilt when GLib stopped bringing its own)
  local s; s="$(unpack https://download.gnome.org/sources/pango/1.56/pango-1.56.3.tar.xz pango-1.56.3.tar.xz)"
  meson_cross "$s" -Dintrospection=disabled -Dbuild-testsuite=false -Dbuild-examples=false -Dxft=disabled \
    -Dfontconfig=enabled -Dfreetype=enabled -Dcairo=enabled -Dlibthai=disabled -Dsysprof=disabled -Ddocumentation=false
  test -e "$PREFIX/lib/pkgconfig/pangoft2.pc"
}
build_gdk_pixbuf() {
  : against GNU libintl, 2 # (rebuilt when GLib stopped bringing its own)
  local s; s="$(unpack https://download.gnome.org/sources/gdk-pixbuf/2.42/gdk-pixbuf-2.42.12.tar.xz gdk-pixbuf-2.42.12.tar.xz)"
  meson_cross "$s" -Dpng=enabled -Djpeg=enabled -Dtiff=disabled -Dothers=disabled -Dbuiltin_loaders=png,jpeg \
    -Dintrospection=disabled -Dman=false -Dgtk_doc=false -Dtests=false -Dinstalled_tests=false
}
# ATK only (GTK 3 needs it; the D-Bus accessibility bus is for X11).
build_atk() {
  : against GNU libintl, 2 # (rebuilt when GLib stopped bringing its own)
  local s; s="$(unpack https://download.gnome.org/sources/at-spi2-core/2.56/at-spi2-core-2.56.0.tar.xz at-spi2-core-2.56.0.tar.xz)"
  # libxml2 is for the accessibility bus's tools, not ATK.
  sed -i "s/^libxml_dep = dependency('libxml-2.0', version: libxml_req_version)$/libxml_dep = dependency('libxml-2.0', version: libxml_req_version, required: not get_option('atk_only'))/" "$s/meson.build"
  grep -q "required: not get_option('atk_only'))" "$s/meson.build"
  meson_cross "$s" -Datk_only=true -Dintrospection=disabled -Ddocs=false -Dx11=disabled
  test -e "$PREFIX/lib/pkgconfig/atk.pc"
}
# GTK's resources need gdk-pixbuf-pixdata on the build machine (CI installs it).
build_gtk3() {
  : against GNU libintl, 2 # (rebuilt when GLib stopped bringing its own)
  command -v gdk-pixbuf-pixdata >/dev/null
  local s; s="$(unpack https://download.gnome.org/sources/gtk/3.24/gtk-3.24.49.tar.xz gtk-3.24.49.tar.xz)"
  # No shm_open in Android's libc: Wayland buffers use memfd_create, which
  # GTK tries first; its shm_open fallback just fails.
  sed -i 's|^#include <linux/memfd.h>$|&\n#ifdef __ANDROID__\n#define shm_open(n, f, m) (errno = ENOSYS, -1)\n#define shm_unlink(n) 0\n#endif|' "$s/gdk/wayland/gdkdisplay-wayland.c"
  grep -q 'define shm_open' "$s/gdk/wayland/gdkdisplay-wayland.c"
  # Keep going past errors while the port is new, so one run shows them all.
  NINJA_KEEP_GOING=1 meson_cross "$s" -Dx11_backend=false -Dwayland_backend=true -Dbroadway_backend=false -Dwin32_backend=false \
    -Dquartz_backend=false -Dprint_backends=file -Dcolord=no -Dintrospection=false -Ddemos=false \
    -Dexamples=false -Dtests=false -Dinstalled_tests=false -Dgtk_doc=false -Dman=false
  test -e "$PREFIX/lib/libgtk-3.so" && test -e "$PREFIX/lib/pkgconfig/gtk+-wayland-3.0.pc"
}

# ---- GIMP (for the app store) -------------------------------------------------
# GIMP 3 and what it needs on top of the GTK stack: GEGL and babl (its image
# engine), libmypaint (brushes), librsvg (icons), Poppler (PDF import),
# AppStream (its extensions' metadata) and GObject Introspection's library
# (Script-Fu). Packaged for the store by native/nativedesk/build.sh.

# pkg-config files for libraries without one: the NDK's zlib (exiv2.pc
# asks for it) and libpng's unversioned name (its CMake build installs
# libpng16.pc only).
gimp_pc() {
  mkdir -p "$PREFIX/lib/pkgconfig"
  [ -e "$PREFIX/lib/pkgconfig/zlib.pc" ] || printf 'Name: zlib\nDescription: zlib (the NDK'"'"'s)\nVersion: 1.3.0\nLibs: -lz\nCflags:\n' \
    > "$PREFIX/lib/pkgconfig/zlib.pc"
  [ -e "$PREFIX/lib/pkgconfig/libpng.pc" ] || ln -s libpng16.pc "$PREFIX/lib/pkgconfig/libpng.pc"
}
build_xz() {
  local s; s="$(unpack https://github.com/tukaani-project/xz/releases/download/v5.8.1/xz-5.8.1.tar.xz xz-5.8.1.tar.xz)"
  autotools_cross "$s" --disable-static --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo \
    --disable-lzma-links --disable-scripts --disable-doc --disable-nls
  test -e "$PREFIX/lib/liblzma.so"
}
build_libtiff() {
  local s; s="$(unpack https://download.osgeo.org/libtiff/tiff-4.7.0.tar.xz tiff-4.7.0.tar.xz)"
  cmake_cross "$s" -DBUILD_SHARED_LIBS=ON -Dtiff-tools=OFF -Dtiff-tests=OFF -Dtiff-contrib=OFF -Dtiff-docs=OFF \
    -Dwebp=OFF -Dzstd=OFF -Djbig=OFF -Dlerc=OFF -Dlibdeflate=OFF -Dlzma=ON -Djpeg=ON -Dzlib=ON
  test -e "$PREFIX/lib/pkgconfig/libtiff-4.pc"
}
build_libxml2() {
  local s; s="$(unpack https://download.gnome.org/sources/libxml2/2.13/libxml2-2.13.8.tar.xz libxml2-2.13.8.tar.xz)"
  cmake_cross "$s" -DBUILD_SHARED_LIBS=ON -DLIBXML2_WITH_PYTHON=OFF -DLIBXML2_WITH_LZMA=OFF -DLIBXML2_WITH_ICU=OFF \
    -DLIBXML2_WITH_TESTS=OFF -DLIBXML2_WITH_PROGRAMS=OFF -DLIBXML2_WITH_ICONV=ON
  test -e "$PREFIX/lib/pkgconfig/libxml-2.0.pc"
}
build_json_glib() {
  local s; s="$(unpack https://download.gnome.org/sources/json-glib/1.10/json-glib-1.10.6.tar.xz json-glib-1.10.6.tar.xz)"
  meson_cross "$s" -Dintrospection=disabled -Ddocumentation=disabled -Dman=false -Dtests=false -Dconformance=false \
    -Dnls=disabled -Dinstalled_tests=false
  test -e "$PREFIX/lib/pkgconfig/json-glib-1.0.pc"
}
build_babl() {
  local s; s="$(unpack https://download.gimp.org/babl/0.1/babl-0.1.124.tar.xz babl-0.1.124.tar.xz)"
  meson_cross "$s" -Denable-gir=false -Dwith-docs=false -Denable-vapi=false -Dgi-docgen=disabled -Dwith-lcms=enabled \
    -Drelocatable=disabled
  test -e "$PREFIX/lib/pkgconfig/babl-0.1.pc"
}
build_gegl() {
  local s; s="$(unpack https://download.gimp.org/gegl/0.4/gegl-0.4.70.tar.xz gegl-0.4.70.tar.xz)"
  # Only what GIMP uses: everything optional off, then Cairo, Pango, LCMS,
  # gdk-pixbuf and libtiff back on.
  gimp_pc
  NINJA_KEEP_GOING=1 meson_cross "$s" -Dauto_features=disabled -Ddocs=false -Dgtk-doc=false -Dworkshop=false \
    -Dintrospection=false -Dvapigen=disabled -Dgi-docgen=disabled -Drelocatable-bundle=no \
    -Dcairo=enabled -Dpango=enabled -Dpangocairo=enabled -Dlcms=enabled -Dgdk-pixbuf=enabled -Dlibtiff=enabled
  test -e "$PREFIX/lib/pkgconfig/gegl-0.4.pc"
}
build_gexiv2() {
  local s; s="$(unpack https://download.gnome.org/sources/gexiv2/0.14/gexiv2-0.14.6.tar.xz gexiv2-0.14.6.tar.xz)"
  gimp_pc
  meson_cross "$s" -Dintrospection=false -Dvapi=false -Dtools=false -Dpython3=false -Dtests=false -Dgtk_doc=false
  test -e "$PREFIX/lib/pkgconfig/gexiv2.pc"
}
build_json_c() {
  local s; s="$(unpack https://s3.amazonaws.com/json-c_releases/releases/json-c-0.18.tar.gz json-c-0.18.tar.gz)"
  cmake_cross "$s" -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF -DBUILD_TESTING=OFF -DBUILD_APPS=OFF -DDISABLE_EXTRA_LIBS=ON
  test -e "$PREFIX/lib/pkgconfig/json-c.pc"
}
build_libmypaint() {
  local s; s="$(unpack https://github.com/mypaint/libmypaint/releases/download/v1.6.1/libmypaint-1.6.1.tar.xz libmypaint-1.6.1.tar.xz)"
  autotools_cross "$s" --disable-static --disable-introspection --disable-gegl --disable-i18n --disable-docs \
    --disable-openmp --with-glib
  test -e "$PREFIX/lib/pkgconfig/libmypaint.pc"
}
build_mypaint_brushes() {
  local s; s="$(unpack https://github.com/mypaint/mypaint-brushes/releases/download/v2.0.2/mypaint-brushes-2.0.2.tar.xz mypaint-brushes-2.0.2.tar.xz)"
  autotools_cross "$s"
  test -e "$PREFIX/share/pkgconfig/mypaint-brushes-2.0.pc"
}
# librsvg's last C version (Rust from 2.41 on): GIMP needs 2.40.6 or later.
build_libcroco() {
  local s; s="$(unpack https://download.gnome.org/sources/libcroco/0.6/libcroco-0.6.13.tar.xz libcroco-0.6.13.tar.xz)"
  autotools_cross "$s" --disable-static --disable-gtk-doc
  test -e "$PREFIX/lib/pkgconfig/libcroco-0.6.pc"
}
build_librsvg() {
  local s; s="$(unpack https://download.gnome.org/sources/librsvg/2.40/librsvg-2.40.21.tar.xz librsvg-2.40.21.tar.xz)"
  # Written for libxml2 before 2.12, whose error callbacks took a non-const error.
  CFLAGS="-O2 -Wno-error=incompatible-function-pointer-types" autotools_cross "$s" --disable-static --disable-introspection --disable-vala --disable-tools \
    --disable-pixbuf-loader --disable-gtk-doc
  test -e "$PREFIX/lib/pkgconfig/librsvg-2.0.pc"
}
build_libarchive() {
  local s; s="$(unpack https://github.com/libarchive/libarchive/releases/download/v3.8.1/libarchive-3.8.1.tar.xz libarchive-3.8.1.tar.xz)"
  cmake_cross "$s" -DENABLE_TEST=OFF -DENABLE_TAR=OFF -DENABLE_CPIO=OFF -DENABLE_CAT=OFF -DENABLE_UNZIP=OFF \
    -DENABLE_OPENSSL=OFF -DENABLE_MBEDTLS=OFF -DENABLE_NETTLE=OFF -DENABLE_ACL=OFF -DENABLE_XATTR=OFF \
    -DENABLE_LIBB2=OFF -DENABLE_LZ4=OFF -DENABLE_ZSTD=OFF -DENABLE_EXPAT=OFF -DENABLE_LIBXML2=OFF \
    -DENABLE_BZip2=OFF -DENABLE_ICONV=OFF -DENABLE_LZMA=ON -DENABLE_ZLIB=ON
  test -e "$PREFIX/lib/pkgconfig/libarchive.pc"
}
build_curl() {
  local s; s="$(unpack https://curl.se/download/curl-8.14.1.tar.xz curl-8.14.1.tar.xz)"
  cmake_cross "$s" -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF -DBUILD_CURL_EXE=OFF -DBUILD_TESTING=OFF \
    -DBUILD_LIBCURL_DOCS=OFF -DBUILD_MISC_DOCS=OFF -DENABLE_CURL_MANUAL=OFF -DCURL_USE_OPENSSL=ON \
    -DCURL_USE_LIBPSL=OFF -DUSE_LIBIDN2=OFF -DCURL_USE_LIBSSH2=OFF -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF \
    -DUSE_NGHTTP2=OFF -DCURL_CA_PATH=/system/etc/security/cacerts
  test -e "$PREFIX/lib/pkgconfig/libcurl.pc"
}
build_libfyaml() {
  local s; s="$(unpack https://github.com/pantoniou/libfyaml/releases/download/v0.9/libfyaml-0.9.tar.gz libfyaml-0.9.tar.gz)"
  LDFLAGS="-L$PREFIX/lib" autotools_cross "$s" --disable-static --disable-network
  test -e "$PREFIX/lib/pkgconfig/libfyaml.pc"
}
build_libxmlb() {
  local s; s="$(unpack https://github.com/hughsie/libxmlb/releases/download/0.3.24/libxmlb-0.3.24.tar.xz libxmlb-0.3.24.tar.xz)"
  meson_cross "$s" -Dgtkdoc=false -Dintrospection=false -Dtests=false -Dcli=false -Dlzma=disabled -Dzstd=disabled
  test -e "$PREFIX/lib/pkgconfig/xmlb.pc"
}
build_appstream() {
  local s; s="$(unpack https://www.freedesktop.org/software/appstream/releases/AppStream-1.2.2.tar.xz AppStream-1.2.2.tar.xz)"
  # Its tarball has one more folder level.
  [ -e "$s/meson.build" ] || s="$(dirname "$(ls "$s"/*/meson.build | head -1)")"
  # Its data folder (metainfo, translation rules) needs AppStream on the
  # build machine when cross-building; the library doesn't use it.
  sed -i "/^subdir('data\/')$/d" "$s/meson.build"
  if grep -q "^subdir('data/')" "$s/meson.build"; then return 1; fi
  NINJA_KEEP_GOING=1 meson_cross "$s" -Dstemming=false -Dsystemd=false -Dvapi=false -Dqt=false -Dcompose=false \
    -Dapt-support=false -Dgir=false -Dtools=false -Dzstd-support=false -Dblake3-support=false \
    -Ddisplay-detection=none -Ddocs=false -Dapidocs=false \
    -Dinstall-docs=false -Dman=false -Dbash-completion=false
  test -e "$PREFIX/lib/pkgconfig/appstream.pc"
}
# The library only (Script-Fu calls GIMP through it); no typelibs, which
# would mean running Android programs on the build machine.
build_gobject_introspection() {
  local s; s="$(unpack https://download.gnome.org/sources/gobject-introspection/1.84/gobject-introspection-1.84.0.tar.xz gobject-introspection-1.84.0.tar.xz)"
  # Without the scanner, a Python module that would need Android's Python headers.
  sed -i -e "/^cc.check_header('Python.h'/d" -e "/^subdir('giscanner')$/d" "$s/meson.build"
  if grep -q "^subdir('giscanner')" "$s/meson.build"; then return 1; fi
  meson_cross "$s" -Dgi_cross_use_prebuilt_gi=true -Dbuild_introspection_data=false -Dtests=false \
    -Ddoctool=disabled -Dcairo=disabled -Dgtk_doc=false
  test -e "$PREFIX/lib/pkgconfig/gobject-introspection-1.0.pc"
}
build_poppler() {
  local s; s="$(unpack https://poppler.freedesktop.org/poppler-25.07.0.tar.xz poppler-25.07.0.tar.xz)"
  cmake_cross "$s" -DENABLE_QT5=OFF -DENABLE_QT6=OFF -DENABLE_CPP=OFF -DENABLE_GLIB=ON -DENABLE_UTILS=OFF \
    -DENABLE_BOOST=OFF -DENABLE_LIBOPENJPEG=none -DENABLE_NSS3=OFF -DENABLE_GPGME=OFF -DENABLE_LIBCURL=OFF \
    -DENABLE_GOBJECT_INTROSPECTION=OFF -DENABLE_LCMS=ON -DENABLE_DCTDECODER=libjpeg -DBUILD_GTK_TESTS=OFF \
    -DBUILD_CPP_TESTS=OFF -DBUILD_MANUAL_TESTS=OFF -DENABLE_GTK_DOC=OFF -DTESTDATADIR="$s"
  test -e "$PREFIX/lib/pkgconfig/poppler-glib.pc"
}
build_poppler_data() {
  local s; s="$(unpack https://poppler.freedesktop.org/poppler-data-0.4.12.tar.gz poppler-data-0.4.12.tar.gz)"
  make -C "$s" install prefix="$PREFIX"
  test -e "$PREFIX/share/pkgconfig/poppler-data.pc"
}
# GIMP itself. Its build normally runs GIMP to render the splash image; a
# cross build can't run it, so that image is left out (GIMP starts without
# a splash) and a stand-in answers its check for a GIMP on the build machine.
# Its few build tools are built for the build machine against the runner's
# GLib and librsvg.
build_gimp() {
  local s; s="$(unpack https://download.gimp.org/gimp/v3.2/gimp-3.2.6.tar.xz gimp-3.2.6.tar.xz)"
  gimp_pc
  python3 - "$s/gimp-data/images/meson.build" <<'EOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
n = len(s)
s = re.sub(r"\nsplash = custom_target\('gimp-splash.png',.*?install: true\)\n", "\n# DeskDroid: no splash (rendered by running GIMP)\n", s, count=1, flags=re.S)
assert len(s) < n, "splash target not found"
open(p, "w").write(s)
EOF
  # A check that runs a test program (Pango's Thai line breaking, for a
  # warning only): skipped when the build can't run Android programs.
  python3 - "$s/meson.build" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read()
old = "if cc.run('''\n  #include <pango/pango.h>"
assert s.count(old) == 1, "Pango check not found"
open(p, "w").write(s.replace(old, "if meson.can_run_host_binaries() and cc.run('''\n  #include <pango/pango.h>"))
EOF
  local stub="$WORK/gimp-stub"; mkdir -p "$stub"
  for n in gimp-console-3.2 gimp-3.2; do printf '#!/bin/sh\nexit 0\n' > "$stub/$n"; chmod +x "$stub/$n"; done
  cat > "$WORK/gimp-native.ini" <<EOF
[built-in options]
pkg_config_path = '/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/share/pkgconfig'
EOF
  rm -rf "$s/_android"
  PATH="$stub:$PATH" meson setup "$s/_android" "$s" --cross-file "$WORK/cross.ini" --native-file "$WORK/gimp-native.ini" \
    --prefix="$PREFIX" --libdir=lib --buildtype=release -Ddefault_library=shared -Dauto_features=disabled \
    -Dshmem-type=none -Dcheck-update=no -Denable-console-bin=false -Dcan-crosscompile-gir=false -Dvala=disabled \
    -Djavascript=disabled -Dlua=false -Dlinux-input=disabled -Dheadless-tests=disabled -Dgi-docgen=disabled \
    -Dappdata-test=disabled -Dlibunwind=false -Dlibbacktrace=false -Drelocatable-bundle=no \
    -Dprint=true -Dcairo-pdf=enabled -Dwebkit-unmaintained=false
  PATH="$stub:$PATH" ninja -C "$s/_android" -k 0 install
  test -e "$PREFIX/bin/gimp-3.2"
}

# ---- plasmashell (stage 4b) ---------------------------------------------------

build_plasmashell() {
  local s; s="$(unpack "https://download.kde.org/stable/plasma/$PLASMA_VERSION/plasma-workspace-$PLASMA_VERSION.tar.xz" "plasma-workspace-$PLASMA_VERSION.tar.xz")"
  python3 "$HERE/plasmashell/add-to-workspace.py" "$s"
  unandroid "$s"
  KEEP_GOING=1 kde_cmake "$s" -DCMAKE_CXX_FLAGS="-D__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__ -I$HERE/x11-stubs"
  test -e "$PREFIX/lib/libplasmashell.so"
  test -e "$PREFIX/lib/libksmserver-logout-greeter.so"
}
# plasma-desktop's QML-only packages: the panel containment, and the desktop
# shell's views and settings.
build_plasma_desktop_packages() {
  local s; s="$(unpack "https://download.kde.org/stable/plasma/$PLASMA_VERSION/plasma-desktop-$PLASMA_VERSION.tar.xz" "plasma-desktop-$PLASMA_VERSION.tar.xz")"
  rm -rf "$PREFIX/share/plasma/plasmoids/org.kde.panel"
  mkdir -p "$PREFIX/share/plasma/plasmoids"
  cp -r "$s/containments/panel" "$PREFIX/share/plasma/plasmoids/org.kde.panel"
  rm -f "$PREFIX/share/plasma/plasmoids/org.kde.panel/Messages.sh"
  test -e "$PREFIX/share/plasma/plasmoids/org.kde.panel/contents/ui/main.qml"
  # Plasma's desktop shell views and settings (edit mode, panel settings,
  # Add Widgets) under DeskDroid's shell; its own files go over these.
  python3 "$HERE/patches/desktoppackage/shell-from-desktop.py" "$s" "$PREFIX/share/plasma/shells/org.deskdroid.desktop"
  test -e "$PREFIX/share/plasma/shells/org.deskdroid.desktop/contents/configuration/PanelConfiguration.qml"
  # The application menu.
  rm -rf "$PREFIX/share/plasma/plasmoids/org.kde.plasma.kickoff"
  cp -r "$s/applets/kickoff/package" "$PREFIX/share/plasma/plasmoids/org.kde.plasma.kickoff"
  test -e "$PREFIX/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/ui/main.qml"
  # Add Panel's choices (Default Panel, Empty Panel): without them its menu
  # was empty. The default panel leaves out widgets not built yet.
  python3 "$HERE/patches/desktoppackage/layout-templates.py" "$s" "$PREFIX/share/plasma/layout-templates"
  test -e "$PREFIX/share/plasma/layout-templates/org.kde.plasma.desktop.defaultPanel/contents/layout.js"
}
# The application menu (Kickoff): KRunner's library and activity stats for
# its models, Kirigami Addons for its header.
build_krunner() { kf krunner; }
build_plasma_activities_stats() {
  local s; s="$(unpack "https://download.kde.org/stable/plasma/$PLASMA_VERSION/plasma-activities-stats-$PLASMA_VERSION.tar.xz" "plasma-activities-stats-$PLASMA_VERSION.tar.xz")"
  unandroid "$s"
  kde_cmake "$s"
}
KIRIGAMI_ADDONS_VERSION=1.9.0
build_kirigami_addons() {
  local s; s="$(unpack "https://download.kde.org/stable/kirigami-addons/kirigami-addons-$KIRIGAMI_ADDONS_VERSION.tar.xz" "kirigami-addons-$KIRIGAMI_ADDONS_VERSION.tar.xz")"
  unandroid "$s"
  sed -i 's/^\( *add_subdirectory(templates)\)/# \1/' "$s/CMakeLists.txt"
  # The date picker's Android integration (Java, built with Gradle) is left out.
  sed -i 's/^#ifdef Q_OS_ANDROID$/#if 0 \/\/ DeskDroid: no Android date picker/' "$s/src/dateandtime/types.h"
  grep -q "^#if 0 // DeskDroid" "$s/src/dateandtime/types.h"
  kde_cmake "$s"
}
# Plasma's desktop: the folder view containment (files, icons, drag and
# drop, right-click menu) and its C++ plugin.
build_plasma_desktop_folder() {
  local s; s="$(unpack "https://download.kde.org/stable/plasma/$PLASMA_VERSION/plasma-desktop-$PLASMA_VERSION.tar.xz" "plasma-desktop-$PLASMA_VERSION.tar.xz")"
  unandroid "$s"
  rm -rf "$s/_folderview" && cp -r "$HERE/desktopcontainment" "$s/_folderview"
  kde_cmake "$s/_folderview" -DDESKTOP_SRC="$s"
  rm -rf "$PREFIX/share/plasma/plasmoids/org.kde.desktopcontainment"
  cp -r "$s/containments/desktop/package" "$PREFIX/share/plasma/plasmoids/org.kde.desktopcontainment"
  test -e "$PREFIX/share/plasma/plasmoids/org.kde.desktopcontainment/contents/ui/main.qml"
  # The desktop containment alone is Plasma's "Desktop" layout, which shows
  # no files; "Folder View" (org.kde.plasma.folder) is its metadata with
  # the desktop containment's files as its root.
  rm -rf "$PREFIX/share/plasma/plasmoids/org.kde.plasma.folder"
  cp -r "$s/containments/folder" "$PREFIX/share/plasma/plasmoids/org.kde.plasma.folder"
  grep -q '"X-Plasma-RootPath": "org.kde.desktopcontainment"' "$PREFIX/share/plasma/plasmoids/org.kde.plasma.folder/metadata.json"
}
# The task manager: plasma-desktop's applet ("Icons-and-Text Task
# Manager") with its C++ plugin, and the icons-only one, which is the same
# applet under another name (plasma-desktop's applets/icontasks).
build_plasma_desktop_taskmanager() {
  local s; s="$(unpack "https://download.kde.org/stable/plasma/$PLASMA_VERSION/plasma-desktop-$PLASMA_VERSION.tar.xz" "plasma-desktop-$PLASMA_VERSION.tar.xz")"
  unandroid "$s"
  python3 "$HERE/taskmanager/patch.py" "$s"
  rm -rf "$s/_taskmanager" && cp -r "$HERE/taskmanager" "$s/_taskmanager"
  rm -rf "$PREFIX/share/plasma/plasmoids/org.kde.plasma.taskmanager"
  kde_cmake "$s/_taskmanager" -DDESKTOP_SRC="$s"
  test -e "$PREFIX/share/plasma/plasmoids/org.kde.plasma.taskmanager/contents/ui/main.qml"
  rm -rf "$PREFIX/share/plasma/plasmoids/org.kde.plasma.icontasks"
  cp -r "$s/applets/icontasks" "$PREFIX/share/plasma/plasmoids/org.kde.plasma.icontasks"
  grep -q '"X-Plasma-RootPath": "org.kde.plasma.taskmanager"' "$PREFIX/share/plasma/plasmoids/org.kde.plasma.icontasks/metadata.json"
}
inputs_plasma_desktop_taskmanager() { cat "$HERE"/taskmanager/CMakeLists.txt "$HERE"/taskmanager/patch.py "$HERE"/taskmanager/stubs/*; }
# KDE's app database needs share/mime/<type>/<subtype>.xml to know MIME
# types (Qt has its own); made from the build machine's shared-mime-info.
build_mime_stubs() {
  local x=/usr/share/mime/packages/freedesktop.org.xml
  [ -e "$x" ] || { sudo apt-get install -y shared-mime-info >/dev/null; }
  rm -rf "$PREFIX/share/mime"
  python3 "$HERE/mime/stubs.py" "$x" "$PREFIX/share/mime"
  test -e "$PREFIX/share/mime/audio/mpeg.xml"
}
inputs_mime_stubs() { cat "$HERE"/mime/*; }
inputs_plasma_desktop_folder() { cat "$HERE"/desktopcontainment/*; echo folder-package; }
inputs_plasma_desktop_packages() { cat "$HERE"/patches/desktoppackage/*; }
inputs_plasmashell() { cat "$HERE"/plasmashell/* "$HERE"/apps/as-library.py "$HERE"/kwin-nativedesk/qthost_entry.cpp "$HERE"/x11-stubs/*; }

ALL=(expat libffi wayland wayland_protocols xkbcommon dbus epoxy lcms2 libdrm libxcvt hwdata
     libdisplay_info freetype fontconfig udev mtdev libevdev libinput xkeyboard_config xorgproto xcb_proto libxau libxcb gbm
     qtbase qtdeclarative qtsvg qtshadertools qt5compat qtsensors qtmultimedia qtspeech qtwayland qttools deskdroid_ahb
     ecm kconfig_host libintl karchive kconfig kcoreaddons ki18n kwidgetsaddons kguiaddons kwindowsystem
     kdbusaddons kcolorscheme kidletime kauth kcrash kglobalaccel kpackage kservice kirigami ksvg
     plasma_wayland_protocols kdecoration kwayland kiconthemes breeze
     kcodecs kitemviews kcompletion kbookmarks kconfigwidgets knotifications kjobwidgets solid openssl qtbase_ssl kio kglobalacceld kwin
     kxmlgui kstatusnotifieritem plasma_activities libplasma layer_shell_qt kitemmodels kdeclarative kcmutils plasma5support
     sonnet ktextwidgets kparts attica syndication knewstuff krunner plasma_activities_stats kirigami_addons qqc2_desktop_style plasma_integration plasmashell plasma_desktop_packages plasma_desktop_folder plasma_desktop_taskmanager mime_stubs kfilemetadata breeze_icons kcmutils_host dolphin
     syntax_highlighting kio_extras ktexteditor kwrite libjpeg_turbo libpng exiv2 gwenview gmp mpfr mpc kcalc icu kpty knotifyconfig konsole
     pcre2 glib pixman fribidi harfbuzz cairo pango gdk_pixbuf atk gtk3 breeze_gtk
     xz libtiff libxml2 json_glib babl gegl gexiv2 json_c libmypaint mypaint_brushes libcroco librsvg libarchive
     curl libfyaml libxmlb appstream gobject_introspection poppler poppler_data gimp)

# Files outside a recipe that it builds from, so changing them builds it again.
inputs_kwin() { cat "$HERE"/kwin-nativedesk/*.* "$HERE"/kwin-nativedesk/CMakeLists.txt "$HERE/../nativedesk/protocol.h" "$HERE/ahb/deskdroid_ahb.h"; }

failed=()
after_qtbase=0
for pkg in "${@:-${ALL[@]}}"; do
  pkg="${pkg//-/_}"
  # The stamp holds the recipe's hash, so a changed recipe builds again.
  # Everything after qtbase is built against it, so a new qtbase rebuilds them.
  recipe="$( { declare -f "build_$pkg"; if declare -F "inputs_$pkg" >/dev/null; then "inputs_$pkg"; fi; if [ "$after_qtbase" = 1 ]; then cat "$STAMPS/qtbase" 2>/dev/null || true; fi; } | sha256sum | cut -c1-16)"
  [ "$pkg" = qtbase ] && after_qtbase=1
  if [ "$(cat "$STAMPS/$pkg" 2>/dev/null)" = "$recipe" ]; then echo "== $pkg: already built"; continue; fi
  echo "== $pkg"
  # Full output goes to <prefix>/logs; a failure prints its errors and tail.
  log="$PREFIX/logs/$pkg.log"
  mkdir -p "$PREFIX/logs"
  set +e
  ( set -euo pipefail; "build_$pkg" ) > "$log" 2>&1
  rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    grep -A3 -E "CMake Error|ERROR:|error:|Error [0-9]|No such file|not found" "$log" | grep -v -E "meson-private|testfile|CMakeScratch|TryCompile|QMLModule|qmldir|ECMFindQmlModule|Call Stack|^--$" | head -40 || true
    echo "-- distinct compile errors:"
    grep -E "^/.*: (fatal )?error: " "$log" | sed 's|^.*/src/[^/]*-[0-9.]*/||' | sort -u | head -60 || true
    echo "-- last lines:"
    tail -40 "$log"
  fi
  if [ $rc -eq 0 ]; then
    echo "$recipe" > "$STAMPS/$pkg"
  else
    echo "== $pkg FAILED"
    failed+=("$pkg")
    # Later packages may need this one; keep going to learn about the rest.
  fi
done
if [ ${#failed[@]} -gt 0 ]; then
  echo "failed: ${failed[*]}"
  exit 1
fi
echo "all built"
