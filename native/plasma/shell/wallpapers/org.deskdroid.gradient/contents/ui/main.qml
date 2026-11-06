// The phone's wallpaper (DeskDroid copies it at each start) over a gradient in
// Plasma's blues, which shows when there's no wallpaper to copy.
import QtQuick
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "#1d2b4f" }
            GradientStop { position: 0.55; color: "#2d5d9b" }
            GradientStop { position: 1.0; color: "#3daee9" }
        }
    }

    Image {
        anchors.fill: parent
        source: root.configuration.Image || ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        // Decoded at the screen's size, not the photo's.
        sourceSize: Qt.size(Math.max(root.width, root.height), Math.max(root.width, root.height))
    }
}
