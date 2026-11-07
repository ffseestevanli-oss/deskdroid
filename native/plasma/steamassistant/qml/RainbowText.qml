// A heading filled with the rainbow, like "DeskDroid!" on the phone app's
// Welcome screen: each letter takes its color along the rainbow, so it draws
// the same with the GPU or with Qt's software renderer (no shaders).
import QtQuick
import "."

Text {
    id: root
    property string heading: ""
    property real size: 34
    textFormat: Text.StyledText
    wrapMode: Text.WordWrap
    font.family: Party.heading
    font.weight: Font.Black
    font.pixelSize: size
    lineHeight: 1.1
    color: Party.pink
    text: {
        const s = heading.toUpperCase()
        const n = Math.max(1, s.length - 1)
        let out = ""
        for (let k = 0; k < s.length; k++) {
            const ch = s[k] === "<" ? "&lt;" : s[k] === "&" ? "&amp;" : s[k] === ">" ? "&gt;" : s[k]
            if (ch === " ") { out += " "; continue }
            const c = Party.rainbowAt(k / n)
            const hex = "#" + [c.r, c.g, c.b].map(v => ("0" + Math.round(v * 255).toString(16)).slice(-2)).join("")
            out += "<font color=\"" + hex + "\">" + ch + "</font>"
        }
        return out
    }
}
