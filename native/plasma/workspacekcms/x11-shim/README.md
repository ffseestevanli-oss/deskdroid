# x11-shim: just enough of X11 for the Cursors page

plasma-workspace's Cursors page (kcms/cursortheme) reads cursor themes with
libXcursor and applies them through Xlib and XFixes. There's no X11 here, so
these headers stand in for them (cursortheme.cmake puts this folder first on
the page's include path):

- `X11/Xcursor/Xcursor.h` and `xcursor.cpp`: libXcursor's image loading
  (theme lookup through index.theme's Inherits, and the Xcursor file format),
  for the page's previews and its list of sizes.
- `X11/Xlib.h`, `X11/extensions/Xfixes.h`, `private/qtx11extras_p.h`: the few
  names the page uses behind "is this X11?" checks, which always say no.

The chosen theme takes effect through kcminputrc, which KWin watches.
