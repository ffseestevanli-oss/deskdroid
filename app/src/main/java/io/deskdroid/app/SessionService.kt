package io.deskdroid.app

import android.app.ActivityOptions
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.os.PowerManager
import java.io.File

/**
 * Owns the desktop session: Termux:X11 server, the proot'd Plasma session,
 * and the X11 window on the chosen display.
 */
class SessionService : Service() {
    private var xServer: Process? = null
    private var session: Process? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSession()
            stopSelf()
            return START_NOT_STICKY
        }
        startForeground(
            1, Notifications.build(this, "Desktop running"),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        )
        if (session?.isAlive == true) {
            showDisplay(intent?.getIntExtra(EXTRA_DISPLAY, 0) ?: 0)
            return START_NOT_STICKY
        }
        val gpu = intent?.getStringExtra(EXTRA_GPU) ?: "llvmpipe"
        val display = intent?.getIntExtra(EXTRA_DISPLAY, 0) ?: 0
        Thread { runSession(gpu, display) }.start()
        return START_NOT_STICKY
    }

    private fun runSession(gpu: String, displayId: Int) {
        val paths = Paths(this)
        try {
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "deskdroid:session")
                .apply { acquire() }

            AppLog.setStatus("Starting display server")
            paths.x11Socket.delete()
            xServer = startX11Server(paths).also { pump("x11", it) }
            waitFor(paths.x11Socket, 15_000)
            showDisplay(displayId)

            AppLog.setStatus("Starting Plasma ($gpu)")
            session = Proot.sessionCommand(paths, gpu).start().also { pump("session", it) }
            AppLog.setStatus("Desktop running")
            val code = session!!.waitFor()
            AppLog.setStatus("Desktop exited (code $code)")
        } catch (e: Exception) {
            AppLog.setStatus("Session failed: ${e.message}")
            AppLog.i(e.stackTraceToString())
        } finally {
            stopSession()
            stopSelf()
        }
    }

    /**
     * Phase 0: run the X server from the installed Termux:X11 APK, the same way
     * Termux's `termux-x11` script does. The socket lands in the rootfs /tmp.
     */
    private fun startX11Server(paths: Paths): Process {
        val apk = packageManager.getApplicationInfo(X11_PACKAGE, 0).sourceDir
        val pb = ProcessBuilder(
            "/system/bin/app_process", "-Xnoimage-dex2oat", "/",
            "com.termux.x11.CmdEntryPoint", ":0"
        ).redirectErrorStream(true)
        pb.environment().apply {
            remove("LD_PRELOAD"); remove("LD_LIBRARY_PATH")
            put("CLASSPATH", apk)
            put("TMPDIR", File(paths.rootfs, "tmp").path)
            put("XKB_CONFIG_ROOT", File(paths.rootfs, "usr/share/X11/xkb").path)
        }
        return pb.start()
    }

    private fun showDisplay(displayId: Int) {
        val intent = Intent().setClassName(X11_PACKAGE, "$X11_PACKAGE.MainActivity")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val opts = ActivityOptions.makeBasic().setLaunchDisplayId(displayId)
        startActivity(intent, opts.toBundle())
    }

    private fun waitFor(f: File, timeoutMs: Long) {
        val end = System.currentTimeMillis() + timeoutMs
        while (!f.exists()) {
            check(xServer?.isAlive == true) { "X server exited early" }
            check(System.currentTimeMillis() < end) { "X server socket did not appear" }
            Thread.sleep(200)
        }
    }

    private fun pump(tag: String, p: Process) = Thread {
        p.inputStream.bufferedReader().forEachLine { AppLog.i("[$tag] $it") }
    }.start()

    private fun stopSession() {
        session?.destroy(); session = null
        xServer?.destroy(); xServer = null
        wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    override fun onDestroy() {
        stopSession()
        super.onDestroy()
    }

    companion object {
        const val X11_PACKAGE = "com.termux.x11"
        const val ACTION_STOP = "io.deskdroid.app.STOP"
        const val EXTRA_GPU = "gpu"
        const val EXTRA_DISPLAY = "display"
    }
}
