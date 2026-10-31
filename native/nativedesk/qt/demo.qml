// Qt Quick window of the native desktop test: the scene graph on the phone's
// GPU through the deskdroid platform plugin, with the pieces Plasma's panels
// and widgets are made of (animations, text, a scrolling list, a text field,
// hover and clicks).
import QtQuick

Window {
    id: win
    width: 760
    height: 440
    visible: true
    title: "Qt Quick"
    color: "#1b1e3a"

    property real fps: 0
    property int clicks: 0

    FrameAnimation {
        running: true
        property int frames: 0
        property real since: 0
        onTriggered: {
            frames++
            since += frameTime
            if (since >= 1) {
                win.fps = frames / since
                frames = 0
                since = 0
            }
        }
    }

    Timer {
        interval: 5000; running: true; repeat: true
        onTriggered: console.log("Qt Quick: " + Math.round(win.fps) + " fps")
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#1c1e3a" }
            GradientStop { position: 1; color: "#341846" }
        }
    }

    Column {
        x: 24; y: 20
        spacing: 8
        Text { text: "Qt Quick window"; color: "white"; font.pixelSize: 30; font.bold: true }
        Text {
            text: Math.round(win.fps) + " fps · QML scene graph on "
                  + (GraphicsInfo.api === GraphicsInfo.OpenGL ? "the GPU (OpenGL ES)" : "the CPU (software)")
            color: "white"; font.pixelSize: 20
        }
        Rectangle {
            width: 330; height: 40; radius: 8
            color: "#22ffffff"
            border.color: input.activeFocus ? "#8ab4ff" : "#44ffffff"
            TextInput {
                id: input
                anchors.fill: parent; anchors.margins: 10
                color: "white"; font.pixelSize: 18
                focus: true
                clip: true
                Text {
                    visible: !input.text
                    text: "Type here"
                    color: "#99ffffff"; font: input.font
                }
            }
        }
        Rectangle {
            width: 330; height: 44; radius: 8
            color: button.pressed ? "#5a7be0" : button.containsMouse ? "#4a6ad0" : "#3a5ac0"
            Behavior on color { ColorAnimation { duration: 120 } }
            Text {
                anchors.centerIn: parent
                text: win.clicks ? "Clicked " + win.clicks + (win.clicks === 1 ? " time" : " times") : "Click me"
                color: "white"; font.pixelSize: 18
            }
            MouseArea {
                id: button
                anchors.fill: parent
                hoverEnabled: true
                onClicked: win.clicks++
            }
        }
        ListView {
            width: 330; height: 200
            clip: true
            model: 100
            spacing: 4
            delegate: Rectangle {
                required property int index
                width: ListView.view.width; height: 36; radius: 6
                color: Qt.hsva((index * 0.07) % 1, 0.5, 0.45, 1)
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 12
                    text: "List row " + (index + 1) + " (scroll me)"
                    color: "white"; font.pixelSize: 16
                }
            }
        }
    }

    Item {
        id: spinner
        x: parent.width * 0.74; y: parent.height * 0.55
        Repeater {
            model: 12
            Rectangle {
                required property int index
                width: 90; height: 28; radius: 14
                x: 40; y: -14
                transform: Rotation { origin.x: -40; origin.y: 14; angle: index * 30 }
                color: Qt.hsva(index / 12, 0.7, 1, 0.85)
            }
        }
        RotationAnimation on rotation { from: 0; to: 360; duration: 9000; loops: Animation.Infinite }
    }

    Rectangle {
        width: 24; height: 24; radius: 12
        color: "#ccffffff"
        x: hover.point.position.x - 12
        y: hover.point.position.y - 12
        visible: hover.hovered
    }
    HoverHandler { id: hover }
}
