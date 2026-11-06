// A small meter for the panel: a label, a bar filling up, and the percentage.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

RowLayout {
    id: meter
    property string label
    property real value: -1 // 0..100, or -1 for not known yet
    property color accent: Kirigami.Theme.highlightColor
    spacing: Kirigami.Units.smallSpacing
    Layout.minimumWidth: implicitWidth
    Layout.preferredWidth: implicitWidth

    Text {
        text: meter.label
        color: Kirigami.Theme.disabledTextColor
        font.pixelSize: Math.max(10, meter.height * 0.32)
        font.bold: true
        Layout.alignment: Qt.AlignVCenter
    }
    Rectangle {
        Layout.preferredWidth: Math.max(6, meter.height * 0.22)
        Layout.preferredHeight: meter.height * 0.62
        Layout.alignment: Qt.AlignVCenter
        color: "transparent"
        border.color: Kirigami.Theme.disabledTextColor
        border.width: 1
        radius: 2
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 2 }
            height: Math.max(0, (parent.height - 4) * Math.max(0, meter.value) / 100)
            color: meter.value > 85 ? Kirigami.Theme.negativeTextColor : meter.accent
            radius: 1
            Behavior on height { NumberAnimation { duration: 300 } }
        }
    }
    Text {
        text: meter.value < 0 ? "–" : Math.round(meter.value) + "%"
        color: Kirigami.Theme.textColor
        font.pixelSize: Math.max(11, meter.height * 0.38)
        Layout.minimumWidth: font.pixelSize * 2.2
        Layout.alignment: Qt.AlignVCenter
    }
}
