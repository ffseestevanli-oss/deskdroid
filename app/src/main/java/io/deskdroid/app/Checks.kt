package io.deskdroid.app

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

/** Non-root limits the user can fix with a toggle (plan section 5). */
object Checks {
    enum class State { OK, NEEDS_FIX, UNKNOWN, NOT_NEEDED }

    fun batteryUnrestricted(ctx: Context): Boolean =
        ctx.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(ctx.packageName)

    @SuppressLint("BatteryLife")
    fun requestBatteryUnrestricted(ctx: Context) {
        ctx.startActivity(
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${ctx.packageName}"))
        )
    }

    /**
     * Android 12+ kills apps with more than 32 child processes ("phantom process
     * killer"); a Plasma session has more. Android 14+ has "Disable child process
     * restrictions" in Developer options, which sets this feature flag; on 12-13
     * the same flag can be set over ADB (Wireless debugging works without a computer).
     */
    fun phantomProcesses(ctx: Context): State {
        if (Build.VERSION.SDK_INT < 31) return State.NOT_NEEDED
        val flag = getprop("persist.sys.fflag.override.$PHANTOM_FLAG")
            .ifEmpty { Settings.Global.getString(ctx.contentResolver, PHANTOM_FLAG) ?: "" }
        return when (flag.lowercase()) {
            "false" -> State.OK
            "true" -> State.NEEDS_FIX
            else -> State.UNKNOWN // never toggled: the killer is on by default
        }
    }

    fun phantomFixIsToggle() = Build.VERSION.SDK_INT >= 34

    /** The one-time command for Android 12-13, run from a computer or a local ADB app. */
    const val PHANTOM_ADB_COMMAND = "adb shell settings put global settings_enable_monitor_phantom_procs false"

    fun developerOptionsEnabled(ctx: Context) =
        Settings.Global.getInt(ctx.contentResolver, Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0) == 1

    fun openDeveloperOptions(ctx: Context) {
        ctx.startActivity(Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS))
    }

    /** "About phone", where tapping Build number 7 times turns on Developer options. */
    fun openAboutPhone(ctx: Context) {
        ctx.startActivity(Intent(Settings.ACTION_DEVICE_INFO_SETTINGS))
    }

    fun notificationsAllowed(ctx: Context) =
        ctx.getSystemService(android.app.NotificationManager::class.java).areNotificationsEnabled()

    private const val PHANTOM_FLAG = "settings_enable_monitor_phantom_procs"

    private fun getprop(name: String): String = try {
        val p = ProcessBuilder("/system/bin/getprop", name).start()
        p.inputStream.bufferedReader().readText().trim().also { p.waitFor() }
    } catch (_: Exception) {
        ""
    }
}
