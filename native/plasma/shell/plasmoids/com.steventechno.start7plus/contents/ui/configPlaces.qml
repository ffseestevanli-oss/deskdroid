import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property bool cfg_showDocuments: true
    property bool cfg_showDocumentsDefault: true
    property string cfg_iconDocuments: ""
    property string cfg_iconDocumentsDefault: ""
    property string cfg_pathDocuments: ""
    property string cfg_pathDocumentsDefault: ""
    property bool cfg_showPictures: true
    property bool cfg_showPicturesDefault: true
    property string cfg_iconPictures: ""
    property string cfg_iconPicturesDefault: ""
    property string cfg_pathPictures: ""
    property string cfg_pathPicturesDefault: ""
    property bool cfg_showMusic: true
    property bool cfg_showMusicDefault: true
    property string cfg_iconMusic: ""
    property string cfg_iconMusicDefault: ""
    property string cfg_pathMusic: ""
    property string cfg_pathMusicDefault: ""
    property bool cfg_showVideos: false
    property bool cfg_showVideosDefault: false
    property string cfg_iconVideos: ""
    property string cfg_iconVideosDefault: ""
    property string cfg_pathVideos: ""
    property string cfg_pathVideosDefault: ""
    property bool cfg_showDownloads: false
    property bool cfg_showDownloadsDefault: false
    property string cfg_iconDownloads: ""
    property string cfg_iconDownloadsDefault: ""
    property string cfg_pathDownloads: ""
    property string cfg_pathDownloadsDefault: ""
    property bool cfg_showComputer: true
    property bool cfg_showComputerDefault: true
    property string cfg_iconComputer: ""
    property string cfg_iconComputerDefault: ""
    property string cfg_pathComputer: ""
    property string cfg_pathComputerDefault: ""
    property bool cfg_showNetwork: true
    property bool cfg_showNetworkDefault: true
    property string cfg_iconNetwork: ""
    property string cfg_iconNetworkDefault: ""
    property string cfg_pathNetwork: ""
    property string cfg_pathNetworkDefault: ""
    property bool cfg_showTrash: false
    property bool cfg_showTrashDefault: false
    property string cfg_iconTrash: ""
    property string cfg_iconTrashDefault: ""
    property string cfg_pathTrash: ""
    property string cfg_pathTrashDefault: ""
    property bool cfg_showSettings: true
    property bool cfg_showSettingsDefault: true
    property string cfg_iconSettings: ""
    property string cfg_iconSettingsDefault: ""
    property bool cfg_showDevices: true
    property bool cfg_showDevicesDefault: true
    property string cfg_iconDevices: ""
    property string cfg_iconDevicesDefault: ""
    property bool cfg_showDefaults: true
    property bool cfg_showDefaultsDefault: true
    property string cfg_iconDefaults: ""
    property string cfg_iconDefaultsDefault: ""
    property bool cfg_showHelp: true
    property bool cfg_showHelpDefault: true
    property string cfg_iconHelp: ""
    property string cfg_iconHelpDefault: ""

    FileDialog {
        id: iconPicker
        property string key: ""
        title: i18n("Choose an icon image")
        fileMode: FileDialog.OpenFile
        nameFilters: [i18n("Images (*.png *.jpg *.jpeg *.bmp *.webp *.gif *.svg)")]
        onAccepted: page["cfg_icon" + key] = selectedFile.toString()
    }
    FolderDialog {
        id: folderPicker
        property string key: ""
        title: i18n("Choose the target folder")
        onAccepted: page["cfg_path" + key] = selectedFolder.toString()
    }

    ColumnLayout {
        spacing: Kirigami.Units.smallSpacing

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: Kirigami.Units.gridUnit * 36
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("Choose which entries appear on the right pane, set a custom icon for each (click the image), and point folders at another location, for example a different drive.")
        }

        RowLayout {
            Layout.fillWidth: true
            QQC2.Button {
                implicitWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing
                implicitHeight: implicitWidth
                display: QQC2.AbstractButton.IconOnly
                icon.name: page.cfg_iconDocuments === "" ? "folder-documents" : ""
                icon.source: page.cfg_iconDocuments
                icon.width: Kirigami.Units.iconSizes.smallMedium
                icon.height: Kirigami.Units.iconSizes.smallMedium
                onClicked: { iconPicker.key = "Documents"; iconPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose a custom icon")
            }
            QQC2.ToolButton {
                visible: page.cfg_iconDocuments !== ""
                icon.name: "edit-clear"
                onClicked: page.cfg_iconDocuments = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default icon")
            }
            QQC2.CheckBox {
                id: showDocumentsCheck
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                text: i18n("Documents")
                checked: page.cfg_showDocuments
                onToggled: page.cfg_showDocuments = checked
            }
            QQC2.TextField {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                readOnly: true
                text: page.cfg_pathDocuments !== "" ? page.cfg_pathDocuments.replace("file://", "") : i18n("(default location)")
                opacity: page.cfg_pathDocuments !== "" ? 1 : 0.6
            }
            QQC2.Button {
                icon.name: "document-open-folder"
                onClicked: { folderPicker.key = "Documents"; folderPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose the target folder")
            }
            QQC2.ToolButton {
                enabled: page.cfg_pathDocuments !== ""
                icon.name: "edit-undo"
                onClicked: page.cfg_pathDocuments = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default location")
            }
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Button {
                implicitWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing
                implicitHeight: implicitWidth
                display: QQC2.AbstractButton.IconOnly
                icon.name: page.cfg_iconPictures === "" ? "folder-pictures" : ""
                icon.source: page.cfg_iconPictures
                icon.width: Kirigami.Units.iconSizes.smallMedium
                icon.height: Kirigami.Units.iconSizes.smallMedium
                onClicked: { iconPicker.key = "Pictures"; iconPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose a custom icon")
            }
            QQC2.ToolButton {
                visible: page.cfg_iconPictures !== ""
                icon.name: "edit-clear"
                onClicked: page.cfg_iconPictures = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default icon")
            }
            QQC2.CheckBox {
                id: showPicturesCheck
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                text: i18n("Pictures")
                checked: page.cfg_showPictures
                onToggled: page.cfg_showPictures = checked
            }
            QQC2.TextField {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                readOnly: true
                text: page.cfg_pathPictures !== "" ? page.cfg_pathPictures.replace("file://", "") : i18n("(default location)")
                opacity: page.cfg_pathPictures !== "" ? 1 : 0.6
            }
            QQC2.Button {
                icon.name: "document-open-folder"
                onClicked: { folderPicker.key = "Pictures"; folderPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose the target folder")
            }
            QQC2.ToolButton {
                enabled: page.cfg_pathPictures !== ""
                icon.name: "edit-undo"
                onClicked: page.cfg_pathPictures = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default location")
            }
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Button {
                implicitWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing
                implicitHeight: implicitWidth
                display: QQC2.AbstractButton.IconOnly
                icon.name: page.cfg_iconMusic === "" ? "folder-music" : ""
                icon.source: page.cfg_iconMusic
                icon.width: Kirigami.Units.iconSizes.smallMedium
                icon.height: Kirigami.Units.iconSizes.smallMedium
                onClicked: { iconPicker.key = "Music"; iconPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose a custom icon")
            }
            QQC2.ToolButton {
                visible: page.cfg_iconMusic !== ""
                icon.name: "edit-clear"
                onClicked: page.cfg_iconMusic = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default icon")
            }
            QQC2.CheckBox {
                id: showMusicCheck
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                text: i18n("Music")
                checked: page.cfg_showMusic
                onToggled: page.cfg_showMusic = checked
            }
            QQC2.TextField {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                readOnly: true
                text: page.cfg_pathMusic !== "" ? page.cfg_pathMusic.replace("file://", "") : i18n("(default location)")
                opacity: page.cfg_pathMusic !== "" ? 1 : 0.6
            }
            QQC2.Button {
                icon.name: "document-open-folder"
                onClicked: { folderPicker.key = "Music"; folderPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose the target folder")
            }
            QQC2.ToolButton {
                enabled: page.cfg_pathMusic !== ""
                icon.name: "edit-undo"
                onClicked: page.cfg_pathMusic = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default location")
            }
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Button {
                implicitWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing
                implicitHeight: implicitWidth
                display: QQC2.AbstractButton.IconOnly
                icon.name: page.cfg_iconVideos === "" ? "folder-videos" : ""
                icon.source: page.cfg_iconVideos
                icon.width: Kirigami.Units.iconSizes.smallMedium
                icon.height: Kirigami.Units.iconSizes.smallMedium
                onClicked: { iconPicker.key = "Videos"; iconPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose a custom icon")
            }
            QQC2.ToolButton {
                visible: page.cfg_iconVideos !== ""
                icon.name: "edit-clear"
                onClicked: page.cfg_iconVideos = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default icon")
            }
            QQC2.CheckBox {
                id: showVideosCheck
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                text: i18n("Videos")
                checked: page.cfg_showVideos
                onToggled: page.cfg_showVideos = checked
            }
            QQC2.TextField {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                readOnly: true
                text: page.cfg_pathVideos !== "" ? page.cfg_pathVideos.replace("file://", "") : i18n("(default location)")
                opacity: page.cfg_pathVideos !== "" ? 1 : 0.6
            }
            QQC2.Button {
                icon.name: "document-open-folder"
                onClicked: { folderPicker.key = "Videos"; folderPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose the target folder")
            }
            QQC2.ToolButton {
                enabled: page.cfg_pathVideos !== ""
                icon.name: "edit-undo"
                onClicked: page.cfg_pathVideos = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default location")
            }
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Button {
                implicitWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing
                implicitHeight: implicitWidth
                display: QQC2.AbstractButton.IconOnly
                icon.name: page.cfg_iconDownloads === "" ? "folder-download" : ""
                icon.source: page.cfg_iconDownloads
                icon.width: Kirigami.Units.iconSizes.smallMedium
                icon.height: Kirigami.Units.iconSizes.smallMedium
                onClicked: { iconPicker.key = "Downloads"; iconPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose a custom icon")
            }
            QQC2.ToolButton {
                visible: page.cfg_iconDownloads !== ""
                icon.name: "edit-clear"
                onClicked: page.cfg_iconDownloads = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default icon")
            }
            QQC2.CheckBox {
                id: showDownloadsCheck
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                text: i18n("Downloads")
                checked: page.cfg_showDownloads
                onToggled: page.cfg_showDownloads = checked
            }
            QQC2.TextField {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                readOnly: true
                text: page.cfg_pathDownloads !== "" ? page.cfg_pathDownloads.replace("file://", "") : i18n("(default location)")
                opacity: page.cfg_pathDownloads !== "" ? 1 : 0.6
            }
            QQC2.Button {
                icon.name: "document-open-folder"
                onClicked: { folderPicker.key = "Downloads"; folderPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose the target folder")
            }
            QQC2.ToolButton {
                enabled: page.cfg_pathDownloads !== ""
                icon.name: "edit-undo"
                onClicked: page.cfg_pathDownloads = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default location")
            }
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Button {
                implicitWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing
                implicitHeight: implicitWidth
                display: QQC2.AbstractButton.IconOnly
                icon.name: page.cfg_iconComputer === "" ? "computer" : ""
                icon.source: page.cfg_iconComputer
                icon.width: Kirigami.Units.iconSizes.smallMedium
                icon.height: Kirigami.Units.iconSizes.smallMedium
                onClicked: { iconPicker.key = "Computer"; iconPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose a custom icon")
            }
            QQC2.ToolButton {
                visible: page.cfg_iconComputer !== ""
                icon.name: "edit-clear"
                onClicked: page.cfg_iconComputer = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default icon")
            }
            QQC2.CheckBox {
                id: showComputerCheck
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                text: i18n("Computer")
                checked: page.cfg_showComputer
                onToggled: page.cfg_showComputer = checked
            }
            QQC2.TextField {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                readOnly: true
                text: page.cfg_pathComputer !== "" ? page.cfg_pathComputer.replace("file://", "") : i18n("(default location)")
                opacity: page.cfg_pathComputer !== "" ? 1 : 0.6
            }
            QQC2.Button {
                icon.name: "document-open-folder"
                onClicked: { folderPicker.key = "Computer"; folderPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose the target folder")
            }
            QQC2.ToolButton {
                enabled: page.cfg_pathComputer !== ""
                icon.name: "edit-undo"
                onClicked: page.cfg_pathComputer = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default location")
            }
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Button {
                implicitWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing
                implicitHeight: implicitWidth
                display: QQC2.AbstractButton.IconOnly
                icon.name: page.cfg_iconNetwork === "" ? "network-workgroup" : ""
                icon.source: page.cfg_iconNetwork
                icon.width: Kirigami.Units.iconSizes.smallMedium
                icon.height: Kirigami.Units.iconSizes.smallMedium
                onClicked: { iconPicker.key = "Network"; iconPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose a custom icon")
            }
            QQC2.ToolButton {
                visible: page.cfg_iconNetwork !== ""
                icon.name: "edit-clear"
                onClicked: page.cfg_iconNetwork = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default icon")
            }
            QQC2.CheckBox {
                id: showNetworkCheck
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                text: i18n("Network")
                checked: page.cfg_showNetwork
                onToggled: page.cfg_showNetwork = checked
            }
            QQC2.TextField {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                readOnly: true
                text: page.cfg_pathNetwork !== "" ? page.cfg_pathNetwork.replace("file://", "") : i18n("(default location)")
                opacity: page.cfg_pathNetwork !== "" ? 1 : 0.6
            }
            QQC2.Button {
                icon.name: "document-open-folder"
                onClicked: { folderPicker.key = "Network"; folderPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose the target folder")
            }
            QQC2.ToolButton {
                enabled: page.cfg_pathNetwork !== ""
                icon.name: "edit-undo"
                onClicked: page.cfg_pathNetwork = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default location")
            }
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Button {
                implicitWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing
                implicitHeight: implicitWidth
                display: QQC2.AbstractButton.IconOnly
                icon.name: page.cfg_iconTrash === "" ? "user-trash" : ""
                icon.source: page.cfg_iconTrash
                icon.width: Kirigami.Units.iconSizes.smallMedium
                icon.height: Kirigami.Units.iconSizes.smallMedium
                onClicked: { iconPicker.key = "Trash"; iconPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose a custom icon")
            }
            QQC2.ToolButton {
                visible: page.cfg_iconTrash !== ""
                icon.name: "edit-clear"
                onClicked: page.cfg_iconTrash = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default icon")
            }
            QQC2.CheckBox {
                id: showTrashCheck
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                text: i18n("Trash")
                checked: page.cfg_showTrash
                onToggled: page.cfg_showTrash = checked
            }
            QQC2.TextField {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 14
                readOnly: true
                text: page.cfg_pathTrash !== "" ? page.cfg_pathTrash.replace("file://", "") : i18n("(default location)")
                opacity: page.cfg_pathTrash !== "" ? 1 : 0.6
            }
            QQC2.Button {
                icon.name: "document-open-folder"
                onClicked: { folderPicker.key = "Trash"; folderPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose the target folder")
            }
            QQC2.ToolButton {
                enabled: page.cfg_pathTrash !== ""
                icon.name: "edit-undo"
                onClicked: page.cfg_pathTrash = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default location")
            }
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Button {
                implicitWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing
                implicitHeight: implicitWidth
                display: QQC2.AbstractButton.IconOnly
                icon.name: page.cfg_iconSettings === "" ? "preferences-system" : ""
                icon.source: page.cfg_iconSettings
                icon.width: Kirigami.Units.iconSizes.smallMedium
                icon.height: Kirigami.Units.iconSizes.smallMedium
                onClicked: { iconPicker.key = "Settings"; iconPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose a custom icon")
            }
            QQC2.ToolButton {
                visible: page.cfg_iconSettings !== ""
                icon.name: "edit-clear"
                onClicked: page.cfg_iconSettings = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default icon")
            }
            QQC2.CheckBox {
                id: showSettingsCheck
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                text: i18n("System Settings")
                checked: page.cfg_showSettings
                onToggled: page.cfg_showSettings = checked
            }
            QQC2.Label {
                opacity: 0.6
                text: i18n("(opens System Settings)")
            }
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Button {
                implicitWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing
                implicitHeight: implicitWidth
                display: QQC2.AbstractButton.IconOnly
                icon.name: page.cfg_iconDevices === "" ? "printer" : ""
                icon.source: page.cfg_iconDevices
                icon.width: Kirigami.Units.iconSizes.smallMedium
                icon.height: Kirigami.Units.iconSizes.smallMedium
                onClicked: { iconPicker.key = "Devices"; iconPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose a custom icon")
            }
            QQC2.ToolButton {
                visible: page.cfg_iconDevices !== ""
                icon.name: "edit-clear"
                onClicked: page.cfg_iconDevices = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default icon")
            }
            QQC2.CheckBox {
                id: showDevicesCheck
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                text: i18n("Printers")
                checked: page.cfg_showDevices
                onToggled: page.cfg_showDevices = checked
            }
            QQC2.Label {
                opacity: 0.6
                text: i18n("(opens Printers)")
            }
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Button {
                implicitWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing
                implicitHeight: implicitWidth
                display: QQC2.AbstractButton.IconOnly
                icon.name: page.cfg_iconDefaults === "" ? "preferences-desktop-default-applications" : ""
                icon.source: page.cfg_iconDefaults
                icon.width: Kirigami.Units.iconSizes.smallMedium
                icon.height: Kirigami.Units.iconSizes.smallMedium
                onClicked: { iconPicker.key = "Defaults"; iconPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose a custom icon")
            }
            QQC2.ToolButton {
                visible: page.cfg_iconDefaults !== ""
                icon.name: "edit-clear"
                onClicked: page.cfg_iconDefaults = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default icon")
            }
            QQC2.CheckBox {
                id: showDefaultsCheck
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                text: i18n("Default Programs")
                checked: page.cfg_showDefaults
                onToggled: page.cfg_showDefaults = checked
            }
            QQC2.Label {
                opacity: 0.6
                text: i18n("(opens Default Programs)")
            }
        }
        RowLayout {
            Layout.fillWidth: true
            QQC2.Button {
                implicitWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.largeSpacing
                implicitHeight: implicitWidth
                display: QQC2.AbstractButton.IconOnly
                icon.name: page.cfg_iconHelp === "" ? "help-browser" : ""
                icon.source: page.cfg_iconHelp
                icon.width: Kirigami.Units.iconSizes.smallMedium
                icon.height: Kirigami.Units.iconSizes.smallMedium
                onClicked: { iconPicker.key = "Help"; iconPicker.open() }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose a custom icon")
            }
            QQC2.ToolButton {
                visible: page.cfg_iconHelp !== ""
                icon.name: "edit-clear"
                onClicked: page.cfg_iconHelp = ""
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Use the default icon")
            }
            QQC2.CheckBox {
                id: showHelpCheck
                Layout.preferredWidth: Kirigami.Units.gridUnit * 11
                text: i18n("Help and Support")
                checked: page.cfg_showHelp
                onToggled: page.cfg_showHelp = checked
            }
            QQC2.Label {
                opacity: 0.6
                text: i18n("(opens Help and Support)")
            }
        }
    }
}
