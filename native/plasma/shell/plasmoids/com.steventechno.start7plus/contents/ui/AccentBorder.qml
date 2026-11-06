import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

// A border ring around the menu. Styles: system | custom | gradient | rainbow | rgbfade | flow
Item {
    id: ab

    property string style: "system"
    property color color1: "#3daee9"
    property color color2: "#9b59b6"
    property real thickness: 2
    property int speed: 8                  // seconds per cycle (animated styles)
    property real tl: 0                    // corner radii (outer)
    property real tr: 0
    property real bl: 0
    property real br: 0

    readonly property bool animated: style === "rgbfade" || style === "flow"
    property real phase: 0                 // driven by the menu so every instance stays in sync
    property string mode: "ring"           // "ring" = outline only, "fill" = solid area
    property real fillOpacity: 0.2

    enabled: false

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
    }
    // colour of gradient stop i (0..6); reads phase so the animated styles update
    function stopColor(i) {
        var t = i / 6
        switch (style) {
        case "custom":   return color1
        case "gradient": return mix(color1, color2, t)
        case "rainbow":  return Qt.hsla(t, 0.9, 0.5, 1)
        case "rgbfade":  return Qt.hsla(phase, 0.9, 0.5, 1)
        case "flow":     return Qt.hsla((t + phase) % 1, 0.9, 0.5, 1)
        default:         return Kirigami.Theme.highlightColor
        }
    }

    // radii for the inner edge, and a floor so arcs never get a zero radius
    function r(v) { return Math.max(0.01, v) }
    readonly property real w: Math.max(1, thickness)

    // solid area (outer outline filled), drawn with the same colors
    Shape {
        anchors.fill: parent
        visible: ab.mode === "fill"
        opacity: ab.fillOpacity
        layer.enabled: visible
        layer.samples: 4

        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0; y1: 0
                x2: ab.width; y2: ab.height
                GradientStop { position: 0.0;  color: ab.stopColor(0) }
                GradientStop { position: 1/6;  color: ab.stopColor(1) }
                GradientStop { position: 2/6;  color: ab.stopColor(2) }
                GradientStop { position: 3/6;  color: ab.stopColor(3) }
                GradientStop { position: 4/6;  color: ab.stopColor(4) }
                GradientStop { position: 5/6;  color: ab.stopColor(5) }
                GradientStop { position: 1.0;  color: ab.stopColor(6) }
            }
            startX: ab.tl; startY: 0
            PathLine { x: ab.width - ab.tr; y: 0 }
            PathArc  { x: ab.width; y: ab.tr; radiusX: ab.r(ab.tr); radiusY: ab.r(ab.tr) }
            PathLine { x: ab.width; y: ab.height - ab.br }
            PathArc  { x: ab.width - ab.br; y: ab.height; radiusX: ab.r(ab.br); radiusY: ab.r(ab.br) }
            PathLine { x: ab.bl; y: ab.height }
            PathArc  { x: 0; y: ab.height - ab.bl; radiusX: ab.r(ab.bl); radiusY: ab.r(ab.bl) }
            PathLine { x: 0; y: ab.tl }
            PathArc  { x: ab.tl; y: 0; radiusX: ab.r(ab.tl); radiusY: ab.r(ab.tl) }
        }
    }

    // outline ring
    Shape {
        anchors.fill: parent
        visible: ab.mode === "ring"
        layer.enabled: visible
        layer.samples: 4

        ShapePath {
            id: ring
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill
            fillGradient: LinearGradient {
                x1: 0; y1: 0
                x2: ab.width; y2: ab.height
                GradientStop { position: 0.0;  color: ab.stopColor(0) }
                GradientStop { position: 1/6;  color: ab.stopColor(1) }
                GradientStop { position: 2/6;  color: ab.stopColor(2) }
                GradientStop { position: 3/6;  color: ab.stopColor(3) }
                GradientStop { position: 4/6;  color: ab.stopColor(4) }
                GradientStop { position: 5/6;  color: ab.stopColor(5) }
                GradientStop { position: 1.0;  color: ab.stopColor(6) }
            }

            // outer edge
            startX: ab.tl; startY: 0
            PathLine { x: ab.width - ab.tr; y: 0 }
            PathArc  { x: ab.width; y: ab.tr; radiusX: ab.r(ab.tr); radiusY: ab.r(ab.tr) }
            PathLine { x: ab.width; y: ab.height - ab.br }
            PathArc  { x: ab.width - ab.br; y: ab.height; radiusX: ab.r(ab.br); radiusY: ab.r(ab.br) }
            PathLine { x: ab.bl; y: ab.height }
            PathArc  { x: 0; y: ab.height - ab.bl; radiusX: ab.r(ab.bl); radiusY: ab.r(ab.bl) }
            PathLine { x: 0; y: ab.tl }
            PathArc  { x: ab.tl; y: 0; radiusX: ab.r(ab.tl); radiusY: ab.r(ab.tl) }

            // inner edge (second sub-path, cut out by the odd-even fill rule)
            PathMove { x: ab.w + Math.max(0, ab.tl - ab.w); y: ab.w }
            PathLine { x: ab.width - ab.w - Math.max(0, ab.tr - ab.w); y: ab.w }
            PathArc  { x: ab.width - ab.w; y: ab.w + Math.max(0, ab.tr - ab.w); radiusX: ab.r(ab.tr - ab.w); radiusY: ab.r(ab.tr - ab.w) }
            PathLine { x: ab.width - ab.w; y: ab.height - ab.w - Math.max(0, ab.br - ab.w) }
            PathArc  { x: ab.width - ab.w - Math.max(0, ab.br - ab.w); y: ab.height - ab.w; radiusX: ab.r(ab.br - ab.w); radiusY: ab.r(ab.br - ab.w) }
            PathLine { x: ab.w + Math.max(0, ab.bl - ab.w); y: ab.height - ab.w }
            PathArc  { x: ab.w; y: ab.height - ab.w - Math.max(0, ab.bl - ab.w); radiusX: ab.r(ab.bl - ab.w); radiusY: ab.r(ab.bl - ab.w) }
            PathLine { x: ab.w; y: ab.w + Math.max(0, ab.tl - ab.w) }
            PathArc  { x: ab.w + Math.max(0, ab.tl - ab.w); y: ab.w; radiusX: ab.r(ab.tl - ab.w); radiusY: ab.r(ab.tl - ab.w) }
        }
    }
}
