import QtQuick

// An on/off switch: magenta when on.
Item {
    id: sw
    property bool checked: false
    signal toggled(bool on)
    implicitWidth: 46; implicitHeight: 24
    activeFocusOnTab: true
    Chamfer {
        anchors.fill: parent
        cut: 6
        fill: sw.checked ? Theme.magenta : Theme.empty
        stroke: sw.checked ? Theme.magentaText : (sw.activeFocus ? Theme.magentaText : Theme.border)
    }
    Rectangle {
        width: 16; height: 16; y: 4
        x: sw.checked ? parent.width - width - 5 : 5
        color: sw.checked ? "white" : Theme.dim
        Behavior on x { NumberAnimation { duration: 120 } }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { sw.checked = !sw.checked; sw.toggled(sw.checked) } }
    Keys.onSpacePressed: { checked = !checked; toggled(checked) }
}
