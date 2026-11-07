#!/system/bin/sh
# DeskDroid: "Set as Desktop Wallpaper" in Dolphin's and the desktop's
# right-click menu (a KIO service menu). Asks plasmashell over D-Bus to put
# the image on every desktop, like KDE's own action does. Run as
# bin/set-wallpaper <file> (a link to libdd_set-wallpaper.so).
#
# What it does goes to $HOME/set-wallpaper.log, which Save log in DeskDroid's
# settings adds to the log it saves, and to stderr.
log="$HOME/set-wallpaper.log"
say() { echo "set-wallpaper: $*" >> "$log"; echo "set-wallpaper: $*" >&2; }
# Keep the log short: the last runs only.
[ -f "$log" ] && [ "$(wc -c < "$log")" -gt 20000 ] && tail -c 10000 "$log" > "$log.new" && mv "$log.new" "$log"
# KDE passes a local path (%f); a file:// URL is taken too.
f="$1"
case "$f" in file://*) f="${f#file://}" ;; esac
say "$(date '+%F %T') $f"
[ -r "$f" ] || { say "can't read $f"; exit 1; }
# The path goes into a JavaScript string: escape \ and '.
esc="$(printf '%s' "$f" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g")"
# Every desktop (desktops(), not only the current activity's: without
# KDE's activity manager there may be no current activity), then each is
# told to read its settings again so the new picture shows at once.
js="var n = 0;
desktops().forEach(function (d) {
    d.wallpaperPlugin = 'org.kde.image';
    d.currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General'];
    d.writeConfig('Image', 'file://$esc');
    d.reloadConfig();
    n++;
});
print(n + ' desktops');"
dir="$(dirname "$0")"
send="$dir/dbus-send"; [ -x "$send" ] || send="$(command -v dbus-send)"
[ -n "$send" ] || { say "no dbus-send"; exit 1; }
[ -n "$DBUS_SESSION_BUS_ADDRESS" ] || say "DBUS_SESSION_BUS_ADDRESS isn't set"
out="$("$send" --session --print-reply --reply-timeout=10000 --dest=org.kde.plasmashell /PlasmaShell \
  org.kde.PlasmaShell.evaluateScript "string:$js" 2>&1)"
code=$?
say "dbus-send exit $code${out:+: $out}"
exit $code
