#!/system/bin/sh
# DeskDroid: starts a program installed from the app store as a whole folder
# of programs and libraries (GIMP...), not a library QtHost loads. Shipped as
# libdd_store-program.so; the app's command (bin/<app>) is a symlink to it.
#
# Android runs programs only from the APK's library folder, so the store's
# programs run through Android's dynamic linker instead, which loads them like
# libraries: /system/bin/linker64 <program>. The app's folder has program.txt
# (its main program, relative to program/) and program.env (variables to set,
# @PROGRAM@ standing for program/'s path).
self="$(readlink -f "$0")"
libs="${self%/*}"
app="${0##*/}"
dir="$HOME/store/apps/$app"
P="$dir/program"
main="$(cat "$dir/program.txt" 2>/dev/null)"
[ -n "$main" ] && [ -e "$P/$main" ] || { echo "$app: not installed" >&2; exit 1; }
# Its libraries: program/lib, and those next to the main program (Firefox's).
export LD_LIBRARY_PATH="$P/lib:$(dirname "$P/$main"):$libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
if [ -e "$dir/program.env" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    export "$(printf '%s' "$line" | sed "s|@PROGRAM@|$P|g")"
  done < "$dir/program.env"
fi
# ddmask (native/ddmask) runs it, and every program it starts (GIMP's
# plug-ins...), through the linker, each keeping its own name, argv[0] and
# /proc/self/exe. The desktop's apps already have it preloaded; otherwise
# preload it here, for this program and its children.
case "$LD_PRELOAD" in *libddmask.so*) exec "$P/$main" "$@" ;; esac
[ -e "$libs/libddmask.so" ] && export LD_PRELOAD="$libs/libddmask.so${LD_PRELOAD:+:$LD_PRELOAD}"
exec /system/bin/linker64 "$P/$main" "$@"
