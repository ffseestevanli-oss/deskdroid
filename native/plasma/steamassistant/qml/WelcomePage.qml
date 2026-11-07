// Page 1: what this is, and the choice.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."

PartyPage {
    id: page
    title: "Welcome"
    glows: [[0.08, 0.04, Party.pink], [0.98, 0.95, Party.purple], [0.9, 0.1, Party.cyan]]

    ColumnLayout {
        spacing: 22
        width: Math.min(page.width - page.leftPadding - page.rightPadding, 760)
        x: Math.max(0, (page.width - page.leftPadding - page.rightPadding - width) / 2)

        Item { Layout.preferredHeight: 4 }
        Text {
            text: "STEP 1 / 2  ·  STEAM INSTALLATION ASSISTANT"
            font.family: Party.body; font.weight: Font.Bold; font.pixelSize: 13; font.letterSpacing: 3
            color: Party.pink
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
        RainbowText {
            heading: "Welcome to DeskDroid's Steam Installation Assistant!"
            size: page.width < 640 ? 26 : 34
            Layout.fillWidth: true
        }
        Text {
            text: "Steam does not come pre-installed due to the nature of how Steam works and your phone's hardware differences. I will do a lot of the heavy lifting to get Steam running for you!"
            font.family: Party.body; font.pixelSize: 17
            color: Party.textSoft
            wrapMode: Text.WordWrap
            lineHeight: 1.2
            Layout.fillWidth: true
        }

        // The "how it works" panel, with a colored bar on the left.
        Item {
            Layout.fillWidth: true
            implicitHeight: fexText.implicitHeight + 32
            Chamfer {
                anchors.fill: parent
                cut: 12
                cutTopLeft: false
                fillColor: Party.surface
            }
            Rectangle { width: 3; height: parent.height; color: Party.cyan }
            Text {
                id: fexText
                anchors.fill: parent
                anchors.margins: 16
                anchors.leftMargin: 20
                textFormat: Text.StyledText
                text: "Steam will make use of a compatibility layer, <b><font color=\"" + Party.cyan + "\">FEX-Emu</font></b>, which will \"train\" your phone on how to mimic the architecture that a desktop or laptop computer uses."
                font.family: Party.body; font.pixelSize: 16
                color: Party.text
                wrapMode: Text.WordWrap
                lineHeight: 1.2
            }
        }

        Text {
            text: "Here, we will work together getting Steam up and running on your phone: the computer that's in your pocket! So, what are we doing?"
            font.family: Party.body; font.pixelSize: 17
            color: Party.textSoft
            wrapMode: Text.WordWrap
            lineHeight: 1.2
            Layout.fillWidth: true
        }

        Flow {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 14
            PartyButton {
                primary: true
                text: "Set up Steam"
                onClicked: {
                    backend.skipped = false
                    applicationWindow().showInstall(true)
                }
            }
            PartyButton {
                text: "Continue without Steam"
                accent: Party.border
                implicitHeight: 56
                onClicked: {
                    backend.skipped = true
                    applicationWindow().showTools()
                }
            }
        }
        Text {
            text: "About 1.2 GB to download and 4 GB on your phone for FEX-Emu and its x86 system, then Steam itself. Continuing without Steam takes you straight to the tools; you can set Steam up from there any time."
            font.family: Party.body; font.pixelSize: 13
            color: Party.dim
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}
