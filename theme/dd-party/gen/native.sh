#!/usr/bin/env bash
# Regenerates DD Party's files for DeskDroid's native Plasma (the Android app).
# DeskDroid's default look is DD Party Glass; the flat DD Party is a separate
# download in Software.
#   native/plasma/shell/ddparty/  in the APK: colours, icons, Kate/KWrite and
#                                 Konsole colours, and Glass's Plasma style,
#                                 global theme and window borders (as share/)
#   native/plasma/shell/images/DDPartyGlass/  Glass's wallpaper, 4K and phone size
#   native/store/themes/dd-party/  the flat DD Party for Software: its Plasma
#                                 style, global theme, window borders and
#                                 wallpaper (share/), and the package's name
#                                 (app.json) and icon (native/nativedesk/build.sh
#                                 packages it)
# native/nativedesk/build.sh ships them. Native Plasma has no Kvantum, so apps
# there are Breeze in DD Party's colours; window borders are Aurorae
# (build-deps.sh builds it). Needs python3 with numpy and Pillow.
# Usage: theme/dd-party/gen/native.sh   (from anywhere in the repository)
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(git rev-parse --show-toplevel)"
DEST="$REPO/native/plasma/shell/ddparty"
IMAGES="$REPO/native/plasma/shell/images"
STORE="$REPO/native/store/themes/dd-party"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

python3 colors.py "$TMP"
python3 plasma.py "$TMP"
python3 editor.py "$TMP"
DDP_NATIVE=1 python3 aurorae.py "$TMP"
python3 icons.py "$TMP" ../assets/deskdroid-logo-256.png
DDP_NATIVE=1 python3 lookandfeel.py "$TMP" ../assets/deskdroid-logo.png
python3 wallpaper.py "$TMP"
export DDP_VARIANT=glass
python3 colors.py "$TMP"
python3 plasma.py "$TMP"
DDP_NATIVE=1 python3 aurorae.py "$TMP"
DDP_NATIVE=1 python3 lookandfeel.py "$TMP" ../assets/deskdroid-logo.png
python3 wallpaper.py "$TMP"

# 4K and phone size of a wallpaper, as JPEG.
wallpaper() {
  mkdir -p "$2/contents/images"
  cp "$TMP/wallpapers/$1/metadata.json" "$2/"
  python3 - "$TMP/wallpapers/$1/contents/images" "$2/contents/images" <<'EOF'
import sys, glob
from PIL import Image
src, dst = sys.argv[1:]
for size in ("3840x2160", "1080x2400"):
    f = glob.glob(f"{src}/{size}.*")[0]
    Image.open(f).convert("RGB").save(f"{dst}/{size}.jpg", quality=88, optimize=True)
EOF
}

rm -rf "$DEST" "$IMAGES/DDParty" "$IMAGES/DDPartyGlass" "$STORE"
mkdir -p "$DEST/plasma/desktoptheme" "$DEST/plasma/look-and-feel" "$DEST/aurorae/themes"
cp -a "$TMP/color-schemes" "$TMP/icons" "$TMP/konsole" "$TMP/org.kde.syntax-highlighting" "$DEST/"
cp -a "$TMP/plasma/desktoptheme/dd-party-glass" "$DEST/plasma/desktoptheme/"
cp -a "$TMP/plasma/look-and-feel/org.deskdroid.ddparty.glass" "$DEST/plasma/look-and-feel/"
cp -a "$TMP/aurorae/themes/DDPartyGlass" "$DEST/aurorae/themes/"
wallpaper DDPartyGlass "$IMAGES/DDPartyGlass"

S="$STORE/share"
mkdir -p "$S/plasma/desktoptheme" "$S/plasma/look-and-feel" "$S/aurorae/themes" "$S/wallpapers"
cp -a "$TMP/plasma/desktoptheme/dd-party" "$S/plasma/desktoptheme/"
cp -a "$TMP/plasma/look-and-feel/org.deskdroid.ddparty" "$S/plasma/look-and-feel/"
cp -a "$TMP/aurorae/themes/DDParty" "$S/aurorae/themes/"
wallpaper DDParty "$S/wallpapers/DDParty"
python3 - "$STORE/app.json" <<'EOF'
import json, sys
json.dump({"id": "dd-party", "name": "DD Party (flat)",
           "summary": "DeskDroid's solid, no-blur look: pick it in Global Theme after installing",
           "version": "1.0"}, open(sys.argv[1], "w"), indent=2)
EOF
python3 - "$STORE/icon.png" ../assets/previews/preview.png <<'EOF'
import sys
from PIL import Image
im = Image.open(sys.argv[2]).convert("RGB")
s = min(im.size); l = (im.width - s) // 2; t = (im.height - s) // 2
im.crop((l, t, l + s, t + s)).resize((128, 128), Image.LANCZOS).save(sys.argv[1])
EOF
echo "DD Party for native Plasma: $(du -sh "$DEST" | cut -f1) + wallpaper $(du -sh "$IMAGES/DDPartyGlass" | cut -f1); flat for Software: $(du -sh "$STORE" | cut -f1)"
