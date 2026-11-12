#!/usr/bin/env bash
# Installs the DD Party global theme on any KDE Plasma 6 desktop.
#
#   ./install.sh                 install for this user (~/.local/share, ~/.config)
#   ./install.sh --system        install for everyone (/usr/share; run with sudo)
#   ./install.sh --apply         install, then switch this user to DD Party
#   ./install.sh --apply --layout   also replace the panel layout with DD Party's
#   ./install.sh --apply --no-fonts keep your current UI fonts
#   ./install.sh --apply --glass    switch to DD Party Glass, the see-through variant
#
# The app widget style needs Kvantum: Debian/Ubuntu "qt-style-kvantum",
# Arch "kvantum", Fedora "kvantum", openSUSE "kvantum-qt6".
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SYSTEM=0 APPLY=0 LAYOUT=0 FONTS=1 GLASS=0
for a in "$@"; do
  case "$a" in
    --system) SYSTEM=1 ;;
    --apply) APPLY=1 ;;
    --layout) LAYOUT=1 ;;
    --no-fonts) FONTS=0 ;;
    --glass) GLASS=1 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
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
for v in dd-party dd-party-glass; do put "$HERE/plasma/desktoptheme/$v" "$DATA/plasma/desktoptheme"; done
for v in org.deskdroid.ddparty org.deskdroid.ddparty.glass; do put "$HERE/plasma/look-and-feel/$v" "$DATA/plasma/look-and-feel"; done
for v in DDParty DDPartyGlass; do put "$HERE/aurorae/themes/$v" "$DATA/aurorae/themes"; done
put "$HERE/icons/DD-Party"                          "$DATA/icons"
for v in DDParty DDPartyGlass; do put "$HERE/wallpapers/$v" "$DATA/wallpapers"; done
for v in DDParty DDPartyGlass; do
  put "$HERE/konsole/$v.colorscheme" "$DATA/konsole"
  put "$HERE/konsole/$v.profile"     "$DATA/konsole"
  put "$HERE/Kvantum/$v"             "$KV"
done
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
  if [ $GLASS = 1 ]; then LNF=org.deskdroid.ddparty.glass V=DDPartyGlass; else LNF=org.deskdroid.ddparty V=DDParty; fi
  if [ $LAYOUT = 1 ]; then
    plasma-apply-lookandfeel --apply $LNF --resetLayout
  else
    plasma-apply-lookandfeel --apply $LNF
  fi
  # Things a global theme can't set by itself:
  "$KW" --file Kvantum/kvantum.kvconfig --group General --key theme $V
  # The wallpaper (Plasma's global theme step leaves an existing one alone)
  command -v plasma-apply-wallpaperimage >/dev/null && plasma-apply-wallpaperimage "$DATA/wallpapers/$V" >/dev/null 2>&1 || true
  # KWin's blur and background contrast, which the glass variant leans on
  "$KW" --file kwinrc --group Plugins --key blurEnabled true
  "$KW" --file kwinrc --group Plugins --key contrastEnabled true
  [ $have_kvantum = 1 ] || "$KW" --file kdeglobals --group KDE --key widgetStyle Breeze
  if [ $FONTS = 1 ]; then
    "$KW" --file kdeglobals --group General --key font "Chakra Petch,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    "$KW" --file kdeglobals --group General --key menuFont "Chakra Petch,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    "$KW" --file kdeglobals --group General --key toolBarFont "Chakra Petch,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    "$KW" --file kdeglobals --group General --key smallestReadableFont "Chakra Petch,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    "$KW" --file kdeglobals --group WM --key activeFont "Orbitron,9,-1,5,700,0,0,0,0,0,0,0,0,0,0,1"
  fi
  "$KW" --file konsolerc --group "Desktop Entry" --key DefaultProfile $V.profile
  # Kate/KWrite editor colours
  "$KW" --file katerc --group "KTextEditor Renderer" --key "Auto Color Theme Selection" false
  "$KW" --file katerc --group "KTextEditor Renderer" --key "Color Theme" "DD Party"
  # Reload KWin so the decoration and title font take effect.
  (qdbus6 org.kde.KWin /KWin reconfigure || qdbus org.kde.KWin /KWin reconfigure) >/dev/null 2>&1 || true
  echo "$( [ $GLASS = 1 ] && echo "DD Party Glass" || echo "DD Party" ) applied. Restart running apps to pick up the widget style and fonts."
else
  echo "Installed. Pick \"DD Party\" or \"DD Party Glass\" in System Settings > Colors & Themes > Global Theme, or rerun with --apply (add --glass for the see-through one)."
fi
