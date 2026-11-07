// A rectangle with the top-left and/or bottom-right corner cut off (the
// mockups' clip-path polygons); fill and stroke can be a color or the rainbow.
import QtQuick
import QtQuick.Shapes
import "."

Shape {
    id: root
    property real cut: 14
    property bool cutTopLeft: true
    property bool cutBottomRight: true
    property color fillColor: "transparent"
    property bool rainbowFill: false
    property color strokeColor: "transparent"
    property bool rainbowStroke: false
    property real strokeWidth: 0
    // A colored bar along the bottom (the tiles' accent).
    property color accent: "transparent"
    property real accentWidth: 0

    readonly property real i: strokeWidth / 2
    // Not from the paths, which follow the size (a binding loop otherwise).
    implicitWidth: 0
    implicitHeight: 0
    antialiasing: true

    component Rainbow: LinearGradient {
        x1: 0; y1: 0; x2: root.width; y2: 0
        GradientStop { position: 0.0; color: Party.red }
        GradientStop { position: 0.17; color: Party.orange }
        GradientStop { position: 0.33; color: Party.yellow }
        GradientStop { position: 0.5; color: Party.green }
        GradientStop { position: 0.67; color: Party.cyan }
        GradientStop { position: 0.83; color: Party.purple }
        GradientStop { position: 1.0; color: Party.pink }
    }

    ShapePath {
        strokeWidth: root.strokeWidth > 0 && !root.rainbowStroke && root.strokeColor.a > 0 ? root.strokeWidth : -1
        strokeColor: root.strokeColor
        fillColor: root.rainbowFill ? "white" : root.fillColor
        fillGradient: root.rainbowFill ? rainbowFillGradient : null
        joinStyle: ShapePath.MiterJoin
        startX: root.i; startY: root.cutTopLeft ? root.cut : root.i
        PathLine { x: root.cutTopLeft ? root.cut : root.i; y: root.i }
        PathLine { x: root.width - root.i; y: root.i }
        PathLine { x: root.width - root.i; y: root.cutBottomRight ? root.height - root.cut : root.height - root.i }
        PathLine { x: root.cutBottomRight ? root.width - root.cut : root.width - root.i; y: root.height - root.i }
        PathLine { x: root.i; y: root.height - root.i }
        PathLine { x: root.i; y: root.cutTopLeft ? root.cut : root.i }
    }
    // The rainbow outline: a second path, since a ShapePath's stroke is one color.
    ShapePath {
        strokeWidth: -1
        fillColor: root.rainbowStroke && root.strokeWidth > 0 ? "white" : "transparent"
        fillGradient: root.rainbowStroke && root.strokeWidth > 0 ? rainbowStrokeGradient : null
        fillRule: ShapePath.OddEvenFill
        // outer
        startX: 0; startY: root.cutTopLeft ? root.cut : 0
        PathLine { x: root.cutTopLeft ? root.cut : 0; y: 0 }
        PathLine { x: root.width; y: 0 }
        PathLine { x: root.width; y: root.cutBottomRight ? root.height - root.cut : root.height }
        PathLine { x: root.cutBottomRight ? root.width - root.cut : root.width; y: root.height }
        PathLine { x: 0; y: root.height }
        PathLine { x: 0; y: root.cutTopLeft ? root.cut : 0 }
        // inner
        PathMove { x: root.strokeWidth; y: root.cutTopLeft ? root.cut + root.strokeWidth * 0.41 : root.strokeWidth }
        PathLine { x: root.cutTopLeft ? root.cut + root.strokeWidth * 0.41 : root.strokeWidth; y: root.strokeWidth }
        PathLine { x: root.width - root.strokeWidth; y: root.strokeWidth }
        PathLine { x: root.width - root.strokeWidth; y: root.cutBottomRight ? root.height - root.cut - root.strokeWidth * 0.41 : root.height - root.strokeWidth }
        PathLine { x: root.cutBottomRight ? root.width - root.cut - root.strokeWidth * 0.41 : root.width - root.strokeWidth; y: root.height - root.strokeWidth }
        PathLine { x: root.strokeWidth; y: root.height - root.strokeWidth }
        PathLine { x: root.strokeWidth; y: root.cutTopLeft ? root.cut + root.strokeWidth * 0.41 : root.strokeWidth }
    }
    Rainbow { id: rainbowFillGradient }
    Rainbow { id: rainbowStrokeGradient }

    Rectangle {
        visible: root.accentWidth > 0
        x: root.strokeWidth; width: parent.width - 2 * root.strokeWidth - (root.cutBottomRight ? root.cut : 0)
        y: parent.height - root.accentWidth - root.strokeWidth; height: root.accentWidth
        color: root.accent
    }
}
