// DeskDroid x11-shim (README.md): libXcursor's image loading (xcursor.cpp).
#pragma once
#include <X11/Xlib.h>
#include <stdint.h>

#define XCURSOR_LIB_MAJOR 1
#define XCURSOR_LIB_MINOR 2
#define XCURSOR_LIB_REVISION 0
#define XCURSOR_LIB_VERSION ((XCURSOR_LIB_MAJOR * 10000) + (XCURSOR_LIB_MINOR * 100) + (XCURSOR_LIB_REVISION))

typedef uint32_t XcursorPixel;
typedef struct _XcursorImage {
    uint32_t version;
    uint32_t size; // nominal size
    uint32_t width, height;
    uint32_t xhot, yhot;
    uint32_t delay; // milliseconds
    XcursorPixel *pixels; // ARGB, premultiplied
} XcursorImage;
typedef struct _XcursorImages {
    int nimage;
    XcursorImage **images;
    char *name;
} XcursorImages;

XcursorImages *XcursorFilenameLoadAllImages(const char *file);
XcursorImage *XcursorLibraryLoadImage(const char *name, const char *theme, int size);
XcursorImages *XcursorLibraryLoadImages(const char *name, const char *theme, int size);
void XcursorImageDestroy(XcursorImage *image);
void XcursorImagesDestroy(XcursorImages *images);
const char *XcursorLibraryPath(void);
static inline Cursor XcursorImagesLoadCursor(Display *, const XcursorImages *) { return None; }
