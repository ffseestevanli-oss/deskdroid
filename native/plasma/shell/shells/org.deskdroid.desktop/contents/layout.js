// The first start's layout: the gradient wallpaper on every desktop, and a
// panel at the bottom with a clock.
var desktops = desktopsForActivity(currentActivity());
for (var i = 0; i < desktops.length; i++) {
    desktops[i].wallpaperPlugin = "org.deskdroid.gradient";
}

var panel = new Panel("org.deskdroid.panel");
panel.location = "bottom";
panel.height = 2 * Math.floor(gridUnit * 2.5 / 2);
panel.addWidget("org.deskdroid.clock");
