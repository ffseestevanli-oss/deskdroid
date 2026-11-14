pragma Singleton
import QtQuick

// DD Party's palette (dd-party-theme gen/palette.py) and fonts.
QtObject {
    readonly property color bg: "#07070D"
    readonly property color view: "#0D0D16"
    readonly property color button: "#12121E"
    readonly property color header: "#0C0C16"
    readonly property color card: "#10101B"
    readonly property color cardOn: "#1A0F22"
    readonly property color border: "#2A2A3D"
    readonly property color borderSoft: "#262638"
    readonly property color text: "#F2F2F7"
    readonly property color soft: "#C9C9DC"
    readonly property color muted: "#A6A6C0"
    readonly property color dim: "#8A8AA6"
    readonly property color empty: "#1E1E2E"
    readonly property color magenta: "#990045"
    readonly property color magentaHi: "#B8105A"
    readonly property color magentaText: "#FF4D94"
    readonly property var rainbow: ["#FF3B5C", "#FF9F1C", "#FFE14D", "#3DFF8B", "#2EC5FF", "#8B5CFF", "#FF4FD8"]
    readonly property string heading: "Orbitron"
    readonly property string body: "Chakra Petch"
    readonly property int cut: 10
}
