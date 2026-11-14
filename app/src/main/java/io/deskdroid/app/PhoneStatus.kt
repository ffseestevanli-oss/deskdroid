package io.deskdroid.app

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Handler
import android.os.HandlerThread
import java.io.File

/**
 * The phone's battery, memory, network and the desktop's CPU use, for the
 * desktop's widgets (Battery, Network, CPU and RAM, native/plasma/shell/plasmoids): written to
 * files/status.json every 2 s while the desktop runs. Android lets an app see
 * only its own processes' CPU time, so CPU is the desktop's share of all cores.
 */
object PhoneStatus {
    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private var tick: Runnable? = null
    @Volatile private var slow = false // SleepMode: written every 30 s instead of 2
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
        val r = object : Runnable {
            override fun run() {
                try { write(app) } catch (e: Exception) { AppLog.i("Native desktop: status: $e") }
                h.postDelayed(this, if (slow) 30_000 else 2000)
            }
        }
        tick = r
        h.post(r)
    }

    /** Every 30 s while the phone sleeps (SleepMode), every 2 s again on wake, starting now. */
    @Synchronized fun setSlow(on: Boolean) {
        if (slow == on) return
        slow = on
        val h = handler ?: return
        val r = tick ?: return
        // Awake: fresh numbers now, not when the 30 s wait ends.
        if (!on) { h.removeCallbacks(r); h.post(r) }
    }

    /** Fresh numbers now (the power profile changed), not at the next tick. */
    @Synchronized fun refresh() {
        val h = handler ?: return
        val r = tick ?: return
        h.removeCallbacks(r); h.post(r)
    }

    @Synchronized fun stop() {
        thread?.quitSafely()
        thread = null; handler = null; tick = null
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
        val net = network(c)
        val json = org.json.JSONObject()
            .put("battery", percent)
            .put("charging", charging)
            .put("plugged", plugged)
            .put("chargeMinutes", minutesLeft)
            .put("ramTotal", mem.totalMem)
            .put("ramAvailable", mem.availMem)
            .put("cpu", cpu)
            .put("cores", cores)
            .put("network", net)
            .put("profile", PowerProfile.effective)
            .put("profileChosen", Prefs.powerProfile(c))
            .put("profileBySaver", PowerProfile.forcedBySaver)
            .put("time", System.currentTimeMillis())
        val out = File(c.filesDir, "status.json")
        val tmp = File(c.filesDir, "status.json.new")
        tmp.writeText(json.toString())
        tmp.renameTo(out)
    }

    /**
     * The phone's connection, for the system tray's Network item: its type
     * (wifi, mobile, ethernet, vpn or none), signal level 0-4, whether it
     * reaches the internet, its speeds, and airplane mode. Wi-Fi's name needs
     * the location permission, so it isn't shown.
     */
    private fun network(c: Context): org.json.JSONObject {
        val o = org.json.JSONObject()
        val airplane = try {
            android.provider.Settings.Global.getInt(c.contentResolver, android.provider.Settings.Global.AIRPLANE_MODE_ON, 0) != 0
        } catch (e: Exception) { false }
        o.put("airplane", airplane)
        val cm = c.getSystemService(android.net.ConnectivityManager::class.java)
        val caps = try { cm?.getNetworkCapabilities(cm.activeNetwork) } catch (e: Exception) { null }
        if (caps == null) return o.put("type", "none").put("level", 0).put("internet", false)
        fun has(t: Int) = caps.hasTransport(t)
        val type = when {
            has(android.net.NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            has(android.net.NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
            has(android.net.NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            has(android.net.NetworkCapabilities.TRANSPORT_USB) -> "ethernet"
            has(android.net.NetworkCapabilities.TRANSPORT_BLUETOOTH) -> "bluetooth"
            has(android.net.NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            else -> "other"
        }
        var level = -1
        if (type == "wifi" && android.os.Build.VERSION.SDK_INT >= 30) {
            val rssi = caps.signalStrength
            val wm = c.applicationContext.getSystemService(android.net.wifi.WifiManager::class.java)
            if (rssi != android.net.NetworkCapabilities.SIGNAL_STRENGTH_UNSPECIFIED && wm != null)
                level = wm.calculateSignalLevel(rssi) * 4 / wm.maxSignalLevel.coerceAtLeast(1)
        }
        if (type == "mobile" && android.os.Build.VERSION.SDK_INT >= 28) {
            level = try { c.getSystemService(android.telephony.TelephonyManager::class.java)?.signalStrength?.level ?: -1 } catch (e: Exception) { -1 }
        }
        o.put("type", type)
        o.put("level", level.coerceIn(-1, 4))
        o.put("internet", caps.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_VALIDATED))
        o.put("vpn", has(android.net.NetworkCapabilities.TRANSPORT_VPN))
        o.put("metered", !caps.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_NOT_METERED))
        o.put("downKbps", caps.linkDownstreamBandwidthKbps)
        o.put("upKbps", caps.linkUpstreamBandwidthKbps)
        return o
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
