#!/usr/bin/env bash
# Installs the DD Party global theme on any KDE Plasma 6 desktop.
#
#   ./install.sh                 install for this user (~/.local/share, ~/.config)
#   ./install.sh --system        install for everyone (/usr/share; run with sudo)
#   ./install.sh --apply         install, then switch this user to DD Party
#   ./install.sh --apply --layout   also replace the panel layout with DD Party's
#   ./install.sh --apply --no-fonts keep your current UI fonts
#
# The app widget style needs Kvantum: Debian/Ubuntu "qt-style-kvantum",
# Arch "kvantum", Fedora "kvantum", openSUSE "kvantum-qt6".
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SYSTEM=0 APPLY=0 LAYOUT=0 FONTS=1
for a in "$@"; do
  case "$a" in
    --system) SYSTEM=1 ;;
    --apply) APPLY=1 ;;
    --layout) LAYOUT=1 ;;
    --no-fonts) FONTS=0 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

if [ $SYSTEM = 1 ]; then
  DATA=/usr/share; KV=/usr/share/Kvantum; FONTDIR=/usr/share/fonts/truetype/ddparty
else
  DATA="${XDG_DATA_HOME:-$HOME/.local/share}"; KV="${XDG_CONFIG_HOME:-$HOME/.config}/Kvantum"; FONTDIR="$DATA/fonts/DDParty"
fi

put() {  # put SRC DEST_DIR  (replaces DEST_DIR/basename SRC)
  mkdir -p "$2"
  rm -rf "$2/$(basename "$1")"
  cp -a "$1" "$2/"
}

echo "Installing DD Party into $DATA"
put "$HERE/color-schemes/DDParty.colors"            "$DATA/color-schemes"
put "$HERE/plasma/desktoptheme/dd-party"            "$DATA/plasma/desktoptheme"
put "$HERE/plasma/look-and-feel/org.deskdroid.ddparty" "$DATA/plasma/look-and-feel"
put "$HERE/aurorae/themes/DDParty"                  "$DATA/aurorae/themes"
put "$HERE/icons/DD-Party"                          "$DATA/icons"
put "$HERE/wallpapers/DDParty"                      "$DATA/wallpapers"
put "$HERE/konsole/DDParty.colorscheme"             "$DATA/konsole"
put "$HERE/konsole/DDParty.profile"                 "$DATA/konsole"
put "$HERE/Kvantum/DDParty"                         "$KV"
put "$HERE/org.kde.syntax-highlighting/themes/dd-party.theme" "$DATA/org.kde.syntax-highlighting/themes"
mkdir -p "$FONTDIR"; cp "$HERE"/fonts/DDParty/* "$FONTDIR/"
command -v fc-cache >/dev/null && fc-cache -f "$FONTDIR" >/dev/null 2>&1 || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -f -t "$DATA/icons/DD-Party" >/dev/null 2>&1 || true

have_kvantum=0
for d in /usr/lib/*/qt6/plugins/styles /usr/lib/qt6/plugins/styles /usr/lib64/qt6/plugins/styles; do
  ls "$d"/libkvantum* >/dev/null 2>&1 && have_kvantum=1
done
[ $have_kvantum = 1 ] || echo "Note: Kvantum isn't installed, so apps keep Breeze shapes (in DD Party colours) until you install it."

if [ $APPLY = 1 ]; then
  [ $SYSTEM = 1 ] && { echo "--apply is per user; run it again without --system as yourself."; exit 0; }
  KW=$(command -v kwriteconfig6 || command -v kwriteconfig5)
  if [ $LAYOUT = 1 ]; then
    plasma-apply-lookandfeel --apply org.deskdroid.ddparty --resetLayout
  else
    plasma-apply-lookandfeel --apply org.deskdroid.ddparty
  fi
  # Things a global theme can't set by itself:
  "$KW" --file Kvantum/kvantum.kvconfig --group General --key theme DDParty
  [ $have_kvantum = 1 ] || "$KW" --file kdeglobals --group KDE --key widgetStyle Breeze
  if [ $FONTS = 1 ]; then
    "$KW" --file kdeglobals --group General --key font "Chakra Petch,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    "$KW" --file kdeglobals --group General --key menuFont "Chakra Petch,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    "$KW" --file kdeglobals --group General --key toolBarFont "Chakra Petch,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    "$KW" --file kdeglobals --group General --key smallestReadableFont "Chakra Petch,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    "$KW" --file kdeglobals --group WM --key activeFont "Orbitron,9,-1,5,700,0,0,0,0,0,0,0,0,0,0,1"
  fi
  "$KW" --file konsolerc --group "Desktop Entry" --key DefaultProfile DDParty.profile
  # Kate/KWrite editor colours
  "$KW" --file katerc --group "KTextEditor Renderer" --key "Auto Color Theme Selection" false
  "$KW" --file katerc --group "KTextEditor Renderer" --key "Color Theme" "DD Party"
  # Reload KWin so the decoration and title font take effect.
  (qdbus6 org.kde.KWin /KWin reconfigure || qdbus org.kde.KWin /KWin reconfigure) >/dev/null 2>&1 || true
  echo "DD Party applied. Restart running apps to pick up the widget style and fonts."
else
  echo "Installed. Pick \"DD Party\" in System Settings > Colors & Themes > Global Theme, or rerun with --apply."
fi
