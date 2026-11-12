#!/bin/bash
# try.sh <store id> <display number> <seconds>: start the app on its own Xvfb, screenshot, stop.
id=$1; n=$2; secs=${3:-240}
F=/data/data/io.deskdroid.app/files
Xvfb :$n -screen 0 1280x800x24 -nolisten tcp >/dev/null 2>&1 & x=$!
sleep 2
export DISPLAY=:$n QT_QPA_PLATFORM=xcb GDK_BACKEND=x11
setsid dbus-run-session -- "$(dirname "$0")/launch.sh" $id >/dev/null 2>&1 & p=$!
sleep $secs
alive=no; kill -0 $p 2>/dev/null && alive=yes
import -window root -display :$n ${SHOTS:-.}/$id.png 2>/dev/null
kill -- -$p 2>/dev/null; sleep 1; pkill -9 -s $p 2>/dev/null; kill $x
colors=$(convert ${SHOTS:-.}/$id.png -format %k info: 2>/dev/null)
echo "$id: still running=$alive, screenshot colors=$colors"
