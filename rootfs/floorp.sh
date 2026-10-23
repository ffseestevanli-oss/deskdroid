#!/usr/bin/env bash
# Installs Floorp, DeskDroid's default browser, into a rootfs (mmdebstrap
# customize hook; $1 is the rootfs). Debian doesn't package Floorp, so this
# takes the latest arm64 Linux build from Floorp's GitHub releases.
# Updates arrive with new DeskDroid images; Floorp's own updater is off.
set -euo pipefail
ROOT="$1"
API=https://api.github.com/repos/Floorp-Projects/Floorp/releases/latest

url=$(curl -fsSL "$API" | jq -r '[.assets[] | select(.name | test("linux.*(aarch64|arm64).*\\.tar\\.(xz|bz2|gz|zst)$"; "i"))][0].browser_download_url')
[ -n "$url" ] && [ "$url" != null ] || { echo "floorp.sh: no arm64 Linux build in the latest Floorp release" >&2; exit 1; }
echo "floorp.sh: $url"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$url" -o "$tmp/floorp.tar"
mkdir -p "$tmp/x"
tar -xf "$tmp/floorp.tar" -C "$tmp/x"
dir=$(dirname "$(find "$tmp/x" -maxdepth 2 -type f -name floorp | head -1)")
[ -x "$dir/floorp" ] || { echo "floorp.sh: no floorp binary in the archive" >&2; exit 1; }
rm -rf "$ROOT/opt/floorp"
mkdir -p "$ROOT/opt"
cp -a "$dir" "$ROOT/opt/floorp"
ln -sf /opt/floorp/floorp "$ROOT/usr/local/bin/floorp"

# Root owns /opt/floorp, so the built-in updater couldn't work anyway.
mkdir -p "$ROOT/opt/floorp/distribution"
echo '{"policies": {"DisableAppUpdate": true}}' > "$ROOT/opt/floorp/distribution/policies.json"

icon=$(cd "$ROOT/opt/floorp" && ls browser/chrome/icons/default/default128.png 2>/dev/null || true)
mkdir -p "$ROOT/usr/share/applications"
cat > "$ROOT/usr/share/applications/floorp.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Floorp
GenericName=Web Browser
Comment=Browse the web
Exec=/opt/floorp/floorp %u
Icon=${icon:+/opt/floorp/$icon}
Terminal=false
Categories=Network;WebBrowser;
MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;
StartupWMClass=floorp
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec=/opt/floorp/floorp --new-window

[Desktop Action new-private-window]
Name=New Private Window
Exec=/opt/floorp/floorp --private-window
DESKTOP

# Default browser for Plasma, MATE and xdg-open.
mkdir -p "$ROOT/etc/xdg"
cat > "$ROOT/etc/xdg/mimeapps.list" <<MIME
[Default Applications]
text/html=floorp.desktop
application/xhtml+xml=floorp.desktop
x-scheme-handler/http=floorp.desktop
x-scheme-handler/https=floorp.desktop
MIME
chroot "$ROOT" update-alternatives --install /usr/bin/x-www-browser x-www-browser /opt/floorp/floorp 200
