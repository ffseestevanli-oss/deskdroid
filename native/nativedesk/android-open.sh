#!/system/bin/sh
# DeskDroid: "Open with Android app" for the native desktop. KDE runs it as
# bin/android-open <files> (a link to libdd_android-open.so); each file goes
# to DeskDroid as a request in $HOME/open-requests, which the app watches and
# answers with Android's app chooser.
d="$HOME/open-requests"
mkdir -p "$d" || exit 1
n=0
for f in "$@"; do
  n=$((n + 1))
  t="$d/.$$-$n"
  printf '%s\n' "$f" > "$t" && mv "$t" "$d/$$-$n.req"
done
