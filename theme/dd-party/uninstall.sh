#!/usr/bin/env bash
# Removes DD Party (per user, or with --system for /usr/share). Switch to
# another global theme first, e.g. plasma-apply-lookandfeel -a org.kde.breezedark.desktop
set -euo pipefail
if [ "${1:-}" = "--system" ]; then
  DATA=/usr/share; KV=/usr/share/Kvantum; FONTDIR=/usr/share/fonts/truetype/ddparty
else
  DATA="${XDG_DATA_HOME:-$HOME/.local/share}"; KV="${XDG_CONFIG_HOME:-$HOME/.config}/Kvantum"; FONTDIR="$DATA/fonts/DDParty"
fi
rm -rf "$DATA/color-schemes/DDParty.colors" "$DATA/plasma/desktoptheme/dd-party" "$DATA/plasma/desktoptheme/dd-party-glass" \
       "$DATA/plasma/look-and-feel/org.deskdroid.ddparty" "$DATA/plasma/look-and-feel/org.deskdroid.ddparty.glass" \
       "$DATA/aurorae/themes/DDParty" "$DATA/aurorae/themes/DDPartyGlass" \
       "$DATA/icons/DD-Party" "$DATA/wallpapers/DDParty" "$DATA/wallpapers/DDPartyGlass" "$DATA/konsole/DDParty.colorscheme" "$DATA/konsole/DDPartyGlass.colorscheme" \
       "$DATA/konsole/DDParty.profile" "$DATA/konsole/DDPartyGlass.profile" "$KV/DDParty" "$KV/DDPartyGlass" "$FONTDIR" \
       "$DATA/org.kde.syntax-highlighting/themes/dd-party.theme"
echo "DD Party removed from $DATA"
