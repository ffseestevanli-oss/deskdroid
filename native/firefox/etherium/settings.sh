#!/usr/bin/env bash
# Etherium's settings as files for a browser that's already built, to put in
# its folder (<dir>): the policies (policies.json) in distribution/, and the
# preferences (prefs.js) as an AutoConfig file that Firefox reads after its
# own defaults, so they win over them as they do when built in. AutoConfig
# also loads DD Party's style sheets (theme.js, chrome/), DeskDroid's look.
#
#   settings.sh <dir> <the browser's folder on the phone>
#
# The app copies them into an installed Etherium at every start
# (Etherium.kt), so a browser built before a change here gets it too.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
dir="$1"; program="$2"
mkdir -p "$dir/distribution" "$dir/defaults/pref" "$dir/etherium-chrome"
sed "s|@DISTRIBUTION@|$program/distribution|g" "$HERE/policies.json" > "$dir/distribution/policies.json"
printf '%s\n' '// Etherium (DeskDroid): reads etherium.cfg, its preferences.' \
  'pref("general.config.filename", "etherium.cfg");' 'pref("general.config.obscure_value", 0);' \
  '// theme.js needs the browser'"'"'s privileges to register its style sheets.' \
  'pref("general.config.sandbox_enabled", false);' \
  > "$dir/defaults/pref/autoconfig.js"
{ echo '// Etherium (DeskDroid): native/firefox/etherium/prefs.js, as defaults.'
  sed 's/^pref(/defaultPref(/' "$HERE/prefs.js"
  cat "$HERE/theme.js"; } > "$dir/etherium.cfg"
cp "$HERE"/chrome/*.css "$dir/etherium-chrome/"
