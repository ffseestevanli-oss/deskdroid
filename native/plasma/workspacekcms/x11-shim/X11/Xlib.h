// DeskDroid x11-shim (README.md): the Xlib names the Cursors page uses
// behind QX11Info::isPlatformX11(), which is false here.
#pragma once
typedef struct _XDisplay Display;
typedef unsigned long XID;
typedef XID Cursor;
typedef unsigned long Atom;
// A constant, not X11's macro, so that Qt's enums named None still build.
static constexpr XID None = 0;
#define DefaultScreen(dpy) 0
#define DisplayWidth(dpy, scr) 0
#define DisplayHeight(dpy, scr) 0
static inline char *XGetDefault(Display *, const char *, const char *) { return nullptr; }
