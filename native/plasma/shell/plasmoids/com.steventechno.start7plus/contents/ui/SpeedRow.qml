import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

// Speed slider: to the right is faster. `seconds` is the time one full colour cycle takes.
RowLayout {
    id: row
    property int seconds: 8
    signal speedPicked(int seconds)

    QQC2.Label { text: i18n("Slower"); opacity: 0.7 }
    QQC2.Slider {
        from: 1
        to: 60
        stepSize: 1
        snapMode: QQC2.Slider.SnapAlways
        value: 61 - row.seconds
        onMoved: row.speedPicked(61 - Math.round(value))
    }
    QQC2.Label { text: i18n("Faster"); opacity: 0.7 }
    QQC2.Label { text: i18n("(%1 s per cycle)", row.seconds); opacity: 0.7 }
}
