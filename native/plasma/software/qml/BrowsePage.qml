// Software's main page: the catalog, A to Z, with a search field, what's
// installed and what has an update, and "Install from a file…" for .adpk
// packages.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."

PartyPage {
    id: page
    title: "Software"
    glows: [[0.05, 0.05, Party.cyan], [0.95, 0.95, Party.pink]]
    property string filter: ""
    property bool installedOnly: false

    readonly property var shown: backend.apps.filter(a => {
        if (page.installedOnly && (a.installed === null || a.installed === undefined)) return false
        const f = page.filter.trim().toLowerCase()
        return f === "" || (a.name + " " + a.summary + " " + a.id).toLowerCase().indexOf(f) >= 0
    })
    readonly property int updates: backend.apps.filter(a => a.installed !== null && a.installed !== undefined && !a.local && a.installed !== a.version).length

    ColumnLayout {
        spacing: 16
        width: Math.min(page.width - page.leftPadding - page.rightPadding, 980)
        x: Math.max(0, (page.width - page.leftPadding - page.rightPadding - width) / 2)

        RowLayout {
            Layout.fillWidth: true
            spacing: 16
            Image {
                source: "qrc:/icon.svg"
                sourceSize: Qt.size(112, 112)
                Layout.preferredWidth: 56
                Layout.preferredHeight: 56
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                RainbowText { heading: "Software"; size: 38; Layout.fillWidth: true }
                Text {
                    text: "Apps built for DeskDroid. Installed apps show up in the menu."
                    font.family: Party.body; font.pixelSize: 15
                    color: Party.textSoft
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 10
            QQC2.TextField {
                id: search
                width: Math.min(360, page.width - 80)
                height: 44
                placeholderText: "Search apps"
                font.family: Party.body
                font.pixelSize: 15
                color: Party.text
                leftPadding: 14
                onTextChanged: page.filter = text
                background: Chamfer {
                    cut: 10
                    fillColor: Party.surfaceDim
                    strokeColor: search.activeFocus ? Party.cyan : Party.border
                    strokeWidth: 1.5
                }
            }
            PartyButton {
                text: page.installedOnly ? "Showing installed" : "All apps"
                accent: page.installedOnly ? Party.green : Party.border
                onClicked: page.installedOnly = !page.installedOnly
            }
            PartyButton {
                text: "Install from a file…"
                accent: Party.purple
                onClicked: applicationWindow().chooseFile()
            }
            PartyButton {
                text: "Refresh"
                onClicked: backend.refresh()
            }
        }

        // Updates waiting.
        Text {
            visible: page.updates > 0
            text: "—  " + page.updates + (page.updates === 1 ? " UPDATE" : " UPDATES") + " READY  —"
            font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 14; font.letterSpacing: 3
            color: Party.yellow
        }

        // Problems and states.
        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: backend.error !== ""
            type: Kirigami.MessageType.Error
            text: backend.error
            showCloseButton: true
        }
        Text {
            visible: backend.offline || backend.catalogError !== "" || (backend.loading && backend.apps.length === 0)
            text: backend.offline
                ? "DeskDroid's app isn't answering. Software needs the DeskDroid app running behind the desktop; try again in a moment."
                : backend.catalogError !== ""
                    ? "Couldn't reach the Software catalog (" + backend.catalogError + "). Check the phone's internet connection, then Refresh." + (backend.apps.length ? " Showing what was there last time." : "")
                    : "Loading the catalog…"
            font.family: Party.body; font.pixelSize: 15
            color: backend.offline || backend.catalogError !== "" ? Party.orange : Party.muted
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        RainbowBar {
            visible: backend.loading && backend.apps.length === 0
            indeterminate: true
            Layout.fillWidth: true
        }

        Text {
            text: "—  " + (page.installedOnly ? "INSTALLED" : "ALL APPS") + "  ·  A TO Z  —"
            font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 14; font.letterSpacing: 3
            color: Party.cyan
            visible: backend.apps.length > 0
            Layout.topMargin: 6
        }
        Text {
            visible: backend.apps.length > 0 && page.shown.length === 0
            text: page.installedOnly && page.filter === "" ? "Nothing installed yet." : "No apps match \"" + page.filter + "\"."
            font.family: Party.body; font.pixelSize: 15
            color: Party.muted
        }
        Repeater {
            model: page.shown
            AppRow {
                Layout.fillWidth: true
                app: modelData
                progress: backend.busy[modelData.id]
            }
        }
    }
}
