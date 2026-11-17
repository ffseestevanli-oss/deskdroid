package io.deskdroid.app

import android.annotation.SuppressLint
import android.app.Activity
import android.app.role.RoleManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
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

    /** "Background usage" off (Settings › Apps › DeskDroid › App battery usage › Restricted). */
    fun backgroundRestricted(ctx: Context): Boolean =
        ctx.getSystemService(android.app.ActivityManager::class.java).isBackgroundRestricted

    /** DeskDroid's App info, where App battery usage is. */
    fun openAppInfo(ctx: Context) {
        ctx.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${ctx.packageName}")))
    }

    fun openNotificationSettings(ctx: Context) {
        ctx.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, ctx.packageName))
    }

    fun notificationsAllowed(ctx: Context) =
        ctx.getSystemService(android.app.NotificationManager::class.java).areNotificationsEnabled()

    /**
     * The first-launch checklist's items (KeepRunningScreen). All but HOME_APP
     * count toward "optimal": the home screen is recommended, not required.
     */
    enum class Item(val required: Boolean = true) {
        CHILD_PROCESSES, BATTERY, BACKGROUND, NOTIFICATIONS, DESKTOP_HELPER, FILES, HOME_APP(required = false)
    }

    fun met(ctx: Context, item: Item): Boolean = when (item) {
        Item.CHILD_PROCESSES -> phantomProcesses(ctx).let { it == State.OK || it == State.NOT_NEEDED }
        Item.BATTERY -> batteryUnrestricted(ctx)
        Item.BACKGROUND -> !backgroundRestricted(ctx)
        Item.NOTIFICATIONS -> notificationsAllowed(ctx)
        Item.DESKTOP_HELPER -> desktopHelperOn(ctx)
        Item.FILES -> Storage.granted(ctx)
        Item.HOME_APP -> isHomeApp(ctx)
    }

    /** Required items that are on, out of all required items. */
    fun progress(ctx: Context): Pair<Int, Int> {
        val required = Item.values().filter { it.required }
        return required.count { met(ctx, it) } to required.size
    }

    /**
     * The DeskDroid desktop helper (PowerMenuService) is turned on in Accessibility.
     * Reads the setting, since the service can be on but not yet connected.
     */
    fun desktopHelperOn(ctx: Context): Boolean {
        if (PowerMenuService.on) return true
        val enabled = Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        val me = ComponentName(ctx, PowerMenuService::class.java)
        return enabled.split(':').any { ComponentName.unflattenFromString(it) == me }
    }

    /** DeskDroid is Android's home app (the desktop opens on Home). */
    fun isHomeApp(ctx: Context): Boolean {
        val roles = ctx.getSystemService(RoleManager::class.java)
        if (roles != null && roles.isRoleAvailable(RoleManager.ROLE_HOME)) return roles.isRoleHeld(RoleManager.ROLE_HOME)
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        return ctx.packageManager.resolveActivity(home, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName == ctx.packageName
    }

    /** Android's "Set DeskDroid as your default home app?" prompt. False if it can't be shown. */
    fun requestHomeApp(activity: Activity): Boolean {
        val roles = activity.getSystemService(RoleManager::class.java) ?: return false
        if (!roles.isRoleAvailable(RoleManager.ROLE_HOME)) return false
        return try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(roles.createRequestRoleIntent(RoleManager.ROLE_HOME), REQUEST_HOME)
            true
        } catch (e: Exception) {
            AppLog.i("Home app request failed: $e")
            false
        }
    }

    /** Default apps › Home app, for when the prompt was declined (Android stops showing it). */
    fun openHomeSettings(ctx: Context) {
        try {
            ctx.startActivity(Intent(Settings.ACTION_HOME_SETTINGS))
        } catch (_: Exception) {
            ctx.startActivity(Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS))
        }
    }

    const val REQUEST_HOME = 7

    private const val PHANTOM_FLAG = "settings_enable_monitor_phantom_procs"

    private fun getprop(name: String): String = try {
        val p = ProcessBuilder("/system/bin/getprop", name).start()
        p.inputStream.bufferedReader().readText().trim().also { p.waitFor() }
    } catch (_: Exception) {
        ""
    }
}
