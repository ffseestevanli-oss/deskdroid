import QtQuick
import QtQuick.Effects

// A horizontally scrolling rainbow, clipped to the alpha of `maskItem` (any layer-enabled item).
// `period` is the width in pixels of one full rainbow; `phase` (0..1) scrolls it to the right.
Item {
    id: wo

    property Item maskItem
    property real period: 40
    property real phase: 0
    property real saturation: 0.9
    property real lightness: 0.5

    readonly property real p: Math.max(8, period)

    Item {
        id: strip
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Row {
            x: (wo.phase - 1) * wo.p
            Repeater {
                model: Math.min(60, Math.ceil(wo.width / wo.p) + 2)
                delegate: Rectangle {
                    width: wo.p
                    height: strip.height
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0/6; color: Qt.hsla(0/6, wo.saturation, wo.lightness, 1) }
                        GradientStop { position: 1/6; color: Qt.hsla(1/6, wo.saturation, wo.lightness, 1) }
                        GradientStop { position: 2/6; color: Qt.hsla(2/6, wo.saturation, wo.lightness, 1) }
                        GradientStop { position: 3/6; color: Qt.hsla(3/6, wo.saturation, wo.lightness, 1) }
                        GradientStop { position: 4/6; color: Qt.hsla(4/6, wo.saturation, wo.lightness, 1) }
                        GradientStop { position: 5/6; color: Qt.hsla(5/6, wo.saturation, wo.lightness, 1) }
                        GradientStop { position: 6/6; color: Qt.hsla(0, wo.saturation, wo.lightness, 1) }
                    }
                }
            }
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: strip
        maskEnabled: wo.maskItem !== null
        maskSource: wo.maskItem
    }
}
