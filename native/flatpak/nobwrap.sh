#!/system/bin/sh
# Stands in for bubblewrap (FLATPAK_BWRAP), which needs user namespaces that
# Android doesn't give apps. Flatpak only uses it here for its install
# triggers (desktop database, icon cache, MIME types): those run unsandboxed,
# and a trigger that can't run is skipped, as Flatpak skips a failed one.
while [ $# -gt 0 ] && [ "$1" != "--" ]; do shift; done
[ "$1" = "--" ] && shift
[ $# -gt 0 ] || exit 0
exec "$@" 2>/dev/null || exit 0
