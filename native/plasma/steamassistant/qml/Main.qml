// The Steam Installation Assistant's window: the guide (Welcome, then the
// install) until Steam is set up or skipped, then the tools.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import "."

Kirigami.ApplicationWindow {
    id: root
    title: "Steam Installation Assistant"
    width: 980
    height: 720
    minimumWidth: 420
    minimumHeight: 480
    color: Party.bg
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.ToolBar
    pageStack.globalToolBar.showNavigationButtons: Kirigami.ApplicationHeaderStyle.ShowBackButton
    pageStack.defaultColumnWidth: width
    font.family: Party.body
    // Dialogs, text fields and the header follow the party colors too,
    // whatever the desktop's color scheme is.
    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.backgroundColor: Party.surface
    Kirigami.Theme.alternateBackgroundColor: Party.card
    Kirigami.Theme.textColor: Party.text
    Kirigami.Theme.disabledTextColor: Party.dim
    Kirigami.Theme.highlightColor: Party.pink
    Kirigami.Theme.highlightedTextColor: Party.bg
    Kirigami.Theme.hoverColor: Party.cyan
    Kirigami.Theme.focusColor: Party.cyan
    Kirigami.Theme.linkColor: Party.cyan
    Kirigami.Theme.positiveTextColor: Party.green
    Kirigami.Theme.neutralTextColor: Party.yellow
    Kirigami.Theme.negativeTextColor: Party.red
    palette.window: Party.surface
    palette.windowText: Party.text
    palette.base: Party.panel
    palette.alternateBase: Party.card
    palette.text: Party.text
    palette.button: Party.surface
    palette.buttonText: Party.text
    palette.highlight: Party.pink
    palette.highlightedText: Party.bg
    palette.placeholderText: Party.dim
    palette.mid: Party.border
    palette.dark: Party.panel
    palette.light: Party.borderSoft

    // The 4 px rainbow line at the top of every screen.
    Rectangle {
        parent: root.overlay
        z: 1000
        anchors.top: parent ? parent.top : undefined
        width: root.width
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

    Component { id: welcomePage; WelcomePage {} }
    Component { id: installPage; InstallPage {} }
    Component { id: toolsPage; ToolsPage {} }

    // "Install from a .zip": FEX-Emu (and maybe the x86 system) from a file
    // on the phone, fex/zip.sh's. Then the install, when asked.
    property bool installAfterZip: false
    function chooseZip(install) { installAfterZip = install; zipDialog.open() }
    FileDialog {
        id: zipDialog
        title: "Choose the FEX .zip"
        nameFilters: ["FEX .zip (*.zip)", "All files (*)"]
        currentFolder: "file:///storage/emulated/0/Download"
        onAccepted: {
            backend.fexZip = selectedFile.toString()
            root.showPassiveNotification("FEX-Emu will install from " + backend.fexZip.split("/").pop())
            if (root.installAfterZip) {
                backend.skipped = false
                root.showInstall(true)
            }
        }
    }

    function showWelcome() { pageStack.clear(); pageStack.push(welcomePage) }
    function showInstall(autoStart) { pageStack.clear(); pageStack.push(installPage, { autoStart: autoStart }) }
    function showTools() { pageStack.clear(); pageStack.push(toolsPage) }

    Component.onCompleted: {
        backend.refresh()
        if (startOnTools || (backend.fexReady && backend.steamReady) || backend.skipped)
            showTools()
        else
            showWelcome()
    }
}
