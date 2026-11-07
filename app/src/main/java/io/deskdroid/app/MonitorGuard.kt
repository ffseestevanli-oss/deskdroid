package io.deskdroid.app

import android.app.Activity
import android.app.ActivityManager
import android.app.ActivityOptions
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.SystemClock
import android.view.Display

/**
 * Keeps Android's own desktop UI off the monitor while DeskDroid's desktop is
 * on it: Android 16's desktop experience (connected displays), Samsung DeX
 * and similar modes otherwise take the monitor over.
 *
 * - The mouse stays captured by a DeskDroid window (NativeDeskActivity and
 *   PhoneTouchpadActivity), so Android's cursor never reaches a screen edge,
 *   where Android reveals its taskbar or status bar on hover.
 * - The desktop's window asks to be full screen instead of a desktop-mode
 *   window with a caption bar ([fullscreen]), and launches as full screen
 *   ([launchOptions]).
 * - On DeX, the Meta key goes to the desktop instead of DeX ([dexMetaKeys]).
 * - With the DeskDroid desktop helper on (PowerMenuService, an accessibility
 *   service), a desktop-mode app, launcher or DeX taking the monitor's top
 *   brings the desktop back on top ([reclaim]), and Meta, Alt+Tab and their
 *   shortcuts go to the desktop instead of Android's taskbar.
 */
object MonitorGuard {
    /** The monitor's display (the first one that isn't the phone's own), if any. */
    fun monitor(c: Context): Display? =
        c.getSystemService(DisplayManager::class.java).displays.firstOrNull {
            it.displayId != Display.DEFAULT_DISPLAY && (it.flags and Display.FLAG_PRIVATE) == 0
        }

    /** The display the desktop shows on now while it's on a monitor, or -1. */
    val desktopDisplay: Int
        get() = if (!NativeDesk.onMonitor) -1 else NativeDesk.owner?.get()?.display?.displayId ?: -1

    /** Samsung DeX is running (Configuration.semDesktopModeEnabled, from Samsung's DeX guide). */
    fun dexRunning(c: Context): Boolean = runCatching {
        val conf = c.resources.configuration
        val cls = conf.javaClass
        cls.getField("semDesktopModeEnabled").getInt(conf) == cls.getField("SEM_DESKTOP_MODE_ENABLED").getInt(cls)
    }.getOrDefault(false)

    /**
     * Opening the desktop on a monitor: on that display, and full screen rather
     * than a desktop-mode window. The windowing mode isn't public API; where
     * Android refuses it, [fullscreen] asks again once the window is up.
     */
    fun launchOptions(display: Int): ActivityOptions {
        val o = ActivityOptions.makeBasic().setLaunchDisplayId(display)
        if (display != Display.DEFAULT_DISPLAY) runCatching {
            ActivityOptions::class.java.getMethod("setLaunchWindowingMode", Int::class.javaPrimitiveType)
                .invoke(o, 1 /* WindowConfiguration.WINDOWING_MODE_FULLSCREEN */)
        }
        return o
    }

    private var lastFullscreenAsk = 0L

    /**
     * The desktop's window on a monitor is a desktop-mode (freeform) window:
     * asks Android to make it full screen (Android 15+, honoured on desktop
     * displays for the focused window, best after a click or key).
     */
    fun fullscreen(a: Activity) {
        if (a.display?.displayId == Display.DEFAULT_DISPLAY || !a.isInMultiWindowMode) return
        if (Build.VERSION.SDK_INT < 35) return
        val now = SystemClock.uptimeMillis()
        if (now - lastFullscreenAsk < 1500) return
        lastFullscreenAsk = now
        runCatching {
            a.requestFullscreenMode(Activity.FULLSCREEN_MODE_REQUEST_ENTER, object : android.os.OutcomeReceiver<Void, Throwable> {
                override fun onResult(r: Void?) = AppLog.i("Monitor: the desktop's window is full screen now")
                override fun onError(e: Throwable) = AppLog.i("Monitor: Android kept the desktop in a window: ${e.message}")
            })
        }.onFailure { AppLog.i("Monitor: couldn't ask for full screen: $it") }
    }

    /**
     * Samsung DeX: the Meta key (Windows key) goes to this window instead of
     * opening DeX's start menu (SemWindowManager.requestMetaKeyEvent, as
     * Termux:X11 does).
     */
    fun dexMetaKeys(a: Activity, on: Boolean) {
        if (!Build.MANUFACTURER.equals("samsung", ignoreCase = true)) return
        runCatching {
            val cls = Class.forName("com.samsung.android.view.SemWindowManager")
            val wm = cls.getMethod("getInstance").invoke(null)
            cls.getDeclaredMethod("requestMetaKeyEvent", ComponentName::class.java, Boolean::class.javaPrimitiveType)
                .invoke(wm, a.componentName, on)
        }.onFailure { AppLog.i("Monitor: DeX Meta key capture unavailable: $it") }
    }

    private var lastFocusAsk = 0L

    /**
     * Brings a DeskDroid window's task to the front of its display, which also
     * gives that display the focus: the mouse can then be captured there.
     * Android allows it while one of DeskDroid's windows is visible.
     */
    fun toFront(a: Activity) {
        val now = SystemClock.uptimeMillis()
        if (now - lastFocusAsk < 800) return
        lastFocusAsk = now
        runCatching { a.getSystemService(ActivityManager::class.java).moveTaskToFront(a.taskId, 0) }
            .onFailure { AppLog.i("Monitor: couldn't bring the desktop forward: $it") }
    }

    // Reclaiming backs off when something keeps taking the monitor back, so
    // DeskDroid and Android don't fight in a loop.
    private val reclaims = ArrayDeque<Long>()

    /**
     * Brings the desktop back on top of the monitor, full screen: its window
     * to the front if it's there, or a new one on the monitor. [manual] is the
     * "Take back the monitor" button, which always tries.
     */
    fun reclaim(c: Context, why: String, manual: Boolean = false): Boolean {
        val m = monitor(c) ?: return false
        val now = SystemClock.uptimeMillis()
        if (!manual) {
            while (reclaims.isNotEmpty() && now - reclaims.first() > 30_000) reclaims.removeFirst()
            if (reclaims.size >= 4) return false
            reclaims.addLast(now)
        }
        AppLog.i("Monitor: taking the monitor back ($why)")
        val owner = NativeDesk.owner?.get()
        if (owner != null && !owner.isFinishing && owner.display?.displayId == m.displayId) {
            runCatching { c.getSystemService(ActivityManager::class.java).moveTaskToFront(owner.taskId, 0) }
                .onFailure { AppLog.i("Monitor: couldn't bring the desktop forward: $it") }
            owner.runOnUiThread { fullscreen(owner) }
        } else {
            runCatching {
                c.startActivity(Intent(c, ExternalDeskActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    launchOptions(m.displayId).toBundle())
            }.onFailure { AppLog.i("Monitor: couldn't open the desktop on the monitor: $it"); return false }
        }
        return true
    }
}
