#!/system/bin/sh
# DeskDroid's flatpak command (README.md). Installing, updating and removing
# go to flatpak itself (Debian's, in files/flatpak-cli, on DeskDroid's glibc);
# "flatpak run" starts the app with ddflatpak instead of bubblewrap.
#
# Paths: $DESKDROID_FILES (default the app's files folder), this script's
# folder (the APK's library folder) for DeskDroid's libraries.
F="${DESKDROID_FILES:-/data/data/io.deskdroid.app/files}"
self="$(readlink -f "$0" 2>/dev/null || echo "$0")"
L="${DESKDROID_LIBS:-${self%/*}}"
CLI="$F/flatpak-cli"
ARCH="${DESKDROID_FLATPAK_ARCH:-aarch64}"
TRIPLE="$ARCH-linux-gnu"
export FLATPAK_USER_DIR="$F/flatpak" FLATPAK_SYSTEM_DIR="$F/flatpak-system"
mkdir -p "$FLATPAK_USER_DIR" "$FLATPAK_SYSTEM_DIR" "$F/flatpak-tmp"
GLIBC_LIB="$F/glibc/lib"
# ddflatpak first, so the paths it maps are real before ddmask starts them.
export DDMASK_GLIBC_LD_PRELOAD="$L/libddflatpak.so:$L/libddmask_glibc.so"
export DDFLATPAK_TMP="$F/flatpak-tmp" TMPDIR="$F/flatpak-tmp"

die() { echo "flatpak: $*" >&2; exit 1; }
# Tests on a desktop machine start glibc programs with this (qemu and
# DeskDroid's loader); on the phone ddmask does it.
G="${DESKDROID_GLIBC_RUN:-}"
# On the phone ddmask starts glibc programs, but only in processes it's
# preloaded into (Konsole's shell). Started from an app without it (Discover),
# Android won't exec a program in app data: run it through glibc's loader in
# the APK's library folder ourselves.
if [ -z "$G" ]; then
  case ":${LD_PRELOAD:-}:" in
    *libddmask.so*) ;;
    *) G="$L/libdd_ld-glibc.so" ;;
  esac
fi

# Flatpak writes Exec=/usr/bin/flatpak into the menu entries it exports; the
# command is "flatpak" on DeskDroid's PATH.
fix_exports() {
  for d in "$FLATPAK_USER_DIR/exports/share/applications"; do
    [ -d "$d" ] || continue
    for f in "$d"/*.desktop; do
      [ -f "$f" ] || continue
      grep -q '/usr/bin/flatpak' "$f" || continue
      sed 's|/usr/bin/flatpak|flatpak|g' "$f" > "$f.new" && mv "$f.new" "$f"
    done
  done
}

cli() {
  [ -f "$CLI/usr/bin/flatpak" ] || die "flatpak isn't unpacked yet (start the desktop once)"
  # The app unpacks this zip without file modes, and the shell won't run a
  # program without its execute bit (ddmask never sees the exec): set them on
  # Flatpak's programs and helpers (gpg, ostree's, flatpak-*), again after
  # each unpack.
  if [ ! -x "$CLI/usr/bin/flatpak" ]; then
    for d in "$CLI/usr/bin" "$CLI/usr/libexec" "$CLI/usr/lib/$TRIPLE/gnupg" "$CLI/usr/lib/gnupg"; do
      [ -d "$d" ] && find "$d" -type f -exec chmod 755 {} +
    done
  fi
  export DDFLATPAK_RUNTIME="$CLI/usr" DDFLATPAK_MOUNTS="/etc/ssl=$CLI/etc/ssl;/usr/etc=$CLI/etc"
  export DDMASK_GLIBC_LD_LIBRARY_PATH="$GLIBC_LIB:$CLI/usr/lib/$TRIPLE:$CLI/usr/lib"
  export FLATPAK_BWRAP="$L/libdd_nobwrap.so" GIO_USE_VFS=local GSETTINGS_BACKEND=memory
  $G "$CLI/usr/bin/flatpak" "$@"
  rc=$?
  fix_exports
  return $rc
}

# flatpak run [--branch=B] [--arch=A] [--command=C] [other options] <app> [args]
run() {
  branch="" cmd=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --branch=*) branch="${1#--branch=}" ;;
      --arch=*) ARCH="${1#--arch=}"; TRIPLE="$ARCH-linux-gnu" ;;
      --command=*) cmd="${1#--command=}" ;;
      --) shift; break ;;
      -*) ;;
      *) break ;;
    esac
    shift
  done
  [ $# -gt 0 ] || die "run: which app?"
  id="$1"; shift
  # The menu entries' file-forwarding markers.
  set -- $(for a in "$@"; do [ "$a" = "@@" ] || [ "$a" = "@@u" ] || printf '%s\n' "$a"; done)
  base="$FLATPAK_USER_DIR/app/$id/$ARCH"
  [ -n "$branch" ] || branch="$(ls "$base" 2>/dev/null | head -1)"
  APP="$(readlink -f "$base/$branch/active/files" 2>/dev/null)"
  [ -d "$APP" ] || die "$id isn't installed (flatpak install flathub $id)"
  meta="$base/$branch/active/metadata"
  rtref="$(sed -n 's/^runtime=//p' "$meta" | head -1)"
  [ -n "$cmd" ] || cmd="$(sed -n 's/^command=//p' "$meta" | head -1)"
  RT="$(readlink -f "$FLATPAK_USER_DIR/runtime/$rtref/active/files" 2>/dev/null)"
  [ -d "$RT" ] || die "runtime $rtref isn't installed"
  rtbranch="${rtref##*/}"
  mounts="/dev/shm=$F/flatpak-tmp"
  libpath="$GLIBC_LIB:$APP/lib:$RT/lib/$TRIPLE:$RT/lib"
  # The GL driver extension (Mesa, software on Android for now), where
  # Flatpak mounts it; with one driver its folders are also the merged ones.
  GL="$(readlink -f "$FLATPAK_USER_DIR/runtime/org.freedesktop.Platform.GL.default/$ARCH/$rtbranch/active/files" 2>/dev/null)"
  if [ -n "$GL" ] && [ -d "$GL" ]; then
    mounts="/usr/lib/$TRIPLE/GL/default=$GL;/usr/lib/$TRIPLE/GL=$GL;$mounts"
    libpath="$libpath:$GL/lib"
  fi
  export DDFLATPAK_APP="$APP" DDFLATPAK_RUNTIME="$RT" DDFLATPAK_MOUNTS="$mounts"
  export DDMASK_GLIBC_LD_LIBRARY_PATH="$libpath"
  # The desktop's own (bionic) Qt and KDE settings would point the app's Qt at
  # the wrong plugins.
  unset QT_PLUGIN_PATH QML2_IMPORT_PATH QML_IMPORT_PATH QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE \
    QT_QUICK_CONTROLS_STYLE KDEDIRS QTWEBENGINEPROCESS_PATH
  # What flatpak run sets inside the sandbox; ddflatpak makes these paths real.
  export PATH=/app/bin:/usr/bin
  export XDG_DATA_DIRS=/app/share:/usr/share:/usr/share/runtime/share
  export XDG_CONFIG_DIRS=/app/etc/xdg:/etc/xdg
  h="$HOME/.var/app/$id"
  export XDG_DATA_HOME="$h/data" XDG_CONFIG_HOME="$h/config" XDG_CACHE_HOME="$h/cache" XDG_STATE_HOME="$h/.local/state"
  mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
  export FLATPAK_ID="$id" LOCPATH="$RT/lib/locale"
  # [Environment] from the app's metadata.
  envs="$(sed -n '/^\[Environment\]/,/^\[/{/^[A-Za-z_][A-Za-z0-9_]*=/p}' "$meta")"
  [ -n "$envs" ] && while IFS= read -r kv; do
    case "${kv%%=*}" in LD_LIBRARY_PATH|LD_PRELOAD|PATH) ;; *) export "$kv" ;; esac
  done <<ENVS
$envs
ENVS
  # The runtime's sh starts the command, so ddflatpak handles it like any
  # program the app starts (a script, zypak, an ELF program).
  exec $G "$RT/bin/sh" -c 'exec "$0" "$@"' "/app/bin/$cmd" "$@"
}

case "$1" in
  run) shift; run "$@" ;;
  *) cli "$@" ;;
esac
