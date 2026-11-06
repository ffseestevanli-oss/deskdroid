// Runs once (Plasma remembers it): desktops still on the old DeskDroid
// gradient get DeskDroid's own wallpaper, the one the Debian desktop had.
var files = userDataPath("config").replace(/\/[^\/]*\/?$/, "");
desktops().forEach(function (d) {
    if (d.wallpaperPlugin != "org.deskdroid.gradient")
        return;
    d.wallpaperPlugin = "org.kde.image";
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    d.writeConfig("Image", "file://" + files + "/kwin/share/wallpapers/DeskDroid/");
});
