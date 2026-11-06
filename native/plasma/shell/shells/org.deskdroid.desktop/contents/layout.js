// The first start's layout: the phone's wallpaper (or DeskDroid's) on every desktop, and
// Plasma's own panel at the bottom: the application menu, the task manager
// (icons only, Dolphin pinned), and the digital clock on the right.
var desktops = desktopsForActivity(currentActivity());
// files/config is the config folder; DeskDroid copies the phone's wallpaper
// to files/wallpaper.jpg at each start.
var files = userDataPath("config").replace(/\/[^\/]*\/?$/, "");
var phoneWallpaper = files + "/wallpaper.jpg";
for (var i = 0; i < desktops.length; i++) {
    if (fileExists(phoneWallpaper)) {
        // Plasma's Image wallpaper, so Configure Desktop and Wallpaper can change it.
        desktops[i].wallpaperPlugin = "org.kde.image";
        desktops[i].currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
        desktops[i].writeConfig("Image", "file://" + phoneWallpaper);
    } else {
        // DeskDroid's own wallpaper (the one the Debian desktop had).
        desktops[i].wallpaperPlugin = "org.kde.image";
        desktops[i].currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
        desktops[i].writeConfig("Image", "file://" + files + "/kwin/share/wallpapers/DeskDroid/");
    }
    // Plasma's folder view shows the Desktop folder (files/Desktop) directly:
    // its usual desktop:/ address needs a KIO worker not built yet.
    desktops[i].currentConfigGroup = ["General"];
    desktops[i].writeConfig("url", "file://" + files + "/Desktop");
}

var panel = new Panel("org.kde.panel");
panel.location = "bottom";
panel.height = 2 * Math.floor(gridUnit * 2.5 / 2);
var kickoff = panel.addWidget("org.kde.plasma.kickoff");
// The menu's power buttons: End Session only (DeskDroid has no sleep,
// restart or shut down for the phone yet).
kickoff.currentConfigGroup = ["General"];
kickoff.writeConfig("systemFavorites", "logout");

// The task manager, icons only, with apps pinned to it as launchers.
var launchers = ["org.kde.dolphin.desktop"];
var pinned = [];
for (var j = 0; j < launchers.length; j++) {
    var path = applicationPath(launchers[j]);
    if (path) {
        pinned.push("applications:" + launchers[j]);
    } else {
        // No app database yet: take the desktop file from the bundled share folder
        // (files/config is the config folder, files/kwin/share holds the apps).
        var bundled = files + "/kwin/share/applications/" + launchers[j];
        if (fileExists(bundled)) pinned.push("file://" + bundled);
    }
}
print("deskdroid layout: launchers " + pinned.join(","));
var tasks = panel.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", pinned);

panel.addWidget("org.kde.plasma.digitalclock");
