#!/usr/bin/env bash
# Regenerates DD Party's files for DeskDroid's native Plasma (the Android app):
#   native/plasma/shell/ddparty/  colours, Plasma style, icons, global theme,
#                                 Kate/KWrite and Konsole colours (as share/)
#   native/plasma/shell/images/DDParty/  the wallpaper, 4K and phone size, JPEG
# native/nativedesk/build.sh ships both in the desktop's data. Native Plasma
# has no Kvantum or Aurorae, so apps and window borders there are Breeze in
# DD Party's colours. Needs python3 with numpy and Pillow.
# Usage: theme/dd-party/gen/native.sh   (from anywhere in the repository)
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(git rev-parse --show-toplevel)"
DEST="$REPO/native/plasma/shell/ddparty"
WALL="$REPO/native/plasma/shell/images/DDParty"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

python3 colors.py "$TMP"
python3 plasma.py "$TMP"
python3 editor.py "$TMP"
python3 icons.py "$TMP" ../assets/deskdroid-logo-256.png
DDP_NATIVE=1 python3 lookandfeel.py "$TMP" ../assets/deskdroid-logo.png
python3 wallpaper.py "$TMP"

rm -rf "$DEST" "$WALL"
mkdir -p "$DEST" "$WALL/contents/images"
cp -a "$TMP/color-schemes" "$TMP/plasma" "$TMP/icons" "$TMP/konsole" "$TMP/org.kde.syntax-highlighting" "$DEST/"
cp "$TMP/wallpapers/DDParty/metadata.json" "$WALL/"
python3 - "$TMP/wallpapers/DDParty/contents/images" "$WALL/contents/images" <<'EOF'
import sys
from PIL import Image
src, dst = sys.argv[1:]
for size in ("3840x2160", "1080x2400"):
    Image.open(f"{src}/{size}.png").convert("RGB").save(f"{dst}/{size}.jpg", quality=88, optimize=True)
EOF
echo "DD Party for native Plasma: $(du -sh "$DEST" | cut -f1) + wallpaper $(du -sh "$WALL" | cut -f1)"
