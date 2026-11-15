// DeskDroid: Qt's private QX11Info (QtGui, xcb platform only) as a stand-in.
// DeskDroid's Qt has no xcb platform: Qt itself is never an X11 client, so
// these answer "not X11, no connection". KWin and KWindowSystem's NETWM code
// talk to Xwayland over the connection KWin opens itself.
#pragma once
#include <QByteArray>
#include <QtGlobal>
#include <xcb/xcb.h>

typedef struct _XDisplay Display;

class QX11Info
{
public:
    enum PeekOption { PeekDefault = 0, PeekFromCachedIndex = 1 };
    Q_DECLARE_FLAGS(PeekOptions, PeekOption)
    typedef bool (*PeekerCallback)(xcb_generic_event_t *, void *);

    static bool isPlatformX11() { return false; }
    static int appDpiX(int = -1) { return 96; }
    static int appDpiY(int = -1) { return 96; }
    static quint32 appRootWindow(int = -1) { return 0; }
    static int appScreen() { return 0; }
    static quint32 appTime() { return s_time; }
    static quint32 appUserTime() { return s_userTime; }
    static void setAppTime(quint32 t) { s_time = t; }
    static void setAppUserTime(quint32 t) { s_userTime = t; }
    static quint32 getTimestamp() { return s_time; }
    static QByteArray nextStartupId() { return s_startupId; }
    static void setNextStartupId(const QByteArray &id) { s_startupId = id; }
    static Display *display() { return nullptr; }
    static xcb_connection_t *connection() { return nullptr; }
    static bool isCompositingManagerRunning(int = -1) { return true; }
    static qint32 generatePeekerId() { return -1; }
    static bool removePeekerId(qint32) { return false; }
    static bool peekEventQueue(PeekerCallback, void * = nullptr, PeekOptions = PeekDefault, qint32 = -1) { return false; }

private:
    static inline quint32 s_time = 0;
    static inline quint32 s_userTime = 0;
    static inline QByteArray s_startupId;
};
Q_DECLARE_OPERATORS_FOR_FLAGS(QX11Info::PeekOptions)
