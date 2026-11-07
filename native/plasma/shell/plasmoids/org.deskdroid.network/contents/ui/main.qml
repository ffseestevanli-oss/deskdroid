// The phone's connection in the system tray: Wi-Fi or mobile signal, wired,
// or offline. DeskDroid writes it to files/status.json (PhoneStatus.kt);
// the popup shows its details and opens the phone's own network settings,
// since Android, not the desktop, manages the connection.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.private.kicker as Kicker
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Status { id: status }
    Kicker.ProcessRunner { id: runner }

    readonly property var net: status.valid && status.data.network ? status.data.network : null
    readonly property string type: net ? net.type : "none"
    readonly property int level: net ? net.level : -1
    readonly property bool online: net ? net.internet : false
    readonly property bool airplane: net ? net.airplane : false

    readonly property string iconName: {
        if (!net) return "network-offline"
        if (type === "none") return airplane ? "network-flightmode-on" : "network-offline"
        if (type === "wifi") return level < 0 ? "network-wireless-connected-100"
            : ["network-wireless-connected-00", "network-wireless-connected-25", "network-wireless-connected-50",
               "network-wireless-connected-75", "network-wireless-connected-100"][level]
        if (type === "mobile") return "network-mobile-" + (level < 0 ? 100 : [0, 20, 40, 80, 100][level])
        if (type === "vpn") return "network-vpn"
        return "network-wired"
    }
    readonly property string title: {
        if (!net) return "Network"
        switch (type) {
        case "wifi": return "Wi-Fi"
        case "mobile": return "Mobile data"
        case "ethernet": return "Wired (Ethernet or USB)"
        case "bluetooth": return "Bluetooth tethering"
        case "vpn": return "VPN"
        case "none": return airplane ? "Airplane mode" : "Not connected"
        default: return "Connected"
        }
    }
    readonly property string signalText: level < 0 ? "" : ["No signal", "Weak signal", "Fair signal", "Good signal", "Excellent signal"][level]
    readonly property string stateText: !net || type === "none" ? "No connection"
        : (online ? "Connected to the internet" : "Connected, no internet") + (signalText ? " · " + signalText : "")

    function speed(kbps) {
        return kbps >= 1000 ? (kbps / 1000).toFixed(kbps >= 10000 ? 0 : 1) + " Mbit/s" : kbps + " kbit/s"
    }

    Plasmoid.icon: iconName
    toolTipMainText: title
    toolTipSubText: stateText
    preferredRepresentation: compactRepresentation

    compactRepresentation: MouseArea {
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded
        Kirigami.Icon {
            anchors.fill: parent
            source: root.iconName
            active: parent.containsMouse
        }
    }

    fullRepresentation: ColumnLayout {
        spacing: Kirigami.Units.largeSpacing
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.preferredWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: implicitHeight
        Layout.preferredHeight: implicitHeight

        RowLayout {
            spacing: Kirigami.Units.largeSpacing
            Layout.margins: Kirigami.Units.largeSpacing
            Kirigami.Icon {
                source: root.iconName
                Layout.preferredWidth: Kirigami.Units.iconSizes.large
                Layout.preferredHeight: Kirigami.Units.iconSizes.large
            }
            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                Kirigami.Heading { level: 2; text: root.title }
                PlasmaComponents3.Label {
                    text: root.stateText
                    opacity: 0.75
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }
        GridLayout {
            visible: root.net !== null && root.type !== "none"
            columns: 2
            columnSpacing: Kirigami.Units.largeSpacing
            Layout.leftMargin: Kirigami.Units.largeSpacing
            Layout.rightMargin: Kirigami.Units.largeSpacing
            PlasmaComponents3.Label { text: "Download:"; opacity: 0.75; visible: root.net && root.net.downKbps > 0 }
            PlasmaComponents3.Label { text: root.net ? root.speed(root.net.downKbps) : ""; visible: root.net && root.net.downKbps > 0 }
            PlasmaComponents3.Label { text: "Upload:"; opacity: 0.75; visible: root.net && root.net.upKbps > 0 }
            PlasmaComponents3.Label { text: root.net ? root.speed(root.net.upKbps) : ""; visible: root.net && root.net.upKbps > 0 }
            PlasmaComponents3.Label { text: "Metered:"; opacity: 0.75 }
            PlasmaComponents3.Label { text: root.net && root.net.metered ? "Yes" : "No" }
            PlasmaComponents3.Label { text: "VPN:"; opacity: 0.75; visible: root.net && root.net.vpn && root.type !== "vpn" }
            PlasmaComponents3.Label { text: "On"; visible: root.net && root.net.vpn && root.type !== "vpn" }
        }
        RowLayout {
            Layout.margins: Kirigami.Units.largeSpacing
            Layout.alignment: Qt.AlignRight
            PlasmaComponents3.Button {
                text: "Wi-Fi…"
                icon.name: "network-wireless"
                onClicked: { runner.runCommand("android-open deskdroid:settings:wifi"); root.expanded = false }
            }
            PlasmaComponents3.Button {
                text: "Phone's Network Settings…"
                icon.name: "configure"
                onClicked: { runner.runCommand("android-open deskdroid:settings:network"); root.expanded = false }
            }
        }
    }
}
