// The installer's segmented rainbow bar (the phone app's Installing screen
// and the old Debian installer's LOADING bar): 20 segments that light up in
// rainbow order, or a running block of four while there's no estimate.
import QtQuick
import "."

Rectangle {
    id: root
    property real fraction: 0
    property bool indeterminate: false
    property int segments: 20
    property int pulse: 0
    implicitHeight: 34
    color: Party.surface
    border.color: Party.border
    border.width: 1

    Timer {
        running: root.indeterminate && root.visible
        interval: 90
        repeat: true
        onTriggered: root.pulse = (root.pulse + 1) % root.segments
    }
    Row {
        id: row
        anchors.fill: parent
        anchors.margins: 4
        spacing: 3
        readonly property real segW: (width - spacing * (root.segments - 1)) / root.segments
        Repeater {
            model: root.segments
            Rectangle {
                width: row.segW
                height: row.height
                readonly property bool on: root.indeterminate
                    ? ((index - root.pulse + root.segments) % root.segments) < 4
                    : index < Math.floor(Math.max(0, Math.min(1, root.fraction)) * root.segments + 0.0001)
                color: on ? Party.rainbowAt(index / (root.segments - 1)) : Party.empty
                Behavior on color { ColorAnimation { duration: 160 } }
            }
        }
    }
}
