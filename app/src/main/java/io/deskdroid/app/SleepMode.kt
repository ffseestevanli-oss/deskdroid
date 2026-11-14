package io.deskdroid.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.display.DisplayManager
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import android.view.Display
import java.io.File

/**
 * The phone's screen off with nothing else showing the desktop: DeskDroid
 * winds down until it comes back on (Prefs.sleepSaver, on by default).
 *
 *  - The compositor hands out one frame a second instead of twenty
 *    (nativeSetSleeping), so KWin, Plasma's animations and the apps, a
 *    playing video included, draw almost nothing. Sound goes on as before.
 *  - Every desktop process (KWin, Plasma, the Linux and Windows apps) runs at
 *    background priority, so Android keeps it off the fast cores when it can.
 *  - The battery, network and CPU widgets' status is written every 30 s, not 2.
 *
 * Screen on, a monitor plugged in, or the desktop moved to a monitor: all of
 * it goes back to full power at once. Nothing is paused outright, so music,
 * downloads and calls in desktop apps keep working.
 */
object SleepMode {
    /** Background priority (Process.THREAD_PRIORITY_BACKGROUND). */
    private const val SLEEP_NICE = 10

    @Volatile var asleep = false
        private set
    private var app: Context? = null
    private val main = Handler(Looper.getMainLooper())
    // Renicing walks every desktop thread; off the main thread, one at a time.
    private val worker by lazy { HandlerThread("sleep-mode").also { it.start() }.let { Handler(it.looper) } }
    // Each desktop thread's priority before the phone went to sleep.
    private val before = HashMap<Int, Int>()

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) = update(intent.action ?: "")
    }
    private val displays = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(id: Int) = update("display added")
        override fun onDisplayRemoved(id: Int) = update("display removed")
        override fun onDisplayChanged(id: Int) = update("display changed")
    }

    /** With the desktop: from now on, the screen going off winds it down. */
    fun start(c: Context) {
        main.post {
            if (app != null) return@post
            val a = c.applicationContext
            app = a
            a.registerReceiver(receiver, IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_SCREEN_ON)
            })
            a.getSystemService(DisplayManager::class.java)?.registerDisplayListener(displays, main)
        }
    }

    /** The desktop stopped: back to normal (its processes are gone anyway). */
    fun stop() {
        main.post {
            val a = app ?: return@post
            app = null
            try { a.unregisterReceiver(receiver) } catch (e: Exception) {}
            a.getSystemService(DisplayManager::class.java)?.unregisterDisplayListener(displays)
            if (asleep) setAsleep(a, false, "desktop stopped")
        }
    }

    /** The setting changed: applies now (only matters with the screen off). */
    fun prefChanged() = main.post { update("setting changed") }

    private fun update(why: String) {
        val a = app ?: return
        val sleep = Prefs.sleepSaver(a) && NativeDesk.running && !NativeDesk.onMonitor && !anyScreenOn(a)
        if (sleep != asleep) setAsleep(a, sleep, why)
    }

    /**
     * The phone's own screen is on (interactive), or another display is: a
     * monitor, or Android's desktop mode on one. Always-on display counts as off.
     */
    private fun anyScreenOn(c: Context): Boolean {
        if (c.getSystemService(PowerManager::class.java)?.isInteractive != false) return true
        val dm = c.getSystemService(DisplayManager::class.java) ?: return true
        return dm.displays.any { it.displayId != Display.DEFAULT_DISPLAY && it.state == Display.STATE_ON }
    }

    private fun setAsleep(c: Context, sleep: Boolean, why: String) {
        asleep = sleep
        if (NativeDesk.running) NativeDesk.nativeSetSleeping(sleep)
        PhoneStatus.setSlow(sleep)
        PowerProfile.sleepChanged(sleep)
        val pkg = c.packageName
        worker.post { renice(pkg, sleep) }
        AppLog.i("Native desktop: " + (if (sleep) "asleep, saving power" else "awake, full power") + " ($why)")
    }

    /**
     * Desktop threads to background priority (sleep), or back to what they
     * had (wake). Threads started while asleep inherit background priority
     * and come back at the usual 0; threads that were at background priority
     * or lower already are left as they were.
     */
    private fun renice(pkg: String, sleep: Boolean) {
        var changed = 0
        if (sleep) before.clear()
        for (tid in desktopThreads(pkg)) {
            val now = try { android.os.Process.getThreadPriority(tid) } catch (e: Exception) { continue }
            val target = if (sleep) {
                before[tid] = now
                if (now < SLEEP_NICE) SLEEP_NICE else continue
            } else {
                if (now != SLEEP_NICE) continue
                before[tid] ?: 0
            }
            if (target == now) continue
            // Android may refuse the scheduling group yet still set the
            // priority, so whether it took is read back rather than assumed.
            try { android.os.Process.setThreadPriority(tid, target) } catch (e: Exception) {}
            try { if (android.os.Process.getThreadPriority(tid) == target) changed++ } catch (e: Exception) {}
        }
        if (!sleep) before.clear()
        AppLog.i("Native desktop: $changed desktop threads " + if (sleep) "to background priority" else "back to full priority")
    }

    /**
     * Every thread of DeskDroid's own processes that aren't Android app
     * processes (those are named after the package): the compositor's
     * clients, KWin, Plasma, proot and what runs in it.
     */
    private fun desktopThreads(pkg: String): List<Int> {
        val me = android.os.Process.myPid()
        val uid = android.os.Process.myUid()
        val out = ArrayList<Int>()
        for (dir in File("/proc").listFiles() ?: return out) {
            val pid = dir.name.toIntOrNull() ?: continue
            if (pid == me) continue
            try {
                if (android.system.Os.stat(dir.path).st_uid != uid) continue
                val cmd = File(dir, "cmdline").readBytes().takeWhile { it != 0.toByte() }.toByteArray().toString(Charsets.UTF_8)
                if (cmd.isEmpty() || cmd.startsWith(pkg)) continue
                File(dir, "task").list()?.forEach { t -> t.toIntOrNull()?.let(out::add) }
            } catch (e: Exception) {
                // Gone already, or not ours to look at.
            }
        }
        return out
    }
}
