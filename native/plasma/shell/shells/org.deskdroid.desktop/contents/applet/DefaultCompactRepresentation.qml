// The compact look of an applet that has none of its own: its name, tappable.
import QtQuick
import org.kde.plasma.plasmoid

Text {
    property PlasmoidItem plasmoidItem
    text: plasmoidItem ? plasmoidItem.Plasmoid.title : ""
    color: "white"
    verticalAlignment: Text.AlignVCenter
    MouseArea {
        anchors.fill: parent
        onClicked: if (parent.plasmoidItem) parent.plasmoidItem.expanded = !parent.plasmoidItem.expanded
    }
}
