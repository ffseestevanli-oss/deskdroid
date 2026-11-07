// After the install (or "Continue without Steam"): the maintenance tools, in
// the phone app's grid.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "."

PartyPage {
    id: page
    title: "Steam Installation Assistant"
    glows: [[0.0, 0.0, Party.pink], [1.0, 0.45, Party.cyan], [0.2, 1.0, Party.purple]]

    readonly property bool installed: backend.fexReady && backend.steamReady
    readonly property int columns: content.width >= 760 ? 4 : content.width >= 380 ? 2 : 1
    property string pendingTool: ""
    property string toolMessage: ""

    Component.onCompleted: {
        backend.refresh()
        // "Welcome back" greets the first visit after Steam was installed.
        if (installed && !backend.welcomedBack) greeting.visible = true
        if (installed) backend.welcomedBack = true
    }

    Connections {
        target: backend
        function onFinished(ok, message) {
            if (page.pendingTool === "") return
            const tool = page.pendingTool
            page.pendingTool = ""
            applicationWindow().showPassiveNotification(ok ? (message || "Done") : ("Didn't work: " + (message || tool)), "long")
            backend.refresh()
            if (ok && tool === "purge") applicationWindow().showWelcome()
        }
    }

    function tool(name) {
        page.pendingTool = name
        backend.runTool(name)
    }
    function confirm(title, text, action, danger) {
        confirmDialog.title = title
        confirmDialog.text = text
        confirmDialog.choices = [{ text: danger === true ? "Yes, do it" : "Continue", accent: danger === true ? Party.red : Party.cyan, run: action }]
        confirmDialog.open()
    }

    PartyDialog { id: confirmDialog }

    PartyDialog {
        id: uninstallDialog
        title: "Uninstall Steam"
        text: "Uninstall removes Steam and its games from this machine… er, device. FEX-Emu and its x86 system stay for your other x86 apps.\n\nPurge also removes FEX-Emu and the x86 system (about 4 GB) and resets this assistant to its first page."
        choices: [
            { text: "Uninstall Steam", accent: Party.red, run: function () { page.tool("uninstall") } },
            { text: "Purge everything", accent: Party.red, run: function () { page.tool("purge") } }
        ]
    }

    FileDialog {
        id: x86Dialog
        title: "Run a desktop (x86-64) application"
        currentFolder: "file://" + backend.steamDir().replace(/\/\.local\/share\/Steam$/, "")
        nameFilters: ["Linux programs (*.x86_64 *.x86 *.bin *.sh *.AppImage *)", "All files (*)"]
        onAccepted: {
            backend.runX86(selectedFile.toString())
            applicationWindow().showPassiveNotification("Starting it through FEX-Emu… (log: x86/apps.log)", "long")
        }
    }
    FileDialog {
        id: windowsDialog
        title: "Run a Windows (x86-64) application"
        currentFolder: "file://" + backend.steamDir().replace(/\/\.local\/share\/Steam$/, "")
        nameFilters: ["Windows programs (*.exe *.msi *.bat)", "All files (*)"]
        onAccepted: {
            backend.runWindows(selectedFile.toString())
            applicationWindow().showPassiveNotification("Starting it with Proton through FEX-Emu… (log: x86/apps.log)", "long")
        }
    }

    ColumnLayout {
        id: content
        spacing: 18
        width: Math.min(page.width - page.leftPadding - page.rightPadding, 1040)
        x: Math.max(0, (page.width - page.leftPadding - page.rightPadding - width) / 2)

        Item { Layout.preferredHeight: 4 }
        Text {
            text: page.installed ? "MAINTENANCE  ·  STEAM IS INSTALLED" : backend.skipped ? "MAINTENANCE  ·  WITHOUT STEAM" : "MAINTENANCE"
            font.family: Party.body; font.weight: Font.Bold; font.pixelSize: 13; font.letterSpacing: 3
            color: page.installed ? Party.green : Party.pink
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
        RainbowText {
            id: greeting
            visible: false
            heading: "Ah! Welcome back! You've unlocked new options!"
            size: page.width < 640 ? 24 : 32
            Layout.fillWidth: true
        }
        RainbowText {
            visible: !greeting.visible
            heading: page.installed ? "Steam & FEX-Emu tools" : "Tools"
            size: page.width < 640 ? 24 : 32
            Layout.fillWidth: true
        }

        // Steam isn't set up (skipped, uninstalled, or the install stopped).
        Item {
            visible: !page.installed
            Layout.fillWidth: true
            implicitHeight: notSet.implicitHeight + 32
            Chamfer { anchors.fill: parent; cut: 12; cutTopLeft: false; fillColor: Party.surface }
            Rectangle { width: 3; height: parent.height; color: Party.yellow }
            RowLayout {
                id: notSet
                anchors.fill: parent
                anchors.margins: 16
                anchors.leftMargin: 20
                spacing: 16
                Text {
                    text: backend.fexReady
                        ? "FEX-Emu is ready, Steam isn't installed. The FEX tools work; Steam's unlock once it's set up."
                        : "Steam and FEX-Emu aren't set up yet, so these tools are locked. Setting up Steam installs FEX-Emu too."
                    font.family: Party.body; font.pixelSize: 15
                    color: Party.text
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
                PartyButton {
                    primary: true
                    text: "Set up Steam"
                    onClicked: { backend.skipped = false; applicationWindow().showInstall(true) }
                }
            }
        }

        Flow {
            visible: page.installed
            Layout.fillWidth: true
            spacing: 14
            PartyButton {
                primary: true
                text: "Launch Steam"
                onClicked: {
                    backend.launchSteam()
                    applicationWindow().showPassiveNotification("Starting Steam… the first start updates it, which takes a while", "long")
                }
            }
            PartyButton {
                text: "Big Picture"
                accent: Party.purple
                implicitHeight: 56
                onClicked: backend.launchSteam("steam://open/bigpicture")
            }
        }

        // -- FEX Tools --
        Text {
            text: "—  FEX TOOLS  —"
            font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 15; font.letterSpacing: 3
            color: Party.cyan
            Layout.topMargin: 10
        }
        GridLayout {
            Layout.fillWidth: true
            columns: page.columns
            columnSpacing: 12
            rowSpacing: 12
            Tile {
                Layout.fillWidth: true
                text: "Manage Proton"
                subtitle: "Wine prefixes: open, configure or delete them"
                iconName: "wine"
                accent: Party.purple
                enabled: backend.fexReady
                lockedText: "Needs FEX-Emu"
                onClicked: applicationWindow().pageStack.push(Qt.resolvedUrl("PrefixesPage.qml"))
            }
            Tile {
                Layout.fillWidth: true
                text: "Run a Desktop (x86-64) application"
                subtitle: "A Linux program built for PCs"
                iconName: "application-x-executable"
                accent: Party.cyan
                enabled: backend.fexReady
                lockedText: "Needs FEX-Emu"
                onClicked: x86Dialog.open()
            }
            Tile {
                Layout.fillWidth: true
                text: "Run a Windows (x86-64) application"
                subtitle: backend.hasProton() ? "An .exe through Proton" : "Needs Proton from Steam (Library › Tools)"
                iconName: "application-x-ms-dos-executable"
                accent: Party.green
                enabled: backend.fexReady
                lockedText: "Needs FEX-Emu"
                onClicked: windowsDialog.open()
            }
            Tile {
                Layout.fillWidth: true
                text: "Manage Software"
                subtitle: "Add/Remove Programs: games and Windows apps"
                iconName: "applications-other"
                accent: Party.yellow
                enabled: backend.fexReady
                lockedText: "Needs FEX-Emu"
                onClicked: applicationWindow().pageStack.push(Qt.resolvedUrl("SoftwarePage.qml"))
            }
        }

        // -- Steam Tools --
        Text {
            text: "—  STEAM TOOLS  —"
            font.family: Party.heading; font.weight: Font.Black; font.pixelSize: 15; font.letterSpacing: 3
            color: Party.pink
            Layout.topMargin: 10
        }
        GridLayout {
            Layout.fillWidth: true
            columns: page.columns
            columnSpacing: 12
            rowSpacing: 12
            enabled: !backend.busy
            Tile {
                Layout.fillWidth: true
                text: "Force Steam Update"
                subtitle: "Download Steam's client again at its next start"
                iconName: "system-software-update"
                accent: Party.cyan
                enabled: backend.steamReady
                lockedText: "Steam isn't installed"
                onClicked: page.confirm("Force Steam Update", "Steam downloads its whole client again the next time it starts. Your games and sign-in stay.", function () { page.tool("update") })
            }
            Tile {
                Layout.fillWidth: true
                text: "Soft Reset"
                subtitle: "Clears out sign-ins"
                iconName: "system-switch-user"
                accent: Party.yellow
                enabled: backend.steamReady
                lockedText: "Steam isn't installed"
                onClicked: page.confirm("Soft Reset", "Signs every account out of Steam on this phone and forgets them. Games stay installed.", function () { page.tool("soft-reset") })
            }
            Tile {
                Layout.fillWidth: true
                text: "Hard Reset"
                subtitle: "Clears out Steam's folders (keeps games)"
                iconName: "edit-clear-all"
                accent: Party.orange
                enabled: backend.steamReady && backend.fexReady
                lockedText: "Steam isn't installed"
                onClicked: page.confirm("Hard Reset", "Deletes Steam's own folders and settings and puts its bootstrap back, like Steam's --reset. Installed games and your userdata stay. Steam downloads its client again next start.", function () { page.tool("hard-reset") }, true)
            }
            Tile {
                Layout.fillWidth: true
                text: "Uninstall"
                subtitle: "Removes Steam from this machine… er, device"
                iconName: "edit-delete"
                accent: Party.red
                enabled: backend.steamReady || backend.fexReady
                lockedText: "Nothing to uninstall"
                onClicked: uninstallDialog.open()
            }
        }

        // Busy with a tool.
        RowLayout {
            visible: backend.busy && page.pendingTool !== ""
            Layout.fillWidth: true
            spacing: 12
            QQC2.BusyIndicator { running: parent.visible; Layout.preferredWidth: 32; Layout.preferredHeight: 32 }
            Text {
                text: "Working on it…"
                font.family: Party.body; font.pixelSize: 15
                color: Party.textSoft
            }
        }

        // Settings and the escape hatch.
        Flow {
            Layout.fillWidth: true
            Layout.topMargin: 14
            spacing: 12
            PartyButton {
                text: "Download from…"
                accent: Party.cyan
                onClicked: applicationWindow().pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
            }
            PartyButton {
                visible: backend.fexReady && !backend.steamReady
                text: "Set up Steam"
                accent: Party.pink
                onClicked: { backend.skipped = false; applicationWindow().showInstall(true) }
            }
            PartyButton {
                visible: backend.fexReady || backend.steamReady || backend.skipped
                text: "Purge Steam (start over)"
                accent: Party.red
                onClicked: page.confirm("Purge Steam", "Removes Steam, its games, FEX-Emu and the x86 system, and resets this assistant to its first page.", function () {
                    if (backend.fexReady || backend.steamReady) page.tool("purge")
                    else { backend.skipped = false; applicationWindow().showWelcome() }
                }, true)
            }
        }
    }
}
