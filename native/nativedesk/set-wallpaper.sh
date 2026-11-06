#!/system/bin/sh
# DeskDroid: "Set as Desktop Wallpaper" in Dolphin's and the desktop's
# right-click menu (a KIO service menu). Asks plasmashell over D-Bus to put
# the image on every desktop, like KDE's own action does. Run as
# bin/set-wallpaper <file> (a link to libdd_set-wallpaper.so).
f="$1"
case "$f" in file://*) f="${f#file://}" ;; esac
log="$HOME/set-wallpaper.log"
[ -r "$f" ] || { echo "set-wallpaper: can't read $f" >> "$log"; exit 1; }
# The path goes into a JavaScript string: escape \ and '.
esc="$(printf '%s' "$f" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g")"
js="var d = desktopsForActivity(currentActivity());
for (var i = 0; i < d.length; i++) {
    d[i].wallpaperPlugin = 'org.kde.image';
    d[i].currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General'];
    d[i].writeConfig('Image', 'file://$esc');
}"
dir="$(dirname "$0")"
send="$dir/dbus-send"; [ -x "$send" ] || send=dbus-send
{
  echo "set-wallpaper: $f"
  "$send" --session --print-reply --dest=org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "string:$js"
  echo "set-wallpaper: exit $?"
} >> "$log" 2>&1
