#!/usr/bin/env bash
# Regenerates the whole theme into ../out. Needs python3 with numpy + Pillow,
# and a copy of Kvantum's KvArcDark (from qt-style-kvantum-themes) as the base
# for the widget style's arrows and minor elements.
set -euo pipefail
cd "$(dirname "$0")"
OUT=${1:-../out}
KVARC=${KVARC:-/usr/share/Kvantum/KvArcDark}
rm -rf "$OUT"; mkdir -p "$OUT"
python3 colors.py "$OUT"
python3 wallpaper.py "$OUT"
python3 plasma.py "$OUT"
python3 aurorae.py "$OUT"
python3 kvantum.py "$OUT" "$KVARC"
python3 editor.py "$OUT"
python3 icons.py "$OUT" ../assets/deskdroid-logo-256.png
python3 lookandfeel.py "$OUT" ../assets/deskdroid-logo.png
# DD Party Glass: the see-through variant (palette.py's glass() values)
for g in colors.py wallpaper.py plasma.py aurorae.py lookandfeel.py; do
  case "$g" in lookandfeel.py) DDP_VARIANT=glass python3 "$g" "$OUT" ../assets/deskdroid-logo.png ;;
                *) DDP_VARIANT=glass python3 "$g" "$OUT" ;; esac
done
DDP_VARIANT=glass python3 kvantum.py "$OUT" "$KVARC"
mkdir -p "$OUT/fonts/DDParty"
cp ../assets/fonts/* "$OUT/fonts/DDParty/"
cp ../install.sh ../uninstall.sh ../README.md "$OUT/" 2>/dev/null || true
echo "built into $OUT"
