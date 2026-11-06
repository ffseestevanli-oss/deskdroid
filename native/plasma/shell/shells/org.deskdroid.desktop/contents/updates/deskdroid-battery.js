// Runs once (Plasma remembers it): panels made before the battery widget
// existed get it, at the end (after the clock).
panels().forEach(function (p) {
    var has = p.widgets().some(function (w) { return w.type == "org.deskdroid.battery"; });
    if (!has) p.addWidget("org.deskdroid.battery");
});
