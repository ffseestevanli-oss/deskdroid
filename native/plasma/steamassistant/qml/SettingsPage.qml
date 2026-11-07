// Where FEX-Emu comes from: the FEX add-on APK, or a download folder
// (~/.config/deskdroid-fex-url, read by the app's X86.kt).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."

PartyPage {
    id: page
    title: "Download from"
    glows: [[0.0, 0.1, Party.cyan], [1.0, 0.9, Party.purple]]

    ColumnLayout {
        spacing: 16
        width: Math.min(page.width - page.leftPadding - page.rightPadding, 760)
        x: Math.max(0, (page.width - page.leftPadding - page.rightPadding - width) / 2)

        BackHeader { title: page.title }

        Text {
            text: "—  WHERE FEX-EMU COMES FROM  —"
            font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 14; font.letterSpacing: 3
            color: Party.cyan
        }
        Item {
            Layout.fillWidth: true
            implicitHeight: addonText.implicitHeight + 28
            Chamfer { anchors.fill: parent; cut: 12; cutTopLeft: false; fillColor: Party.surface }
            Rectangle { width: 3; height: parent.height; color: backend.fexAddon ? Party.green : Party.border }
            Text {
                id: addonText
                anchors.fill: parent
                anchors.margins: 14
                anchors.leftMargin: 20
                text: backend.fexAddon
                    ? "The FEX add-on APK is installed: FEX-Emu comes from it, no download needed."
                    : "FEX add-on APK: not installed. Install \"DeskDroid FEX\" (the deskdroid-fex APK) and FEX-Emu comes from it instead of a download. Start the desktop again after installing it."
                font.family: Party.body; font.pixelSize: 15
                color: Party.text
                wrapMode: Text.WordWrap
            }
        }
        Text {
            text: "Otherwise it downloads from this folder. Each file is the folder's address plus its name (deskdroid-fex-arm64.tar.zst, deskdroid-x86-rootfs.tar.zst and their .sha256 files). For a host with one link per file, add NAME=LINK lines; NAME.sha256= also takes the checksum itself."
            font.family: Party.body; font.pixelSize: 14
            color: Party.textSoft
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            color: Party.panel
            border.color: source.activeFocus ? Party.cyan : Party.border
            border.width: 1
            QQC2.ScrollView {
                anchors.fill: parent
                anchors.margins: 6
                QQC2.TextArea {
                    id: source
                    text: backend.fexSource
                    placeholderText: backend.defaultFexSource
                    wrapMode: TextEdit.WrapAnywhere
                    font.family: "monospace"
                    font.pixelSize: 13
                    color: Party.text
                    background: null
                }
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: 12
            PartyButton {
                primary: true
                text: "Save"
                onClicked: {
                    backend.fexSource = source.text
                    applicationWindow().showPassiveNotification("Saved")
                    applicationWindow().pageStack.goBack()
                }
            }
            PartyButton {
                text: "Use the default"
                onClicked: { source.text = ""; backend.fexSource = "" }
            }
        }
    }
}
