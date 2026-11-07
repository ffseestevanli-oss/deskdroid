// Runs once (Plasma remembers it): desktops still showing the phone's
// wallpaper, which earlier builds put there by default, get DeskDroid's own
// (the Debian trixie desktop's), now the default. The phone's wallpaper stays
// one of the choices in Configure Desktop and Wallpaper.
var files = userDataPath("config").replace(/\/[^\/]*\/?$/, "");
var phone = "file://" + files + "/wallpaper.jpg";
desktops().forEach(function (d) {
    if (d.wallpaperPlugin != "org.kde.image")
        return;
    d.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    var image = String(d.readConfig("Image", ""));
    if (image != phone && image != files + "/wallpaper.jpg")
        return;
    d.writeConfig("Image", "file://" + files + "/kwin/share/wallpapers/DeskDroid/");
});
