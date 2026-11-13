// Software's window: the catalog (BrowsePage), an .adpk to install
// (PackagePage) when Software was opened with one, or a .flatpakref,
// .flatpakrepo or .flatpak (FlatpakFilePage). A Flathub app's page
// (FlathubAppPage) opens over the catalog.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import "."

Kirigami.ApplicationWindow {
    id: root
    title: "Agora"
    width: 1000
    height: 720
    minimumWidth: 420
    minimumHeight: 480
    color: Party.bg
    pageStack.globalToolBar.style: Kirigami.ApplicationHeaderStyle.None
    pageStack.defaultColumnWidth: width
    font.family: Party.body
    // The party colors, whatever the desktop's color scheme is (as the Steam
    // Installation Assistant does).
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

    Component { id: browsePage; BrowsePage {} }
    Component { id: packagePage; PackagePage {} }
    Component { id: flathubAppPage; FlathubAppPage {} }
    Component { id: flatpakFilePage; FlatpakFilePage {} }

    function showPackage(path) {
        backend.inspect(path)
        pageStack.clear()
        pageStack.push(packagePage, { path: path })
    }
    function showFlatpakFile(path) {
        backend.inspectFlatpakFile(path)
        pageStack.clear()
        pageStack.push(flatpakFilePage, { path: path })
    }
    function showFlathubApp(hit) {
        pageStack.push(flathubAppPage, { hit: hit })
    }
    function back() {
        if (pageStack.depth > 1) pageStack.pop()
        else showBrowse()
    }
    function openFile(path) {
        if (backend.isFlatpakFile(path)) showFlatpakFile(path)
        else showPackage(path)
    }
    function showBrowse() {
        if (backend.package.path) backend.dismiss()
        pageStack.clear()
        pageStack.push(browsePage)
    }
    function chooseFile() { fileDialog.open() }

    FileDialog {
        id: fileDialog
        title: "Choose a package"
        nameFilters: ["Packages (*.adpk *.flatpakref *.flatpakrepo *.flatpak)", "DeskDroid packages (*.adpk)",
                      "Flatpak files (*.flatpakref *.flatpakrepo *.flatpak)", "All files (*)"]
        currentFolder: "file:///storage/emulated/0/Download"
        onAccepted: root.openFile(backend.localPath(selectedFile.toString()))
    }

    Component.onCompleted: startFlatpakFile ? showFlatpakFile(startFlatpakFile)
        : startPackage ? showPackage(startPackage) : showBrowse()
}
