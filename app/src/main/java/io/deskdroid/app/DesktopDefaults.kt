package io.deskdroid.app

import android.content.Context
import android.util.DisplayMetrics
import android.view.WindowManager

/**
 * Settings for the embedded Termux:X11 (lorie) activity. lorie keeps its
 * preferences in this app's default SharedPreferences and reacts to changes
 * live, so DeskDroid writes the keys it cares about directly.
 * Keys: external/termux-x11/lorie/src/main/res/xml/preferences.xml.
 */
object DesktopDefaults {
    private const val VERSION = 1

    private fun lorie(c: Context) = c.getSharedPreferences("${c.packageName}_preferences", Context.MODE_PRIVATE)

    /** First start (or a newer defaults version): a phone-friendly desktop. */
    fun apply(c: Context) {
        val p = lorie(c)
        if (p.getInt("deskdroid_defaults", 0) >= VERSION) return
        p.edit()
            .putString("displayResolutionMode", "native")
            .putBoolean("fullscreen", true)
            .putBoolean("hideCutout", true)
            .putBoolean("Reseed", true)
            .putString("screenIdleTimeout", "never")
            .putBoolean("clipboardEnable", true)
            .putBoolean("showAdditionalKbd", true)
            .putBoolean("additionalKbdVisible", false)
            .putBoolean("dexMetaKeyCapture", true)
            .putBoolean("requestNotificationPermission", false)
            .putString("backButtonAction", "toggle soft keyboard")
            .putString("swipeDownAction", "toggle additional key bar")
            .putString("notificationTapAction", "no action")
            .putInt("deskdroid_defaults", VERSION)
            .apply()
        applyTouchMode(c)
    }

    /** lorie touchMode: 1 = trackpad, 3 = direct touch. */
    fun applyTouchMode(c: Context) {
        lorie(c).edit().putString("touchMode", if (Prefs.touchMode(c) == "direct") "3" else "1").apply()
    }

    fun setExtraKeysVisible(c: Context, visible: Boolean) =
        lorie(c).edit().putBoolean("additionalKbdVisible", visible).apply()

    /**
     * Plasma scale from screen density: a 6.5" 1080p phone (~420 dpi) gets 2x so
     * text is readable; monitors (~100-160 dpi) get 1x.
     */
    fun scaleFor(c: Context, displayContext: Context = c): Float {
        val dm = DisplayMetrics()
        @Suppress("DEPRECATION")
        displayContext.getSystemService(WindowManager::class.java).defaultDisplay.getRealMetrics(dm)
        val s = dm.densityDpi / 192f
        return (Math.round(s * 4) / 4f).coerceIn(1f, 2.5f)
    }
}
