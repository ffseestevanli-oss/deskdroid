import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property string cfg_avatarMode: "system"
    property string cfg_avatarModeDefault: "system"
    property string cfg_avatarPath: ""
    property string cfg_avatarPathDefault: ""

    FileDialog {
        id: picker
        title: i18n("Choose a profile picture")
        fileMode: FileDialog.OpenFile
        nameFilters: [i18n("Images (*.png *.jpg *.jpeg *.bmp *.webp *.gif *.svg)")]
        onAccepted: {
            page.cfg_avatarPath = selectedFile.toString()
            page.cfg_avatarMode = "custom"
        }
    }

    QQC2.ButtonGroup { id: modeGroup }

    Kirigami.FormLayout {
        QQC2.RadioButton {
            Kirigami.FormData.label: i18n("Picture source:")
            QQC2.ButtonGroup.group: modeGroup
            text: i18n("Use my account picture (set in System Settings → Users)")
            checked: page.cfg_avatarMode !== "custom"
            onToggled: if (checked) page.cfg_avatarMode = "system"
        }

        QQC2.RadioButton {
            QQC2.ButtonGroup.group: modeGroup
            text: i18n("Use a custom picture")
            checked: page.cfg_avatarMode === "custom"
            onToggled: if (checked) page.cfg_avatarMode = "custom"
        }

        RowLayout {
            enabled: page.cfg_avatarMode === "custom"
            QQC2.TextField {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 16
                readOnly: true
                text: page.cfg_avatarPath.replace("file://", "")
                placeholderText: i18n("No picture chosen")
            }
            QQC2.Button {
                text: i18n("Browse…")
                icon.name: "document-open"
                onClicked: picker.open()
            }
        }

        Rectangle {
            Kirigami.FormData.label: i18n("Preview:")
            implicitWidth: Kirigami.Units.iconSizes.huge
            implicitHeight: Kirigami.Units.iconSizes.huge
            color: "transparent"
            border.width: 2
            border.color: Kirigami.Theme.disabledTextColor

            Image {
                anchors.fill: parent
                anchors.margins: 2
                fillMode: Image.PreserveAspectCrop
                source: page.cfg_avatarMode === "custom" && page.cfg_avatarPath !== ""
                        ? page.cfg_avatarPath : ""
                visible: status === Image.Ready
            }
            Kirigami.Icon {
                anchors.fill: parent
                anchors.margins: 2
                source: "user-identity"
                visible: page.cfg_avatarMode !== "custom" || page.cfg_avatarPath === ""
            }
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("You can also click your picture in the start menu to choose a custom one.")
        }
    }
}
