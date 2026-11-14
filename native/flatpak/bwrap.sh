#!/bin/sh
# Stands in for bubblewrap inside Flathub apps (adpk-run.sh mounts it at
# /usr/bin/bwrap). Android gives apps no user namespaces, so nothing can be
# sandboxed; apps that sandbox their helpers with bwrap (glycin, GNOME's image
# loading: GTK apps load no images or icons without it) get them run as they
# would be unsandboxed: the command, in its folder (--chdir), with the
# environment bwrap would give it (--clearenv, --setenv, --unsetenv). Mounts,
# namespaces and seccomp filters are left out. DeskDroid's own variables
# (DDMASK_*, DDFLATPAK_*, DESKDROID_*) stay, so programs still start on Android.
# Runs with the runtime's sh, through ddflatpak (/usr/... paths work).
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
clear="" set_="" unset_="" dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --) shift; break ;;
    --clearenv) clear=1; shift ;;
    --setenv) set_="$set_ $(q "$2=$3")"; shift 3 ;;
    --unsetenv) unset_="$unset_ -u $(q "$2")"; shift 2 ;;
    --chdir) dir="$2"; shift 2 ;;
    --bind|--bind-try|--ro-bind|--ro-bind-try|--dev-bind|--dev-bind-try|--symlink|--file|--bind-data|--ro-bind-data|--chmod|--overlay-src) shift 3 ;;
    --dev|--proc|--tmpfs|--mqueue|--dir|--remount-ro|--seccomp|--add-seccomp-fd|--info-fd|--json-status-fd|--block-fd|--userns-block-fd|--sync-fd|--uid|--gid|--hostname|--exec-label|--file-label|--lock-file|--cap-add|--cap-drop|--perms|--size|--argv0|--userns|--userns2|--pidns|--tmp-overlay|--ro-overlay) shift 2 ;;
    --overlay) shift 4 ;;
    --*) shift ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || { echo "bwrap: No program specified" >&2; exit 1; }
[ -n "$dir" ] && { cd "$dir" || exit 1; }
keep=""
if [ -n "$clear" ]; then
  for v in $(env | sed -n 's/^\(DDMASK_[A-Za-z0-9_]*\|DDFLATPAK_[A-Za-z0-9_]*\|DESKDROID_[A-Za-z0-9_]*\)=.*/\1/p'); do
    eval "keep=\"\$keep \$(q \"\$v=\$$v\")\""
  done
  eval "exec /usr/bin/env -i $keep $set_ \"\$@\""
fi
eval "exec /usr/bin/env $unset_ $set_ \"\$@\""
