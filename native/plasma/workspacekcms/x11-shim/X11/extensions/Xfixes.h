// DeskDroid x11-shim (README.md): XFixes is never there.
#pragma once
#include <X11/Xlib.h>
static inline int XFixesQueryExtension(Display *, int *, int *) { return 0; }
static inline int XFixesQueryVersion(Display *, int *major, int *minor) { *major = *minor = 0; return 0; }
static inline void XFixesSetCursorName(Display *, Cursor, const char *) { }
static inline void XFixesChangeCursorByName(Display *, Cursor, const char *) { }
