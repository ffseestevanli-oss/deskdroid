package io.deskdroid.app

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent
import android.widget.Toast

/**
 * Android's power menu (Power off, Restart, Emergency) for the desktop's
 * Restart or Power Off button: no app can restart or power off the phone
 * itself without root, but an accessibility service the user turns on can
 * open the menu that does. It reads nothing on the screen.
 */
class PowerMenuService : AccessibilityService() {
    override fun onServiceConnected() {
        instance = this
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    companion object {
        @Volatile private var instance: PowerMenuService? = null

        /** Opens the power menu, or Android's accessibility settings to turn the service on. */
        fun open(c: Context) {
            val s = instance
            if (s != null && s.performGlobalAction(GLOBAL_ACTION_POWER_DIALOG)) {
                AppLog.i("Native desktop: Android's power menu")
                return
            }
            AppLog.i("Native desktop: power menu service is off, opening accessibility settings")
            Toast.makeText(c, "Turn on \"DeskDroid power menu\" to restart or power off from the desktop", Toast.LENGTH_LONG).show()
            c.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}
