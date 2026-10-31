// The time, as the phone's settings show it.
import QtQuick
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    property date now: new Date()

    preferredRepresentation: fullRepresentation

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    fullRepresentation: Text {
        implicitWidth: contentWidth
        text: Qt.formatTime(root.now, Qt.locale().timeFormat(Locale.ShortFormat))
        color: "white"
        font.pixelSize: Math.max(12, height * 0.45)
        verticalAlignment: Text.AlignVCenter
    }
}
