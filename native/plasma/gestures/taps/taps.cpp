// DeskDroid: System Settings › Gestures › Taps (gesturemodule.h).
#include "gesturemodule.h"

#include <KPluginFactory>

class GestureTaps : public GestureModule
{
    Q_OBJECT
public:
    GestureTaps(QObject *parent, const KPluginMetaData &data)
        : GestureModule(parent, data,
                        QStringLiteral("Tap the phone's screen with three fingers at once."),
                        {
                            {QStringLiteral("three_finger_tap"), QStringLiteral("Three-finger tap"),
                             QStringLiteral("Put three fingers down together and lift them. The desktop doesn't get the touch, so nothing is "
                                            "clicked."),
                             QStringLiteral("touch_mode")},
                        })
    {
    }
};

K_PLUGIN_CLASS_WITH_JSON(GestureTaps, "kcm_gesturetaps.json")

#include "taps.moc"
