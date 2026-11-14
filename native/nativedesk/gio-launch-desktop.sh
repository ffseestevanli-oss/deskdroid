#!/system/bin/sh
# DeskDroid: GLib's gio-launch-desktop, shipped as libdd_gio-launch-desktop.so
# (NativeDesk.kt points GIO_LAUNCH_DESKTOP at it).
#
# GIO starts every app it opens something with (g_app_info_launch: a GTK
# program's "Open", "Open containing folder") through this helper, which it
# looks for at the path GLib was built with or on PATH. Neither exists on the
# phone, so the launch failed and nothing opened: Etherium's downloads, files
# and folders. Like GLib's own helper, it notes its PID and runs the command.
export GIO_LAUNCHED_DESKTOP_FILE_PID=$$
exec "$@"
