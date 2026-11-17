// DeskDroid: System Settings › Gestures › Edge Swipes (gesturemodule.h).
#include "gesturemodule.h"

#include <KPluginFactory>

class GestureSwipes : public GestureModule
{
    Q_OBJECT
public:
    GestureSwipes(QObject *parent, const KPluginMetaData &data)
        : GestureModule(parent, data,
                        QStringLiteral("Swipe in from a corner or an edge of the phone's screen, or of its touch area while the desktop is on a monitor. A touch that isn't a swipe still reaches the desktop."),
                        {
                            {QStringLiteral("bottom_left"), QStringLiteral("Bottom left corner"), QStringLiteral("Swipe up from the corner."),
                             QStringLiteral("keyboard")},
                            {QStringLiteral("bottom_right"), QStringLiteral("Bottom right corner"), QStringLiteral("Swipe up from the corner."),
                             QStringLiteral("dd_menu")},
                            {QStringLiteral("bottom"), QStringLiteral("Bottom edge"),
                             QStringLiteral("Swipe up from between the corners. With Do nothing, Android's navigation bar comes up."),
                             QStringLiteral("app_drawer")},
                            {QStringLiteral("left"), QStringLiteral("Left edge"),
                             QStringLiteral("Swipe in from the edge's middle. Above and below it, Android's Back gesture still works."),
                             QStringLiteral("none")},
                            {QStringLiteral("right"), QStringLiteral("Right edge"),
                             QStringLiteral("Swipe in from the edge's middle. Above and below it, Android's Back gesture still works."),
                             QStringLiteral("none")},
                            {QStringLiteral("top"), QStringLiteral("Top edge"),
                             QStringLiteral("Swipe down from the edge. With Do nothing, Android's status bar comes down."),
                             QStringLiteral("none")},
                        },
                        // Phone features, on or off (Gestures.kt's switches).
                        {
                            {QStringLiteral("mode_indicator"), QStringLiteral("Show the touch mode in the system tray"),
                             QStringLiteral("A mouse pointer in Touchpad mode, a finger on a screen in Direct touch. Click it to switch."),
                             true},
                            {QStringLiteral("app_drawer_on"), QStringLiteral("App drawer"),
                             QStringLiteral("All of the phone's apps on one screen, with search, like a phone's home screen. A swipe up from the bottom edge opens it (or any gesture set to Open the app drawer), and so does Apps in the DD menu. Pull it down, or press Back or Home, to put it away."),
                             true},
                            {QStringLiteral("private_space"), QStringLiteral("Private Space in the app drawer"),
                             QStringLiteral("Android's Private Space becomes a locked section at the bottom of the app drawer, and its apps leave the start menu and search. Unlocking asks for the phone's lock screen. Needs the app drawer on (off, its apps are in Android Apps › Private Space while unlocked)."),
                             true},
                        })
    {
    }
};

K_PLUGIN_CLASS_WITH_JSON(GestureSwipes, "kcm_gestureswipes.json")

#include "swipes.moc"
