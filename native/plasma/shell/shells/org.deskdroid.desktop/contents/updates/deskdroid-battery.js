// Runs once (Plasma remembers it): panels made before the battery widget
// existed get it, at the end (after the clock). Not panels with the system
// tray: the battery is one of its items now.
panels().forEach(function (p) {
    var has = p.widgets().some(function (w) { return w.type == "org.deskdroid.battery" || w.type == "org.kde.plasma.systemtray"; });
    if (!has) p.addWidget("org.deskdroid.battery");
});
