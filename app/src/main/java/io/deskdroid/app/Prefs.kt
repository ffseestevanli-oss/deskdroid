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

    fun touchMode(c: Context) = prefs(c).getString("touch_mode", "touchpad")!!
    fun setTouchMode(c: Context, mode: String) = prefs(c).edit().putString("touch_mode", mode).apply()

    /** Desktop scale: 1 = native pixels (default), 0 = from the display's density. */
    fun scale(c: Context) = prefs(c).getFloat("scale", 1f)
    fun setScale(c: Context, s: Float) = prefs(c).edit().putFloat("scale", s).apply()

    fun setupDone(c: Context) = prefs(c).getBoolean("setup_done", false)
    fun setSetupDone(c: Context, on: Boolean) = prefs(c).edit().putBoolean("setup_done", on).apply()

    /** Edition picked on the install screen; the download resumes with it. */
    fun pendingEdition(c: Context) = prefs(c).getString("pending_edition", null)
    fun setPendingEdition(c: Context, e: String?) = prefs(c).edit().putString("pending_edition", e).apply()
}
