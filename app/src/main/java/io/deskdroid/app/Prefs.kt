package io.deskdroid.app

import android.content.Context

/** Launcher preferences. */
object Prefs {
    private fun prefs(c: Context) = c.getSharedPreferences("settings", Context.MODE_PRIVATE)

    fun autoStart(c: Context) = prefs(c).getBoolean("auto_start", false)
    fun setAutoStart(c: Context, on: Boolean) = prefs(c).edit().putBoolean("auto_start", on).apply()

    /** "Lock my desktop": fingerprint/PIN in the app plus Plasma's lock screen at start. */
    fun lockDesktop(c: Context) = prefs(c).getBoolean("lock_desktop", false)
    fun setLockDesktop(c: Context, on: Boolean) = prefs(c).edit().putBoolean("lock_desktop", on).apply()

    /** "auto" picks from the GPU found on the device (GpuProfile). */
    fun gpuMode(c: Context) = prefs(c).getString("gpu_mode", "auto")!!.let { if (it == "virgl") "venus" else it }
    fun setGpuMode(c: Context, mode: String) = prefs(c).edit().putString("gpu_mode", mode).apply()

    /** Venus GPU memory sharing: "auto" (asks the driver), "dmabuf" or "ahb" (VenusServer). */
    fun venusMemory(c: Context) = prefs(c).getString("venus_memory", "auto")!!
    fun setVenusMemory(c: Context, m: String) = prefs(c).edit().putString("venus_memory", m).apply()

    /** In Venus mode, also put KWin (desktop effects) on the GPU. Off: KWin uses llvmpipe. */
    fun gpuDesktop(c: Context) = prefs(c).getBoolean("gpu_desktop", false)
    fun setGpuDesktop(c: Context, on: Boolean) = prefs(c).edit().putBoolean("gpu_desktop", on).apply()

    /** Plasma session: "x11" (default) or "wayland" (experimental: KWin nested in the X server, software rendering). */
    fun sessionType(c: Context) = prefs(c).getString("session_type", "x11")!!
    fun setSessionType(c: Context, type: String) = prefs(c).edit().putString("session_type", type).apply()

    /** touchpad (the screen moves a pointer) or direct (a phone's touch: tap clicks, slide scrolls, hold for the right button or to drag). */
    fun touchMode(c: Context) = prefs(c).getString("touch_mode", "touchpad")!!.let { if (it == "touch") "direct" else it }
    val TOUCH_MODES = listOf("touchpad", "direct")
    val TOUCH_MODE_LABELS = listOf("Touchpad", "Direct touch")
    fun setTouchMode(c: Context, mode: String) = prefs(c).edit().putString("touch_mode", mode).apply()

    /** Desktop scale: 1 = native pixels (default), 0 = from the display's density. */
    fun scale(c: Context) = prefs(c).getFloat("scale", 1f)
    fun setScale(c: Context, s: Float) = prefs(c).edit().putFloat("scale", s).apply()

    /** The native desktop's scale (KWin's output); 0 = from the display's density. */
    fun nativeScale(c: Context) = prefs(c).getFloat("native_scale", 0f)
    fun setNativeScale(c: Context, s: Float) = prefs(c).edit().putFloat("native_scale", s).apply()

    /** Keep panels and maximized windows clear of the camera cutout and rounded corners. */
    fun dodgeCutouts(c: Context) = prefs(c).getBoolean("dodge_cutouts", true)
    fun setDodgeCutouts(c: Context, on: Boolean) = prefs(c).edit().putBoolean("dodge_cutouts", on).apply()

    /** The phone's keyboard opens by itself for a desktop text field (else only from the menu). */
    fun autoKeyboard(c: Context) = prefs(c).getBoolean("auto_keyboard", false)
    fun setAutoKeyboard(c: Context, on: Boolean) = prefs(c).edit().putBoolean("auto_keyboard", on).apply()

    /** The screen stays on while the desktop is showing. */
    fun keepAwake(c: Context) = prefs(c).getBoolean("keep_awake", false)
    fun setKeepAwake(c: Context, on: Boolean) = prefs(c).edit().putBoolean("keep_awake", on).apply()

    /** Two-finger scrolling as a mouse wheel (vertical, by lines; default) or a touchpad's (any direction, smooth). */
    fun scrollWheel(c: Context) = prefs(c).getBoolean("scroll_wheel", true)
    fun setScrollWheel(c: Context, on: Boolean) = prefs(c).edit().putBoolean("scroll_wheel", on).apply()

    /** The DD menu's dock: up to 10 phone apps, as flattened component names. */
    fun dockApps(c: Context): List<String> =
        prefs(c).getString("dock_apps", "")!!.split('\n').filter { it.isNotBlank() }
    fun setDockApps(c: Context, apps: List<String>) =
        prefs(c).edit().putString("dock_apps", apps.take(10).joinToString("\n")).apply()

    fun askedNotifications(c: Context) = prefs(c).getBoolean("asked_notifications", false)
    fun setAskedNotifications(c: Context) = prefs(c).edit().putBoolean("asked_notifications", true).apply()
    fun setupDone(c: Context) = prefs(c).getBoolean("setup_done", false)
    fun setSetupDone(c: Context, on: Boolean) = prefs(c).edit().putBoolean("setup_done", on).apply()

    /** Edition picked on the install screen; the download resumes with it. */
    fun pendingEdition(c: Context) = prefs(c).getString("pending_edition", null)
    fun setPendingEdition(c: Context, e: String?) = prefs(c).edit().putString("pending_edition", e).apply()
}
