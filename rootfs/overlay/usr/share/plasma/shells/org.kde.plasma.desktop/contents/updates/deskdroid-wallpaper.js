// Runs once per user on first Plasma start: make the DeskDroid gradient the default wallpaper.
desktops().forEach(function (d) {
    d.wallpaperPlugin = "org.kde.image";
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    d.writeConfig("Image", "file:///usr/share/wallpapers/DeskDroid/");
});
