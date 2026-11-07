// A page in the party look: near-black with soft colored glows behind the
// content (the mockups' blurred circles), the content in a scrolling column.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import "."

Kirigami.ScrollablePage {
    id: page
    // Glows: [x, y, color] with x and y from 0 to 1.
    property var glows: [[0.1, 0.05, Party.pink], [0.95, 0.9, Party.cyan]]
    property bool showHeader: false
    globalToolBarStyle: showHeader ? Kirigami.ApplicationHeaderStyle.ToolBar : Kirigami.ApplicationHeaderStyle.None
    leftPadding: Kirigami.Units.gridUnit * 2
    rightPadding: Kirigami.Units.gridUnit * 2
    topPadding: Kirigami.Units.gridUnit * 2
    bottomPadding: Kirigami.Units.gridUnit * 2
    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.View
    Kirigami.Theme.backgroundColor: Party.bg
    Kirigami.Theme.textColor: Party.text
    Kirigami.Theme.highlightColor: Party.pink
    Kirigami.Theme.disabledTextColor: Party.dim

    background: Rectangle {
        color: Party.bg
        clip: true
        Repeater {
            model: page.glows
            Shape {
                readonly property real r: Math.max(page.width, page.height) * 0.55
                readonly property color glow: modelData[2]
                x: page.width * modelData[0] - r
                y: page.height * modelData[1] - r
                width: r * 2
                height: r * 2
                ShapePath {
                    strokeWidth: -1
                    fillGradient: RadialGradient {
                        centerX: r; centerY: r; centerRadius: r
                        focalX: r; focalY: r
                        GradientStop { position: 0.0; color: Qt.rgba(glow.r, glow.g, glow.b, 0.22) }
                        GradientStop { position: 1.0; color: Qt.rgba(glow.r, glow.g, glow.b, 0) }
                    }
                    startX: 0; startY: 0
                    PathLine { x: r * 2; y: 0 }
                    PathLine { x: r * 2; y: r * 2 }
                    PathLine { x: 0; y: r * 2 }
                    PathLine { x: 0; y: 0 }
                }
            }
        }
    }
}
