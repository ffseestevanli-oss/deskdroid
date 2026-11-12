#!/usr/bin/env bash
# Removes DD Party (per user, or with --system for /usr/share). Switch to
# another global theme first, e.g. plasma-apply-lookandfeel -a org.kde.breezedark.desktop
set -euo pipefail
if [ "${1:-}" = "--system" ]; then
  DATA=/usr/share; KV=/usr/share/Kvantum; FONTDIR=/usr/share/fonts/truetype/ddparty
else
  DATA="${XDG_DATA_HOME:-$HOME/.local/share}"; KV="${XDG_CONFIG_HOME:-$HOME/.config}/Kvantum"; FONTDIR="$DATA/fonts/DDParty"
fi
rm -rf "$DATA/color-schemes/DDParty.colors" "$DATA/plasma/desktoptheme/dd-party" \
       "$DATA/plasma/look-and-feel/org.deskdroid.ddparty" "$DATA/aurorae/themes/DDParty" \
       "$DATA/icons/DD-Party" "$DATA/wallpapers/DDParty" "$DATA/konsole/DDParty.colorscheme" \
       "$DATA/konsole/DDParty.profile" "$KV/DDParty" "$FONTDIR" \
       "$DATA/org.kde.syntax-highlighting/themes/dd-party.theme"
echo "DD Party removed from $DATA"
