// A wallpaper in Plasma's blues, until Plasma's own image wallpaper is built.
import QtQuick
import org.kde.plasma.plasmoid

WallpaperItem {
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: "#1d2b4f" }
            GradientStop { position: 0.55; color: "#2d5d9b" }
            GradientStop { position: 1.0; color: "#3daee9" }
        }
    }
}
