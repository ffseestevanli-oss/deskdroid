// DeskDroid: no X11 here, so KDE's platform theme's X11 part does nothing
// (it's only created when Qt runs on X11).
#include "x11integration.h"

X11Integration::X11Integration(KdePlatformTheme *platformTheme)
    : QObject()
    , m_platformTheme(platformTheme)
{
}
X11Integration::~X11Integration() = default;
void X11Integration::init() {}
bool X11Integration::eventFilter(QObject *watched, QEvent *event) { return QObject::eventFilter(watched, event); }
void X11Integration::setWindowProperty(QWindow *, const QByteArray &, const QByteArray &) {}
void X11Integration::installColorScheme(QWindow *) {}
void X11Integration::installDesktopFileName(QWindow *) {}
