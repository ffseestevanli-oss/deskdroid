package io.deskdroid.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent

object Notifications {
    const val SESSION_ID = 1
    const val INSTALL_ID = 2
    private const val DONE_ID = 3
    private const val SESSION = "session"
    private const val INSTALL = "install"

    private fun channels(c: Context) {
        val nm = c.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(SESSION, "Desktop session", NotificationManager.IMPORTANCE_LOW))
        nm.createNotificationChannel(NotificationChannel(INSTALL, "Installing", NotificationManager.IMPORTANCE_LOW))
    }

    private fun open(c: Context) = PendingIntent.getActivity(
        c, 0, Intent(c, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE
    )

    /** Session notification; tapping it opens the desktop. */
    fun session(c: Context, text: String): Notification {
        channels(c)
        val show = PendingIntent.getService(
            c, 1, android.content.Intent(c, SessionService::class.java).setAction(SessionService.ACTION_SHOW),
            PendingIntent.FLAG_IMMUTABLE
        )
        val stop = PendingIntent.getService(
            c, 2, android.content.Intent(c, SessionService::class.java).setAction(SessionService.ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(c, SESSION)
            .setContentTitle("DeskDroid")
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(show)
            .addAction(Notification.Action.Builder(null, "Stop desktop", stop).build())
            .setOngoing(true)
            .build()
    }

    fun install(c: Context, text: String, fraction: Float): Notification {
        channels(c)
        val cancel = PendingIntent.getService(
            c, 3, Intent(c, InstallService::class.java).setAction(InstallService.ACTION_CANCEL),
            PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(c, INSTALL)
            .setContentTitle("Installing your desktop")
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(open(c))
            .setProgress(1000, (fraction * 1000).toInt(), fraction < 0)
            .addAction(Notification.Action.Builder(null, "Cancel", cancel).build())
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .build()
    }

    fun updateInstall(c: Context, text: String, fraction: Float) =
        c.getSystemService(NotificationManager::class.java).notify(INSTALL_ID, install(c, text, fraction))

    fun installDone(c: Context) {
        channels(c)
        c.getSystemService(NotificationManager::class.java).notify(
            DONE_ID,
            Notification.Builder(c, INSTALL)
                .setContentTitle("Your desktop is ready")
                .setContentText("Tap to finish setting up")
                .setSmallIcon(R.drawable.ic_notification)
                .setContentIntent(open(c))
                .setAutoCancel(true)
                .build()
        )
    }
}
