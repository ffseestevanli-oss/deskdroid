#!/usr/bin/env bash
# Makes Breeze Dark the system default for Plasma editions (mmdebstrap
# customize hook; $1 is the rootfs). Users can still pick another theme;
# their own ~/.config/kdeglobals wins over /etc/xdg.
set -euo pipefail
ROOT="$1"
COLORS="$ROOT/usr/share/color-schemes/BreezeDark.colors"
[ -f "$COLORS" ] || exit 0  # not a Plasma edition

mkdir -p "$ROOT/etc/xdg"
# Apps read the colors themselves from kdeglobals, not just the scheme name,
# so the whole scheme goes in. KConfig merges repeated groups.
{
  cat "$COLORS"
  printf '\n[General]\nColorScheme=BreezeDark\n'
  printf '\n[KDE]\nLookAndFeelPackage=org.kde.breezedark.desktop\n'
  printf '\n[Icons]\nTheme=breeze-dark\n'
} > "$ROOT/etc/xdg/kdeglobals"
printf '[Theme]\nname=breeze-dark\n' > "$ROOT/etc/xdg/plasmarc"

# GTK apps (Firefox, GIMP) follow the dark preference.
for v in 3.0 4.0; do
  mkdir -p "$ROOT/etc/gtk-$v"
  printf '[Settings]\ngtk-application-prefer-dark-theme=1\n' > "$ROOT/etc/gtk-$v/settings.ini"
done
