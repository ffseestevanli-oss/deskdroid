package io.deskdroid.app

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Handler
import android.os.HandlerThread
import java.io.File

/**
 * The phone's battery, memory and the desktop's CPU use, for the desktop's
 * widgets (Battery, CPU and RAM, native/plasma/shell/plasmoids): written to
 * files/status.json every 2 s while the desktop runs. Android lets an app see
 * only its own processes' CPU time, so CPU is the desktop's share of all cores.
 */
object PhoneStatus {
    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private var lastTicks = -1L
    private var lastAt = 0L
    private val ticksPerSecond by lazy {
        try { android.system.Os.sysconf(android.system.OsConstants._SC_CLK_TCK) } catch (e: Exception) { 100L }
    }
    private val cores = Runtime.getRuntime().availableProcessors()

    @Synchronized fun start(c: Context) {
        if (thread != null) return
        val t = HandlerThread("phone-status").also { it.start() }
        val h = Handler(t.looper)
        thread = t; handler = h
        lastTicks = -1L
        val app = c.applicationContext
        h.post(object : Runnable {
            override fun run() {
                try { write(app) } catch (e: Exception) { AppLog.i("Native desktop: status: $e") }
                h.postDelayed(this, 2000)
            }
        })
    }

    @Synchronized fun stop() {
        thread?.quitSafely()
        thread = null; handler = null
    }

    private fun write(c: Context) {
        val b = c.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = b?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = b?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val percent = if (level >= 0 && scale > 0) level * 100 / scale else -1
        val status = b?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        val plugged = (b?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0
        val bm = c.getSystemService(BatteryManager::class.java)
        val minutesLeft = if (plugged && android.os.Build.VERSION.SDK_INT >= 28)
            bm?.computeChargeTimeRemaining()?.takeIf { it > 0 }?.let { it / 60000 } ?: -1 else -1

        val mem = android.app.ActivityManager.MemoryInfo()
        c.getSystemService(android.app.ActivityManager::class.java).getMemoryInfo(mem)

        val cpu = cpuPercent()
        val json = org.json.JSONObject()
            .put("battery", percent)
            .put("charging", charging)
            .put("plugged", plugged)
            .put("chargeMinutes", minutesLeft)
            .put("ramTotal", mem.totalMem)
            .put("ramAvailable", mem.availMem)
            .put("cpu", cpu)
            .put("cores", cores)
            .put("time", System.currentTimeMillis())
        val out = File(c.filesDir, "status.json")
        val tmp = File(c.filesDir, "status.json.new")
        tmp.writeText(json.toString())
        tmp.renameTo(out)
    }

    /** The desktop's processes' CPU use since last time, in percent of all cores. */
    private fun cpuPercent(): Double {
        var ticks = 0L
        File("/proc").listFiles()?.forEach { d ->
            if (d.name.isEmpty() || !d.name[0].isDigit()) return@forEach
            try {
                val stat = File(d, "stat").readText()
                // Fields after the command's closing parenthesis: utime is the 14th field overall.
                val f = stat.substring(stat.lastIndexOf(')') + 2).split(' ')
                ticks += f[11].toLong() + f[12].toLong()
            } catch (e: Exception) { }
        }
        val now = android.os.SystemClock.elapsedRealtime()
        val result = if (lastTicks < 0 || now <= lastAt) 0.0 else
            ((ticks - lastTicks).coerceAtLeast(0) * 1000.0 / ticksPerSecond) / ((now - lastAt) * cores) * 100.0
        lastTicks = ticks; lastAt = now
        return result.coerceIn(0.0, 100.0)
    }
}
