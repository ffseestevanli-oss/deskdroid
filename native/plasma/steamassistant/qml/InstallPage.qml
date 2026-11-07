// Page 2: the install, with the rainbow LOADING bar and the verbose log.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."

PartyPage {
    id: page
    title: "Setting up Steam"
    glows: [[0.05, 0.1, Party.purple], [0.95, 0.85, Party.pink]]

    property bool autoStart: false
    // "running", "done" or "failed"
    property string phase: "running"
    property real fraction: 0
    property string step: "Getting started"
    property string error: ""
    property bool verbose: false

    function begin() {
        phase = "running"; fraction = 0; error = ""; step = "Getting started"
        log.clear()
        backend.install()
    }

    Connections {
        target: backend
        function onLine(text) {
            log.append(text)
        }
        function onProgress(f, label) {
            page.fraction = Math.max(page.fraction, f)
            page.step = label
        }
        function onFinished(ok, message) {
            if (ok) {
                page.fraction = 1
                page.phase = "done"
                backend.welcomedBack = false
            } else {
                page.phase = "failed"
                page.error = message
            }
        }
    }
    Component.onCompleted: if (autoStart && !backend.busy) begin()

    ColumnLayout {
        spacing: 22
        width: Math.min(page.width - page.leftPadding - page.rightPadding, 760)
        x: Math.max(0, (page.width - page.leftPadding - page.rightPadding - width) / 2)

        Item { Layout.preferredHeight: 4 }
        Text {
            text: page.phase === "done" ? "ALL DONE" : "STEP 2 / 2  ·  INSTALLING"
            font.family: Party.body; font.weight: Font.Bold; font.pixelSize: 13; font.letterSpacing: 3
            color: page.phase === "failed" ? Party.red : page.phase === "done" ? Party.green : Party.pink
        }
        RainbowText {
            heading: page.phase === "done" ? "Steam is installed!" : page.phase === "failed" ? "That didn't work" : "Sit back, I've got this"
            size: page.width < 640 ? 26 : 34
            Layout.fillWidth: true
        }
        Text {
            text: page.phase === "done"
                ? "Come back here if you need to manage anything: this assistant is now your maintenance tool for Steam, FEX-Emu and Proton."
                : page.phase === "failed"
                ? "Something stopped the install. Nothing is lost: what finished stays, and trying again picks up from there."
                : "I'm going to fetch Steam and FEX-Emu for ya, and I'll assemble everything too. Grab a drink and sit back. This will take a minute!"
            font.family: Party.body; font.pixelSize: 17
            color: Party.textSoft
            wrapMode: Text.WordWrap
            lineHeight: 1.2
            Layout.fillWidth: true
        }

        // LOADING: [=======}
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: page.phase === "done" ? "LOADED:" : page.phase === "failed" ? "STOPPED:" : "LOADING:"
                    font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 15; font.letterSpacing: 2
                    color: Party.text
                }
                Text {
                    text: page.step
                    font.family: Party.body; font.pixelSize: 14
                    color: Party.muted
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: Math.round(page.fraction * 100) + "%"
                    font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 15
                    color: page.phase === "failed" ? Party.red : Party.cyan
                }
            }
            RainbowBar {
                Layout.fillWidth: true
                fraction: page.fraction
                // Before the first estimate (asking the app, checking free space).
                indeterminate: page.phase === "running" && page.fraction === 0
            }
        }

        // The error, in plain words, with the way out.
        Item {
            visible: page.phase === "failed"
            Layout.fillWidth: true
            implicitHeight: errCol.implicitHeight + 28
            Chamfer { anchors.fill: parent; cut: 12; cutTopLeft: false; fillColor: Party.surface }
            Rectangle { width: 3; height: parent.height; color: Party.red }
            ColumnLayout {
                id: errCol
                anchors.fill: parent
                anchors.margins: 14
                anchors.leftMargin: 20
                spacing: 6
                Text {
                    text: page.error || "The install stopped."
                    font.family: Party.body; font.weight: Font.Bold; font.pixelSize: 15
                    color: Party.text
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                Text {
                    visible: /HTTP 404|HTTP 403|isn't published|FEX add-on/.test(page.error)
                    text: "DeskDroid's FEX-Emu build has no download home yet. Install the FEX add-on APK, or point \"Download from\" at a folder that has it."
                    font.family: Party.body; font.pixelSize: 14
                    color: Party.muted
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 14
            PartyButton {
                visible: page.phase === "done"
                primary: true
                text: "Launch Steam"
                onClicked: backend.launchSteam()
            }
            PartyButton {
                visible: page.phase === "done"
                text: "Open the tools"
                accent: Party.pink
                implicitHeight: 56
                onClicked: applicationWindow().showTools()
            }
            PartyButton {
                visible: page.phase === "failed"
                primary: true
                text: "Try again"
                onClicked: page.begin()
            }
            PartyButton {
                visible: page.phase === "failed"
                text: "Download from…"
                accent: Party.cyan
                implicitHeight: 56
                onClicked: applicationWindow().pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
            }
            PartyButton {
                visible: page.phase === "failed"
                text: "Back"
                implicitHeight: 56
                onClicked: applicationWindow().showWelcome()
            }
            PartyButton {
                visible: page.phase === "running"
                text: "Cancel"
                accent: Party.border
                onClicked: { backend.cancel(); page.phase = "failed"; page.error = "Cancelled." }
            }
        }

        // View Verbose (Advanced)
        QQC2.AbstractButton {
            id: verboseToggle
            Layout.fillWidth: true
            implicitHeight: 36
            hoverEnabled: true
            onClicked: page.verbose = !page.verbose
            contentItem: Text {
                text: (page.verbose ? "▾  Hide verbose" : "▸  View verbose (advanced)")
                font.family: Party.body; font.weight: Font.Bold; font.pixelSize: 14
                color: verboseToggle.hovered ? Party.text : Party.cyan
                verticalAlignment: Text.AlignVCenter
            }
        }
        Rectangle {
            visible: page.verbose
            Layout.fillWidth: true
            Layout.preferredHeight: 260
            color: Party.panel
            border.color: Party.border
            border.width: 1
            QQC2.ScrollView {
                id: logScroll
                anchors.fill: parent
                anchors.margins: 8
                QQC2.TextArea {
                    id: log
                    readOnly: true
                    wrapMode: TextEdit.WrapAnywhere
                    font.family: "monospace"
                    font.pixelSize: 12
                    color: Party.textSoft
                    selectByMouse: true
                    background: null
                    onTextChanged: cursorPosition = length
                }
            }
        }
    }
}
