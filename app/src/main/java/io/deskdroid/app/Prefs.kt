package io.deskdroid.app

import android.content.Context

/** Launcher preferences. */
object Prefs {
    private fun prefs(c: Context) = c.getSharedPreferences("settings", Context.MODE_PRIVATE)

    fun autoStart(c: Context) = prefs(c).getBoolean("auto_start", false)
    fun setAutoStart(c: Context, on: Boolean) = prefs(c).edit().putBoolean("auto_start", on).apply()

    fun gpuMode(c: Context) = prefs(c).getString("gpu_mode", "llvmpipe")!!
    fun setGpuMode(c: Context, mode: String) = prefs(c).edit().putString("gpu_mode", mode).apply()
}
