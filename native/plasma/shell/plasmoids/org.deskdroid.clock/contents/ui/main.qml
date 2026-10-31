// The time, as the phone's settings show it.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    property date now: new Date()

    preferredRepresentation: fullRepresentation

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    fullRepresentation: Text {
        Layout.minimumWidth: contentWidth
        Layout.preferredWidth: contentWidth
        // Without seconds, even in the C locale (whose short format has them).
        text: Qt.formatTime(root.now, Qt.locale().timeFormat(Locale.ShortFormat).replace(/:ss/, ""))
        color: Kirigami.Theme.textColor // the panel theme's
        font.pixelSize: Math.max(12, height * 0.45)
        verticalAlignment: Text.AlignVCenter
    }
}
