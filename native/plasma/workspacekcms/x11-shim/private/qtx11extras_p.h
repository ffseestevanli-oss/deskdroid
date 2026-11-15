// DeskDroid x11-shim (README.md): Qt's QX11Info, on a system without X11.
#pragma once
#include <X11/Xlib.h>
class QX11Info
{
public:
    static bool isPlatformX11() { return false; }
    static Display *display() { return nullptr; }
};
