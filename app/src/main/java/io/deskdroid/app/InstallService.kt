package io.deskdroid.app

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.IBinder

/** Runs the install in a foreground service so leaving the app doesn't kill it. */
class InstallService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(
            2, Notifications.build(this, "Installing the desktop"),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        )
        val url = intent?.getStringExtra(EXTRA_URL)
        @Suppress("DEPRECATION")
        val file = intent?.getParcelableExtra<Uri>(EXTRA_FILE)
        Thread {
            try {
                val installer = RootfsInstaller(Paths(this))
                when {
                    file != null -> contentResolver.openInputStream(file)!!.use { installer.installFromStream(it) }
                    url != null -> installer.installFromUrl(url)
                }
            } catch (e: Exception) {
                AppLog.setStatus("Install failed: ${e.message}")
                AppLog.i(e.stackTraceToString())
            } finally {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }.start()
        return START_NOT_STICKY
    }

    companion object {
        const val EXTRA_URL = "url"
        const val EXTRA_FILE = "file"
    }
}
