#!/bin/bash
# Tests adpk-run.sh (libdd_adpk_run.so) on a desktop machine: what it reads
# from a Flathub package and what it hands glibc's loader, with a stand-in
# loader that prints its environment and arguments.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0
expect() { # name text regex...
  local name="$1" text="$2"; shift 2
  for re in "$@"; do
    grep -Eq -- "$re" <<<"$text" || { echo "FAIL $name: no /$re/ in:"; sed 's/^/     /' <<<"$text"; fails=$((fails+1)); return; }
  done
  echo "ok   $name"
}
F="$T/files" S="$T/files/store/apps" L="$T/libs"
mkdir -p "$F/glibc/lib" "$L" && : > "$F/glibc/lib/libc.so.6" && : > "$L/libdd_ld-glibc.so"
pkg() { # id metadata
  mkdir -p "$S/$1/program/files"; : > "$S/$1/app.txt"; : > "$S/$1/program/.ddsetup-done"
  printf '%s\n' "$2" > "$S/$1/program/metadata"
}
mkdir -p "$T/desk-config/gtk-3.0" "$T/desk-config/glib-2.0/settings"
printf '# DeskDroid\n[Settings]\ngtk-theme-name=DD-Party\ngtk-icon-theme-name=DD-Party\ngtk-application-prefer-dark-theme=true\n' > "$T/desk-config/gtk-3.0/settings.ini"
printf "[org/gnome/desktop/interface]\nother='kept'\ngtk-theme='Adwaita'\n" > "$T/desk-config/glib-2.0/settings/keyfile"
printf '[Colors:View]\nBackgroundNormal=20,10,30\n\n[General]\nColorScheme=DDParty\n' > "$T/desk-config/kdeglobals"
pkg runtime-kde-6.11 '[Runtime]
name = org.kde.Platform
runtime = org.kde.Platform/aarch64/6.11

[Environment]
QT_PLUGIN_PATH = /app/lib/plugins:/usr/share/runtime/lib/plugins
KDE_FORK_SLAVES = 1'
pkg runtime-mesa-25.08 ''
pkg kid3 '[Application]
name=org.kde.kid3
runtime=org.kde.Platform/aarch64/6.11
command=kid3

[Environment]
TMPDIR=/var/tmp
LD_LIBRARY_PATH=/app/lib/extra'
cat > "$T/loader" <<'L'
#!/bin/sh
echo "args: $*"
env | sort
L
chmod +x "$T/loader"
run() {
  env -i HOME="$T/home" PATH=/usr/bin:/bin XDG_RUNTIME_DIR="$T/run" XDG_CONFIG_HOME="$T/desk-config" \
    XDG_DATA_DIRS="$T/desk-share" XDG_CONFIG_DIRS="$T/desk-xdg" QT_QPA_PLATFORMTHEME=deskdroid QT_PLUGIN_PATH=/desktop/plugins DDAPP_PROGRAM="$S/$1/program" \
    DESKDROID_FILES="$F" DESKDROID_LIBS="$L" DESKDROID_GLIBC_RUN="$T/loader" sh "$HERE/../adpk-run.sh" "${@:2}"
}
out="$(run kid3 --dd-command=kid3-cli a b)"
log="$(cat "$S/kid3/run.log")"
expect "reads the app, its command and its runtime from the package" "$log" \
  "^kid3: starting /app/bin/kid3-cli a b \(org.kde.kid3, runtime-kde-6.11, software \(llvmpipe\)\)$"
expect "starts it with the runtime's sh, through the loader" "$out" "^args: $S/runtime-kde-6.11/program/files/bin/sh -c exec \"\\\$0\" \"\\\$@\" /app/bin/kid3-cli a b$"
expect "the runtime's [Environment] replaces the desktop's Qt settings" "$out" \
  "^QT_PLUGIN_PATH=/app/lib/plugins:/usr/share/runtime/lib/plugins$" "^KDE_FORK_SLAVES=1$" "^TMPDIR=/var/tmp$"
expect "the app's own paths" "$out" "^PATH=/app/bin:/usr/bin$" "^FLATPAK_ID=org.kde.kid3$" "^ELECTRON_OZONE_PLATFORM_HINT=wayland$" \
  "^DDMASK_GLIBC_LD_LIBRARY_PATH=.*$S/kid3/program/files/lib/extra" "^DDFLATPAK_RUNTIME=$S/runtime-kde-6.11/program/files$"
expect "the home folder as on Linux: the desktop's settings folder, ~/.local/share" "$out" \
  "^XDG_CONFIG_HOME=$T/desk-config$" "^XDG_DATA_HOME=$T/home/.local/share$" "^XDG_CACHE_HOME=$T/home/.cache$"
expect "the desktop's theme: KDE's platform theme, its data and settings folders after the runtime's" "$out" \
  "^QT_QPA_PLATFORMTHEME=kde$" "^XDG_DATA_DIRS=/app/share:/usr/share:/usr/share/runtime/share:$T/desk-share$" \
  "^XDG_CONFIG_DIRS=/app/etc/xdg:/etc/xdg:$T/desk-xdg(:$F/flatpak-tmp/kde-look)?$"
expect "GTK apps get the desktop's GTK theme" "$out" "^GTK_THEME=DD-Party$" "^GSETTINGS_BACKEND=keyfile$"
expect "...in GSettings too, only those keys" "$(cat "$T/desk-config/glib-2.0/settings/keyfile")" "^other='kept'$" \
  "^\[org/gnome/desktop/interface\]$" "^color-scheme='prefer-dark'$" "^gtk-theme='DD-Party'$" "^icon-theme='DD-Party'$"
run kid3 >/dev/null
expect "...the same each start" "$(grep -c "^gtk-theme=" "$T/desk-config/glib-2.0/settings/keyfile")" "^1$"
expect "Android's fonts beside the runtime's" "$(cat "$F/flatpak-tmp/fonts.conf")" "<include ignore_missing=\"yes\">/etc/fonts/fonts.conf</include>" "<dir>/system/fonts</dir>"
expect "full FFmpeg (codecs-extra) ahead of the runtime's" "$out" "^DDMASK_GLIBC_LD_LIBRARY_PATH=$F/glibc/lib:$S/kid3/program/files/lib:$S/runtime-mesa-25.08/program/codecs-extra/lib:"
if [ -r /proc/version ]; then
  expect "a readable /proc/version is left alone" "$out" "^DDFLATPAK_MOUNTS=[^ ]*/dev/shm=$F/flatpak-tmp(;/proc/sys[^;]*)?;/run/host/font-dirs.xml=[^;]*$"
fi
mkdir -p "$T/run" && : > "$L/libdd_vulkan_virtio.so"
python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$T/run/virgl.sock"
out2="$(run kid3)"
expect "with the desktop's virgl server, OpenGL goes to Android's GLES" "$out2" "^GALLIUM_DRIVER=virpipe$" "^LIBGL_ALWAYS_SOFTWARE=1$" "^VTEST_SOCKET_NAME=$T/run/virgl.sock$"
expect "...and says so" "$(cat "$S/kid3/run.log")" "GPU \(virgl on Android's GLES\)\)$"
rm -f "$T/run/virgl.sock"
python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$T/run/venus.sock"
out2="$(run kid3)"
expect "with a Venus server, apps draw on the GPU" "$out2" "^VN_DEBUG=vtest$" "^VTEST_SOCKET_NAME=$T/run/venus.sock$" \
  "^MESA_LOADER_DRIVER_OVERRIDE=zink$" "^VK_DRIVER_FILES=$F/flatpak-tmp/venus_icd.json$"
expect "...through the APK's Venus driver" "$(cat "$F/flatpak-tmp/venus_icd.json")" "\"library_path\": \"$L/libdd_vulkan_virtio.so\""
expect "...and say so" "$(cat "$S/kid3/run.log")" "GPU \(Venus\)\)$"
expect "a Venus server instead: Vulkan to Android's Vulkan driver" "$out2" "^VN_DEBUG=vtest$"
expect "DESKDROID_GPU=software keeps one app on llvmpipe" "$(env -i HOME="$T/home" PATH=/usr/bin:/bin XDG_RUNTIME_DIR="$T/run" DESKDROID_GPU=software DDAPP_PROGRAM="$S/kid3/program" DESKDROID_FILES="$F" DESKDROID_LIBS="$L" DESKDROID_GLIBC_RUN="$T/loader" sh "$HERE/../adpk-run.sh"; cat "$S/kid3/run.log")" "software \(llvmpipe\)\)$"

# A failed app: crash.log and Software's crash dialog (a stand-in that notes its arguments).
mkdir -p "$F/kwin/bin" "$S/kid3/program/files/share/applications"
printf '#!/bin/sh\necho "$@" > "%s/dialog"\n' "$T" > "$F/kwin/bin/software"; chmod +x "$F/kwin/bin/software"
printf '[Desktop Entry]\nName=Kid3 Tag Editor\n' > "$S/kid3/program/files/share/applications/org.kde.kid3.desktop"
printf '#!/bin/sh\necho "segfaulting now" >&2\nexit "${EXIT:-0}"\n' > "$T/exiter"; chmod +x "$T/exiter"
crash() { # <exit status>
  rm -f "$T/dialog" "$S/kid3/crash.log"
  env -i HOME="$T/home" PATH=/usr/bin:/bin XDG_RUNTIME_DIR="$T/run" WAYLAND_DISPLAY=wayland-0 EXIT="$1" DDAPP_PROGRAM="$S/kid3/program" \
    DESKDROID_FILES="$F" DESKDROID_LIBS="$L" DESKDROID_GLIBC_RUN="$T/exiter" sh "$HERE/../adpk-run.sh"
  echo "status=$?"
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "$T/dialog" ] && break; sleep 0.1; done
}
c_out="$(crash 139)"
expect "an app killed by a signal keeps its exit status" "$c_out" "^status=139$"
expect "...writes crash.log with its log" "$(cat "$S/kid3/crash.log")" "^== kid3 failed: it was stopped by signal 11" "^== run.log$" "^segfaulting now$"
expect "...and opens the crash dialog with its name" "$(cat "$T/dialog" 2>/dev/null)" "^--crashed kid3 Kid3 Tag Editor $S/kid3/crash.log$"
c_out="$(crash 0)"
expect "an app that closes normally gets no dialog" "$c_out|$(cat "$T/dialog" 2>/dev/null)" "^status=0\|$"
c_out="$(crash 143)"
expect "...nor one that was told to stop (SIGTERM)" "$c_out|$(cat "$T/dialog" 2>/dev/null)" "^status=143\|$"
c_out="$(crash 2)"
expect "an error exit gets the dialog too" "$(cat "$T/dialog" 2>/dev/null)|$(head -n 1 "$S/kid3/crash.log")" "^--crashed kid3 .*\|== kid3 failed: it exited with status 2$"
rm -f "$F/kwin/bin/software"
rm -f "$T/run/venus.sock"
expect "a Qt app gets no Electron flags" "$out" "^args: .*/app/bin/kid3-cli a b$"
mkdir -p "$S/kid3/program/files/main" && : > "$S/kid3/program/files/main/chrome-sandbox"
expect "an Electron app is asked for Wayland, without Chromium's sandbox" "$(run kid3 x)" \
  "^args: .*/app/bin/kid3 --ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations --no-sandbox x$"
rm -r "$S/kid3/program/files/main"
rm "$S/runtime-kde-6.11/app.txt"
run kid3 >/dev/null || true
expect "a missing runtime says so" "$(cat "$S/kid3/run.log")" "^kid3: needs runtime-kde-6.11 first: Software is installing it"
expect "...and asks Software to install it" "$(cat "$F"/open-requests/*.req)" "^deskdroid:software:install:runtime-kde-6.11$"
rm -rf "$S/runtime-kde-6.11" "$F/open-requests"
run kid3 >/dev/null || true
expect "a runtime that was never installed gets its package name from the metadata" "$(cat "$F"/open-requests/*.req)" "^deskdroid:software:install:runtime-kde-6.11$"

# flatpak run (flatpak.sh): an app the flatpak command installed starts here
# too, with its runtime and extensions from Flatpak's folders. Firefox gets
# Etherium's settings over its folder.
FU="$F/flatpak"
A="$FU/app/org.mozilla.firefox/aarch64/stable/abc"
R="$FU/runtime/org.freedesktop.Platform/aarch64/25.08/def"
mkdir -p "$A/files/lib/firefox/defaults/pref" "$A/files/lib/firefox/distribution" "$A/files/bin" "$R/files/bin" \
  "$FU/runtime/org.freedesktop.Platform.GL.default/aarch64/25.08/g/files/lib" "$FU/runtime/org.freedesktop.Platform.codecs-extra/aarch64/25.08-extra/c/files/lib"
for d in "$A" "$R" "$FU"/runtime/org.freedesktop.Platform.*/aarch64/*/*; do ln -sfn "${d##*/}" "${d%/*}/active"; done
printf '[Application]\nname=org.mozilla.firefox\nruntime=org.freedesktop.Platform/aarch64/25.08\ncommand=firefox\n' > "$A/metadata"
printf '[Runtime]\nname=org.freedesktop.Platform\n\n[Environment]\nGST_FROM_RUNTIME=1\n' > "$R/metadata"
printf '[App]\nVendor=Mozilla\nName=Firefox\nID={ec8030f7-c20a-464f-9b0e-13a3a9e97384}\n' > "$A/files/lib/firefox/application.ini"
echo 'pref("app.update.channel", "release");' > "$A/files/lib/firefox/defaults/pref/channel-prefs.js"
echo '[Global]' > "$A/files/lib/firefox/distribution/distribution.ini"
echo '{"flathub":1}' > "$A/files/lib/firefox/distribution/policies.json"
E="$F/kwin/share/deskdroid/etherium"
mkdir -p "$E/defaults/pref" "$E/distribution" "$E/etherium-chrome"
echo 'pref("general.config.filename", "etherium.cfg");' > "$E/defaults/pref/autoconfig.js"
echo '{"etherium":1}' > "$E/distribution/policies.json"
echo '// cfg' > "$E/etherium.cfg"; echo '/* css */' > "$E/etherium-chrome/userChrome.css"
cp "$HERE/../flatpak.sh" "$L/libdd_flatpak.so"; cp "$HERE/../adpk-run.sh" "$L/libdd_adpk_run.so"
out="$(env -i HOME="$T/home" PATH=/usr/bin:/bin XDG_RUNTIME_DIR="$T/run" XDG_CONFIG_HOME="$T/desk-config" \
  DESKDROID_FILES="$F" DESKDROID_LIBS="$L" DESKDROID_GLIBC_RUN="$T/loader" DESKDROID_SH=/bin/sh DESKDROID_CRASH_DIALOG=0 \
  sh "$L/libdd_flatpak.so" run --branch=stable --arch=aarch64 org.mozilla.firefox @@u https://example.org @@ 2>&1)"
log="$(cat "$F/flatpak-tmp/run/org.mozilla.firefox/run.log" 2>&1)"
AF="$(readlink -f "$A/files")"
expect "flatpak run starts an app the way a store package starts" "$out" \
  "^args: $(readlink -f "$R/files")/bin/sh -c exec \"\\\$0\" \"\\\$@\" /app/bin/firefox https://example.org$" \
  "^GTK_THEME=DD-Party$" "^QT_QPA_PLATFORMTHEME=kde$" "^XDG_CONFIG_HOME=$T/desk-config$" "^FLATPAK_ID=org.mozilla.firefox$" \
  "^GST_FROM_RUNTIME=1$" "^FONTCONFIG_FILE=" "^PATH=/app/bin:/usr/bin$"
expect "...with Flatpak's GL driver and full FFmpeg" "$out" \
  "^DDFLATPAK_MOUNTS=.*/usr/lib/aarch64-linux-gnu/GL/default=$(readlink -f "$FU"/runtime/org.freedesktop.Platform.GL.default/aarch64/25.08/active/files)" \
  "^DDMASK_GLIBC_LD_LIBRARY_PATH=.*codecs-extra/aarch64/25.08-extra/c/files/lib"
L2="$F/flatpak-tmp/kde-look"
expect "KDE apps that choose their own colours get the desktop's scheme as their default" "$out" "^XDG_CONFIG_DIRS=.*:$L2$" "^XDG_CURRENT_DESKTOP=KDE$" \
  "^QT_LOGGING_RULES=qt.qpa.theme=true$"
expect "...named under [UiSettings], from kdeglobals" "$(cat "$L2/kdeglobals")" '^\[UiSettings\]$' '^ColorScheme=DDParty$'
expect "...and its log where the crash dialog finds it" "$log" "^org.mozilla.firefox: starting /app/bin/firefox https://example.org" "Etherium's settings for firefox"
mounts="$(sed -n 's/^DDFLATPAK_MOUNTS=//p' <<<"$out" | tr ';' '\n')"
expect "Firefox: Etherium's files over its folder, at /app and the real path" "$mounts" \
  "^/app/lib/firefox/etherium.cfg=$E/etherium.cfg$" "^$AF/lib/firefox/etherium.cfg=$E/etherium.cfg$" "^/app/lib/firefox/etherium-chrome=$E/etherium-chrome$"
M="$F/flatpak-tmp/etherium/org.mozilla.firefox"
expect "...folders both have merged: Firefox's own prefs and Etherium's" "$(ls "$M/defaults/pref" | tr '\n' ' ')" "autoconfig.js" "channel-prefs.js"
expect "...Etherium's policies win, Firefox's other files stay" "$(cat "$M/distribution/policies.json" "$M/distribution/distribution.ini")" '"etherium":1' '^\[Global\]$'
[ "$fails" -eq 0 ] && echo "all adpk-run tests passed" || { echo "$fails failed"; exit 1; }
