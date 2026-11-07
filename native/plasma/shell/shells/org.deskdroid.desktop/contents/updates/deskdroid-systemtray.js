// Runs once (Plasma remembers it): panels made before the system tray was
// built get it, just before the clock (the clock is added again after it).
panels().forEach(function (p) {
    var widgets = p.widgets();
    if (widgets.some(function (w) { return w.type == "org.kde.plasma.systemtray"; })) return;
    var clocks = widgets.filter(function (w) { return w.type == "org.kde.plasma.digitalclock"; });
    if (clocks.length == 0) return; // not a panel with DeskDroid's layout
    clocks.forEach(function (w) { w.remove(); });
    p.addWidget("org.kde.plasma.systemtray");
    p.addWidget("org.kde.plasma.digitalclock");
});
