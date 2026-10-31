// The first start's layout: the gradient wallpaper on every desktop, and
// Plasma's own panel at the bottom with its digital clock.
var desktops = desktopsForActivity(currentActivity());
for (var i = 0; i < desktops.length; i++) {
    desktops[i].wallpaperPlugin = "org.deskdroid.gradient";
}

var panel = new Panel("org.kde.panel");
panel.location = "bottom";
panel.height = 2 * Math.floor(gridUnit * 2.5 / 2);
panel.addWidget("org.kde.plasma.panelspacer");
panel.addWidget("org.kde.plasma.digitalclock");
