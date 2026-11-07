package io.deskdroid.app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import android.widget.Toast

/**
 * The DeskDroid desktop helper, an accessibility service the user turns on.
 *
 * - Android's power menu (Power off, Restart, Emergency) for the desktop's
 *   Restart or Power Off button: no app can restart or power off the phone
 *   itself without root, but this service can open the menu that does.
 * - While the desktop is on a monitor, it keeps Android's own desktop UI off
 *   it (MonitorGuard): an app, launcher or DeX taking the monitor's top brings
 *   the desktop back, and Meta, Meta shortcuts and Alt+Tab go to the desktop
 *   instead of opening Android's taskbar, app list or recent apps.
 * - Exit DeX: turns Samsung DeX off with its Quick Settings tile.
 *
 * Of the screen it reads only which app each window belongs to and on which
 * display, and of the keyboard only those keys while a DeskDroid window has
 * the focus; nothing is kept or sent anywhere.
 */
class PowerMenuService : AccessibilityService() {
    private val main = Handler(Looper.getMainLooper())
    // A DeskDroid window has the keyboard focus (from the latest window change).
    @Volatile private var ddFocused = false
    // Key codes whose press went to the desktop: their release goes there too.
    private val forwarded = mutableSetOf<Int>()
    private var lastSeen = ""

    override fun onServiceConnected() {
        instance = this
        AppLog.i("Desktop helper: on")
        check()
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    private val checkSoon = Runnable { check() }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Windows come and go in bursts: look once they've settled.
        main.removeCallbacks(checkSoon)
        main.postDelayed(checkSoon, 250)
    }

    override fun onInterrupt() {}

    /** Who has the focus, and whether something else took the top of the monitor. */
    private fun check() {
        if (Build.VERSION.SDK_INT < 30) return
        val all = runCatching { windowsOnAllDisplays }.getOrNull() ?: return
        var focused = false
        for (i in 0 until all.size()) for (w in all.valueAt(i))
            if (w.isFocused && w.type == AccessibilityWindowInfo.TYPE_APPLICATION && owner(w) == packageName) focused = true
        ddFocused = focused
        if (!NativeDesk.running || !Prefs.monitorGuard(this)) return
        // The desktop's monitor, or a monitor Android's desktop mode or DeX
        // opened its own home on while the desktop ran on the phone.
        val monitor = MonitorGuard.desktopDisplay.takeIf { it >= 0 } ?: MonitorGuard.monitor(this)?.displayId ?: return
        val windows = all.get(monitor) ?: return
        val top = windows.filter { it.type == AccessibilityWindowInfo.TYPE_APPLICATION }.maxByOrNull { it.layer } ?: return
        val pkg = owner(top) ?: return
        // Android's taskbar and DeX's panels are system windows: logged, for
        // the log's sake; the captured mouse keeps them from sliding in.
        val seen = windows.filter { it.type == AccessibilityWindowInfo.TYPE_SYSTEM }.mapNotNull { owner(it) }.distinct().sorted().joinToString()
        if (seen != lastSeen) { lastSeen = seen; if (seen.isNotEmpty()) AppLog.i("Desktop helper: system windows on the monitor: $seen") }
        // Android's own dialogs (permissions and the like) are left to answer.
        if (pkg != packageName && pkg !in DIALOGS) MonitorGuard.reclaim(this, "$pkg was on top of the monitor")
    }

    private fun owner(w: AccessibilityWindowInfo): String? = runCatching { w.root?.packageName?.toString() }.getOrNull()

    override fun onKeyEvent(e: KeyEvent): Boolean {
        val down = e.action == KeyEvent.ACTION_DOWN
        if (!down && forwarded.remove(e.keyCode)) { NativeDesk.nativeKey(e.keyCode, e.unicodeChar, false); return true }
        if (!down || !ddFocused || !NativeDesk.running || !NativeDesk.onMonitor || !Prefs.monitorGuard(this)) return false
        val meta = e.keyCode == KeyEvent.KEYCODE_META_LEFT || e.keyCode == KeyEvent.KEYCODE_META_RIGHT || e.isMetaPressed
        val altTab = e.keyCode == KeyEvent.KEYCODE_TAB && e.isAltPressed
        if (!meta && !altTab) return false
        forwarded += e.keyCode
        NativeDesk.nativeKey(e.keyCode, e.unicodeChar, true)
        return true
    }

    /** Opens Quick Settings and taps the DeX tile while DeX is on, then closes the panel. */
    private fun exitDex() {
        AppLog.i("Desktop helper: turning DeX off with its Quick Settings tile")
        if (!performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)) return
        main.postDelayed({
            val tile = runCatching { findDexTile() }.getOrNull()
            if (tile == null) {
                AppLog.i("Desktop helper: no DeX tile in Quick Settings")
                Toast.makeText(this, "Couldn't find the DeX tile. Tap DeX in Quick Settings to turn it off.", Toast.LENGTH_LONG).show()
                return@postDelayed
            }
            tile.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            main.postDelayed({
                performGlobalAction(GLOBAL_ACTION_BACK)
                // DeX gone, the desktop takes the monitor (if one is still there).
                main.postDelayed({ MonitorGuard.reclaim(this, "DeX turned off", manual = true) }, 1500)
            }, 700)
        }, 900)
    }

    /** Quick Settings' DeX tile (its label is "DeX" or "Samsung DeX" in every language), clickable. */
    private fun findDexTile(): AccessibilityNodeInfo? {
        val roots = if (Build.VERSION.SDK_INT >= 30)
            windowsOnAllDisplays.get(android.view.Display.DEFAULT_DISPLAY)?.mapNotNull { it.root }.orEmpty()
        else listOfNotNull(rootInActiveWindow)
        for (root in roots) {
            for (n in root.findAccessibilityNodeInfosByText("DeX")) {
                val label = (n.text ?: n.contentDescription)?.toString()?.trim() ?: continue
                if (!label.startsWith("DeX") && !label.startsWith("Samsung DeX")) continue
                var c: AccessibilityNodeInfo? = n
                while (c != null && !c.isClickable) c = c.parent
                if (c != null) return c
            }
        }
        return null
    }

    companion object {
        @Volatile private var instance: PowerMenuService? = null
        val on get() = instance != null
        private val DIALOGS = setOf("android", "com.android.systemui", "com.android.permissioncontroller",
            "com.google.android.permissioncontroller", "com.android.settings")

        /** Opens the power menu, or Android's accessibility settings to turn the service on. */
        fun open(c: Context) {
            val s = instance
            if (s != null && s.performGlobalAction(GLOBAL_ACTION_POWER_DIALOG)) {
                AppLog.i("Native desktop: Android's power menu")
                return
            }
            AppLog.i("Native desktop: power menu service is off, opening accessibility settings")
            turnOn(c, "Turn on \"DeskDroid desktop helper\" to restart or power off from the desktop")
        }

        /** Exit DeX: with the helper, its Quick Settings tile; without, how to. */
        fun exitDex(c: Context) {
            val s = instance
            if (s != null) { s.main.post { s.exitDex() }; return }
            turnOn(c, "Turn on \"DeskDroid desktop helper\" so DeskDroid can turn DeX off, or tap DeX in Quick Settings")
        }

        fun turnOn(c: Context, why: String) {
            Toast.makeText(c, why, Toast.LENGTH_LONG).show()
            c.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}
