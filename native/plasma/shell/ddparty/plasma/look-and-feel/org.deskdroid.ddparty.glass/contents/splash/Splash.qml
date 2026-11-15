/*
    DD Party Glass's splash screen, shown by ksplashqml while the desktop
    starts: DeskDroid's own start-up look (the app's splash, DesktopActivity),
    near-black with purple and cyan glows, the logo, the name in rainbow
    letters and a segmented rainbow bar.

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kirigami 2 as Kirigami

Rectangle {
    id: root
    color: "#07070d"

    property int stage

    readonly property var rainbow: ["#ff3b5c", "#ff9f1c", "#ffe14d", "#3dff8b", "#2ec5ff", "#8b5cff", "#ff4fd8"]

    // A colour along the rainbow, t from 0 to 1.
    function rainbowAt(t) {
        const n = rainbow.length - 1
        const i = Math.min(n - 1, Math.floor(t * n))
        const f = t * n - i
        const a = Qt.lighter(rainbow[i], 1), b = Qt.lighter(rainbow[i + 1], 1)
        return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, 1)
    }

    // Fades in once the compositor is up (ksplash's stage 2), however many
    // stages arrive at once.
    onStageChanged: {
        if (stage >= 2 && content.opacity == 0 && !introAnimation.running) {
            introAnimation.running = true
        }
    }

    // The glows, as in the app: purple top left, cyan right (drawn once
    // into images/background.png).
    Image {
        anchors.fill: parent
        source: "images/background.png"
        fillMode: Image.PreserveAspectCrop
    }

    // The app's title font.
    FontLoader {
        id: orbitron
        source: "fonts/Orbitron.ttf"
    }

    // The rainbow strip along the top.
    Row {
        anchors.top: parent.top
        width: parent.width
        Repeater {
            model: root.rainbow
            Rectangle {
                required property string modelData
                width: root.width / root.rainbow.length + 1
                height: 4
                color: modelData
            }
        }
    }

    Column {
        id: content
        anchors.centerIn: parent
        spacing: Kirigami.Units.gridUnit
        opacity: 0

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property real size: Kirigami.Units.gridUnit * 8
            source: "images/deskdroid.svg"
            sourceSize.width: size
            sourceSize.height: size
            asynchronous: true
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            Repeater {
                id: letters
                model: "DeskDroid".split("")
                Text {
                    required property string modelData
                    required property int index
                    text: modelData
                    color: root.rainbowAt(index / (letters.count - 1))
                    font.family: orbitron.status == FontLoader.Ready ? orbitron.font.family : Kirigami.Theme.defaultFont.family
                    font.pixelSize: Kirigami.Units.gridUnit * 2.2
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                }
            }
        }

        // Segmented progress, as the app's while the desktop starts: a rainbow
        // glint running along the bar until the desktop is up.
        Row {
            id: bar
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 3
            readonly property int segments: 20
            property int pulse: 0
            Timer {
                interval: 90
                repeat: true
                running: true
                onTriggered: bar.pulse = (bar.pulse + 1) % bar.segments
            }
            Repeater {
                model: bar.segments
                Rectangle {
                    required property int index
                    readonly property bool glint: (index - bar.pulse + bar.segments) % bar.segments < 4
                    width: Kirigami.Units.gridUnit * 0.7
                    height: Kirigami.Units.gridUnit * 0.9
                    color: glint ? root.rainbowAt(index / (bar.segments - 1)) : "#1e1e2e"
                }
            }
        }
    }

    OpacityAnimator {
        id: introAnimation
        running: false
        target: content
        from: 0
        to: 1
        duration: Kirigami.Units.veryLongDuration * 2
        easing.type: Easing.InOutQuad
    }
}
