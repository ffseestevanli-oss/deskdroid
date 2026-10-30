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
  ninja -C "$src/_android" install
}
cmake_cross() { # <src> [options...]
  local src="$1"; shift
  cmake -S "$src" -B "$src/_android" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$API -DANDROID_STL=c++_shared \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_FIND_ROOT_PATH="$PREFIX" -DCMAKE_PREFIX_PATH="$PREFIX" "$@"
  cmake --build "$src/_android" -j "$JOBS" ${KEEP_GOING:+-- -k 0}
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
  mkdir -p "$s/_android"
  (cd "$s/_android" && PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig" "$s/configure" \
    -platform android-clang -android-ndk "$NDK" -android-sdk "$ANDROID_HOME" -android-abis arm64-v8a \
    -android-ndk-platform android-$API -qt-host-path "$QT_HOST_PATH" -prefix "$PREFIX" \
    -release -nomake tests -nomake examples -dbus-linked -feature-dbus -feature-wayland -pkg-config -system-freetype -fontconfig \
    -- $(qt_find_args) -DQT_FEATURE_vulkan=OFF)
  cmake --build "$s/_android" -j "$JOBS"
  cmake --install "$s/_android"
}

build_qtshadertools() { qt_module qtshadertools; }
build_qtdeclarative() { qt_module qtdeclarative; }
build_qtsvg() { qt_module qtsvg; }
build_qt5compat() { qt_module qt5compat; }
build_qtsensors() { qt_module qtsensors; }
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
  cmake --build "$src/_android" -j "$JOBS"
  cmake --install "$src/_android"
}
# KDE's Android support is for Android apps (Java UI, Gradle, no D-Bus, no
# Wayland). Here KDE runs like on Linux, so drop those Android branches from
# the build files; C++ code keeps its Q_OS_ANDROID parts.
unandroid() {
  find "$1" -name CMakeLists.txt -o -name '*.cmake' | xargs sed -i -E \
    -e 's/(AND|OR) NOT ANDROID//g' -e 's/NOT ANDROID AND //g' \
    -e 's/if ?\(ANDROID\)/if(FALSE)/g' -e 's/\(ANDROID OR /(/g' -e 's/ OR ANDROID//g'
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
}

build_karchive() { kf karchive -DWITH_BZIP2=OFF -DWITH_LIBLZMA=OFF -DWITH_LIBZSTD=OFF -DWITH_OPENSSL=OFF; }
build_kconfig() { kf kconfig; }
build_kcoreaddons() { kf kcoreaddons -DUSE_DBUS=ON; }
build_ki18n() {
  local s; s="$(kf_src ki18n)"
  # Android apps' translations come from APK assets through a function KDE's
  # Android gettext adds; ours come from files like on Linux.
  sed -i 's/^\( *\)loadMessageCatalogFile(domain, moFile);/\1(void)domain;/' "$s/src/i18n/kcatalog.cpp"
  grep -q "(void)domain;" "$s/src/i18n/kcatalog.cpp"
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
build_kirigami() { kf kirigami; }
build_kservice() { kf kservice; }
build_ksvg() { kf ksvg; }

build_plasma_wayland_protocols() {
  local s; s="$(unpack https://download.kde.org/stable/plasma-wayland-protocols/plasma-wayland-protocols-1.18.0.tar.xz plasma-wayland-protocols-1.18.0.tar.xz)"
  kde_cmake "$s"
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
  # memfd_create and friends are API 30+; the Pixel has them, so link them weakly.
  # Big build, many fixes to come: keep going past errors so a run shows them all.
  KEEP_GOING=1 kde_cmake "$s" -DCMAKE_CXX_FLAGS=-D__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__ -DCMAKE_C_FLAGS=-D__ANDROID_UNAVAILABLE_SYMBOLS_ARE_WEAK__ -DKWIN_BUILD_KCMS=OFF -DKWIN_BUILD_NOTIFICATIONS=OFF -DKWIN_BUILD_SCREENLOCKER=OFF \
    -DKWIN_BUILD_X11=OFF -DKWIN_BUILD_GLOBALSHORTCUTS=OFF -DKWIN_BUILD_RUNNERS=OFF -DKWIN_BUILD_TABBOX=OFF \
    -DKWIN_BUILD_ACTIVITIES=OFF -DKWIN_BUILD_EIS=OFF -DBUILD_DOC=OFF -DNATIVE_PREFIX="$QT_HOST_PATH"
}

ALL=(expat libffi wayland wayland_protocols xkbcommon dbus epoxy lcms2 libdrm libxcvt hwdata
     libdisplay_info freetype fontconfig udev mtdev libevdev libinput gbm
     qtbase qtdeclarative qtsvg qtshadertools qt5compat qtsensors qtwayland qttools
     ecm kconfig_host libintl karchive kconfig kcoreaddons ki18n kwidgetsaddons kguiaddons kwindowsystem
     kdbusaddons kcolorscheme kidletime kauth kcrash kglobalaccel kpackage kservice kirigami ksvg
     plasma_wayland_protocols kdecoration kwayland kwin)

# Files outside a recipe that it builds from, so changing them builds it again.
inputs_kwin() { cat "$HERE"/kwin-nativedesk/* "$HERE/../nativedesk/protocol.h"; }

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
    grep -A3 -E "CMake Error|ERROR:|error:|Error [0-9]|No such file|not found" "$log" | grep -v -E "meson-private|testfile|CMakeScratch|TryCompile|QMLModule|qmldir|ECMFindQmlModule|Call Stack|^--$" | head -40
    echo "-- distinct compile errors:"
    grep -E "^/.*: (fatal )?error: " "$log" | sed 's|^.*/src/[^/]*-[0-9.]*/||' | sort -u | head -60
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
