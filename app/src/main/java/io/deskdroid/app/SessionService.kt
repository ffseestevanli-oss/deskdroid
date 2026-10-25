package io.deskdroid.app

import android.app.ActivityOptions
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.system.Os
import java.io.File
import java.util.TimeZone

/**
 * Owns the desktop session: the embedded X server (Termux:X11's lorie), the
 * proot'd Plasma session, the audio bridge, and the desktop window.
 */
class SessionService : Service() {
    private var xServer: Process? = null
    private var session: Process? = null
    private var gpuServer: Process? = null
    private var audio: AudioBridge? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var displayId = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        AppLog.attach(this)
        when (intent?.action) {
            ACTION_STOP -> {
                stopSession()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_SHOW -> {
                if (session?.isAlive == true) showDesktop(displayId)
                else startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return START_NOT_STICKY
            }
        }
        startForeground(
            Notifications.SESSION_ID, Notifications.session(this, "Starting your desktop"),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        )
        displayId = intent?.getIntExtra(EXTRA_DISPLAY, 0) ?: 0
        if (session?.isAlive == true) {
            showDesktop(displayId)
            return START_NOT_STICKY
        }
        // Started at boot: Android won't let a background app open a window, so run
        // without showing it; "Start desktop" or the notification brings it up.
        val headless = intent?.getBooleanExtra(EXTRA_HEADLESS, false) ?: false
        running = true
        Thread { runSession(headless) }.start()
        return START_NOT_STICKY
    }

    private fun runSession(headless: Boolean) {
        val paths = Paths(this)
        try {
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "deskdroid:session")
                .apply { acquire() }

            paths.runtime.mkdirs()
            paths.readyFile.delete()
            audio = AudioBridge(paths.audioPipe).also { it.start() }

            AppLog.setStatus("Starting display server")
            File(paths.rootfsTmp, ".X11-unix").mkdirs()
            paths.x11Socket.delete()
            DesktopDefaults.apply(this)
            xServer = startX11Server(paths).also { pump("x11", it) }
            waitFor(paths.x11Socket, 15_000)
            if (!headless) showDesktop(displayId)

            val wayland = Prefs.sessionType(this) == "wayland"
            // The experimental Wayland session renders in software for now (deskdroid-session).
            var gpu = if (wayland) "llvmpipe" else GpuProfile.resolve(Prefs.gpuMode(this), paths)
            if (gpu == "venus") {
                AppLog.setStatus("Starting the GPU server")
                gpuServer = VenusServer.start(this, paths) { pump("venus", it) }
                if (gpuServer != null) {
                    AppLog.setStatus("Testing the GPU")
                    if (!VenusServer.selfTest(paths)) { gpuServer?.destroy(); gpuServer = null }
                }
                if (gpuServer == null) {
                    AppLog.i("GPU server unavailable; using software rendering")
                    gpu = "llvmpipe"
                }
            }
            VenusServer.writeSessionEnv(this, paths, gpu == "venus")
            Browsers.install(this, paths)
            Flatpak.install(this, paths)
            Steam.install(this, paths)
            Splash.install(this, paths)
            AppLog.setStatus("Linking your phone's files")
            val binds = Storage.prepare(this, paths)
            AppLog.setStatus("Starting the desktop (${if (wayland) "Wayland, " else ""}${GpuProfile.describe(gpu)})")
            session = Proot.sessionCommand(paths, sessionEnv(gpu, wayland), binds).start().also { pump("session", it) }
            AppLog.setStatus("Loading the desktop")
            notify("Desktop starting · tap to open")
            watchReady(paths, session!!)
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

    /** Waits for the splash watcher's ready file (Splash), which takes the splash screen down. */
    private fun watchReady(paths: Paths, p: Process) = Thread {
        while (p.isAlive && !paths.readyFile.exists()) Thread.sleep(500)
        if (p.isAlive) {
            ready = true
            AppLog.setStatus("Desktop running")
            notify("Desktop running · tap to open")
        }
    }.start()

    private fun sessionEnv(gpu: String, wayland: Boolean): Map<String, String> {
        val scale = Prefs.scale(this).takeIf { it > 0f } ?: DesktopDefaults.scaleFor(this)
        return mapOf(
            "DESKDROID_GPU" to gpu,
            "DESKDROID_SESSION" to if (wayland) "wayland" else "x11",
            "DESKDROID_SCALE" to "%.2f".format(java.util.Locale.ROOT, scale),
            "TZ" to TimeZone.getDefault().id,
        ) + Browsers.geckoEnv
    }

    /**
     * The X server is Termux:X11's CmdEntryPoint, compiled into this APK. It runs
     * as a separate app_process, the same way the termux-x11 command starts it,
     * and connects back to DesktopActivity. The socket lands in the rootfs /tmp.
     *
     * CmdEntryPoint finds libXlorie.so as the class path resource
     * lib/<abi>/libXlorie.so and System.load()s that path. Native libs in the APK
     * are compressed (they must be extracted for proot, W^X), so a directory that
     * links the resource to the extracted copy goes ahead of the APK.
     */
    private fun startX11Server(paths: Paths): Process {
        val libRoot = File(cacheDir, "x11-libpath")
        val abiDir = File(libRoot, "lib/${Build.SUPPORTED_ABIS[0]}").apply { mkdirs() }
        val link = File(abiDir, "libXlorie.so")
        link.delete()
        Os.symlink(File(applicationInfo.nativeLibraryDir, "libXlorie.so").path, link.path)
        val pb = ProcessBuilder(
            "/system/bin/app_process", "-Xnoimage-dex2oat", "/",
            "com.termux.x11.CmdEntryPoint", ":0"
        ).redirectErrorStream(true)
        pb.environment().apply {
            remove("LD_PRELOAD"); remove("LD_LIBRARY_PATH")
            put("CLASSPATH", "${libRoot.path}:${applicationInfo.sourceDir}")
            put("TMPDIR", paths.rootfsTmp.path)
            put("XKB_CONFIG_ROOT", File(paths.rootfs, "usr/share/X11/xkb").path)
        }
        return pb.start()
    }

    private fun showDesktop(id: Int) {
        val intent = Intent(this, DesktopActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val opts = ActivityOptions.makeBasic().setLaunchDisplayId(id)
        try {
            startActivity(intent, opts.toBundle())
        } catch (e: Exception) {
            // Background start blocked (Android 10+); the notification opens it.
            AppLog.i("Couldn't open the desktop window: ${e.message}")
        }
    }

    private fun notify(text: String) =
        getSystemService(android.app.NotificationManager::class.java)
            .notify(Notifications.SESSION_ID, Notifications.session(this, text))

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

    @Synchronized
    private fun stopSession() {
        session?.destroy(); session = null
        gpuServer?.destroy(); gpuServer = null
        xServer?.destroy(); xServer = null
        audio?.stop(); audio = null
        wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null
        sendBroadcast(Intent("com.termux.x11.ACTION_STOP").setPackage(packageName))
        running = false
        ready = false
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    override fun onDestroy() {
        stopSession()
        super.onDestroy()
    }

    companion object {
        const val ACTION_STOP = "io.deskdroid.app.STOP"
        const val ACTION_SHOW = "io.deskdroid.app.SHOW"
        const val EXTRA_DISPLAY = "display"
        const val EXTRA_HEADLESS = "headless"

        @Volatile var running = false
            private set

        /** The desktop shell is up, so the splash screen can go. */
        @Volatile var ready = false
            private set

        fun start(c: Context, displayId: Int) = c.startForegroundService(
            Intent(c, SessionService::class.java).putExtra(EXTRA_DISPLAY, displayId)
        )

        fun stop(c: Context) =
            c.startService(Intent(c, SessionService::class.java).setAction(ACTION_STOP))
    }
}
