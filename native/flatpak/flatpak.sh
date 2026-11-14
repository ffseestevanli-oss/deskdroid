#!/system/bin/sh
# DeskDroid's flatpak command (README.md). Installing, updating and removing
# go to flatpak itself (Debian's, in files/flatpak-cli, on DeskDroid's glibc);
# "flatpak run" starts the app with ddflatpak instead of bubblewrap.
#
# Paths: $DESKDROID_FILES (default the app's files folder), this script's
# folder (the APK's library folder) for DeskDroid's libraries.
# The ddmask module (native/ddmask/module.sh), when it's installed: its copy
# of this script runs instead, and its builds of ddmask's libraries are used
# (ddlib). DDMASK_MODULE is where it would be (NativeDesk.kt); api-1 says it
# fits this APK.
DM="${DDMASK_MODULE:-}"
[ -n "$DM" ] && [ -e "$DM/api-1" ] || DM=""
if [ -n "$DM" ] && [ -e "$DM/scripts/flatpak.sh" ]; then
  case "$0" in "$DM"/*) ;; *) exec "${DESKDROID_SH:-/system/bin/sh}" "$DM/scripts/flatpak.sh" "$@" ;; esac
fi
ddlib() { if [ -n "$DM" ] && [ -e "$DM/lib/$1" ]; then echo "$DM/lib/$1"; else echo "$L/$1"; fi; }
F="${DESKDROID_FILES:-/data/data/io.deskdroid.app/files}"
self="$(readlink -f "$0" 2>/dev/null || echo "$0")"
L="${DESKDROID_LIBS:-${DDMASK_LIBS:-${self%/*}}}"
CLI="$F/flatpak-cli"
ARCH="${DESKDROID_FLATPAK_ARCH:-aarch64}"
TRIPLE="$ARCH-linux-gnu"
export FLATPAK_USER_DIR="$F/flatpak" FLATPAK_SYSTEM_DIR="$F/flatpak-system"
mkdir -p "$FLATPAK_USER_DIR" "$FLATPAK_SYSTEM_DIR" "$F/flatpak-tmp"
GLIBC_LIB="$F/glibc/lib"
# ddflatpak first, so the paths it maps are real before ddmask starts them.
export DDMASK_GLIBC_LD_PRELOAD="$(ddlib libddflatpak.so):$(ddlib libddmask_glibc.so)"
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
    # Globs, not find: Android's find opens the current folder first, which
    # apps like Discover may not be allowed to read.
    chmod 755 "$CLI"/usr/bin/* "$CLI"/usr/libexec/* "$CLI"/usr/libexec/*/* \
      "$CLI"/usr/lib/"$TRIPLE"/gnupg/* "$CLI"/usr/lib/gnupg/* 2>/dev/null
    [ -x "$CLI/usr/bin/flatpak" ] || die "can't make $CLI/usr/bin/flatpak executable"
  fi
  export DDFLATPAK_RUNTIME="$CLI/usr" DDFLATPAK_MOUNTS="/etc/ssl=$CLI/etc/ssl;/usr/etc=$CLI/etc"
  export DDMASK_GLIBC_LD_LIBRARY_PATH="$GLIBC_LIB:$CLI/usr/lib/$TRIPLE:$CLI/usr/lib"
  # Flatpak's own helpers (gpgconf and gpg, which check Flathub's signatures)
  # start straight through the APK's glibc loader, by ddflatpak, as in the
  # ARM test that installed from Flathub; ddmask only sees the loader.
  export DDFLATPAK_LOADER="$L/libdd_ld-glibc.so" DDFLATPAK_LIBPATH="$DDMASK_GLIBC_LD_LIBRARY_PATH"
  export FLATPAK_BWRAP="$L/libdd_nobwrap.so" GIO_USE_VFS=local GSETTINGS_BACKEND=memory
  # gpgme finds gpgconf (and through it gpg) by searching PATH, and the
  # desktop's PATH has no /usr/bin: without it gpgme decides there's no
  # OpenPGP engine ("Invalid crypto engine") and no remote can be added.
  # ddflatpak maps /usr/bin to Flatpak's own programs here.
  case ":$PATH:" in *:/usr/bin:*) ;; *) export PATH="$PATH:/usr/bin" ;; esac
  # Installing an app checks parental controls (malcontent) over the system
  # D-Bus, which Android doesn't have: "Could not connect: No such file or
  # directory" after the runtimes were in. Flatpak skips the check when its
  # system helper is on the session bus, which only changes system-wide
  # installs (never used here: everything is --user). Tests on this machine
  # ran as root, which skips the check too.
  export FLATPAK_SYSTEM_HELPER_ON_SESSION=1
  # Helpers that can't start are noted here (gpgme hides their errors).
  export DDMASK_LOG="$F/glibc/exec.log"
  rm -f "$F/glibc/sigsys.log" "$DDMASK_LOG"
  # flatpak's errors, kept to check them below (shown as they were after).
  errs="$F/flatpak-tmp/stderr.$$"
  $G "$CLI/usr/bin/flatpak" "$@" 2>"$errs"
  rc=$?
  cat "$errs" >&2
  # gpg's engine missing: gpgme hides why. Start gpgconf as gpgme does, and
  # say what it did.
  if [ $rc -ne 0 ] && grep -q GPGME "$errs"; then
    sys="$F/glibc/sigsys.log"; rm -f "$sys"
    out="$("$L/libdd_ld-glibc.so" --library-path "$DDFLATPAK_LIBPATH" "$CLI/usr/bin/gpgconf" --list-dirs 2>&1)"
    grc=$?
    echo "flatpak: gpgconf check: exit $grc, $(printf '%s\n' "$out" | grep -c .) lines, first: $(printf '%s\n' "$out" | head -1)$([ -s "$sys" ] && echo "; blocked calls: $(sort -un "$sys" | tr '\n' ' ')")" >&2
  fi
  rm -f "$errs"
  if [ $rc -ne 0 ] && [ -s "$DDMASK_LOG" ]; then
    echo "flatpak: programs that couldn't start: $(sort -u "$DDMASK_LOG" | head -3 | tr '\n' ' ')" >&2
  fi
  # Killed on a system call Android blocks (SIGSYS, 128+31): say which ones
  # glibc caught along the way (../glibc/patch.py logs them), for the report.
  if [ $rc -eq 159 ]; then
    echo "flatpak: stopped by Android (Bad system call); blocked calls caught: $(sort -un "$F/glibc/sigsys.log" 2>/dev/null | tr '\n' ' ')" >&2
  fi
  fix_exports
  return $rc
}

# Whether folder $1 (ending in /) holds shared libraries.
has_libs() { for f in "$1"*.so*; do [ -e "$f" ] && return 0; done; return 1; }

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
  # An app installed only for x86-64 (flatpak install --arch=x86_64) runs
  # through FEX-Emu (fex-run.sh).
  [ ! -d "$FLATPAK_USER_DIR/app/$id/$ARCH" ] && [ -d "$FLATPAK_USER_DIR/app/$id/x86_64" ] && { ARCH=x86_64; TRIPLE=x86_64-linux-gnu; }
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
  # Extensions Flatpak would mount: the GL driver (Mesa) and the full FFmpeg.
  GL="$(readlink -f "$FLATPAK_USER_DIR/runtime/org.freedesktop.Platform.GL.default/$ARCH/$rtbranch/active/files" 2>/dev/null)"
  [ -d "$GL" ] || GL=""
  CX=""
  for b in "$rtbranch-extra" "$rtbranch"; do
    c="$(readlink -f "$FLATPAK_USER_DIR/runtime/org.freedesktop.Platform.codecs-extra/$ARCH/$b/active/files" 2>/dev/null)"
    [ -n "$c" ] && [ -d "$c" ] && { CX="$c"; break; }
  done
  # The rest is what starting a store package does (adpk-run.sh): the
  # desktop's home folder and look (DD Party), fonts, the GPU, Electron's
  # Wayland flags, Firefox's Etherium settings, x86-64 apps through FEX-Emu,
  # the crash dialog.
  export DDAPP_PROGRAM="$(readlink -f "$base/$branch/active")" DDAPP_ID="$id" DDAPP_RUNTIME="$RT" \
    DDAPP_RUNTIME_META="$FLATPAK_USER_DIR/runtime/$rtref/active/metadata" DDAPP_GL="$GL" DDAPP_CODECS="$CX" \
    DDAPP_STATE="$F/flatpak-tmp/run/$id" DESKDROID_FILES="$F" DESKDROID_LIBS="$L"
  [ -n "$G" ] && export DESKDROID_GLIBC_RUN="$G"
  run_sh="$L/libdd_adpk_run.so"
  [ -n "$DM" ] && [ -e "$DM/scripts/adpk-run.sh" ] && run_sh="$DM/scripts/adpk-run.sh"
  exec "${DESKDROID_SH:-/system/bin/sh}" "$run_sh" --dd-command="$cmd" "$@"
}

# A remote whose signing key never got imported (remote-add stopped partway,
# as on builds where gpg couldn't start) can't verify Flathub's summary:
# every fetch then fails with "No such ref 'appstream2/<arch>'", and
# "remote-add --if-not-exists" skips it, so it would never heal. Drop such
# remotes before adding remotes, so remote-add sets them up again.
drop_keyless_remotes() {
  repo="$FLATPAK_USER_DIR/repo"
  [ -f "$repo/config" ] || return 0
  sed -n 's/^\[remote "\(.*\)"\]$/\1/p' "$repo/config" | while read -r name; do
    [ -n "$name" ] || continue
    [ -s "$repo/$name.trustedkeys.gpg" ] && continue
    # Only remotes that verify signatures need the key.
    sed -n "/^\[remote \"$name\"\]/,/^\[/p" "$repo/config" | grep -q '^gpg-verify=false' && continue
    echo "flatpak: $name has no signing key (an earlier setup stopped partway); setting it up again" >&2
    cli remote-delete --user --force "$name" >/dev/null 2>&1
  done
}

case "$1" in
  run) shift; run "$@" ;;
  remote-add) drop_keyless_remotes; cli "$@" ;;
  *) cli "$@" ;;
esac
