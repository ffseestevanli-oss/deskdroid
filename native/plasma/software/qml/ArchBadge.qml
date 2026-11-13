// Which of a Flathub app's builds runs here: ARM64 as it is (through
// ddmask), x86-64 through FEX, or none of them.
import QtQuick
import "."

Rectangle {
    id: badge
    property var arches: []
    // Set when the app is installed: the build that is.
    property string installedArch: ""
    readonly property string pick: installedArch !== "" ? (installedArch === backend.arch ? "" : installedArch) : backend.archFor(arches)
    readonly property color tint: pick === "" ? Party.green : pick === "none" ? Party.red : Party.orange
    implicitWidth: label.implicitWidth + 14
    implicitHeight: label.implicitHeight + 6
    radius: 3
    color: "transparent"
    border.color: tint
    border.width: 1
    Text {
        id: label
        anchors.centerIn: parent
        text: badge.pick === "" ? (backend.arch === "aarch64" ? "ARM64" : backend.arch.toUpperCase())
            : badge.pick === "x86_64" ? "x86-64 · FEX"
            : "No build for this device"
        font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 10; font.letterSpacing: 1
        color: badge.tint
    }
}
