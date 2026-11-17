package io.deskdroid.app

import android.content.Context
import android.os.FileObserver
import org.json.JSONObject
import java.io.File

/**
 * The phone's touch gestures on the desktop: swipes in from the screen's
 * corners and edges, and a three-finger tap. Which action each one does is set in
 * System Settings › Gestures (native/plasma/gestures), which saves
 * $HOME/gestures.json (the app's files/), for example:
 *   {"bottom_left": "keyboard", "bottom_right": "dd_menu", "right": "none", "three_finger_tap": "touch_mode",
 *    "mode_indicator": true}
 * A gesture the file leaves out keeps its default. The file is watched, so a
 * change in System Settings applies to the next touch.
 */
object Gestures {
    const val FILE = "gestures.json"

    // Gestures (the file's keys).
    const val BOTTOM_LEFT = "bottom_left"   // swipe up from the bottom left corner
    const val BOTTOM_RIGHT = "bottom_right" // swipe up from the bottom right corner
    const val BOTTOM = "bottom"             // swipe up from the bottom edge (between the corners)
    const val LEFT = "left"                 // swipe in from the left edge
    const val RIGHT = "right"               // swipe in from the right edge
    const val TOP = "top"                   // swipe down from the top edge
    const val THREE_FINGER_TAP = "three_finger_tap" // three fingers tapped once, together

    // Actions (the file's values). The same list is in native/plasma/gestures/gesturemodule.h.
    const val NONE = "none"                 // nothing: the touch goes to the desktop (and Android) as usual
    const val DD_MENU = "dd_menu"           // the DD menu
    const val KEYBOARD = "keyboard"         // the phone's keyboard, up or away
    const val TOUCH_MODE = "touch_mode"     // Touchpad <-> Direct touch
    const val START_MENU = "start_menu"     // Plasma's start menu
    const val OVERVIEW = "overview"         // KWin's Overview
    const val SHOW_DESKTOP = "show_desktop" // every window minimized, or back
    const val SWITCH_WINDOW = "switch_window" // the window used before (Alt+Tab)
    const val BACK = "back"                 // the phone's Back: Escape, or out of edit mode
    const val APP_DRAWER = "app_drawer"     // the phone's app drawer (PhoneAppDrawer), while the APP_DRAWER switch is on

    val ACTIONS = setOf(NONE, DD_MENU, KEYBOARD, TOUCH_MODE, START_MENU, OVERVIEW, SHOW_DESKTOP, SWITCH_WINDOW, BACK, APP_DRAWER)

    /** Before anything is set: the corner swipes DeskDroid always had, a three-finger tap switches the touch mode. */
    val DEFAULTS = mapOf(
        BOTTOM_LEFT to KEYBOARD,
        BOTTOM_RIGHT to DD_MENU,
        BOTTOM to APP_DRAWER, // swipe up for the app drawer, as on a phone's home screen
        LEFT to NONE,
        RIGHT to NONE,
        TOP to NONE,    // Android's own: its status bar
        THREE_FINGER_TAP to TOUCH_MODE,
    )

    // On/off switches (the file's true/false values), also in System Settings › Gestures.
    const val MODE_INDICATOR = "mode_indicator" // the touch mode's icon in the system tray (org.deskdroid.touchmode reads it itself)

    // The app drawer: off, the app_drawer action does nothing (its edge is Android's again) and the DD menu has no Apps tile.
    const val APP_DRAWER_ON = "app_drawer_on"
    // The Private Space as a locked section of the app drawer, and out of Plasma's menus and search (NativeDesk.writeAndroidApps).
    // Off, the drawer leaves it out and Plasma's menus list it as before (Android Apps › Private Space).
    const val PRIVATE_SPACE = "private_space"

    val SWITCH_DEFAULTS = mapOf(
        MODE_INDICATOR to true,
        APP_DRAWER_ON to true,
        PRIVATE_SPACE to true,
    )

    /** The Private Space is in the app drawer only, not in Plasma's menus. */
    fun privateSpaceInDrawer() = switch(APP_DRAWER_ON) && switch(PRIVATE_SPACE)
    @Volatile private var switches: Map<String, Boolean> = SWITCH_DEFAULTS

    /** An on/off switch from the file, or its default. */
    fun switch(id: String): Boolean = switches[id] ?: SWITCH_DEFAULTS[id] ?: false

    @Volatile private var actions: Map<String, String> = DEFAULTS
    private var watcher: FileObserver? = null
    /** Called on the watcher's thread after the file changed. */
    @Volatile var changed: (() -> Unit)? = null

    fun action(gesture: String): String {
        val a = actions[gesture] ?: NONE
        // With the app drawer off, its gesture is no gesture: the touch goes on to the desktop (and Android).
        return if (a == APP_DRAWER && !switch(APP_DRAWER_ON)) NONE else a
    }

    /** Reads the file and keeps watching it (once per process). */
    @Synchronized fun start(c: Context) {
        val app = c.applicationContext
        load(app)
        if (watcher != null) return
        // System Settings saves with a rename (QSaveFile): MOVED_TO.
        watcher = object : FileObserver(app.filesDir, CLOSE_WRITE or MOVED_TO or DELETE) {
            override fun onEvent(event: Int, path: String?) {
                if (path != FILE) return
                load(app)
                changed?.invoke()
            }
        }.also { it.startWatching() }
    }

    fun load(c: Context) {
        val f = File(c.filesDir, FILE)
        val m = HashMap(DEFAULTS)
        val sw = HashMap(SWITCH_DEFAULTS)
        try {
            if (f.exists()) {
                val o = JSONObject(f.readText())
                for (g in DEFAULTS.keys) {
                    val a = o.optString(g, "")
                    if (a in ACTIONS) m[g] = a
                }
                for (k in SWITCH_DEFAULTS.keys) if (o.opt(k) is Boolean) sw[k] = o.getBoolean(k)
            }
        } catch (e: Exception) {
            AppLog.i("Gestures: couldn't read $FILE: $e")
        }
        if (m != actions) AppLog.i("Gestures: " + m.entries.sortedBy { it.key }.joinToString { "${it.key}=${it.value}" })
        actions = m
        switches = sw
    }
}
