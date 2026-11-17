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
                             QStringLiteral("none")},
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
                        })
    {
    }
};

K_PLUGIN_CLASS_WITH_JSON(GestureSwipes, "kcm_gestureswipes.json")

#include "swipes.moc"
