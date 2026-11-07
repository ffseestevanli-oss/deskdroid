// The first start's layout: DeskDroid's own wallpaper (the one the Debian
// trixie desktop had) on every desktop, and Plasma's own panel at the bottom:
// the application menu, the task manager (icons only, Dolphin and Etherium
// pinned), and the digital clock on the right.
var desktops = desktopsForActivity(currentActivity());
// files/config is the config folder. The phone's wallpaper (DeskDroid copies
// it at each start) is one of the choices in Configure Desktop and Wallpaper,
// not the default.
var files = userDataPath("config").replace(/\/[^\/]*\/?$/, "");
for (var i = 0; i < desktops.length; i++) {
    // Plasma's Image wallpaper, so Configure Desktop and Wallpaper can change it.
    desktops[i].wallpaperPlugin = "org.kde.image";
    desktops[i].currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desktops[i].writeConfig("Image", "file://" + files + "/kwin/share/wallpapers/DeskDroid/");
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
// Etherium only when it's installed (from the app store).
var launchers = ["org.kde.dolphin.desktop", "org.deskdroid.firefox.desktop"];
var pinned = [];
for (var j = 0; j < launchers.length; j++) {
    var path = applicationPath(launchers[j]);
    if (path) {
        pinned.push("applications:" + launchers[j]);
    } else {
        // No app database yet: take the desktop file from the bundled share folder
        // (files/config is the config folder, files/kwin/share holds the apps,
        // files/.local/share the app store's).
        var bundled = files + "/kwin/share/applications/" + launchers[j];
        var store = files + "/.local/share/applications/" + launchers[j];
        if (fileExists(bundled)) pinned.push("file://" + bundled);
        else if (fileExists(store)) pinned.push("file://" + store);
    }
}
print("deskdroid layout: launchers " + pinned.join(","));
var tasks = panel.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", pinned);

// Plasma's system tray (apps' tray icons), the keyboard button (opens the
// phone's keyboard), the phone's battery (DeskDroid's widget), then the clock.
panel.addWidget("org.kde.plasma.systemtray");
var keyboard = panel.addWidget("org.kde.plasma.icon");
keyboard.currentConfigGroup = ["General"];
keyboard.writeConfig("url", "file://" + files + "/.local/share/applications/org.deskdroid.keyboard.desktop");
panel.addWidget("org.deskdroid.battery");
panel.addWidget("org.kde.plasma.digitalclock");
