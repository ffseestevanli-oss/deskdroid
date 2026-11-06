import QtQuick

// The vertical banner of the Windows 9x layout: distro name on a gradient / rainbow strip
Item {
    id: strip

    property string text: "Linux"
    property string style: "gradient"      // gradient | solid | rainbow | rgbfade | wave
    property color color1: "#000080"
    property color color2: "#1084d0"
    property color textColor: "white"
    property int fontSize: 32
    property int speed: 8                  // seconds per cycle for animated styles

    readonly property bool animated: style === "rgbfade" || style === "wave"
    property real phase: 0

    NumberAnimation on phase {
        from: 0
        to: 1
        duration: Math.max(1, strip.speed) * 1000
        loops: Animation.Infinite
        running: strip.animated && strip.visible
    }

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
    }
    // colour of stop i (0..6); reads phase so animated styles update
    function stopColor(i) {
        var t = i / 6
        switch (style) {
        case "solid":    return color1
        case "rainbow":  return Qt.hsla(t * 0.83, 0.9, 0.5, 1)
        case "rgbfade":  return Qt.hsla(phase, 0.9, 0.5, 1)
        case "wave":     return Qt.hsla((t * 0.8 + phase) % 1, 0.9, 0.5, 1)
        default:         return mix(color1, color2, t)
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0;   color: strip.stopColor(0) }
            GradientStop { position: 1/6;   color: strip.stopColor(1) }
            GradientStop { position: 2/6;   color: strip.stopColor(2) }
            GradientStop { position: 3/6;   color: strip.stopColor(3) }
            GradientStop { position: 4/6;   color: strip.stopColor(4) }
            GradientStop { position: 5/6;   color: strip.stopColor(5) }
            GradientStop { position: 1.0;   color: strip.stopColor(6) }
        }
    }

    // Text reads bottom-to-top, like the original banner
    Item {
        x: 0
        y: strip.height
        width: strip.height
        height: strip.width
        rotation: -90
        transformOrigin: Item.TopLeft

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 20
            elide: Text.ElideRight
            text: strip.text
            color: strip.textColor
            font.pixelSize: strip.fontSize
            font.bold: true
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.35)
        }
    }
}
