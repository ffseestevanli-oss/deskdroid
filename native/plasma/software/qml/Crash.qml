// The crash dialog: an app from Software failed (`software --crashed <id>
// <name> <log>`, opened by native/flatpak/adpk-run.sh). Says so, shows the
// end of the report, and saves the report where the person chooses, so it's
// easy to pass along.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import "."

QQC2.ApplicationWindow {
    id: root
    visible: true
    title: "Something's not right"
    width: 640
    height: 520
    minimumWidth: 420
    minimumHeight: 360
    color: Party.bg
    font.family: Party.body
    palette.window: Party.surface
    palette.windowText: Party.text
    palette.base: Party.panel
    palette.text: Party.text
    palette.button: Party.surface
    palette.buttonText: Party.text
    palette.highlight: Party.pink
    palette.highlightedText: Party.bg

    property string saved: ""
    property string saveError: ""

    // The rainbow line at the top, as in Software's window.
    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 4
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Party.red }
            GradientStop { position: 0.17; color: Party.orange }
            GradientStop { position: 0.33; color: Party.yellow }
            GradientStop { position: 0.5; color: Party.green }
            GradientStop { position: 0.67; color: Party.cyan }
            GradientStop { position: 0.83; color: Party.purple }
            GradientStop { position: 1.0; color: Party.pink }
        }
    }

    Column {
        id: top
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24; topMargin: 28 }
        spacing: 10
        RainbowText {
            heading: "Uh oh! Something's not right!"
            size: 24
            width: parent.width
        }
        Text {
            width: parent.width
            text: "This software failed to launch! <b>" + (report.name || report.id) + "</b> stopped before it could start properly. "
                + "Save the log and pass it along, and we'll take a look."
            textFormat: Text.StyledText
            wrapMode: Text.WordWrap
            font.family: Party.body; font.pixelSize: 15
            color: Party.textSoft
            lineHeight: 1.2
        }
    }

    Chamfer {
        id: logBox
        anchors { left: parent.left; right: parent.right; top: top.bottom; bottom: buttons.top; margins: 24; topMargin: 16; bottomMargin: 16 }
        cut: 10
        fillColor: Party.panel
        strokeColor: Party.border
        strokeWidth: 1
        QQC2.ScrollView {
            anchors.fill: parent
            anchors.margins: 12
            clip: true
            QQC2.TextArea {
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.WrapAnywhere
                text: report.tail(60)
                font.family: "monospace"; font.pixelSize: 12
                color: Party.muted
                background: null
                Component.onCompleted: cursorPosition = length
            }
        }
    }

    Column {
        id: buttons
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 24 }
        spacing: 10
        Text {
            width: parent.width
            visible: root.saved !== "" || root.saveError !== ""
            text: root.saveError !== "" ? "Couldn't save the log: " + root.saveError : "Saved to " + root.saved
            wrapMode: Text.WrapAnywhere
            font.family: Party.body; font.pixelSize: 14
            color: root.saveError !== "" ? Party.red : Party.green
        }
        Flow {
            width: parent.width
            spacing: 10
            PartyButton {
                text: "Save log as…"
                primary: true
                onClicked: saveDialog.open()
            }
            PartyButton {
                text: "Close"
                onClicked: Qt.quit()
            }
        }
    }

    FileDialog {
        id: saveDialog
        title: "Save the log"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Logs (*.log *.txt)", "All files (*)"]
        currentFolder: "file:///storage/emulated/0/Download"
        selectedFile: "file:///storage/emulated/0/Download/" + report.suggestedName()
        onAccepted: {
            const err = report.saveTo(selectedFile.toString())
            root.saveError = err
            root.saved = err === "" ? decodeURIComponent(selectedFile.toString().replace("file://", "")) : ""
        }
    }
}
