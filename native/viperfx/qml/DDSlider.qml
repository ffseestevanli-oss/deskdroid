import QtQuick
import QtQuick.Controls.Basic as B
import QtQuick.Layouts

// A labelled slider with its value; the filled part is DD Party's rainbow.
ColumnLayout {
    id: root
    property string label
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property real value: 0
    property var format: function (v) { return Math.round(v) }
    property bool enabledLook: true
    signal moved(real value)
    spacing: 2
    Layout.fillWidth: true
    RowLayout {
        Layout.fillWidth: true
        Text { text: root.label; color: root.enabledLook ? Theme.soft : Theme.dim; font.family: Theme.body; font.pixelSize: 13; Layout.fillWidth: true; elide: Text.ElideRight }
        Text { text: root.format(slider.value); color: root.enabledLook ? Theme.magentaText : Theme.dim; font.family: Theme.body; font.pixelSize: 13; font.weight: Font.DemiBold }
    }
    B.Slider {
        id: slider
        Layout.fillWidth: true
        from: root.from; to: root.to; stepSize: root.stepSize
        snapMode: B.Slider.SnapAlways
        onMoved: root.moved(value)
        Binding on value { value: root.value; when: !slider.pressed }
        background: Item {
            x: slider.leftPadding; y: slider.topPadding + slider.availableHeight / 2 - 3
            width: slider.availableWidth; height: 6
            Rectangle { anchors.fill: parent; color: Theme.empty; border.color: Theme.borderSoft }
            Item {
                width: slider.visualPosition * parent.width; height: parent.height; clip: true
                Rainbow { width: slider.availableWidth; height: parent.height; opacity: root.enabledLook ? 1 : 0.35 }
            }
        }
        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: 14; height: 20
            color: slider.pressed ? Theme.magentaHi : Theme.magenta
            border.color: Theme.magentaText
        }
    }
}
