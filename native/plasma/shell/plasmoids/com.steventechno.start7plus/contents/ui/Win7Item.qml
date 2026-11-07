import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents

// A single menu row styled after the Win7 start menu (light rounded hover box)
Item {
    id: item

    property alias text: label.text
    property var iconSource
    property int iconSize: Kirigami.Units.iconSizes.smallMedium
    property int leftIndent: 0
    property bool showArrow: false
    property bool showIcon: true
    property bool arrowOpen: false
    property bool bold: false
    property bool highlighted: false   // keyboard selection
    property string dragUrl: ""        // when set, the row can be dragged out as a link to this URL
    property int verticalPadding: Kirigami.Units.smallSpacing + 1
    readonly property bool hovered: mouse.containsMouse

    signal clicked()
    signal dragStarted()
    signal dragEnded()
    signal rightClicked(real mx, real my)

    implicitHeight: Math.max(showIcon ? iconSize : 0, label.implicitHeight) + verticalPadding * 2
    implicitWidth: 200

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 1
        anchors.rightMargin: 1
        radius: 3
        visible: item.hovered || item.activeFocus || item.highlighted
        color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.22)
        border.width: 1
        border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.75)

        Rectangle { // inner highlight, like Aero's glossy edge
            anchors.fill: parent
            anchors.margins: 1
            radius: 2
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.35)
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Kirigami.Units.smallSpacing + item.leftIndent
        anchors.rightMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing + 2

        Kirigami.Icon {
            visible: item.showIcon
            source: item.iconSource
            Layout.preferredWidth: item.iconSize
            Layout.preferredHeight: item.iconSize
            Layout.alignment: Qt.AlignVCenter
        }

        PlasmaComponents.Label {
            id: label
            Layout.fillWidth: true
            elide: Text.ElideRight
            font.bold: item.bold
            maximumLineCount: 1
        }

        Kirigami.Icon {
            visible: item.showArrow
            source: "arrow-right"
            Layout.preferredWidth: Kirigami.Units.iconSizes.small
            Layout.preferredHeight: Kirigami.Units.iconSizes.small
            rotation: item.arrowOpen ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: 120 } }
        }
    }

    // Drag out to panels / desktop / file managers, same pattern Plasma's own launchers use:
    // the row itself carries the drag and a DragHandler decides when it is active.
    Drag.active: dragHandler.active
    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.CopyAction | Qt.LinkAction
    Drag.mimeData: ({ "text/uri-list": item.dragUrl, "text/plain": item.dragUrl })

    DragHandler {
        id: dragHandler
        target: null
        enabled: item.dragUrl !== "" && Plasmoid.configuration.allowDrag
        onActiveChanged: {
            if (active) item.dragStarted()
            else item.dragEnded()
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                item.rightClicked(mouse.x, mouse.y)
            } else {
                item.clicked()
            }
        }
    }

    Keys.onReturnPressed: item.clicked()
    Keys.onEnterPressed: item.clicked()
}
