package io.deskdroid.app

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.IBinder
import android.os.PowerManager
import io.deskdroid.app.InstallState.Snapshot
import io.deskdroid.app.InstallState.Step
import java.io.File

/** Runs the install in a foreground service so leaving the app doesn't stop it. */
class InstallService : Service() {
    @Volatile private var worker: Thread? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL) {
            InstallState.cancelled = true
            return START_NOT_STICKY
        }
        startForeground(
            Notifications.INSTALL_ID, Notifications.install(this, "Getting ready", -1f),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        )
        if (worker?.isAlive == true) return START_NOT_STICKY
        val edition = intent?.getStringExtra(EXTRA_EDITION)
        @Suppress("DEPRECATION")
        val file = intent?.getParcelableExtra<Uri>(EXTRA_FILE)
        InstallState.cancelled = false
        val progress: (Snapshot) -> Unit = { s ->
            if (s.running) Notifications.updateInstall(this, s.detail.ifEmpty { s.step.name }, s.overall)
        }
        InstallState.listen(progress)
        worker = Thread {
            val wake = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "deskdroid:install")
            wake.acquire(3 * 60 * 60 * 1000L)
            try {
                val installer = RootfsInstaller(Paths(this))
                when {
                    file != null -> installer.installFromFile(copyPicked(file))
                    edition != null -> installer.installEdition(BuildConfig.ROOTFS_BASE_URL, edition)
                }
                Prefs.setPendingEdition(this, null)
            } catch (e: RootfsInstaller.Cancelled) {
                InstallState.update(Snapshot(Step.IDLE, detail = "Cancelled"))
            } catch (e: Exception) {
                AppLog.i(e.stackTraceToString())
                InstallState.update(Snapshot(Step.FAILED, error = e.message ?: e.javaClass.simpleName))
            } finally {
                if (wake.isHeld) wake.release()
                InstallState.unlisten(progress)
                stopForeground(STOP_FOREGROUND_REMOVE)
                if (InstallState.current.step == Step.DONE) Notifications.installDone(this)
                stopSelf()
            }
        }.apply { start() }
        return START_NOT_STICKY
    }

    private fun copyPicked(uri: Uri): File {
        InstallState.update(Snapshot(Step.DOWNLOAD, -1f, "Copying the file"))
        val paths = Paths(this)
        paths.downloads.mkdirs()
        val dest = File(paths.downloads, "picked.tar.zst")
        contentResolver.openInputStream(uri)!!.use { i -> dest.outputStream().use { i.copyTo(it, 1 shl 17) } }
        return dest
    }

    companion object {
        const val EXTRA_EDITION = "edition"
        const val EXTRA_FILE = "file"
        const val ACTION_CANCEL = "io.deskdroid.app.CANCEL_INSTALL"

        fun startEdition(c: Context, edition: String) {
            Prefs.setPendingEdition(c, edition)
            c.startForegroundService(Intent(c, InstallService::class.java).putExtra(EXTRA_EDITION, edition))
        }

        fun startFile(c: Context, uri: Uri) = c.startForegroundService(
            Intent(c, InstallService::class.java).putExtra(EXTRA_FILE, uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        )

        fun cancel(c: Context) =
            c.startService(Intent(c, InstallService::class.java).setAction(ACTION_CANCEL))
    }
}
