import QtQuick
import QtQuick.Shapes

// A filled / outlined shape of any width and height. When it is wider than tall the ends keep
// their shape and only the middle gets longer ("stretch").
// Kinds: circle | square | rounded | hexagon | diamond | octagon | arrow
Item {
    id: sf

    property string kind: "circle"
    property bool useGradient: false
    property color topColor: "white"
    property color midColor: "gray"
    property color bottomColor: "black"
    property color fillColor: "transparent"
    property color borderColor: "transparent"
    property real borderWidth: 0

    readonly property real cx: width / 2
    readonly property real cy: height / 2
    readonly property real hr: Math.max(0, height / 2 - borderWidth / 2)         // half height
    readonly property real hx: Math.max(0, width / 2 - borderWidth / 2)         // half width
    readonly property real hy: kind === "hexagon" ? hr * 0.8660254 : hr           // half height of the polygon
    readonly property real minSide: Math.min(width, height)
    readonly property bool isPoly: kind === "hexagon" || kind === "diamond" || kind === "octagon" || kind === "arrow"
    readonly property real cornerR: kind === "circle" ? minSide / 2
        : (kind === "square" ? minSide * 0.05 : (kind === "rounded" ? minSide * 0.28 : 0))

    readonly property var pts: {
        switch (kind) {
        case "diamond": {
            var d = hr
            return [Qt.point(cx + hx, cy), Qt.point(cx + hx - d, cy + hr), Qt.point(cx - hx + d, cy + hr),
                    Qt.point(cx - hx, cy), Qt.point(cx - hx + d, cy - hr), Qt.point(cx + hx - d, cy - hr)]
        }
        case "octagon": {
            var c = hr * 0.586
            return [Qt.point(cx - hx + c, cy - hr), Qt.point(cx + hx - c, cy - hr), Qt.point(cx + hx, cy - hr + c), Qt.point(cx + hx, cy + hr - c),
                    Qt.point(cx + hx - c, cy + hr), Qt.point(cx - hx + c, cy + hr), Qt.point(cx - hx, cy + hr - c), Qt.point(cx - hx, cy - hr + c)]
        }
        case "arrow": {
            var t = hr * 0.8
            return [Qt.point(cx - hx, cy - hr), Qt.point(cx + hx - t, cy - hr), Qt.point(cx + hx, cy),
                    Qt.point(cx + hx - t, cy + hr), Qt.point(cx - hx, cy + hr)]
        }
        default: {   // hexagon
            var a = hr / 2
            return [Qt.point(cx + hx, cy), Qt.point(cx + hx - a, cy + hy), Qt.point(cx - hx + a, cy + hy),
                    Qt.point(cx - hx, cy), Qt.point(cx - hx + a, cy - hy), Qt.point(cx + hx - a, cy - hy)]
        }
        }
    }

    // circle / square / rounded square, gradient fill
    Rectangle {
        visible: !sf.isPoly && sf.useGradient
        anchors.fill: parent
        radius: sf.cornerR
        border.width: sf.borderWidth
        border.color: sf.borderColor
        gradient: Gradient {
            GradientStop { position: 0.0;  color: sf.topColor }
            GradientStop { position: 0.45; color: sf.midColor }
            GradientStop { position: 1.0;  color: sf.bottomColor }
        }
    }

    // circle / square / rounded square, solid fill
    Rectangle {
        visible: !sf.isPoly && !sf.useGradient
        anchors.fill: parent
        radius: sf.cornerR
        color: sf.fillColor
        border.width: sf.borderWidth
        border.color: sf.borderColor
    }

    // polygons, gradient fill
    Shape {
        visible: sf.isPoly && sf.useGradient
        anchors.fill: parent
        layer.enabled: visible
        layer.samples: 4

        ShapePath {
            strokeWidth: sf.borderWidth > 0 ? sf.borderWidth : -1
            strokeColor: sf.borderColor
            fillGradient: LinearGradient {
                x1: 0
                y1: sf.cy - sf.hy
                x2: 0
                y2: sf.cy + sf.hy
                GradientStop { position: 0.0;  color: sf.topColor }
                GradientStop { position: 0.45; color: sf.midColor }
                GradientStop { position: 1.0;  color: sf.bottomColor }
            }
            startX: sf.pts[0].x
            startY: sf.pts[0].y
            PathPolyline { path: sf.pts }
        }
    }

    // polygons, solid fill
    Shape {
        visible: sf.isPoly && !sf.useGradient
        anchors.fill: parent
        layer.enabled: visible
        layer.samples: 4

        ShapePath {
            strokeWidth: sf.borderWidth > 0 ? sf.borderWidth : -1
            strokeColor: sf.borderColor
            fillColor: sf.fillColor
            startX: sf.pts[0].x
            startY: sf.pts[0].y
            PathPolyline { path: sf.pts }
        }
    }
}
