// DeskDroid's "party" look, as in the phone app (app/.../ui/Party.kt):
// near-black, rainbow accents on strips, borders and main buttons, chamfered
// corners, Orbitron headings and Chakra Petch text.
pragma Singleton
import QtQuick

QtObject {
    readonly property color bg: "#07070D"
    readonly property color surface: "#12121E"
    readonly property color surfaceDim: "#0D0D16"
    readonly property color card: "#10101B"
    readonly property color cardOn: "#1A0F22"
    readonly property color panel: "#0C0C16"
    readonly property color border: "#2A2A3D"
    readonly property color borderSoft: "#262638"
    readonly property color text: "#F2F2F7"
    readonly property color textSoft: "#C9C9DC"
    readonly property color muted: "#A6A6C0"
    readonly property color dim: "#8A8AA6"
    readonly property color empty: "#1E1E2E"

    readonly property color red: "#FF3B5C"
    readonly property color orange: "#FF9F1C"
    readonly property color yellow: "#FFE14D"
    readonly property color green: "#3DFF8B"
    readonly property color cyan: "#2EC5FF"
    readonly property color purple: "#8B5CFF"
    readonly property color pink: "#FF4FD8"
    readonly property var rainbow: [red, orange, yellow, green, cyan, purple, pink]

    readonly property string heading: "Orbitron"
    readonly property string body: "Chakra Petch"

    // A color along the rainbow, t from 0 to 1 (the segmented bar's segments).
    function rainbowAt(t) {
        const n = rainbow.length - 1
        const pos = Math.max(0, Math.min(1, t)) * n
        const i = Math.min(Math.floor(pos), n - 1)
        const f = pos - i
        const a = rainbow[i], b = rainbow[i + 1]
        return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, 1)
    }
}
