import QtQuick
import org.kde.kirigami as Kirigami

// A context menu drawn inside the start menu itself, so it always opens at the mouse.
Item {
    id: root
    property Item host
    property real px: 0
    property real py: 0
    property real panelW: Kirigami.Units.gridUnit * 10
    default property alias content: col.data

    // Fixed corner: open at the bottom right of the host instead of at the click point
    property bool fixedCorner: false
    property real cornerMarginX: 6
    property real cornerMarginY: 6

    parent: host
    // (explicit size rather than anchors: this menu can be declared inside another item,
    // where anchoring to the host fails and leaves it with zero size)
    x: 0
    y: 0
    width: host ? host.width : 0
    height: host ? host.height : 0
    z: 1000
    visible: false

    function measure() {
        var w = Kirigami.Units.gridUnit * 10
        for (var i = 0; i < col.children.length; ++i) {
            var c = col.children[i]
            if (c.visible) w = Math.max(w, c.implicitWidth)
        }
        panelW = w + 2
    }
    function popup(sourceItem, x, y) {
        measure()
        var p = sourceItem.mapToItem(host, x, y)
        px = p.x
        py = p.y
        visible = true
    }
    function close() { visible = false }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: root.close()
    }

    Rectangle {
        id: panel
        width: root.panelW
        height: col.implicitHeight + 2
        x: root.fixedCorner ? Math.max(0, root.width - width - root.cornerMarginX)
                            : Math.max(0, Math.min(root.px, root.width - width))
        y: root.fixedCorner ? Math.max(0, root.height - height - root.cornerMarginY)
                            : ((root.py + height > root.height) ? Math.max(0, root.py - height) : root.py)
        color: Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.3)
        radius: 3

        MouseArea { anchors.fill: parent } // swallow clicks on the panel's own padding

        Column {
            id: col
            x: 1
            y: 1
            width: panel.width - 2
        }
    }

    // choosing an entry closes the menu
    Component.onCompleted: {
        for (var i = 0; i < col.children.length; ++i) {
            var c = col.children[i]
            if (c.triggered) c.triggered.connect(root.close)
        }
    }
}
