#!/system/bin/sh
# DeskDroid: starts a KDE app built as a library (native/plasma/apps/as-library.py)
# in an app_process, where QtHost gives Qt for Android its Java VM. Shipped as
# libdd_qtapp.so; the app's command (bin/<app>, e.g. bin/dolphin) is a symlink
# to it, so the app is the name it was called by. Needs CLASSPATH (the APK)
# from the desktop's environment.
self="$(readlink -f "$0")"
libs="${self%/*}"
app="${0##*/}"
if [ "$app" = libdd_qtapp.so ]; then app="$1"; shift; fi
exec /system/bin/app_process -Xnoimage-dex2oat / io.deskdroid.app.QtHost "$libs" "libdd_$app.so" "$@"
