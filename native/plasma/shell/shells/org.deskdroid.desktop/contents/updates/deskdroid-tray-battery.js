// Runs once (Plasma remembers it): the battery moves into the system tray
// (next to the new Network item), so panels that have the tray lose the
// battery widget they had on its own. It can still be added back from
// Add Widgets.
panels().forEach(function (p) {
    var widgets = p.widgets();
    if (!widgets.some(function (w) { return w.type == "org.kde.plasma.systemtray"; })) return;
    widgets.forEach(function (w) {
        if (w.type == "org.deskdroid.battery") w.remove();
    });
});
