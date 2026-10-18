package io.deskdroid.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Optional "start desktop when the phone boots". BOOT_COMPLETED arrives after the
 * first unlock, when app storage (and so the rootfs) is decrypted. The session
 * starts in the background; the user opens it from the notification or the app.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (!Prefs.autoStart(context) || !Paths(context).isInstalled) return
        context.startForegroundService(
            Intent(context, SessionService::class.java)
                .putExtra(SessionService.EXTRA_GPU, Prefs.gpuMode(context))
                .putExtra(SessionService.EXTRA_HEADLESS, true)
        )
    }
}
