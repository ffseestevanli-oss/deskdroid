import QtQuick

Item {
    id: b
    property string text
    property bool accent: false
    signal clicked()
    implicitWidth: Math.max(72, t.implicitWidth + 24); implicitHeight: 30
    Chamfer {
        anchors.fill: parent; cut: 7
        fill: b.accent ? (ma.containsMouse ? Theme.magentaHi : Theme.magenta) : (ma.containsMouse ? Theme.cardOn : Theme.button)
        stroke: b.accent ? Theme.magentaText : Theme.border
        opacity: b.enabled ? 1 : 0.5
    }
    Text { id: t; anchors.centerIn: parent; text: b.text; color: b.enabled ? Theme.text : Theme.dim; font.family: Theme.body; font.pixelSize: 13; font.weight: Font.DemiBold }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
}
