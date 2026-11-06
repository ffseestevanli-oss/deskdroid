// Runs once (Plasma remembers it): panels made before the keyboard button
// existed get it, before the battery widget when there is one.
var files = userDataPath("config").replace(/\/[^\/]*\/?$/, "");
var url = "file://" + files + "/.local/share/applications/org.deskdroid.keyboard.desktop";
panels().forEach(function (p) {
    var has = p.widgets().some(function (w) {
        if (w.type != "org.kde.plasma.icon") return false;
        w.currentConfigGroup = ["General"];
        return String(w.readConfig("url", "")).indexOf("org.deskdroid.keyboard") >= 0;
    });
    if (has) return;
    var k = p.addWidget("org.kde.plasma.icon");
    k.currentConfigGroup = ["General"];
    k.writeConfig("url", url);
});
