// What an applet that failed to load shows: why. libplasma needs a
// PlasmoidItem here (anything else leaves it with no item, and it crashes).
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    property var errorInformation

    preferredRepresentation: fullRepresentation
    fullRepresentation: Rectangle {
        Layout.minimumWidth: 200
        Layout.minimumHeight: 24
        Layout.preferredWidth: 320
        Layout.preferredHeight: 120
        color: "#80000000"
        Text {
            anchors.fill: parent
            anchors.margins: 6
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            color: "white"
            text: root.errorInformation && root.errorInformation.errors
                  ? root.errorInformation.errors.join("\n") : "This widget could not be loaded."
        }
    }
}
