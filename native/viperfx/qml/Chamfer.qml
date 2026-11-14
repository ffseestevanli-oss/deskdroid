import QtQuick
import QtQuick.Shapes

// A box with DD Party's cut corners (top-left and bottom-right).
Shape {
    id: s
    property color fill: Theme.card
    property color stroke: Theme.border
    property real cut: Theme.cut
    property real strokeWidth: 1
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        fillColor: s.fill
        strokeColor: s.stroke
        strokeWidth: s.strokeWidth
        startX: s.cut; startY: 0.5
        PathLine { x: s.width - 0.5; y: 0.5 }
        PathLine { x: s.width - 0.5; y: s.height - s.cut }
        PathLine { x: s.width - s.cut; y: s.height - 0.5 }
        PathLine { x: 0.5; y: s.height - 0.5 }
        PathLine { x: 0.5; y: s.cut }
        PathLine { x: s.cut; y: 0.5 }
    }
}
