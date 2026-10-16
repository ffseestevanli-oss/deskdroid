package io.deskdroid.app

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

/** Non-root limits the user can fix with a toggle (see plan section 5). */
object Checks {
    fun x11Installed(ctx: Context): Boolean = try {
        ctx.packageManager.getApplicationInfo(SessionService.X11_PACKAGE, 0); true
    } catch (_: Exception) { false }

    fun batteryUnrestricted(ctx: Context): Boolean =
        ctx.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(ctx.packageName)

    @SuppressLint("BatteryLife")
    fun requestBatteryUnrestricted(ctx: Context) {
        ctx.startActivity(
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:${ctx.packageName}"))
        )
    }

    /**
     * Android 14+ has "Disable child process restrictions" in Developer options.
     * Android 12-13 need `adb shell settings put global settings_enable_monitor_phantom_procs false`
     * (Phase 1 automates this over Wireless debugging).
     */
    fun phantomProcessHelp(): String = when {
        Build.VERSION.SDK_INT >= 34 ->
            "Developer options → turn on \"Disable child process restrictions\". " +
                "Without it Android may kill the desktop when it starts many processes."
        Build.VERSION.SDK_INT >= 31 ->
            "Android 12/13: run once from a computer: adb shell settings put global " +
                "settings_enable_monitor_phantom_procs false"
        else -> "No phantom process limit on this Android version."
    }

    fun openDeveloperOptions(ctx: Context) {
        ctx.startActivity(Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS))
    }
}
