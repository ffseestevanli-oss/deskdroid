# Termux's Firefox patches

Termux packages desktop Firefox (GTK) for Android's libc, Bionic, and treats
it as Linux: the build's target OS is GNU/Linux, not Android, so none of
GeckoView's Java-backed Android code is pulled in. That's the same thing
DeskDroid needs, so these patches come from Termux unchanged:
termux/termux-packages, `x11-packages/firefox` at the commit in
`SOURCE-COMMIT` (Firefox 159.0, the version DeskDroid builds).

As Termux says, package patches are under the package's own license, here
Firefox's (MPL 2.0).

`build.sh` fills in `@TERMUX_PREFIX@` with DeskDroid's prefix and defines
`__TERMUX__`, which these patches use to mean "Bionic, treated as Linux".
