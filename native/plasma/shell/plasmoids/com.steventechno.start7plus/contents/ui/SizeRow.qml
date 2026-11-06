import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Size (%) editor: slider limited to lockedMax, or a free number box when unlocked
RowLayout {
    id: r

    property int value: 100
    property int from: 50
    property int lockedMax: 120
    property bool unlocked: false
    signal edited(int v)

    QQC2.Slider {
        visible: !r.unlocked
        Layout.preferredWidth: Kirigami.Units.gridUnit * 10
        from: r.from
        to: r.lockedMax
        stepSize: 1
        snapMode: QQC2.Slider.SnapAlways
        value: r.value
        onMoved: r.edited(Math.round(value))
    }
    QQC2.SpinBox {
        editable: true
        from: r.from
        to: r.unlocked ? 100000 : r.lockedMax
        value: r.value
        textFromValue: function (v) { return v + "%" }
        valueFromText: function (t) { return parseInt(t) || r.from }
        onValueModified: r.edited(value)
    }
}
