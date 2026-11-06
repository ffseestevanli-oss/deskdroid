import QtQuick
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// A flyout list that opens beside the Classic column. Items are plain JS objects:
// { name, icon, type: "app"|"entry"|"place"|"action"|"sub"|"new"|"none", sep: true, ... }
// or, for Recents, the recent-apps model itself.
Rectangle {
    id: panel

    property var m
    property var items: []
    property bool recents: false
    property real anchorY: 0

    signal activated(var item, int index, Item row)
    signal rowHovered(var item, Item row)
    signal contextRequested(var item, var app, Item row, real mx, real my)

    readonly property real wantH: Math.max(list.contentHeight, Kirigami.Units.gridUnit * 2) + 6
    height: Math.min(wantH, parent ? parent.height : wantH)
    y: parent ? Math.max(0, Math.min(anchorY, parent.height - height)) : 0

    Kirigami.Theme.colorSet: Kirigami.Theme.View
    Kirigami.Theme.inherit: false
    color: Kirigami.Theme.backgroundColor
    border.width: 1
    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.3)
    radius: 3
    z: 5

    // swallow clicks on empty space
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    ListView {
        id: list
        anchors.fill: parent
        anchors.margins: 3
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: panel.recents ? panel.m.recentModel : panel.items
        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
        readonly property real barPad: contentHeight > height ? Kirigami.Units.gridUnit : 0

        delegate: Item {
            id: cell
            readonly property var d: panel.recents ? null : modelData
            readonly property bool isSep: !panel.recents && !!cell.d.sep
            readonly property bool hidden: panel.recents && index >= panel.m.maxRecents
            readonly property var appRec: panel.recents
                ? panel.m.lookupApp(model.favoriteId, model.display)
                : (cell.d.app ? cell.d.app : null)

            visible: !hidden
            width: ListView.view.width - list.barPad
            height: hidden ? 0 : (isSep ? Kirigami.Units.largeSpacing : row.implicitHeight)

            Rectangle {
                visible: cell.isSep
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Kirigami.Units.smallSpacing
                anchors.rightMargin: Kirigami.Units.smallSpacing
                height: 1
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
            }

            Win7Item {
                id: row
                visible: !cell.isSep
                anchors.left: parent.left
                anchors.right: parent.right
                opacity: (!panel.recents && cell.d.type === "none") ? 0.6 : 1
                iconSize: Kirigami.Units.iconSizes.smallMedium
                text: panel.recents ? model.display : (cell.isSep ? "" : cell.d.name)
                iconSource: panel.recents ? model.decoration : (cell.isSep ? "" : (cell.d.icon || ""))
                showArrow: !panel.recents && !cell.isSep && cell.d.type === "sub"
                // only recents can be dragged out (dragging from All Programs crashed the shell)
                dragUrl: panel.recents ? panel.m.dragUrlFor(cell.appRec) : ""
                onDragStarted: panel.m.dragging = true
                onDragEnded: panel.m.dragging = false
                onClicked: panel.activated(cell.d, index, row)
                onHoveredChanged: if (hovered) panel.rowHovered(cell.d, row)
                onRightClicked: (mx, my) => panel.contextRequested(cell.d, cell.appRec, row, mx, my)
            }
        }
    }

    PlasmaComponents.Label {
        anchors.centerIn: parent
        visible: panel.recents && list.count === 0
        opacity: 0.6
        text: i18n("No recent programs")
    }
}
