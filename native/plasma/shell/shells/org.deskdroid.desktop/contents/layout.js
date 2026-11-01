// The first start's layout: the phone's wallpaper (or a gradient) on every desktop, and
// Plasma's own panel at the bottom: the application menu and app launchers
// on the left, the digital
// clock on the right.
var desktops = desktopsForActivity(currentActivity());
// files/config is the config folder; DeskDroid copies the phone's wallpaper
// to files/wallpaper.jpg at each start.
var files = userDataPath("config").replace(/\/[^\/]*\/?$/, "");
for (var i = 0; i < desktops.length; i++) {
    desktops[i].wallpaperPlugin = "org.deskdroid.gradient";
    desktops[i].currentConfigGroup = ["Wallpaper", "org.deskdroid.gradient", "General"];
    desktops[i].writeConfig("Image", "file://" + files + "/wallpaper.jpg");
    // Plasma's folder view shows the Desktop folder (files/Desktop) directly:
    // its usual desktop:/ address needs a KIO worker not built yet.
    desktops[i].currentConfigGroup = ["General"];
    desktops[i].writeConfig("url", "file://" + files + "/Desktop");
}

var panel = new Panel("org.kde.panel");
panel.location = "bottom";
panel.height = 2 * Math.floor(gridUnit * 2.5 / 2);
panel.addWidget("org.kde.plasma.kickoff");

var launchers = ["org.kde.dolphin.desktop"];
for (var j = 0; j < launchers.length; j++) {
    var path = applicationPath(launchers[j]);
    if (!path) {
        // No app database yet: take the desktop file from the bundled share folder
        // (files/config is the config folder, files/kwin/share holds the apps).
        var bundled = files + "/kwin/share/applications/" + launchers[j];
        if (fileExists(bundled)) path = bundled;
    }
    print("deskdroid layout: " + launchers[j] + " -> " + path);
    if (path) {
        var icon = panel.addWidget("org.kde.plasma.icon");
        icon.currentConfigGroup = ["General"];
        icon.writeConfig("url", "file://" + path);
    }
}

panel.addWidget("org.kde.plasma.panelspacer");
panel.addWidget("org.kde.plasma.digitalclock");
