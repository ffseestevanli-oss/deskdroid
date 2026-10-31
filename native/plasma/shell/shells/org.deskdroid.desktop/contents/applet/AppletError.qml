// What an applet that failed to load shows: why.
import QtQuick

Rectangle {
    property var plasmoidItem
    property string reason
    color: "#80000000"
    implicitWidth: 300
    implicitHeight: 120
    Text {
        anchors.fill: parent
        anchors.margins: 8
        wrapMode: Text.Wrap
        color: "white"
        text: parent.reason
    }
}
