package io.deskdroid.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder

/**
 * Keeps the native desktop (compositor, KWin, Plasma, apps) running while its
 * window is in the background: a foreground service with a notification that
 * brings the desktop back or stops it.
 */
class NativeDeskService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            NativeDesk.stop(this, "Stop desktop in the notification")
            stopSelf()
            return START_NOT_STICKY
        }
        startForeground(ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        return START_NOT_STICKY
    }

    private fun notification(): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        // As the phone's home app the desktop is always there: its notification
        // goes in a minimal channel (no status bar icon, folded at the bottom).
        val home = packageManager.resolveActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), android.content.pm.PackageManager.MATCH_DEFAULT_ONLY
        )?.activityInfo?.packageName == packageName
        val channel = if (home) CHANNEL_HOME else CHANNEL
        if (home) nm.createNotificationChannel(NotificationChannel(CHANNEL_HOME, "Plasma desktop (home app)", NotificationManager.IMPORTANCE_MIN))
        else nm.createNotificationChannel(NotificationChannel(CHANNEL, "Plasma desktop", NotificationManager.IMPORTANCE_LOW))
        val show = PendingIntent.getActivity(
            this, 10, Intent(this, NativeDeskActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE
        )
        val stop = PendingIntent.getService(
            this, 11, Intent(this, NativeDeskService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, channel)
            .setContentTitle("DeskDroid")
            .setContentText("Plasma desktop running · tap to open")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(show)
            .addAction(Notification.Action.Builder(null, "Stop desktop", stop).build())
            .setOngoing(true)
            .build()
    }

    companion object {
        const val ACTION_STOP = "io.deskdroid.app.NATIVE_STOP"
        private const val CHANNEL = "nativedesk"
        private const val CHANNEL_HOME = "nativedesk-home"
        private const val ID = 4
    }
}
