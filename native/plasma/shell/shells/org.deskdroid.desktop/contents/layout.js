// The first start's layout: the gradient wallpaper on every desktop, and
// Plasma's own panel at the bottom: app launchers on the left, the digital
// clock on the right.
var desktops = desktopsForActivity(currentActivity());
for (var i = 0; i < desktops.length; i++) {
    desktops[i].wallpaperPlugin = "org.deskdroid.gradient";
}

var panel = new Panel("org.kde.panel");
panel.location = "bottom";
panel.height = 2 * Math.floor(gridUnit * 2.5 / 2);

var launchers = ["org.kde.dolphin.desktop"];
for (var j = 0; j < launchers.length; j++) {
    var path = applicationPath(launchers[j]);
    if (!path) {
        // No app database yet: take the desktop file from the bundled share folder
        // (files/config is the config folder, files/kwin/share holds the apps).
        var files = userDataPath("config").replace(/\/[^\/]*\/?$/, "");
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
