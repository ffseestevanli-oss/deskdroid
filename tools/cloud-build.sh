#!/usr/bin/env bash
# Builds DeskDroid's debug APK on a fresh Ubuntu 24.04 machine (the project's
# cloud sessions) without GitHub Actions: the steps of .github/workflows/
# android.yml and plasma.yml in one script.
#
#   tools/cloud-build.sh [build-number]
#
# Needs root (apt), network access to the source hosts, ~30 GB of disk.
# The Plasma prefix (Qt, KDE Frameworks, KWin, Plasma, GIMP's libraries) takes
# about 1.5 hours from nothing on 4 cores; with DESKDROID_PREFIX_CACHE pointing
# at a plasma-prefix.tar.zst from an earlier run, only changed recipes rebuild.
# The APK lands in app/build/outputs/apk/debug/.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${1:-1000}"
NDK_VERSION="$(sed -n 's/.*ndkVersion = "\(.*\)".*/\1/p' "$HERE/app/build.gradle.kts")"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/android/sdk}"
NDK="$ANDROID_HOME/ndk/$NDK_VERSION"
QT_HOST="$HOME/Qt/6.8.3/gcc_64"
PREFIX="$HOME/plasma-prefix"
CACHE_TAR="${DESKDROID_PREFIX_CACHE:-/mnt/project-files/build-cache/plasma-prefix.tar.zst}"

echo "== build tools"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q >/dev/null
apt-get install -y -q bison flex gperf gawk autoconf automake libtool libexpat1-dev pkg-config \
  libegl1 libgl1 libopengl0 libxkbcommon0 libfontconfig1 gettext libgdk-pixbuf2.0-bin \
  libgdk-pixbuf-2.0-dev python3-gi python3-gi-cairo python3-cairo gir1.2-gexiv2-0.10 xsltproc \
  gobject-introspection libglib2.0-dev librsvg2-dev librsvg2-bin libgtk-3-bin itstool sassc \
  hwdata patchelf zip zstd pipx gcc-aarch64-linux-gnu g++-aarch64-linux-gnu qemu-user >/dev/null
export PATH="$HOME/.local/bin:$PATH"
for t in meson==1.12.1 ninja aqtinstall; do pipx install -q "$t" >/dev/null 2>&1 || true; done
# python3-gi and python3-cairo are built for the distribution's Python; a
# newer python3 earlier on PATH can't import them.
mkdir -p "$HOME/.cache/deskdroid/py"
ln -sf "/usr/bin/python3.$(ls /usr/lib/python3/dist-packages/cairo/_cairo.cpython-3*-x86_64-linux-gnu.so | sed 's/.*cpython-3\([0-9]*\).*/\1/')" "$HOME/.cache/deskdroid/py/python3"
export PATH="$HOME/.cache/deskdroid/py:$PATH"

echo "== Android SDK and NDK $NDK_VERSION"
if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
  tmp="$(mktemp -d)"
  curl -sSfL -o "$tmp/clt.zip" https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip
  unzip -q "$tmp/clt.zip" -d "$tmp" && mkdir -p "$ANDROID_HOME/cmdline-tools"
  mv "$tmp/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" && rm -rf "$tmp"
fi
{ yes || true; } | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" --install \
  "ndk;$NDK_VERSION" "platforms;android-36" "build-tools;36.0.0" platform-tools >/dev/null
echo "sdk.dir=$ANDROID_HOME" > "$HERE/local.properties"
# Maven Central rate-limits these machines (429); Google's mirror of it doesn't.
# Tried first, so a 429 doesn't disable the repository for the whole build.
mkdir -p "$HOME/.gradle/init.d"
cat > "$HOME/.gradle/init.d/deskdroid-maven-mirror.gradle" <<'GRADLE'
def mirror = { repos ->
  def r = repos.maven { url 'https://maven-central.storage-download.googleapis.com/maven2/' }
  repos.remove(r)
  repos.addFirst(r)
}
settingsEvaluated { s ->
  mirror(s.pluginManagement.repositories)
  mirror(s.dependencyResolutionManagement.repositories)
}
allprojects { mirror(buildscript.repositories) }
GRADLE

echo "== desktop Qt (host tools)"
[ -d "$QT_HOST" ] || aqt install-qt linux desktop 6.8.3 linux_gcc_64 -O "$HOME/Qt" -m qtshadertools >/dev/null

echo "== submodules"
git -C "$HERE" submodule update --init --recursive --jobs 8 --depth 1
# A clone interrupted part way leaves a submodule registered but empty.
# (Only empty ones: Termux:X11's build patches some sources in place.)
git -C "$HERE" submodule foreach --recursive -q \
  '[ "$(ls -A | grep -vx .git | head -1)" ] || git checkout -q -f HEAD -- .'

echo "== Plasma prefix"
if [ ! -d "$PREFIX" ] && [ -s "$CACHE_TAR" ]; then
  echo "   unpacking $CACHE_TAR"
  zstd -dc "$CACHE_TAR" | tar -xf - -C "$HOME"
fi
QT_HOST_PATH="$QT_HOST" "$HERE/native/plasma/build-deps.sh" "$PREFIX" "$NDK"

echo "== APK (build $BUILD)"
rm -rf "$HERE/app/build"   # buildNativeTools doesn't notice a new Qt prefix
cd "$HERE"
DESKDROID_QT_ANDROID="$PREFIX" DESKDROID_QT_HOST="$QT_HOST" \
  ./gradlew --no-daemon assembleDebug -PdeskdroidBuildNumber="$BUILD"

apk="$(ls app/build/outputs/apk/debug/*.apk)"
bt="$ANDROID_HOME/build-tools/36.0.0"
"$bt/apksigner" verify "$apk"
"$bt/zipalign" -c -P 16 4 "$apk"
list="$(unzip -l "$apk")"
for f in libnativedesk libkwin_wayland libplasmashell libkwin_data libQt6Core_arm64-v8a; do
  grep -q "lib/arm64-v8a/$f.so" <<<"$list" || { echo "missing $f.so" >&2; exit 1; }
done
echo "== done: $apk"
