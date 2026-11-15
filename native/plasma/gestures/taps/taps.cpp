// DeskDroid: System Settings › Gestures › Taps (gesturemodule.h).
#include "gesturemodule.h"

#include <KPluginFactory>

class GestureTaps : public GestureModule
{
    Q_OBJECT
public:
    GestureTaps(QObject *parent, const KPluginMetaData &data)
        : GestureModule(parent, data,
                        QStringLiteral("Tap the phone's screen three times quickly, in one place."),
                        {
                            {QStringLiteral("triple_tap"), QStringLiteral("Triple tap"),
                             QStringLiteral("The first two taps still reach the desktop as clicks. Choose Do nothing to keep triple clicks for selecting "
                                            "a line of text."),
                             QStringLiteral("touch_mode")},
                        })
    {
    }
};

K_PLUGIN_CLASS_WITH_JSON(GestureTaps, "kcm_gesturetaps.json")

#include "taps.moc"
