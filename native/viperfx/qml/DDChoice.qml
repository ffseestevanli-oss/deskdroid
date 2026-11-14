import QtQuick
import QtQuick.Layouts

// A row of options, one picked (ViPER4Android's lists, as segments).
ColumnLayout {
    id: root
    property string label
    property var options: []
    property int current: 0
    property bool enabledLook: true
    signal picked(int index)
    spacing: 4
    Layout.fillWidth: true
    Text { visible: root.label !== ""; text: root.label; color: root.enabledLook ? Theme.soft : Theme.dim; font.family: Theme.body; font.pixelSize: 13 }
    Flow {
        Layout.fillWidth: true
        spacing: 4
        Repeater {
            model: root.options
            delegate: Item {
                required property int index
                required property string modelData
                width: Math.max(64, t.implicitWidth + 20); height: 28
                Chamfer {
                    anchors.fill: parent; cut: 6
                    fill: index === root.current ? Theme.magenta : (ma.containsMouse ? Theme.cardOn : Theme.button)
                    stroke: index === root.current ? Theme.magentaText : Theme.border
                    opacity: root.enabledLook || index === root.current ? 1 : 0.6
                }
                Text { id: t; anchors.centerIn: parent; text: modelData; color: index === root.current ? "white" : Theme.soft; font.family: Theme.body; font.pixelSize: 12; font.weight: Font.DemiBold }
                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.current = index; root.picked(index) } }
            }
        }
    }
}
