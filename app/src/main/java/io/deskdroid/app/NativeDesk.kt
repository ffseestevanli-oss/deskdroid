package io.deskdroid.app

import android.app.Activity
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.widget.FrameLayout
import android.widget.LinearLayout
import io.deskdroid.app.ui.dp
import io.deskdroid.app.ui.spacer
import io.deskdroid.app.ui.tile
import android.widget.TextView
import java.io.File
import kotlin.math.abs

/** The menu's desktop scales; 0 is automatic (from the screen's density). */
private val SCALES = listOf(0f, 1f, 1.25f, 1.5f, 1.75f, 2f, 2.5f, 3f)
private const val EDGE_DP = 56f // how far up from the bottom a corner swipe may start

/**
 * Native desktop test: the first step towards running Plasma as Android code
 * (no proot, no Linux libc, no GPU forwarding). native/nativedesk/compositor.c
 * draws windows into this activity's surface with the phone's own GPU driver;
 * the windows belong to separate app processes (testclient.c) that render into
 * shared GPU buffers. The overlay shows frame rates, which is what this test
 * is for. Nothing here touches the Linux desktop or its files.
 */
object NativeDesk {
    init {
        System.loadLibrary("nativedesk")
    }

    @JvmStatic external fun nativeStart(surface: Surface): Boolean
    @JvmStatic external fun nativeStop()
    @JvmStatic external fun nativePointer(x: Float, y: Float, buttons: Int)
    @JvmStatic external fun nativeKey(keycode: Int, unicode: Int, down: Boolean)
    @JvmStatic external fun nativeScroll(dx: Float, dy: Float, wheel: Boolean)
    @JvmStatic external fun nativeStats(): String
    @JvmStatic external fun nativeResized()
    @JvmStatic external fun nativeDetach()
    @JvmStatic external fun nativeSetScale(scale: Float)
    @JvmStatic external fun nativeSetSafeArea(left: Float, top: Float, right: Float, bottom: Float)
    /** The phone's apps in Plasma's menu are watched once per process (watchAndroidApps). */
    @Volatile var appsWatched = false
    private val appsLock = Any()
    private var appsRunning = false
    private var appsAgain = false

    /**
     * Runs a listing of the phone's apps for the menu, one at a time: asked
     * again while one runs, it runs once more afterwards instead of alongside.
     */
    fun refreshAndroidApps(list: () -> Unit) {
        synchronized(appsLock) {
            if (appsRunning) { appsAgain = true; return }
            appsRunning = true
        }
        Thread {
            while (true) {
                synchronized(appsLock) { appsAgain = false }
                runCatching(list).onFailure { AppLog.i("Native desktop: listing Android apps failed: $it") }
                synchronized(appsLock) {
                    if (!appsAgain) { appsRunning = false; return@Thread }
                }
            }
        }.start()
    }

    /** A desktop action (protocol.h's NDESK_ACTION_*): 1 shows the desktop. */
    @JvmStatic external fun nativeAction(action: Int)

    /** Plasma's usual size on a phone (about twice the panel's pixels), or the menu's choice. */
    fun desktopScale(c: android.content.Context): Float =
        Prefs.nativeScale(c).takeIf { it > 0f }
            ?: ((c.resources.displayMetrics.density / 1.75f * 4).toInt().coerceIn(4, 12) / 4f)

    /** From the compositor: a text field in the desktop took (or lost) the keyboard focus. */
    @JvmStatic @androidx.annotation.Keep
    fun onIme(show: Boolean) {
        Handler(Looper.getMainLooper()).post {
            // Manual keyboard (the default): a text field doesn't open it, only the menu does.
            val c = touchpad?.get() ?: activity?.get()
            if (show && c != null && !Prefs.autoKeyboard(c)) return@post
            // On a monitor the keyboard belongs to the phone's touchpad screen.
            touchpad?.get()?.softKeyboard(show) ?: (activity?.get() as? NativeDeskActivity)?.softKeyboard(show)
        }
    }

    // The desktop outlives its window: Home or switching apps takes the
    // activity's surface away, but the compositor, KWin, Plasma and the apps
    // keep running under NativeDeskService until the user stops the desktop.
    val apps = mutableListOf<Process>()
    @Volatile var running = false
    @Volatile var activity: java.lang.ref.WeakReference<Activity>? = null
    // The window the compositor draws into now (the phone's or a monitor's), and its size.
    @Volatile var owner: java.lang.ref.WeakReference<Activity>? = null
    @Volatile var surfaceW = 0f
    @Volatile var surfaceH = 0f
    // The phone's touchpad screen while the desktop is on a monitor.
    @Volatile var touchpad: java.lang.ref.WeakReference<PhoneTouchpadActivity>? = null
    // The overlay's last lines, kept across activity instances.
    val qtLines = ArrayDeque<String>()
    @Volatile var qtStatus = "Qt demo: not in this build"
    // KWin said it takes apps' GPU buffers (deskdroid_ahb_v1): Qt apps draw on the GPU.
    @Volatile var kwinTakesGpuBuffers = false

    // Open with Android app: bin/android-open (android-open.sh) leaves each file
    // as a request in files/open-requests; this opens it in Android's chooser.
    private var openWatcher: android.os.FileObserver? = null

    fun watchOpenRequests(c: android.content.Context) {
        if (openWatcher != null) return
        val dir = File(c.filesDir, "open-requests").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() } // left from an earlier session
        @Suppress("DEPRECATION")
        openWatcher = object : android.os.FileObserver(dir.path, MOVED_TO) {
            override fun onEvent(event: Int, name: String?) {
                if (name == null || !name.endsWith(".req")) return
                val req = File(dir, name)
                val path = try { req.readText().trim() } catch (e: Exception) { "" }
                req.delete()
                // KDE's logout screen: Close Desktop (patched in add-to-workspace.py).
                if (name == "end-session.req") {
                    AppLog.i("Native desktop: Close Desktop from the logout screen")
                    Handler(Looper.getMainLooper()).post { stop(c, "Close Desktop") }
                    return
                }
                // Restart or Power Off on the logout screen: Android's power menu.
                if (name == "power-menu.req") {
                    Handler(Looper.getMainLooper()).post { PowerMenuService.open(activity?.get() ?: c) }
                    return
                }
                // App Store in Plasma's menu.
                if (path == "deskdroid:store") {
                    Handler(Looper.getMainLooper()).post {
                        val a = activity?.get() ?: c
                        a.startActivity(android.content.Intent(a, StoreActivity::class.java).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
                    }
                    return
                }
                // An Android app from Plasma's menu (writeAndroidApps).
                if (path.startsWith("android-app:")) {
                    Handler(Looper.getMainLooper()).post { launchAndroidApp(c, path.removePrefix("android-app:")) }
                    return
                }
                if (path.isNotEmpty()) Handler(Looper.getMainLooper()).post { openWithAndroid(c, path) }
            }
        }.also { it.startWatching() }
    }

    private fun launchAndroidApp(c: android.content.Context, target: String) {
        // An app in another profile (Private Space, Work): <package>@<profile serial>.
        if ('@' in target) {
            val pkg = target.substringBefore('@')
            val users = c.getSystemService(android.os.UserManager::class.java)
            val user = target.substringAfter('@').toLongOrNull()?.let { users.getUserForSerialNumber(it) }
            val launcher = c.getSystemService(android.content.pm.LauncherApps::class.java)
            try {
                if (user == null) throw Exception("profile is gone")
                // Locked (Private Space) or paused (Work): Android asks to unlock it first.
                if (users.isQuietModeEnabled(user)) {
                    users.requestQuietModeEnabled(false, user)
                    AppLog.i("Native desktop: asked to unlock profile for $pkg")
                    return
                }
                val activity = launcher.getActivityList(pkg, user).firstOrNull() ?: throw Exception("no app to open")
                launcher.startMainActivity(activity.componentName, user, null, null)
                AppLog.i("Native desktop: opened $target")
            } catch (e: Exception) {
                AppLog.i("Native desktop: couldn't open $target: $e")
            }
            return
        }
        val pkg = target
        val intent = c.packageManager.getLaunchIntentForPackage(pkg)
            ?.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        if (intent == null) {
            AppLog.i("Native desktop: $pkg has no app to open")
            return
        }
        try {
            (activity?.get() ?: c).startActivity(intent)
            AppLog.i("Native desktop: opened $pkg")
        } catch (e: Exception) {
            AppLog.i("Native desktop: couldn't open $pkg: $e")
        }
    }

    private fun openWithAndroid(c: android.content.Context, path: String) {
        // A web link (no browser on the desktop): the phone's browser.
        if (path.startsWith("http://") || path.startsWith("https://")) {
            try {
                val view = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(path))
                    .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                (activity?.get() ?: c).startActivity(view)
                AppLog.i("Native desktop: opening a link with the phone's browser")
            } catch (e: Exception) {
                AppLog.i("Native desktop: couldn't open a link with the phone's browser: $e")
            }
            return
        }
        val file = File(if (path.startsWith("file://")) android.net.Uri.parse(path).path ?: path else path)
        try {
            val uri = androidx.core.content.FileProvider.getUriForFile(c, "${c.packageName}.files", file)
            val ext = file.name.substringAfterLast('.', "").lowercase()
            val type = android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "*/*"
            val view = android.content.Intent(android.content.Intent.ACTION_VIEW)
                .setDataAndType(uri, type)
                .addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION or android.content.Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            val chooser = android.content.Intent.createChooser(view, file.name)
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            (activity?.get() ?: c).startActivity(chooser)
            AppLog.i("Native desktop: opening ${file.path} ($type) with an Android app")
        } catch (e: Exception) {
            AppLog.i("Native desktop: couldn't open ${file.path} with an Android app: $e")
        }
    }

    /** Ends the desktop: its processes, the compositor, the service and the window. */
    fun stop(c: android.content.Context, why: String) {
        synchronized(apps) {
            apps.forEach { it.destroy() }
            apps.clear()
        }
        openWatcher?.stopWatching()
        openWatcher = null
        if (running) nativeStop()
        running = false
        PhoneStatus.stop()
        c.stopService(android.content.Intent(c, NativeDeskService::class.java))
        activity?.get()?.finish()
        AppLog.i("Native desktop stopped ($why)")
    }
}

open class NativeDeskActivity : Activity(), SurfaceHolder.Callback {
    private lateinit var surfaceView: SurfaceView
    private lateinit var stats: TextView
    private val apps get() = NativeDesk.apps
    private val main = Handler(Looper.getMainLooper())
    private var started = false
    private var lastInsets: WindowInsets? = null

    /** Screen pixels at the left and right edges to keep panels out of. */
    fun sendSafeArea() {
        val insets = lastInsets
        val e = FloatArray(4) // left, top, right, bottom
        if (insets != null && Prefs.dodgeCutouts(this)) {
            // Panels dodge sideways only, by the same amount on both sides so
            // they stay centred: the deeper of the cutouts and the full
            // radius of the screen's rounded corners.
            var side = 0f
            insets.displayCutout?.let { side = maxOf(it.safeInsetLeft, it.safeInsetRight).toFloat() }
            if (Build.VERSION.SDK_INT >= 31) {
                for (p in listOf(android.view.RoundedCorner.POSITION_TOP_LEFT, android.view.RoundedCorner.POSITION_TOP_RIGHT,
                        android.view.RoundedCorner.POSITION_BOTTOM_LEFT, android.view.RoundedCorner.POSITION_BOTTOM_RIGHT))
                    side = maxOf(side, insets.getRoundedCorner(p)?.radius?.toFloat() ?: 0f)
            }
            e[0] = side; e[2] = side
        }
        NativeDesk.nativeSetSafeArea(e[0], e[1], e[2], e[3])
    }
    /** On a monitor (display out): the phone becomes its touchpad and keyboard. */
    private val external get() = (display?.displayId ?: android.view.Display.DEFAULT_DISPLAY) != android.view.Display.DEFAULT_DISPLAY
    // The Qt demo's last output lines, shown in the overlay so its errors are visible.
    private val qtLines get() = NativeDesk.qtLines

    /**
     * The overlay keeps only what matters at a glance (errors, crashes, exits);
     * every line of output goes to DeskDroid's log (Settings, Save log).
     */
    private fun overlay(line: String, always: Boolean = false) {
        val l = line.lowercase()
        if (!always && !(l.contains("critical:") || l.contains("fatal:") || l.contains("crash") ||
                l.contains("exited") || l.contains("couldn't") || l.contains("error"))) return
        synchronized(qtLines) {
            qtLines.addLast(line.take(160))
            while (qtLines.size > 12) qtLines.removeFirst()
        }
    }
    private var qtStatus: String
        get() = NativeDesk.qtStatus
        set(v) { NativeDesk.qtStatus = v }

    // The screen stays clear: the compositor's numbers go to DeskDroid's log
    // (Settings, Save log) once a minute, with the status and recent problems.
    private val tick = object : Runnable {
        override fun run() {
            if (started) AppLog.i("Native desktop: " + NativeDesk.nativeStats().replace("\n", " | ") + " | $qtStatus")
            main.postDelayed(this, 60_000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppLog.attach(this)
        NativeDesk.activity = java.lang.ref.WeakReference(this)
        surfaceView = KeyboardSurface(this).apply {
            holder.addCallback(this@NativeDeskActivity)
            isFocusable = true
            isFocusableInTouchMode = true
        }
        stats = TextView(this).apply {
            setTextColor(Color.WHITE)
            setShadowLayer(4f, 0f, 0f, Color.BLACK)
            textSize = 13f
            typeface = android.graphics.Typeface.MONOSPACE
            setPadding(24, 24, 24, 24)
            visibility = android.view.View.GONE // only for a failed start
        }
        setContentView(FrameLayout(this).apply {
            addView(surfaceView, FrameLayout.LayoutParams(-1, -1))
            addView(stats, FrameLayout.LayoutParams(-2, -2))
            addView(buildMenu(), FrameLayout.LayoutParams(-1, -1))
        })
        applyKeepAwake()
        // Dodge display cutouts: tell KWin which screen edges the camera cutout
        // and rounded corners hide, again whenever they move (rotation).
        window.decorView.setOnApplyWindowInsetsListener { v, insets ->
            lastInsets = insets
            sendSafeArea()
            padMenu()
            v.onApplyWindowInsets(insets)
        }
        if (Build.VERSION.SDK_INT >= 30) {
            window.insetsController?.apply {
                hide(WindowInsets.Type.systemBars())
                systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        // Ask for the panel's top refresh rate (120 Hz on the Pixel 10 Pro).
        if (Build.VERSION.SDK_INT >= 30) {
            val hz = display?.supportedModes?.maxOfOrNull { it.refreshRate } ?: 60f
            holder.surface.setFrameRate(hz, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
        }
        if (NativeDesk.running) {
            // Back from the background: the desktop kept running, show it again.
            started = NativeDesk.nativeStart(holder.surface)
            AppLog.i(if (started) "Native desktop: back on screen" + (if (external) " (monitor)" else "") else "Native desktop: couldn't show it again")
            if (started) { stats.visibility = android.view.View.GONE; tookSurface(); main.post(tick) }
            return
        }
        firstStart(holder, 0)
    }

    /**
     * The compositor's first start. Right after an update the old process can
     * still hold the compositor's socket for a moment, so a failed start is
     * tried again for a few seconds before the error shows.
     */
    private fun firstStart(holder: SurfaceHolder, attempt: Int) {
        if (!holder.surface.isValid || NativeDesk.running) return
        started = NativeDesk.nativeStart(holder.surface)
        if (!started) {
            if (attempt < 15) {
                if (attempt == 0) AppLog.i("Native desktop test couldn't start yet, trying again (see logcat: nativedesk)")
                main.postDelayed({ firstStart(holder, attempt + 1) }, 400)
                return
            }
            AppLog.i("Native desktop test couldn't start (see logcat: nativedesk)")
            stats.visibility = android.view.View.VISIBLE
            stats.text = "The native compositor couldn't start on this GPU."
            return
        }
        stats.visibility = android.view.View.GONE
        tookSurface()
        NativeDesk.running = true
        PhoneStatus.start(applicationContext)
        startForegroundService(android.content.Intent(this, NativeDeskService::class.java))
        AppLog.i("Native desktop test started" + if (attempt > 0) " (try ${attempt + 1})" else "")
        if (File(applicationInfo.nativeLibraryDir, "libkwin_wayland.so").exists()) {
            // Stage 3: KWin is the desktop, fullscreen on the compositor.
            startKWin()
        } else {
            startApp("Light app", "640x420", 16)
            startApp("Heavy app", "900x600", 1024)
            startQtApp()
        }
        main.post(tick)
    }

    /** This window shows the desktop now; on a monitor, the phone becomes its touchpad. */
    private fun tookSurface() {
        NativeDesk.owner = java.lang.ref.WeakReference(this)
        surfaceView.holder.surfaceFrame.let { NativeDesk.surfaceW = it.width().toFloat(); NativeDesk.surfaceH = it.height().toFloat() }
        if (external) {
            AppLog.i("Native desktop: on a monitor (display ${display?.displayId}); the phone is its touchpad")
            val opts = android.app.ActivityOptions.makeBasic().setLaunchDisplayId(android.view.Display.DEFAULT_DISPLAY)
            startActivity(android.content.Intent(this, PhoneTouchpadActivity::class.java)
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK), opts.toBundle())
        }
    }

    // The phone turned: the compositor passes the new size on to KWin.
    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        if (started && NativeDesk.owner?.get() === this) { NativeDesk.surfaceW = width.toFloat(); NativeDesk.surfaceH = height.toFloat() }
        if (started) {
            AppLog.i("Native desktop test: screen ${width}x$height")
            NativeDesk.nativeResized()
        }
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        // Home, app switching or the screen turning off: stop drawing, keep running.
        main.removeCallbacks(tick)
        // Only the window the compositor draws into lets go of it: the phone's
        // window going away while a monitor shows the desktop changes nothing.
        if (started && NativeDesk.owner?.get() === this) {
            NativeDesk.nativeDetach()
            NativeDesk.owner = null
        }
        started = false
    }

    /** Test apps are separate processes, like real apps would be. */
    private fun startApp(title: String, size: String, load: Int) {
        val exe = File(applicationInfo.nativeLibraryDir, "libnativedesk_client.so")
        try {
            val p = ProcessBuilder(exe.path, "--title", title, "--size", size, "--load", load.toString())
                .redirectErrorStream(true).start()
            apps += p
            Thread {
                p.inputStream.bufferedReader().outputLines { AppLog.i("[nativedesk] $it") }
            }.apply { isDaemon = true }.start()
        } catch (e: Exception) {
            AppLog.i("Native desktop test: couldn't start $title: $e")
        }
    }

    /**
     * Stage 2: an ordinary Qt app (native/nativedesk/qt) on the same compositor,
     * through DeskDroid's own Qt platform plugin, run by QtHost in its own
     * app_process (Qt for Android needs a Java VM). Only in builds made with Qt.
     */
    /**
     * With [kwinRuntime] (KWin's XDG_RUNTIME_DIR), the demo is instead an
     * ordinary Wayland client of KWin, through Qt's own Wayland plugin, and
     * its output shares the overlay with KWin's.
     */
    private fun startQtApp(kwinRuntime: File? = null) {
        val libs = applicationInfo.nativeLibraryDir
        val exe = File(libs, "libnativedesk_qt.so")
        if (!exe.exists()) return
        val platform = if (kwinRuntime != null) "wayland" else "deskdroid"
        if (kwinRuntime == null) qtStatus = "Qt demo: starting"
        try {
            val p = ProcessBuilder(
                "/system/bin/app_process", "-Xnoimage-dex2oat", "/",
                QtHost::class.java.name, libs, exe.name, "-platform", platform
            ).redirectErrorStream(true).also { pb ->
                pb.environment().apply {
                    remove("LD_PRELOAD")
                    put("CLASSPATH", applicationInfo.sourceDir)
                    put("LD_LIBRARY_PATH", libs)
                    put("QT_QPA_PLATFORM", platform)
                    put("QT_QPA_FONTDIR", "/system/fonts")
                    put("HOME", filesDir.path)
                    put("TMPDIR", cacheDir.path)
                    put("XDG_RUNTIME_DIR", (kwinRuntime ?: cacheDir).path)
                    if (kwinRuntime != null) {
                        put("WAYLAND_DISPLAY", "wayland-0")
                        put("QT_PLUGIN_PATH", pluginPath(libs, File(filesDir, "kwin"))) // Qt's Wayland plugins, flat in the library folder
                        put("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1") // KWin draws the borders (Breeze, soon)
                        if (appsOnGpu()) put("QT_WAYLAND_CLIENT_BUFFER_INTEGRATION", "deskdroid-ahb") else put("QT_QUICK_BACKEND", "software")
                        put("QT_DISABLE_SHADER_DISK_CACHE", "1") // see startPlasmaShell
                        // KWin's keymaps and fonts setup: a Wayland client compiles the keymap
                        // KWin sends, and Qt crashes when xkbcommon finds no layouts.
                        val data = File(filesDir, "kwin")
                        put("XKB_CONFIG_ROOT", File(data, "share/X11/xkb").path)
                        put("FONTCONFIG_FILE", File(data, "fonts.conf").path)
                        put("XDG_DATA_DIRS", File(data, "share").path)
                        put("XDG_CONFIG_HOME", File(filesDir, "config").path)
                        put("XCURSOR_PATH", File(data, "share/icons").path)
                        sessionBus?.let { put("DBUS_SESSION_BUS_ADDRESS", it) }
                    }
                }
            }.start()
            apps += p
            if (kwinRuntime == null) qtStatus = "Qt demo: running"
            Thread {
                p.inputStream.bufferedReader().outputLines {
                    AppLog.i("[nativedesk-qt] $it")
                    overlay(if (kwinRuntime != null) "demo: $it" else it)
                }
                val code = p.waitFor()
                val exit = "exited with code $code" + if (code > 128) " (signal ${code - 128})" else ""
                if (kwinRuntime != null) synchronized(qtLines) { qtLines.addLast("demo: $exit") }
                else qtStatus = "Qt demo: $exit"
                AppLog.i("[nativedesk-qt] exited ($code)")
            }.apply { isDaemon = true }.start()
        } catch (e: Exception) {
            qtStatus = "Qt demo: couldn't start: $e"
            AppLog.i("Native desktop test: couldn't start the Qt demo: $e")
        }
    }

    /**
     * Stage 3: KWin (built by native/plasma) with DeskDroid's nativedesk
     * backend, which shows its desktop fullscreen on the compositor. Runs in
     * QtHost like the Qt demo; its data (keyboard layouts...) ships zipped as
     * libkwin_data.so and is unpacked once per app version.
     */
    private fun startKWin() {
        val libs = applicationInfo.nativeLibraryDir
        val data = File(filesDir, "kwin")
        qtStatus = "KWin: starting"
        try {
            unpackKWinData(File(libs, "libkwin_data.so"), data)
            linkPlugins(libs, data)
            // KWin remembers each screen's scale; the app sets it at every start.
            File(filesDir, "config/kwinoutputconfig.json").delete()
            val runtime = File(cacheDir, "runtime").apply { mkdirs(); setReadable(true, true); setWritable(true, true); setExecutable(true, true) }
            val fonts = File(data, "fonts.conf").apply { writeText(fontsConf()) }
            val config = File(filesDir, "config").apply { mkdirs() }
            // Breeze cursors (shipped in KWin's data) unless the user picked others.
            File(config, "kcminputrc").takeUnless { it.exists() }
                ?.writeText("[Mouse]\ncursorTheme=breeze_cursors\ncursorSize=24\n")
            applyDarkDefault(config, data)
            // KDE's app database (ksycoca) lists only the apps a menu file takes in;
            // with none, Plasma finds no apps. One menu with every installed app,
            // and a fresh database each start so it matches this build's apps.
            File(config, "menus").mkdirs()
            File(config, "menus/applications.menu").writeText(
                "<!DOCTYPE Menu PUBLIC \"-//freedesktop//DTD Menu 1.0//EN\"\n" +
                "  \"http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd\">\n" +
                "<Menu>\n  <Name>Applications</Name>\n  <DefaultAppDirs/>\n  <DefaultDirectoryDirs/>\n" +
                "  <Include><And><All/><Not><Category>X-DeskDroid-Android</Category></Not>" +
                "<Not><Category>X-DeskDroid-Android-Private</Category></Not><Not><Category>X-DeskDroid-Android-Work</Category></Not></And></Include>\n" +
                "  <Menu>\n    <Name>Android Apps</Name>\n" +
                "    <Include><Category>X-DeskDroid-Android</Category></Include>\n  </Menu>\n" +
                "  <Menu>\n    <Name>Private Space</Name>\n" +
                "    <Include><Category>X-DeskDroid-Android-Private</Category></Include>\n  </Menu>\n" +
                "  <Menu>\n    <Name>Work Apps</Name>\n" +
                "    <Include><Category>X-DeskDroid-Android-Work</Category></Include>\n  </Menu>\n</Menu>\n")
            File(filesDir, ".cache").listFiles { f -> f.name.startsWith("ksycoca6") }?.forEach { it.delete() }
            // Open with Android app: KDE offers it for every file (all files derive
            // from application/octet-stream), so files without a KDE app open in
            // Android's app chooser.
            File(filesDir, ".local/share/applications").apply { mkdirs() }
                .resolve("org.deskdroid.android-open.desktop").writeText(
                    "[Desktop Entry]\nType=Application\nName=Android app\nGenericName=Open with an Android app\n" +
                    "Icon=smartphone\nExec=android-open %F\nMimeType=application/octet-stream;\nNoDisplay=true\n" +
                    "InitialPreference=1\n")
            // Links when Etherium isn't installed: the phone's browser.
            File(filesDir, ".local/share/applications/org.deskdroid.android-browser.desktop").writeText(
                "[Desktop Entry]\nType=Application\nName=Phone's browser\nGenericName=Web Browser\n" +
                "Icon=smartphone\nExec=android-open %u\nMimeType=x-scheme-handler/http;x-scheme-handler/https;\nNoDisplay=true\n")
            // Termux's Firefox patches put /tmp under files/usr.
            File(filesDir, "usr/tmp").mkdirs()
            File(filesDir, ".local/share/applications/org.deskdroid.store.desktop").writeText(
                "[Desktop Entry]\nType=Application\nName=App Store\nGenericName=Install KDE apps\n" +
                "Icon=plasmadiscover\nExec=android-open deskdroid:store\nCategories=System;\n")
            NativeDesk.watchOpenRequests(applicationContext)
            NativeDesk.refreshAndroidApps { writeAndroidApps(applicationContext) } // before plasmashell reads the menu (KWin starts first)
            watchAndroidApps()
            val bus = startSessionBus(libs, data, runtime)
            val scale = NativeDesk.desktopScale(this).toDouble()
            val p = ProcessBuilder(
                "/system/bin/app_process", "-Xnoimage-dex2oat", "/",
                QtHost::class.java.name, libs, "libkwin_wayland.so",
                "--nativedesk", "--scale", scale.toString(), "--socket", "wayland-0"
            ).redirectErrorStream(true).also { pb ->
                pb.environment().apply {
                    remove("LD_PRELOAD")
                    put("CLASSPATH", applicationInfo.sourceDir)
                    put("LD_LIBRARY_PATH", libs)
                    ddmask(this, libs)
                    put("HOME", filesDir.path)
                    put("TMPDIR", cacheDir.path)
                    put("XDG_RUNTIME_DIR", runtime.path)
                    put("XDG_DATA_DIRS", File(data, "share").path)
                    put("XDG_CONFIG_HOME", config.path)
                    put("XKB_CONFIG_ROOT", File(data, "share/X11/xkb").path)
                    put("QT_PLUGIN_PATH", pluginPath(libs, data)) // Qt's plugins flat, KDE's by namespace
                    put("XCURSOR_PATH", File(data, "share/icons").path)
                    if (bus != null) put("DBUS_SESSION_BUS_ADDRESS", bus)
                    put("FONTCONFIG_FILE", fonts.path)
                    put("QT_QPA_FONTDIR", "/system/fonts")
                    // KWin composites on the phone's GPU (OpenGL ES), falling back to the CPU (QPainter) by itself.
                    // A file named kwin-cpu in the app's files folder forces the CPU, to compare.
                    if (File(filesDir, "kwin-cpu").exists()) put("KWIN_COMPOSE", "Q")
                    // KWin's own Qt Quick windows (OSDs, effects) would draw with GL through
                    // a DRM device, which there isn't here: Qt's software renderer for those.
                    put("QT_QUICK_BACKEND", "software")
                    put("KDE_DEBUG", "1")
                    put("QT_LOGGING_RULES", "js=true;kde.plasma.activitiesstats=false;qt.sql.qsqldatabase=false") // no KCrash handler: our own prints where a crash happened
                    put("KWIN_FORCE_OWN_QPA", "1") // KWin only takes its own Qt platform plugin when the program is named kwin_wayland; ours is app_process
                }
            }.start()
            apps += p
            NativeDesk.kwinTakesGpuBuffers = false
            qtStatus = "KWin: running"
            Thread {
                var demoStarted = false
                p.inputStream.bufferedReader().outputLines {
                    AppLog.i("[kwin] $it")
                    if (it.contains("deskdroid_ahb: apps can hand KWin GPU buffers")) NativeDesk.kwinTakesGpuBuffers = true
                    // KWin is ready for clients: a first window inside it.
                    if (!demoStarted && it.contains("Accepting client connections")) {
                        demoStarted = true
                        // plasmashell when the build has it, else the Qt demo.
                        val shell = File(libs, "libplasmashell.so").exists()
                        // Even if the window left the screen meanwhile (it did in build 225,
                        // and Plasma never came): the desktop keeps running in the background.
                        main.postDelayed({ if (NativeDesk.running) { if (shell) startPlasmaShell(runtime) else startQtApp(runtime) } }, 1500)
                    }
                    overlay("kwin: $it")
                }
                val code = p.waitFor()
                qtStatus = "KWin: exited with code $code" + if (code > 128) " (signal ${code - 128})" else ""
                AppLog.i("[kwin] exited ($code)")
                if (code == 137) AppLog.i("[kwin] killed: " + AppLog.memoryReport(this))
            }.apply { isDaemon = true }.start()
        } catch (e: Exception) {
            qtStatus = "KWin: couldn't start: $e"
            AppLog.i("Native desktop test: couldn't start KWin: $e")
        }
    }

    /**
     * Stage 4: plasmashell (Plasma's desktop and panels), a Wayland client of
     * KWin, run by QtHost like KWin. Its shell for now is DeskDroid's own
     * (native/plasma/shell); its QML modules and packages come in KWin's data.
     */
    private fun startPlasmaShell(runtime: File) {
        val libs = applicationInfo.nativeLibraryDir
        val data = File(filesDir, "kwin")
        val config = File(filesDir, "config").apply { mkdirs() }
        // Qt Quick on the GPU when KWin takes GPU buffers (a file named app-cpu in the
        // app's files folder forces the CPU, to compare); else Qt's software renderer
        // through Wayland shm. KDE reads its choice of renderer from kdeglobals.
        val gpu = appsOnGpu()
        // Shader binaries build 247 cached: loading them back draws garbage.
        File(filesDir, ".cache").walkTopDown().maxDepth(2).filter { it.isDirectory && it.name.startsWith("qtshadercache") }
            .toList().forEach { it.deleteRecursively() }
        File(config, "kdeglobals").let { g ->
            val t = if (g.exists()) g.readText() else ""
            val section = "[QtQuickRendererSettings]\nSceneGraphBackend=" + (if (gpu) "rhi" else "software") + "\n"
            val old = Regex("\\[QtQuickRendererSettings]\nSceneGraphBackend=[a-z]*\n")
            g.writeText(if (old.containsMatchIn(t)) t.replace(old, Regex.escapeReplacement(section)) else t + "\n" + section)
        }
        // Breeze Dark's icons (white symbolic ones) to match the dark colors; earlier
        // builds wrote the light theme here.
        File(config, "kdeglobals").let { g ->
            val t = g.readText()
            if (!t.contains("[Icons]")) g.appendText("\n[Icons]\nTheme=breeze-dark\n")
            else if (t.contains("[Icons]\nTheme=breeze\n")) g.writeText(t.replace("[Icons]\nTheme=breeze\n", "[Icons]\nTheme=breeze-dark\n"))
        }
        // No screen locker here: Lock stays out of the menus.
        File(config, "kdeglobals").takeUnless { it.readText().contains("[KDE Action Restrictions]") }
            ?.appendText("\n[KDE Action Restrictions]\naction/lock_screen=false\n")
        writeUserDirs(config)
        writeTerminalSetup(config)
        copyWallpaper()
        // While DeskDroid's default layout changes from build to build, start from it
        // again when it's newer than the saved one (layout.js runs only without one).
        val layoutVersion = "11"
        val stamp = File(config, "deskdroid-layout-version")
        if (stamp.takeIf { it.exists() }?.readText() != layoutVersion) {
            File(config, "plasma-org.deskdroid.desktop-appletsrc").delete()
            File(config, "plasmashellrc").delete()
            stamp.writeText(layoutVersion)
        }
        val bin = linkApps(libs, data)
        try {
            val p = ProcessBuilder(
                "/system/bin/app_process", "-Xnoimage-dex2oat", "/",
                QtHost::class.java.name, libs, "libplasmashell.so",
                "--no-respawn", "-p", "org.deskdroid.desktop"
            ).redirectErrorStream(true).also { pb ->
                pb.environment().apply {
                    remove("LD_PRELOAD")
                    put("CLASSPATH", applicationInfo.sourceDir)
                    put("LD_LIBRARY_PATH", libs)
                    ddmask(this, libs)
                    put("HOME", filesDir.path)
                    put("LANG", java.util.Locale.getDefault().let { "${it.language}_${it.country}.UTF-8" }) // the phone's language, for dates, times and text
                    put("TMPDIR", cacheDir.path)
                    put("XDG_RUNTIME_DIR", runtime.path)
                    put("XDG_DATA_DIRS", File(data, "share").path)
                    put("XDG_CONFIG_HOME", config.path)
                    put("XKB_CONFIG_ROOT", File(data, "share/X11/xkb").path)
                    put("XCURSOR_PATH", File(data, "share/icons").path)
                    put("FONTCONFIG_FILE", File(data, "fonts.conf").path)
                    put("QT_QPA_FONTDIR", "/system/fonts")
                    put("QT_QPA_PLATFORM", "wayland")
                    put("WAYLAND_DISPLAY", "wayland-0")
                    put("QT_PLUGIN_PATH", pluginPath(libs, data))
                    put("QML_IMPORT_PATH", File(data, "qml").path)
                    // DeskDroid's battery, CPU and RAM widgets read files/status.json.
                    put("QML_XHR_ALLOW_FILE_READ", "1")
                    // KDE's look instead of Android's (Qt picks Material there: white
                    // windows, big controls): Plasma's platform theme (colors, fonts,
                    // icons, file dialogs) and KDE's Qt Quick Controls style. A file
                    // named android-style in the app's files folder turns it off.
                    if (!File(filesDir, "android-style").exists()) {
                        put("QT_QPA_PLATFORMTHEME", "kde")
                        put("QT_QUICK_CONTROLS_STYLE", "org.kde.desktop")
                    }
                    if (gpu) put("QT_WAYLAND_CLIENT_BUFFER_INTEGRATION", "deskdroid-ahb") else put("QT_QUICK_BACKEND", "software")
                    // No compiled-shader cache: the PowerVR driver takes cached program
                    // binaries back and draws garbage with them (build 247's second start).
                    put("QT_DISABLE_SHADER_DISK_CACHE", "1")
                    put("KDE_DEBUG", "1")
                    put("QT_LOGGING_RULES", "js=true;kf.service.*=false;kde.plasma.activitiesstats=false;qt.sql.qsqldatabase=false;org.kde.plasma.kicker=false") // a flood of lines keeps the app busy
                    // GTK programs: Wayland, and settings kept in memory (no dconf here).
                    put("GDK_BACKEND", "wayland")
                    put("GSETTINGS_BACKEND", "memory")
                    // Apps the desktop starts (bin/dolphin...) inherit all this.
                    put("PATH", "${bin.path}:${System.getenv("PATH") ?: "/system/bin"}")
                    put("DESKDROID_BIN", bin.path) // help in the terminal lists these apps
                    put("SHELL", "/system/bin/sh") // terminals (Konsole, Kate's, Dolphin's) start Android's shell
                    sessionBus?.let { put("DBUS_SESSION_BUS_ADDRESS", it) }
                }
            }.start()
            apps += p
            Thread {
                p.inputStream.bufferedReader().outputLines {
                    AppLog.i("[plasmashell] $it")
                    overlay("shell: $it")
                }
                val code = p.waitFor()
                val exit = "exited with code $code" + if (code > 128) " (signal ${code - 128})" else ""
                overlay("shell: $exit", always = true)
                overlay("Full log: Settings, Save log to Downloads", always = true)
                val dir = File(data, "plugins/kf6/packagestructure")
                AppLog.i("[plasmashell] ${dir.path}: ${dir.list()?.joinToString() ?: "missing"}")
                AppLog.i("[plasmashell] exited ($code)")
                if (code == 137) AppLog.i("[plasmashell] killed: " + AppLog.memoryReport(this))
            }.apply { isDaemon = true }.start()
        } catch (e: Exception) {
            synchronized(qtLines) { qtLines.addLast("shell: couldn't start: $e") }
            AppLog.i("Native desktop test: couldn't start plasmashell: $e")
        }
    }

    private var sessionBus: String? = null

    /** Where Qt (flat, Android style) and KDE (by namespace, Linux style) find plugins. */
    private fun appsOnGpu() = NativeDesk.kwinTakesGpuBuffers && !File(filesDir, "app-cpu").exists()

    private fun pluginPath(libs: String, data: File) = "${File(data, "plugins").path}:$libs"

    /**
     * KDE finds plugins as <plugin path>/<namespace>/<name>.so and takes the
     * plugin's ID from that name; the APK can only carry them flat in the
     * library folder (libplugins_<namespace>_<name>.so). So the plugins
     * folder gets links with the real layout, from the list the build ships.
     */
    /**
     * The apps in this build (apps.txt): each command bin/<app> is a link to
     * libdd_qtapp.so, which starts lib<app> in an app_process through QtHost.
     * The link lives in app storage, the program in the APK's library folder,
     * where Android lets the app run programs.
     */
    /**
     * ddmask (native/ddmask): preloaded into KWin and plasmashell, and so into
     * every program they start, it starts programs from the app's own files
     * (store apps, their plug-ins and helpers) through Android's linker, which
     * Android allows where exec isn't. A file named ddmask-off in the app's
     * files folder turns it off.
     */
    private fun ddmask(env: MutableMap<String, String>, libs: String) {
        val lib = File(libs, "libddmask.so")
        if (lib.exists() && !File(filesDir, "ddmask-off").exists()) {
            env["LD_PRELOAD"] = lib.path
            try { glibcRuntime(libs) } catch (e: Exception) { AppLog.i("Native desktop test: glibc runtime: $e") }
        }
    }

    /**
     * glibc and musl (native/glibc, native/musl), for the ordinary Linux
     * programs ddmask starts. glibc's libraries ship zipped as libdd_glibc.so
     * and are unpacked into files/glibc, the folder it was built for, once per
     * app version; musl is all in its loader (libdd_ld-musl.so), and files/musl
     * holds the libraries musl programs bring. Each one's /etc is written here:
     * the app's user, and DNS from Android's current network.
     */
    private fun glibcRuntime(libs: String) {
        val zip = File(libs, "libdd_glibc.so")
        if (zip.exists()) unpackKWinData(zip, File(filesDir, "glibc"))
        val uid = android.os.Process.myUid()
        val home = File(filesDir, "home").apply { mkdirs() }
        val dns = try {
            val cm = getSystemService(android.net.ConnectivityManager::class.java)
            cm.getLinkProperties(cm.activeNetwork)?.dnsServers?.mapNotNull { it.hostAddress?.substringBefore('%') }.orEmpty()
        } catch (e: Exception) { emptyList() }
        for ((name, loader) in listOf("glibc" to "libdd_ld-glibc.so", "musl" to "libdd_ld-musl.so")) {
            if (!File(libs, loader).exists()) continue
            val root = File(filesDir, name)
            val etc = File(root, "etc").apply { mkdirs() }
            File(etc, "passwd").writeText("root:x:0:0:root:/:/system/bin/sh\n" +
                "deskdroid:x:$uid:$uid:DeskDroid:${home.path}:/system/bin/sh\n")
            File(etc, "group").writeText("root:x:0:\ndeskdroid:x:$uid:\n")
            File(etc, "resolv.conf").writeText((dns.ifEmpty { listOf("8.8.8.8", "1.1.1.1") }).joinToString("") { "nameserver $it\n" })
            File(etc, "hosts").takeIf { !it.exists() }?.writeText("127.0.0.1 localhost\n::1 localhost\n")
            File(root, "lib").mkdirs()
            File(root, "tmp").mkdirs()
            File(root, "var/tmp").mkdirs()
        }
    }

    private fun linkApps(libs: String, data: File): File {
        val bin = File(data, "bin").apply { mkdirs() }
        bin.listFiles()?.forEach { it.delete() }
        val apps = File(data, "apps.txt").takeIf { it.exists() }?.readLines()?.filter { it.isNotBlank() }.orEmpty()
        for (app in apps) {
            try {
                android.system.Os.symlink(File(libs, "libdd_qtapp.so").path, File(bin, app).path)
            } catch (e: Exception) {
                AppLog.i("Native desktop test: couldn't link $app: $e")
            }
        }
        // GTK programs (gtktest.c...): the program itself, no QtHost.
        File(data, "gtkapps.txt").takeIf { it.exists() }?.readLines()?.filter { it.isNotBlank() }?.forEach { app ->
            try { android.system.Os.symlink(File(libs, "libdd_$app.so").path, File(bin, app).path) }
            catch (e: Exception) { AppLog.i("Native desktop test: couldn't link $app: $e") }
        }
        // Apps from the app store (Store.kt).
        Store.installed(this).forEach { Store.linkCommand(this, it) }
        File(libs, "libdd_android-open.so").takeIf { it.exists() }?.let {
            try { android.system.Os.symlink(it.path, File(bin, "android-open").path) }
            catch (e: Exception) { AppLog.i("Native desktop test: couldn't link android-open: $e") }
        }
        AppLog.i("Native desktop test: apps: ${apps.joinToString().ifEmpty { "none" }}")
        return bin
    }

    /**
     * The phone's apps in Plasma's menu (Android Apps, and search): a desktop
     * file and an icon for each, run through bin/android-open as
     * android-app:<package>[@<profile>]. Apps in other profiles get their own
     * folder: Private Space (Android 15+, listed only while DeskDroid is the
     * home app) and Work. Icons are drawn again only for updated apps.
     */

    /** The menu follows apps installed or removed, and Private Space locking or unlocking. */
    private fun watchAndroidApps() {
        // Once per process, not per window: every desktop window used to add its
        // own watchers, and their listings ran all at once, so many that Android's
        // binder gave up halfway (BadParcelable, DeadSystem) and apps left the menu.
        if (NativeDesk.appsWatched) return
        NativeDesk.appsWatched = true
        val app = applicationContext
        val again = Runnable { NativeDesk.refreshAndroidApps { writeAndroidApps(app) } }
        val ui = android.os.Handler(Looper.getMainLooper())
        val later: () -> Unit = { ui.removeCallbacks(again); ui.postDelayed(again, 1500) }
        app.getSystemService(android.content.pm.LauncherApps::class.java).registerCallback(object : android.content.pm.LauncherApps.Callback() {
            override fun onPackageRemoved(packageName: String?, user: android.os.UserHandle?) = later()
            override fun onPackageAdded(packageName: String?, user: android.os.UserHandle?) = later()
            override fun onPackageChanged(packageName: String?, user: android.os.UserHandle?) = later()
            override fun onPackagesAvailable(packageNames: Array<out String>?, user: android.os.UserHandle?, replacing: Boolean) = later()
            override fun onPackagesUnavailable(packageNames: Array<out String>?, user: android.os.UserHandle?, replacing: Boolean) = later()
        }, android.os.Handler(Looper.getMainLooper()))
        if (Build.VERSION.SDK_INT >= 31) {
            val filter = android.content.IntentFilter().apply {
                addAction(android.content.Intent.ACTION_PROFILE_AVAILABLE)
                addAction(android.content.Intent.ACTION_PROFILE_UNAVAILABLE)
                addAction(android.content.Intent.ACTION_PROFILE_ADDED)
                addAction(android.content.Intent.ACTION_PROFILE_REMOVED)
            }
            val receiver = object : android.content.BroadcastReceiver() {
                override fun onReceive(c: android.content.Context, i: android.content.Intent) = later()
            }
            if (Build.VERSION.SDK_INT >= 33) app.registerReceiver(receiver, filter, android.content.Context.RECEIVER_EXPORTED)
            else app.registerReceiver(receiver, filter)
        }
    }

    private fun writeAndroidApps(c: android.content.Context) {
        val dir = File(c.filesDir, ".local/share/applications").apply { mkdirs() }
        val icons = File(c.filesDir, ".local/share/deskdroid-android-icons").apply { mkdirs() }
        val launcher = c.getSystemService(android.content.pm.LauncherApps::class.java)
        val users = c.getSystemService(android.os.UserManager::class.java)
        val me = android.os.Process.myUserHandle()
        val keep = mutableSetOf<String>()
        // A listing that fails (Android's app service restarting: DeadSystemException)
        // must not empty the menu: then nothing is taken out this time.
        var failed = false
        for (user in runCatching { launcher.profiles }.getOrElse { failed = true; emptyList() }) {
            val serial = users.getSerialNumberForUser(user)
            val private = user != me && Build.VERSION.SDK_INT >= 35 &&
                runCatching { launcher.getLauncherUserInfo(user)?.userType == android.os.UserManager.USER_TYPE_PROFILE_PRIVATE }.getOrDefault(false)
            val (category, suffix) = when {
                user == me -> "X-DeskDroid-Android" to ""
                private -> "X-DeskDroid-Android-Private" to "@$serial"
                else -> "X-DeskDroid-Android-Work" to "@$serial"
            }
            val apps = try { launcher.getActivityList(null, user) } catch (e: Exception) {
                AppLog.i("Native desktop: couldn't list profile $serial: $e"); failed = true; emptyList()
            }.distinctBy { it.componentName.packageName }
            for (info in apps) {
                val pkg = info.componentName.packageName
                val id = pkg + suffix
                val name = "android-$id.desktop"
                keep += name
                try {
                    val icon = File(icons, "$id.png")
                    if (!icon.exists() || icon.lastModified() < info.firstInstallTime ||
                        icon.lastModified() < runCatching { c.packageManager.getPackageInfo(pkg, 0).lastUpdateTime }.getOrDefault(0L)) {
                        val d = info.getBadgedIcon(0) // the profile's badge (briefcase, lock) on its apps
                        val px = 128
                        val bmp = android.graphics.Bitmap.createBitmap(px, px, android.graphics.Bitmap.Config.ARGB_8888)
                        d.setBounds(0, 0, px, px)
                        d.draw(android.graphics.Canvas(bmp))
                        icon.outputStream().use { bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
                        bmp.recycle()
                    }
                    val label = info.label.toString().replace("\n", " ")
                    File(dir, name).writeText("[Desktop Entry]\nType=Application\nName=$label\nComment=Android app\n" +
                        "Icon=${icon.path}\nExec=android-open android-app:$id\nCategories=$category;\n")
                } catch (e: Exception) {
                    AppLog.i("Native desktop: couldn't list $id: $e")
                }
            }
            AppLog.i("Native desktop: profile $serial${if (private) " (private)" else ""}: ${apps.size} apps")
        }
        // Apps uninstalled since the last start (and a locked Private Space's).
        if (!failed) dir.listFiles { f -> f.name.startsWith("android-") && f.name !in keep }?.forEach { it.delete() }
        AppLog.i("Native desktop: ${keep.size} Android apps in the menu")
    }

    /**
     * Fontconfig for every program: Android's fonts, plus the generic names
     * (monospace, sans-serif, serif) and the monospace fonts programs ask for
     * by name (Hack, KDE's default) mapped onto them. Without these, a request for a monospace
     * font got the first font in /system/fonts, a proportional one, and
     * Konsole spread every character over the widest one's cell.
     * ~/.local/share/fonts takes fonts the user adds.
     */
    private fun fontsConf(): String {
        val mono = monospaceFont()
        fun alias(families: List<String>, prefer: List<String>) = families.joinToString("") { f ->
            "  <alias binding=\"same\"><family>$f</family><prefer>" +
                prefer.joinToString("") { "<family>$it</family>" } + "</prefer></alias>\n"
        }
        return "<?xml version=\"1.0\"?>\n<!DOCTYPE fontconfig SYSTEM \"urn:fontconfig:fonts.dtd\">\n<fontconfig>\n" +
            "  <dir>/system/fonts</dir>\n  <dir>${File(filesDir, ".local/share/fonts").path}</dir>\n" +
            "  <cachedir>${File(cacheDir, "fontconfig").path}</cachedir>\n" +
            alias(listOf("monospace", "Monospace", "Hack", "DejaVu Sans Mono", "Noto Sans Mono", "Liberation Mono", "Courier", "Courier New"),
                listOf(mono, "Droid Sans Mono", "Cutive Mono")) +
            alias(listOf("sans-serif", "sans", "Sans"),
                listOf("Roboto", "Google Sans", "Noto Sans")) +
            alias(listOf("serif", "Serif"),
                listOf("Noto Serif", "Droid Serif")) +
            "</fontconfig>\n"
    }

    /** The phone's monospace font: Droid Sans Mono on every Android so far. */
    private fun monospaceFont() = listOf("DroidSansMono.ttf" to "Droid Sans Mono", "CutiveMono.ttf" to "Cutive Mono")
        .firstOrNull { File("/system/fonts", it.first).exists() }?.second ?: "Droid Sans Mono"

    /**
     * Konsole: a DeskDroid profile (the default unless the user picked another)
     * that starts Android's shell with DeskDroid's setup (assets/linux/deskdroid-shrc:
     * the welcome, a short prompt and help) and the phone's monospace font.
     * Konsole's built-in profile has no command and warned "Could not find ''".
     * The profile is written once, so changes made in Konsole stay.
     */
    private fun writeTerminalSetup(config: File) {
        try {
            val rc = File(filesDir, "deskdroid/shrc")
            rc.parentFile?.mkdirs()
            Tuning.writeIfChanged(rc, assets.open("linux/deskdroid-shrc").use { it.readBytes() })
            val font = "${monospaceFont()},10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
            File(filesDir, ".local/share/konsole").apply { mkdirs() }.resolve("DeskDroid.profile")
                .takeUnless { it.exists() }
                ?.writeText("[General]\nName=DeskDroid\nParent=FALLBACK/\nCommand=/system/bin/sh\n" +
                    "Environment=TERM=xterm-256color,COLORTERM=truecolor,SHELL=/system/bin/sh,ENV=${rc.path}\n" +
                    "\n[Appearance]\nFont=$font\n")
            File(config, "konsolerc").let { f ->
                if (!f.exists() || !f.readText().contains("DefaultProfile=")) f.appendText("\n[Desktop Entry]\nDefaultProfile=DeskDroid.profile\n")
            }
            // KDE's fixed-width font (Kate, Dolphin's terminal...) unless one is set.
            File(config, "kdeglobals").let { g ->
                if (!g.exists() || !Regex("(?m)^fixed=").containsMatchIn(g.readText())) g.appendText("\n[General]\nfixed=$font\n")
            }
        } catch (e: Exception) {
            AppLog.i("Native desktop test: couldn't write the terminal setup: $e")
        }
    }

    /**
     * Breeze Dark by default, once: its colors in kdeglobals (as Plasma's
     * colour settings write them, for KWin's borders and the apps) and the
     * Breeze Dark Plasma theme. A colour scheme or theme set later is kept.
     */
    private fun applyDarkDefault(config: File, data: File) {
        val globals = File(config, "kdeglobals")
        val dark = File(data, "share/color-schemes/BreezeDark.colors")
        if (dark.exists() && !(globals.exists() && globals.readText().contains("ColorScheme="))) {
            globals.appendText("\n" + dark.readText() + "\n[General]\nColorScheme=BreezeDark\n")
            AppLog.i("Native desktop test: Breeze Dark colors set")
        } else if (!dark.exists()) AppLog.i("Native desktop test: no BreezeDark.colors in the data")
        // Apps (Dolphin, KWrite...) pick their colors with KDE's colour scheme
        // manager, which reads UiSettings (kdeglobals falls through to every
        // app's settings); there is no KDE platform theme to set them.
        if (!globals.exists() || !globals.readText().contains("[UiSettings]"))
            globals.appendText("\n[UiSettings]\nColorScheme=Breeze Dark\n")
        File(config, "plasmarc").takeUnless { it.exists() && it.readText().contains("[Theme]") }
            ?.appendText("\n[Theme]\nname=breeze-dark\n")
        // GTK programs (Floorp): Breeze for GTK (breeze-gtk), light or dark as
        // Plasma's colour scheme is, at every start. A settings.ini without
        // DeskDroid's first line is the user's own and is kept.
        val gtk = File(config, "gtk-3.0/settings.ini")
        if (!gtk.exists() || gtk.readLines().firstOrNull() == GTK_MARK) {
            val scheme = Regex("(?m)^ColorScheme=(.*)$").find(globals.readText())?.groupValues?.get(1).orEmpty()
            val light = scheme.contains("Light", ignoreCase = true) || scheme == "Breeze"
            gtk.parentFile?.mkdirs()
            gtk.writeText("$GTK_MARK\n[Settings]\ngtk-theme-name=${if (light) "Breeze" else "Breeze-Dark"}\n" +
                "gtk-icon-theme-name=${if (light) "breeze" else "breeze-dark"}\n" +
                "gtk-application-prefer-dark-theme=${!light}\ngtk-cursor-theme-name=breeze_cursors\n")
        }
    }
    private val GTK_MARK = "# Written by DeskDroid to match Plasma's colors; delete this line to keep your own."

    /**
     * The home folder stays in app storage (KDE's config, caches and sockets need a real
     * Linux filesystem); Documents, Downloads, Pictures, Music and Videos are the phone's
     * own folders when All files access is granted, through KDE's standard user-dirs file.
     * Written at every start, so it follows the permission.
     */
    /**
     * The phone's wallpaper on the desktop: Android lets an app with All files
     * access read the current (still) wallpaper, and DeskDroid's wallpaper
     * shows files/wallpaper.jpg over its gradient. Without access, or with a
     * live wallpaper, the file is removed and the gradient shows.
     */
    private fun phoneWallpaperInPlasma() =
        File(filesDir, ".local/share/wallpapers/Phone wallpaper.jpg").also { it.parentFile?.mkdirs() }

    private fun copyWallpaper() {
        val out = File(filesDir, "wallpaper.jpg")
        try {
            val d = if (Storage.granted(this)) android.app.WallpaperManager.getInstance(this).drawable else null
            if (d == null) {
                out.delete()
                phoneWallpaperInPlasma().delete()
                AppLog.i("Native desktop test: no phone wallpaper to copy, using the gradient")
                return
            }
            val w = d.intrinsicWidth.takeIf { it > 0 } ?: resources.displayMetrics.widthPixels
            val h = d.intrinsicHeight.takeIf { it > 0 } ?: resources.displayMetrics.heightPixels
            val bmp = android.graphics.Bitmap.createBitmap(w, h, android.graphics.Bitmap.Config.ARGB_8888)
            d.setBounds(0, 0, w, h)
            d.draw(android.graphics.Canvas(bmp))
            val tmp = File(filesDir, "wallpaper.jpg.new")
            tmp.outputStream().use { bmp.compress(android.graphics.Bitmap.CompressFormat.JPEG, 92, it) }
            bmp.recycle()
            tmp.renameTo(out)
            // Also among Plasma's wallpapers, for the Image wallpaper's settings page.
            out.copyTo(phoneWallpaperInPlasma(), overwrite = true)
            AppLog.i("Native desktop test: phone wallpaper copied (${w}x$h)")
        } catch (e: Exception) {
            out.delete()
            AppLog.i("Native desktop test: couldn't copy the phone wallpaper: $e")
        }
    }

    private fun writeUserDirs(config: File) {
        val home = filesDir.path
        fun phone(type: String) = if (Storage.granted(this))
            android.os.Environment.getExternalStoragePublicDirectory(type).path else "$home/${type}"
        val dirs = linkedMapOf(
            "DESKTOP" to "$home/Desktop",
            "DOCUMENTS" to phone(android.os.Environment.DIRECTORY_DOCUMENTS),
            "DOWNLOAD" to phone(android.os.Environment.DIRECTORY_DOWNLOADS),
            "MUSIC" to phone(android.os.Environment.DIRECTORY_MUSIC),
            "PICTURES" to phone(android.os.Environment.DIRECTORY_PICTURES),
            "VIDEOS" to phone(android.os.Environment.DIRECTORY_MOVIES),
            "TEMPLATES" to "$home/Templates",
            "PUBLICSHARE" to "$home/Public",
        )
        // The desktop shows the phone's Desktop folder when DeskDroid has All files
        // access: files/Desktop (where the desktop and user-dirs point) links to it.
        val desktop = File(home, "Desktop")
        if (Storage.granted(this)) {
            val phoneDesktop = File(android.os.Environment.getExternalStorageDirectory(), "Desktop").apply { mkdirs() }
            try {
                val link = java.nio.file.Files.isSymbolicLink(desktop.toPath())
                if (!link && desktop.isDirectory && desktop.list().isNullOrEmpty()) desktop.delete()
                if (!link && desktop.exists()) {
                    AppLog.i("Native desktop test: files/Desktop has files, so the desktop keeps showing it")
                } else if (!link) {
                    android.system.Os.symlink(phoneDesktop.path, desktop.path)
                }
            } catch (e: Exception) {
                AppLog.i("Native desktop test: couldn't link the phone's Desktop folder: $e")
            }
        } else if (java.nio.file.Files.isSymbolicLink(desktop.toPath())) {
            desktop.delete() // no access to the phone's folder any more
        }
        dirs.values.forEach { File(it).mkdirs() }
        File(config, "user-dirs.dirs").writeText(dirs.entries.joinToString("") { (k, v) -> "XDG_${k}_DIR=\"$v\"\n" })
        AppLog.i("Native desktop test: user folders ${if (Storage.granted(this)) "on the phone's storage" else "in app storage (no All files access)"}")
    }

    private fun linkPlugins(libs: String, data: File) {
        linkFlatLibraries(libs, File(data, "plugins.txt"), File(data, "plugins"), clear = true)
        // QML plugins, next to their qmldir files (unpacked from the data).
        linkFlatLibraries(libs, File(data, "qml.txt"), File(data, "qml"), clear = false)
        // Firefox used to come in the APK, linked here; it's in the app store now.
        File(data, "firefox").takeIf { it.exists() }?.deleteRecursively()
    }

    private fun linkFlatLibraries(libs: String, listFile: File, root: File, clear: Boolean) {
        val list = listFile.takeIf { it.exists() } ?: return
        if (clear) root.deleteRecursively()
        var linked = 0
        var failed = 0
        list.forEachLine { line ->
            val (flat, rel) = line.split('\t').takeIf { it.size == 2 } ?: return@forEachLine
            // Names from the build's own list; still, nothing outside the folder.
            if (rel.startsWith("/") || rel.split('/').any { it == ".." }) return@forEachLine
            val link = File(root, rel)
            link.parentFile?.mkdirs()
            link.delete()
            try {
                android.system.Os.symlink(File(libs, flat).path, link.path)
                linked++
            } catch (e: Exception) {
                failed++
                AppLog.i("Native desktop test: couldn't link $rel: $e")
            }
        }
        AppLog.i("Native desktop test: ${listFile.name}: $linked linked, $failed failed, into ${root.path}")
        if (failed > 0) overlay("couldn't link $failed of ${linked + failed} from ${listFile.name} (see the log)", always = true)
    }

    /**
     * The D-Bus session bus KDE software talks over: DeskDroid's own
     * dbus-daemon, listening in KWin's runtime folder. Returns its address,
     * or null (KWin runs without one) if it didn't start.
     */
    private fun startSessionBus(libs: String, data: File, runtime: File): String? {
        val exe = File(libs, "libdd_dbus-daemon.so")
        if (!exe.exists()) return null
        val socket = File(runtime, "bus").apply { delete() }
        val machineId = File(data, "machine-id").apply {
            if (!exists()) writeText(java.util.UUID.randomUUID().toString().replace("-", "") + "\n")
        }
        val conf = File(data, "session.conf").apply {
            writeText("""
                <busconfig>
                  <type>session</type>
                  <listen>unix:path=${socket.path}</listen>
                  <auth>EXTERNAL</auth>
                  <policy context="default">
                    <allow send_destination="*" eavesdrop="true"/>
                    <allow eavesdrop="true"/>
                    <allow own="*"/>
                  </policy>
                </busconfig>
            """.trimIndent() + "\n")
        }
        return try {
            val p = ProcessBuilder(exe.path, "--config-file=${conf.path}", "--nofork", "--nopidfile")
                .redirectErrorStream(true).also { pb ->
                    pb.environment().apply {
                        remove("LD_PRELOAD")
                        put("LD_LIBRARY_PATH", libs)
                        put("DBUS_MACHINE_ID_FILE", machineId.path)
                    }
                }.start()
            apps += p
            Thread {
                p.inputStream.bufferedReader().outputLines {
                    AppLog.i("[dbus] $it")
                    overlay("dbus: $it")
                }
                val code = p.waitFor()
                synchronized(qtLines) { qtLines.addLast("dbus: exited with code $code") }
            }.apply { isDaemon = true }.start()
            // KWin connects at startup: wait for the socket, briefly.
            for (i in 0 until 40) { if (socket.exists() || !p.isAlive) break; Thread.sleep(50) }
            if (socket.exists()) "unix:path=${socket.path}".also { sessionBus = it } else null
        } catch (e: Exception) {
            AppLog.i("Native desktop test: couldn't start the session bus: $e")
            null
        }
    }

    private fun unpackKWinData(zip: File, dest: File) {
        val stamp = File(dest, ".version")
        val version = packageManager.getPackageInfo(packageName, 0).lastUpdateTime.toString()
        if (stamp.exists() && stamp.readText() == version) return
        dest.deleteRecursively()
        java.util.zip.ZipInputStream(zip.inputStream().buffered()).use { z ->
            while (true) {
                val e = z.nextEntry ?: break
                val out = File(dest, e.name)
                if (!out.canonicalPath.startsWith(dest.canonicalPath + File.separator)) continue
                if (e.isDirectory) out.mkdirs() else {
                    out.parentFile?.mkdirs()
                    out.outputStream().use { z.copyTo(it) }
                }
            }
        }
        stamp.writeText(version)
    }


    private val touchpad = Touchpad()
    private val touchScreen by lazy { TouchScreen(surfaceView) }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (!started) return false
        val mode = Prefs.touchMode(this)
        when {
            e.isFromSource(InputDevice.SOURCE_MOUSE) -> mouse(e)
            // Direct touch: like a phone (TouchScreen).
            mode == "direct" -> {
                touchScreen.wheel = Prefs.scrollWheel(this)
                touchScreen.onTouch(e)
            }
            else -> {
                touchpad.wheel = Prefs.scrollWheel(this)
                touchpad.onTouch(e, surfaceView.width.toFloat(), surfaceView.height.toFloat())
            }
        }
        return true
    }

    override fun onGenericMotionEvent(e: MotionEvent): Boolean {
        if (!started) return false
        if (e.actionMasked == MotionEvent.ACTION_SCROLL) {
            // A real wheel: its clicks, in 120ths (fractions from a smooth wheel).
            NativeDesk.nativeScroll(-e.getAxisValue(MotionEvent.AXIS_HSCROLL) * 120f,
                -e.getAxisValue(MotionEvent.AXIS_VSCROLL) * 120f, true)
            return true
        }
        mouse(e)
        return true
    }

    /** A real mouse: absolute position, its own buttons (bit 1 left, 2 right, 4 middle). */
    private fun mouse(e: MotionEvent) {
        touchpad.moveTo(e.x, e.y)
        NativeDesk.nativePointer(e.x, e.y, e.buttonState)
    }

    override fun onKeyDown(keyCode: Int, e: KeyEvent): Boolean {
        // Back closes the DD menu, or else shows the desktop (every window
        // minimized; Back again brings them back). The menu opens with a swipe
        // up from the bottom right corner.
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            if (e.repeatCount == 0) {
                if (menu.visibility == android.view.View.VISIBLE) showMenu(false)
                else if (started) NativeDesk.nativeAction(1)
            }
            return true
        }
        // Volume keys set the phone's volume, which is the desktop's sound too
        // (there's no KDE mixer yet): Android's own volume slider shows.
        if (isVolumeKey(keyCode)) return super.onKeyDown(keyCode, e)
        if (started) NativeDesk.nativeKey(keyCode, e.unicodeChar, true)
        return true
    }

    private fun isVolumeKey(k: Int) =
        k == KeyEvent.KEYCODE_VOLUME_UP || k == KeyEvent.KEYCODE_VOLUME_DOWN || k == KeyEvent.KEYCODE_VOLUME_MUTE

    override fun onKeyUp(keyCode: Int, e: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK) return true // handled in onKeyDown
        if (isVolumeKey(keyCode)) return super.onKeyUp(keyCode, e)
        if (started) NativeDesk.nativeKey(keyCode, e.unicodeChar, false)
        return true
    }

    // ---- The DD menu: a sheet that slides up from the bottom, where the
    // keyboard sits. Swipe up from the bottom right corner opens it (Back
    // closes it); swipe up from the bottom left corner brings the keyboard.

    private lateinit var menu: FrameLayout
    private lateinit var panel: LinearLayout

    private fun buildMenu(): android.view.View {
        menu = FrameLayout(this).apply {
            setBackgroundColor(0x55000000)
            visibility = android.view.View.GONE
            setOnClickListener { showMenu(false) } // a tap outside the sheet closes it
        }
        panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(io.deskdroid.app.ui.Party.PANEL)
            elevation = dp(16f)
            isClickable = true // touches don't fall through to the desktop
        }
        menu.addView(panel, FrameLayout.LayoutParams(-1, -2, android.view.Gravity.BOTTOM or android.view.Gravity.CENTER_HORIZONTAL))
        return menu
    }

    /**
     * The sheet's contents, made again each time it opens (the dock and the
     * layout follow changes and rotation). The title, the dock and the action
     * buttons stay put; the settings between them scroll, under small
     * category headings.
     */
    private fun fillMenu() {
        val ui = io.deskdroid.app.ui.Ui(this)
        val wide = resources.configuration.screenWidthDp >= 600
        val P = io.deskdroid.app.ui.Party
        panel.removeAllViews()
        panel.setPadding(dp(16), dp(10), dp(16), dp(14))

        // A grab handle, like a bottom sheet.
        panel.addView(android.view.View(this).apply {
            background = android.graphics.drawable.GradientDrawable().apply {
                cornerRadius = dp(2f); setColor(P.BORDER)
            }
        }, LinearLayout.LayoutParams(dp(40), dp(4)).apply { gravity = android.view.Gravity.CENTER_HORIZONTAL; bottomMargin = dp(6) })
        panel.addView(ui.row {
            addView(ui.text("DESKDROID", 15f).apply { typeface = P.orbitron(context); letterSpacing = 0.08f })
            spacer()
            addView(ui.outlineButton("✕", P.TEXT) { showMenu(false) }, LinearLayout.LayoutParams(dp(40), dp(40)))
        }, LinearLayout.LayoutParams(-1, -2))
        panel.addView(dockRow(ui), LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(6); bottomMargin = dp(6) })

        fun heading(title: String) = ui.text("— ${title.uppercase()} —", 11f, P.MUTED, 700).apply {
            gravity = android.view.Gravity.CENTER
            letterSpacing = 0.12f
        }
        fun section(title: String, vararg views: android.view.View) = ui.column(6) {
            addView(heading(title), LinearLayout.LayoutParams(-1, -2))
            views.forEach { addView(it, LinearLayout.LayoutParams(-1, -2)) }
        }

        val scaleTile = ui.tile(scaleLabel(), P.YELLOW) {}
        scaleTile.setOnClickListener {
            val i = (SCALES.indexOf(Prefs.nativeScale(this)) + 1) % SCALES.size
            Prefs.setNativeScale(this, SCALES[i])
            scaleTile.text = scaleLabel()
            // Applied now: KWin lays the desktop out again at the new scale.
            if (started) NativeDesk.nativeSetScale(NativeDesk.desktopScale(this))
        }
        val sections = listOf(
            section("Touchscreen mode",
                io.deskdroid.app.ui.Segmented(ui, Prefs.TOUCH_MODE_LABELS,
                    maxOf(0, Prefs.TOUCH_MODES.indexOf(Prefs.touchMode(this)))) { i ->
                    Prefs.setTouchMode(this, Prefs.TOUCH_MODES[i])
                }.view),
            section("Scroll behavior",
                io.deskdroid.app.ui.Segmented(ui, listOf("Wheel", "Touchpad"),
                    if (Prefs.scrollWheel(this)) 0 else 1) { i ->
                    Prefs.setScrollWheel(this, i == 0)
                }.view),
            section("Panel display behavior",
                io.deskdroid.app.ui.Segmented(ui, listOf("Full screen", "Dodge cutouts"),
                    if (Prefs.dodgeCutouts(this)) 1 else 0) { i ->
                    Prefs.setDodgeCutouts(this, i == 1)
                    sendSafeArea()
                }.view),
            section("Keyboard spawning",
                io.deskdroid.app.ui.Segmented(ui, listOf("Manual", "Automatic"),
                    if (Prefs.autoKeyboard(this)) 1 else 0) { i ->
                    Prefs.setAutoKeyboard(this, i == 1)
                }.view),
            section("Display options",
                io.deskdroid.app.ui.Segmented(ui, listOf("Screen may sleep", "Keep awake"),
                    if (Prefs.keepAwake(this)) 1 else 0) { i ->
                    Prefs.setKeepAwake(this, i == 1)
                    applyKeepAwake()
                }.view,
                scaleTile),
        )
        val settings = ui.column(14) {
            setPadding(0, dp(4), 0, dp(8))
            // Two sections side by side on a wide (landscape) screen.
            sections.chunked(if (wide) 2 else 1).forEach { pair ->
                addView(ui.row(10) { pair.forEach { addView(ui.weight(it)) } }, LinearLayout.LayoutParams(-1, -2))
            }
        }
        panel.addView(android.widget.ScrollView(this).apply {
            isVerticalScrollBarEnabled = true
            isVerticalFadingEdgeEnabled = true
            setFadingEdgeLength(dp(24))
            addView(settings, FrameLayout.LayoutParams(-1, -2))
        }, LinearLayout.LayoutParams(-1, 0, 1f))

        val stop = ui.text("STOP", 12f, 0xFFFF6B82.toInt()).apply {
            typeface = P.orbitron(context)
            letterSpacing = 0.12f
            gravity = android.view.Gravity.CENTER
            minHeight = dp(44)
            background = io.deskdroid.app.ui.ChamferDrawable(dp(12f), stroke = P.RED, strokeWidth = dp(1.5f))
            setOnClickListener { confirmStop() }
        }
        val actions = listOf(
            ui.tile("Keyboard", P.CYAN) { showMenu(false); toggleKeyboard() },
            ui.tile("App Store", P.GREEN) {
                showMenu(false)
                startActivity(android.content.Intent(this@NativeDeskActivity, StoreActivity::class.java))
            },
            stop,
        )
        panel.addView(ui.row(6) { actions.forEach { addView(ui.weight(it)) } },
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(8) })

        // A fixed height, about half the screen (most of it when the screen is
        // wide and short); the settings scroll inside it.
        val dm = resources.displayMetrics
        (panel.layoutParams as FrameLayout.LayoutParams).apply {
            width = if (wide) minOf(dp(720), dm.widthPixels) else -1
            height = (dm.heightPixels * if (dm.heightPixels > dm.widthPixels) 0.5f else 0.85f).toInt()
        }
        panel.requestLayout()
    }

    /** Up to 10 phone apps: tap opens one, long press takes it off, + adds one. */
    private fun dockRow(ui: io.deskdroid.app.ui.Ui): android.view.View {
        val launcher = getSystemService(android.content.pm.LauncherApps::class.java)
        val me = android.os.Process.myUserHandle()
        val apps = Prefs.dockApps(this).mapNotNull { name ->
            val cn = android.content.ComponentName.unflattenFromString(name) ?: return@mapNotNull null
            try { launcher.resolveActivity(android.content.Intent().setComponent(cn).addCategory(android.content.Intent.CATEGORY_LAUNCHER), me) }
            catch (e: Exception) { null } // uninstalled: left out
        }
        val row = ui.row(4) {
            for (a in apps) addView(dockItem(ui, a.getBadgedIcon(0), a.label.toString(), {
                showMenu(false)
                try { launcher.startMainActivity(a.componentName, me, null, null) }
                catch (e: Exception) { AppLog.i("Native desktop: couldn't open ${a.componentName}: $e") }
            }) {
                Prefs.setDockApps(this@NativeDeskActivity, Prefs.dockApps(this@NativeDeskActivity) - a.componentName.flattenToString())
                android.widget.Toast.makeText(this@NativeDeskActivity, "${a.label} is off the dock", android.widget.Toast.LENGTH_SHORT).show()
                fillMenu()
            })
            if (apps.size < 10) addView(dockItem(ui, null, "Add app", { pickDockApp() }, null))
        }
        return android.widget.HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(row)
        }
    }

    private fun dockItem(ui: io.deskdroid.app.ui.Ui, icon: android.graphics.drawable.Drawable?, label: String,
                         onTap: () -> Unit, onLongPress: (() -> Unit)?) = ui.column(2) {
        gravity = android.view.Gravity.CENTER_HORIZONTAL
        setPadding(dp(4), dp(4), dp(4), dp(4))
        addView(if (icon != null) android.widget.ImageView(context).apply { setImageDrawable(icon) }
                else ui.text("+", 26f, io.deskdroid.app.ui.Party.CYAN, 700).apply {
                    gravity = android.view.Gravity.CENTER
                    background = io.deskdroid.app.ui.ChamferDrawable(dp(10f), stroke = io.deskdroid.app.ui.Party.BORDER, strokeWidth = dp(1.5f))
                }, LinearLayout.LayoutParams(dp(48), dp(48)))
        addView(ui.ellipsize(ui.text(label, 11f, io.deskdroid.app.ui.Party.TEXT).apply { gravity = android.view.Gravity.CENTER }),
            LinearLayout.LayoutParams(dp(64), -2))
        setOnClickListener { onTap() }
        if (onLongPress != null) setOnLongClickListener { onLongPress(); true }
    }

    private fun pickDockApp() {
        val launcher = getSystemService(android.content.pm.LauncherApps::class.java)
        val have = Prefs.dockApps(this).toSet()
        val all = launcher.getActivityList(null, android.os.Process.myUserHandle())
            .filter { it.componentName.packageName != packageName && it.componentName.flattenToString() !in have }
            .sortedBy { it.label.toString().lowercase() }
        android.app.AlertDialog.Builder(this)
            .setTitle("Add to the dock")
            .setItems(all.map { it.label }.toTypedArray()) { _, i ->
                Prefs.setDockApps(this, Prefs.dockApps(this) + all[i].componentName.flattenToString())
                fillMenu()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    // ---- Swipes up from the bottom corners (in every touch mode): left
    // brings the keyboard, right opens the DD menu. A touch that starts in a
    // corner is held back until it's clearly a swipe up or clearly not one;
    // if not, it goes to the desktop as it happened.
    private var edge = 0 // 0 none, 1 left corner, 2 right corner, -1 swipe done (rest of the touch ignored)
    private var edgeX = 0f
    private var edgeY = 0f
    private val held = ArrayList<MotionEvent>()

    override fun dispatchTouchEvent(e: MotionEvent): Boolean {
        if (e.actionMasked == MotionEvent.ACTION_DOWN) {
            edge = 0
            val v = window.decorView
            if (started && menu.visibility != android.view.View.VISIBLE &&
                    !e.isFromSource(InputDevice.SOURCE_MOUSE) && e.rawY > v.height - dp(EDGE_DP)) {
                edge = when {
                    e.rawX < v.width * 0.3f -> 1
                    e.rawX > v.width * 0.7f -> 2
                    else -> 0
                }
            }
            if (edge == 0) return super.dispatchTouchEvent(e)
            edgeX = e.rawX; edgeY = e.rawY
            held.add(MotionEvent.obtain(e))
            return true
        }
        val end = e.actionMasked == MotionEvent.ACTION_UP || e.actionMasked == MotionEvent.ACTION_CANCEL
        when (edge) {
            0 -> return super.dispatchTouchEvent(e)
            -1 -> { if (end) edge = 0; return true }
        }
        val up = edgeY - e.rawY
        val side = abs(e.rawX - edgeX)
        if (e.actionMasked == MotionEvent.ACTION_MOVE && up > dp(48f) && up > side * 1.5f) {
            val which = edge
            edge = -1
            held.forEach { it.recycle() }; held.clear()
            if (which == 1) toggleKeyboard() else showMenu(true)
            return true
        }
        val notASwipe = end || e.actionMasked == MotionEvent.ACTION_POINTER_DOWN ||
            side > dp(32f) || e.eventTime - e.downTime > 500
        if (!notASwipe) { held.add(MotionEvent.obtain(e)); return true }
        edge = 0
        held.forEach { super.dispatchTouchEvent(it); it.recycle() }; held.clear()
        return super.dispatchTouchEvent(e)
    }

    // Home (button or swipe up) while the desktop is already showing: like
    // a phone launcher going back to its home screen, every window is
    // minimized (KWin's Show Desktop; Home again brings them back). Coming
    // back from another app, Home only brings the desktop forward.
    private var inFront = false
    override fun onResume() { super.onResume(); inFront = true }
    override fun onPause() { super.onPause(); inFront = false }
    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        if (inFront && started && intent.hasCategory(android.content.Intent.CATEGORY_HOME)) {
            showMenu(false)
            NativeDesk.nativeAction(1)
        }
    }

    /** The menu's Keep awake: the screen stays on while the desktop shows. */
    protected open fun applyKeepAwake() {
        val flag = android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
        if (Prefs.keepAwake(this)) window.addFlags(flag) else window.clearFlags(flag)
    }

    private fun scaleLabel() = Prefs.nativeScale(this).let { if (it == 0f) "Scale: auto" else "Scale ${"%.2f".format(it).trimEnd('0').trimEnd('.')}×" }

    /**
     * While the DD menu is open Android's status and navigation bars show
     * (and stay), and the sheet sits above the navigation bar's buttons;
     * closed, the desktop is full screen again. The window is edge to edge,
     * so the desktop's size doesn't change when the bars come and go.
     */
    private fun systemBars(show: Boolean) {
        if (Build.VERSION.SDK_INT < 30) return
        window.insetsController?.apply {
            if (show) {
                systemBarsBehavior = WindowInsetsController.BEHAVIOR_DEFAULT
                show(WindowInsets.Type.systemBars())
            } else {
                hide(WindowInsets.Type.systemBars())
                systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        }
    }

    private fun padMenu() {
        if (!::menu.isInitialized) return
        val i = if (Build.VERSION.SDK_INT >= 30)
            lastInsets?.getInsets(WindowInsets.Type.systemBars()) else null
        menu.setPadding(i?.left ?: 0, i?.top ?: 0, i?.right ?: 0, i?.bottom ?: 0)
    }

    private fun showMenu(open: Boolean) {
        systemBars(open)
        if (open) {
            softKeyboard(false) // the sheet takes the keyboard's place
            fillMenu()
            menu.visibility = android.view.View.VISIBLE
            panel.translationY = resources.displayMetrics.heightPixels.toFloat()
            panel.animate().translationY(0f).setDuration(200).start()
        } else if (menu.visibility == android.view.View.VISIBLE) {
            panel.animate().translationY(panel.height.toFloat()).setDuration(150)
                .withEndAction { menu.visibility = android.view.View.GONE }.start()
        }
    }

    private fun toggleKeyboard() {
        val imm = getSystemService(android.view.inputmethod.InputMethodManager::class.java)
        surfaceView.requestFocus()
        imm.showSoftInput(surfaceView, android.view.inputmethod.InputMethodManager.SHOW_FORCED)
    }

    /** The phone's keyboard for a desktop text field (it follows the field's focus). */
    fun softKeyboard(show: Boolean) {
        val imm = getSystemService(android.view.inputmethod.InputMethodManager::class.java)
        if (show) {
            surfaceView.requestFocus()
            imm.showSoftInput(surfaceView, 0)
        } else {
            imm.hideSoftInputFromWindow(surfaceView.windowToken, 0)
        }
    }

    private fun confirmStop() {
        android.app.AlertDialog.Builder(this)
            .setTitle("Stop the desktop?")
            .setMessage("Unsaved work in desktop apps will be lost.")
            .setPositiveButton("Stop") { _, _ -> NativeDesk.stop(this, "Stop in the menu") }
            .setNegativeButton("Cancel", null)
            .show()
    }

    /**
     * The desktop's view, which takes the on-screen keyboard: its text arrives as
     * key events (BaseInputConnection without an editor), handled like a real
     * keyboard's in onKeyDown/onKeyUp.
     */
    class KeyboardSurface(c: android.content.Context) : SurfaceView(c) {
        override fun onCheckIsTextEditor() = true
        override fun onCreateInputConnection(info: android.view.inputmethod.EditorInfo): android.view.inputmethod.InputConnection {
            info.inputType = android.text.InputType.TYPE_NULL
            info.imeOptions = android.view.inputmethod.EditorInfo.IME_FLAG_NO_FULLSCREEN
            return android.view.inputmethod.BaseInputConnection(this, false)
        }
    }

    /**
     * The phone screen as a laptop touchpad, like the desktop's Touchpad mode:
     * one finger moves the pointer, a tap clicks, a two-finger tap right-clicks,
     * two fingers scroll, a double tap double-clicks, and tap then hold drags.
     */
    class Touchpad {
        private var px = -1f
        private var py = -1f
        private var lastX = 0f
        private var lastY = 0f
        private var downAt = 0L
        private var lastTapAt = 0L
        private var travel = 0f
        private var maxFingers = 0
        private var dragging = false
        // Two-finger scroll keeps to the axis it started on (0 not yet known,
        // 1 vertical, 2 horizontal), so a slightly slanted swipe through a page
        // doesn't also scroll it sideways.
        private var scrollAxis = 0
        private var scrollX = 0f
        private var scrollY = 0f
        // Tap, tap, then touch and hold: the middle button held (3D views, autoscroll).
        private var lastDoubleTapAt = 0L
        private var middle = false
        /** Scroll type (DD menu): a mouse wheel's steps, up and down only, or a touchpad's. */
        var wheel = true
        private var wheelSteps = 0f

        fun moveTo(x: Float, y: Float) { px = x; py = y }

        /** The buttons held (bit 1 left, 2 right), from on-screen buttons, at the pointer. */
        fun buttons(b: Int) { if (px >= 0) NativeDesk.nativePointer(px, py, b) }

        fun onTouch(e: MotionEvent, w: Float, h: Float) {
            if (px < 0) { px = w / 2; py = h / 2 }
            val n = e.pointerCount
            val cx = (0 until n).map { e.getX(it) }.average().toFloat()
            val cy = (0 until n).map { e.getY(it) }.average().toFloat()
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downAt = e.eventTime
                    travel = 0f
                    maxFingers = 1
                    scrollAxis = 0; scrollX = 0f; scrollY = 0f; wheelSteps = 0f
                    // Tap, tap, then touch and hold: the middle button, held until lifted.
                    middle = e.eventTime - lastDoubleTapAt < DOUBLE_TAP_MS
                    lastDoubleTapAt = 0L
                    // Tap, then touch again and hold: drag with the left button down. The
                    // tap's own click waits for this (pendingTap), so a drag is one press,
                    // not a click and then a press (a double click: title bars maximize).
                    dragging = !middle && e.eventTime - lastTapAt < DOUBLE_TAP_MS
                    if (middle) {
                        NativeDesk.nativePointer(px, py, 4)
                    } else if (dragging) {
                        handler.removeCallbacks(pendingTap)
                        NativeDesk.nativePointer(px, py, 1)
                    }
                }
                MotionEvent.ACTION_POINTER_DOWN, MotionEvent.ACTION_POINTER_UP -> maxFingers = maxOf(maxFingers, n)
                MotionEvent.ACTION_MOVE -> {
                    val dx = cx - lastX
                    val dy = cy - lastY
                    travel += abs(dx) + abs(dy)
                    if (n >= 2 && !middle) {
                        scroll(dx, dy)
                    } else {
                        px = (px + dx * SPEED).coerceIn(0f, w - 1)
                        py = (py + dy * SPEED).coerceIn(0f, h - 1)
                        NativeDesk.nativePointer(px, py, if (middle) 4 else if (dragging) 1 else 0)
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    val tap = travel < TAP_SLOP && e.eventTime - downAt < TAP_MS
                    when {
                        middle -> NativeDesk.nativePointer(px, py, 0)
                        // Tap, tap: the second touch's press, its release, then one more
                        // click, so apps see a double click. Tap, hold (or move): a drag.
                        dragging && tap -> { NativeDesk.nativePointer(px, py, 0); click(1) }
                        dragging -> NativeDesk.nativePointer(px, py, 0)
                        tap && maxFingers >= 2 -> click(2)
                        tap -> handler.postDelayed(pendingTap, DOUBLE_TAP_MS)
                    }
                    lastDoubleTapAt = if (dragging && tap) e.eventTime else 0L
                    lastTapAt = if (tap && maxFingers == 1 && !dragging && !middle) e.eventTime else 0L
                    dragging = false
                    middle = false
                }
            }
            // Re-anchor after the finger count changes, so the pointer doesn't jump.
            lastX = if (e.actionMasked == MotionEvent.ACTION_POINTER_UP) avgWithout(e, e.actionIndex) { e.getX(it) } else cx
            lastY = if (e.actionMasked == MotionEvent.ACTION_POINTER_UP) avgWithout(e, e.actionIndex) { e.getY(it) } else cy
        }

        /** Two-finger scroll, kept to the axis the swipe starts along unless it's clearly diagonal. */
        private fun scroll(dx: Float, dy: Float) {
            if (wheel) {
                // Up and down only, as whole 120ths of a wheel click (natural:
                // the content follows the fingers).
                wheelSteps += -dy * WHEEL_PER_PX
                val steps = wheelSteps.toInt()
                if (steps != 0) {
                    NativeDesk.nativeScroll(0f, steps.toFloat(), true)
                    wheelSteps -= steps
                }
                return
            }
            if (scrollAxis == 0) {
                scrollX += dx; scrollY += dy
                if (abs(scrollX) + abs(scrollY) < AXIS_SLOP) return
                scrollAxis = when {
                    abs(scrollY) >= abs(scrollX) * 2 -> 1
                    abs(scrollX) >= abs(scrollY) * 2 -> 2
                    else -> 3 // diagonal: both (panning a large image)
                }
                dxdy(scrollX, scrollY)
                return
            }
            dxdy(dx, dy)
        }

        private fun dxdy(dx: Float, dy: Float) {
            val sx = if (scrollAxis == 1) 0f else dx
            val sy = if (scrollAxis == 2) 0f else dy
            NativeDesk.nativeScroll(-sx * SCROLL_SPEED, -sy * SCROLL_SPEED, false) // natural scrolling
        }

        private val handler = Handler(Looper.getMainLooper())
        private val pendingTap = Runnable { click(1) }

        private fun click(button: Int) {
            NativeDesk.nativePointer(px, py, button)
            NativeDesk.nativePointer(px, py, 0)
        }

        private inline fun avgWithout(e: MotionEvent, skip: Int, v: (Int) -> Float) =
            (0 until e.pointerCount).filter { it != skip }.map { v(it) }.average().toFloat()

        companion object {
            const val SPEED = 1.6f
            const val SCROLL_SPEED = 1.5f
            const val TAP_MS = 220L
            const val DOUBLE_TAP_MS = 300L
            const val TAP_SLOP = 24f
            const val AXIS_SLOP = 12f
            const val WHEEL_PER_PX = 3f // a wheel click (120) per 40 px of finger travel
        }
    }

    override fun onDestroy() {
        main.removeCallbacks(tick)
        // Stop (in the menu or the notification) ends the desktop; anything else
        // that destroys the window leaves it running in the background.
        // A monitor unplugged closes its window; the desktop goes on, back on the phone.
        // Only the current window: as the home app, Android opens a new desktop
        // window as soon as Stop finishes this one, and this one's late onDestroy
        // used to stop (and finish) the new one, over and over (the restart loop).
        val current = NativeDesk.activity?.get().let { it == null || it === this }
        if (isFinishing && !external && current && NativeDesk.running) NativeDesk.stop(this, "window closed")
        if (NativeDesk.activity?.get() === this) NativeDesk.activity = null
        super.onDestroy()
    }
}

/**
 * A desktop process's output, line by line, until it ends. Stopping the desktop
 * closes the stream under the reader; that ends the loop instead of crashing the app.
 */
internal inline fun java.io.BufferedReader.outputLines(action: (String) -> Unit) {
    try {
        while (true) action(readLine() ?: break)
    } catch (e: java.io.IOException) {
    } finally {
        runCatching { close() }
    }
}

/**
 * The desktop on a monitor (display out). Android starts it there as the
 * monitor's home when DeskDroid is the phone's home app, instead of its own
 * desktop mode; Start desktop with Monitor also opens it there. Its own class
 * because a monitor's home can't be a single-task activity like the phone's.
 */
class ExternalDeskActivity : NativeDeskActivity() {
    // Input comes from the phone's touchpad or a USB/Bluetooth mouse, which
    // Android doesn't count as activity on the monitor: without this it sleeps.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun applyKeepAwake() {} // always on (above)
}

/**
 * The phone's screen while the desktop is on a monitor: a touchpad (the same
 * gestures as Touchpad mode) and the keyboard. It closes when the monitor goes,
 * and the desktop comes back to the phone.
 */
class PhoneTouchpadActivity : Activity() {
    private val touchpad = NativeDeskActivity.Touchpad()
    private lateinit var pad: NativeDeskActivity.KeyboardSurface
    private val displays by lazy { getSystemService(android.hardware.display.DisplayManager::class.java) }
    private val listener = object : android.hardware.display.DisplayManager.DisplayListener {
        override fun onDisplayAdded(id: Int) = Unit
        override fun onDisplayChanged(id: Int) = Unit
        override fun onDisplayRemoved(id: Int) {
            if (displays.displays.none { it.displayId != android.view.Display.DEFAULT_DISPLAY }) {
                AppLog.i("Native desktop: monitor unplugged, back to the phone")
                finish()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        NativeDesk.touchpad = java.lang.ref.WeakReference(this)
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        pad = NativeDeskActivity.KeyboardSurface(this).apply {
            isFocusable = true
            isFocusableInTouchMode = true
            setZOrderOnTop(false)
        }
        // The mockup (ui/mockups/Touchpad): a rainbow line, "On the big
        // screen", the touch area with its grid and glow, Left and Right
        // buttons, and keys a phone keyboard lacks.
        val ui = io.deskdroid.app.ui.Ui(this)
        val P = io.deskdroid.app.ui.Party
        fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
        val header = ui.column(2) {
            addView(ui.text("ON THE BIG SCREEN", 15f).apply { typeface = P.orbitron(context); letterSpacing = 0.06f })
            addView(ui.text("${NativeDesk.surfaceW.toInt()} × ${NativeDesk.surfaceH.toInt()} · unplug to bring it back", 12f, P.MUTED))
        }
        val area = FrameLayout(this).apply {
            addView(TouchpadArea(context), FrameLayout.LayoutParams(-1, -1))
            addView(pad, FrameLayout.LayoutParams(1, 1)) // takes the keyboard's text
            addView(ui.column(6) {
                gravity = android.view.Gravity.CENTER_HORIZONTAL
                addView(ui.text("☝", 34f, P.PINK).apply { gravity = android.view.Gravity.CENTER })
                for (line in listOf("Tap to click", "Two-finger tap to right-click", "Two fingers to scroll · tap, then hold to drag"))
                    addView(ui.text(line, 13f, P.MUTED).apply { gravity = android.view.Gravity.CENTER })
            }, FrameLayout.LayoutParams(-2, -2, android.view.Gravity.CENTER))
        }
        fun bigButton(label: String, accent: Int, buttons: Int) = ui.text(label, 14f, P.TEXT, 700).apply {
            gravity = android.view.Gravity.CENTER
            letterSpacing = 0.08f
            typeface = P.orbitron(context, 700)
            minHeight = dp(64)
            background = io.deskdroid.app.ui.ChamferDrawable(0f, fill = P.SURFACE, stroke = P.BORDER_SOFT, strokeWidth = dp(1).toFloat(),
                cutTopLeft = false, cutBottomRight = false, accent = accent, accentEdge = android.view.Gravity.BOTTOM, accentWidth = dp(2).toFloat())
            // Held while the finger is on it: a click, or a drag with the touchpad.
            setOnTouchListener { v, e ->
                when (e.actionMasked) {
                    MotionEvent.ACTION_DOWN -> { v.isPressed = true; touchpad.buttons(buttons) }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> { v.isPressed = false; touchpad.buttons(0) }
                }
                true
            }
        }
        // Modifiers latch: tap Ctrl, then the key; tap Ctrl again to let go.
        val held = mutableSetOf<Int>()
        fun key(label: String, accent: Int, code: Int, latch: Boolean) = ui.text(label, 12f, P.TEXT, 700).apply {
            gravity = android.view.Gravity.CENTER
            typeface = P.orbitron(context, 700)
            minHeight = dp(48)
            fun paint(on: Boolean) {
                background = io.deskdroid.app.ui.ChamferDrawable(0f, fill = if (on) 0xFF24102A.toInt() else P.SURFACE,
                    stroke = if (on) P.PINK else P.BORDER_SOFT, strokeWidth = dp(1).toFloat(), cutTopLeft = false, cutBottomRight = false,
                    accent = accent, accentEdge = android.view.Gravity.BOTTOM, accentWidth = dp(2).toFloat())
            }
            paint(false)
            setOnClickListener {
                if (!latch) {
                    NativeDesk.nativeKey(code, 0, true); NativeDesk.nativeKey(code, 0, false)
                    // A plain key lets go of latched modifiers (Ctrl+Tab, then done).
                } else if (code in held) {
                    held -= code; NativeDesk.nativeKey(code, 0, false); paint(false)
                } else {
                    held += code; NativeDesk.nativeKey(code, 0, true); paint(true)
                }
            }
        }
        val keyboard = android.widget.ImageView(this).apply {
            setImageDrawable(object : android.graphics.drawable.Drawable() {
                val p = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                    style = android.graphics.Paint.Style.STROKE; strokeWidth = dp(2).toFloat(); color = Color.WHITE
                }
                override fun draw(c: android.graphics.Canvas) {
                    val w = bounds.width().toFloat(); val h = bounds.height().toFloat()
                    val r = android.graphics.RectF(w * 0.3f, h * 0.36f, w * 0.7f, h * 0.64f)
                    c.drawRoundRect(r, dp(2).toFloat(), dp(2).toFloat(), p)
                    c.drawLine(w * 0.4f, h * 0.56f, w * 0.6f, h * 0.56f, p)
                }
                override fun setAlpha(a: Int) {}
                override fun setColorFilter(f: android.graphics.ColorFilter?) {}
                @Suppress("OVERRIDE_DEPRECATION") override fun getOpacity() = android.graphics.PixelFormat.TRANSLUCENT
            })
            background = io.deskdroid.app.ui.ChamferDrawable(0f, rainbowFill = true, cutTopLeft = false, cutBottomRight = false)
            minimumHeight = dp(48)
            setOnClickListener { softKeyboard(true) }
        }
        val content = ui.column(10) {
            setPadding(dp(16), dp(20), dp(16), dp(16))
            addView(header, LinearLayout.LayoutParams(-1, -2))
            addView(area, LinearLayout.LayoutParams(-1, 0, 1f))
            addView(ui.row(8) {
                addView(ui.weight(bigButton("LEFT", P.CYAN, 1)))
                addView(ui.weight(bigButton("RIGHT", P.PINK, 2)))
            }, LinearLayout.LayoutParams(-1, -2))
            addView(ui.row(6) {
                addView(ui.weight(key("ESC", P.RED, KeyEvent.KEYCODE_ESCAPE, false)))
                addView(ui.weight(key("TAB", P.ORANGE, KeyEvent.KEYCODE_TAB, false)))
                addView(ui.weight(key("CTRL", P.YELLOW, KeyEvent.KEYCODE_CTRL_LEFT, true)))
                addView(ui.weight(key("ALT", P.GREEN, KeyEvent.KEYCODE_ALT_LEFT, true)))
                addView(ui.weight(key("META", P.CYAN, KeyEvent.KEYCODE_META_LEFT, true)))
                addView(ui.weight(keyboard))
            }, LinearLayout.LayoutParams(-1, -2))
            addView(ui.text("Got a Bluetooth mouse and keyboard? This screen can go dark.", 12f, P.DIM).apply {
                gravity = android.view.Gravity.CENTER
            }, LinearLayout.LayoutParams(-1, -2))
        }
        setContentView(FrameLayout(this).apply {
            setBackgroundColor(P.BG)
            addView(content, FrameLayout.LayoutParams(-1, -1))
            addView(io.deskdroid.app.ui.RainbowStrip(context), FrameLayout.LayoutParams(-1, dp(4)))
        })
        displays.registerDisplayListener(listener, Handler(Looper.getMainLooper()))
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (NativeDesk.surfaceW <= 0f) return false
        touchpad.wheel = Prefs.scrollWheel(this)
        touchpad.onTouch(e, NativeDesk.surfaceW, NativeDesk.surfaceH)
        return true
    }

    override fun onKeyDown(keyCode: Int, e: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK) return true
        NativeDesk.nativeKey(keyCode, e.unicodeChar, true)
        return true
    }

    override fun onKeyUp(keyCode: Int, e: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK) return true
        NativeDesk.nativeKey(keyCode, e.unicodeChar, false)
        return true
    }

    fun softKeyboard(show: Boolean) {
        val imm = getSystemService(android.view.inputmethod.InputMethodManager::class.java)
        if (show) {
            pad.requestFocus()
            imm.showSoftInput(pad, 0)
        } else {
            imm.hideSoftInputFromWindow(pad.windowToken, 0)
        }
    }

    override fun onDestroy() {
        displays.unregisterDisplayListener(listener)
        if (NativeDesk.touchpad?.get() === this) NativeDesk.touchpad = null
        super.onDestroy()
    }
}

/**
 * Direct touch: the screen works like a phone's, on the desktop's mouse. A tap
 * clicks where it lands; a slide scrolls what's under the finger (the content
 * follows it, as wheel steps or smoothly, per Scroll behavior); touch and
 * hold, then lift, is the right button; touch and hold, then move, drags with
 * the left button (selecting text, moving windows and files). A two-finger tap
 * is the right button too.
 */
class TouchScreen(private val view: android.view.View) {
    var wheel = true
    private enum class State { IDLE, PENDING, SCROLL, HOLD, DRAG, TWO }
    private var state = State.IDLE
    private var downX = 0f
    private var downY = 0f
    private var lastX = 0f
    private var lastY = 0f
    private var wheelSteps = 0f
    private val handler = Handler(Looper.getMainLooper())
    private val slop = view.context.resources.displayMetrics.density * 10f

    private val longPress = Runnable {
        if (state == State.PENDING) {
            state = State.HOLD
            view.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
        }
    }

    fun onTouch(e: MotionEvent) {
        val n = e.pointerCount
        val cx = (0 until n).map { e.getX(it) }.average().toFloat()
        val cy = (0 until n).map { e.getY(it) }.average().toFloat()
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                state = State.PENDING
                downX = e.x; downY = e.y
                wheelSteps = 0f
                NativeDesk.nativePointer(e.x, e.y, 0) // the pointer goes where the finger is
                handler.postDelayed(longPress, LONG_PRESS_MS)
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                handler.removeCallbacks(longPress)
                when (state) {
                    State.PENDING, State.HOLD -> state = State.TWO
                    State.DRAG -> { NativeDesk.nativePointer(lastX, lastY, 0); state = State.SCROLL }
                    else -> {}
                }
            }
            MotionEvent.ACTION_MOVE -> {
                val moved = abs(e.x - downX) > slop || abs(e.y - downY) > slop
                when (state) {
                    State.PENDING, State.TWO -> if (moved) {
                        handler.removeCallbacks(longPress)
                        state = State.SCROLL
                        scroll(cx - lastX, cy - lastY)
                    }
                    State.HOLD -> if (moved) {
                        state = State.DRAG
                        NativeDesk.nativePointer(downX, downY, 1)
                        NativeDesk.nativePointer(e.x, e.y, 1)
                    }
                    State.SCROLL -> scroll(cx - lastX, cy - lastY)
                    State.DRAG -> NativeDesk.nativePointer(e.x, e.y, 1)
                    State.IDLE -> {}
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                handler.removeCallbacks(longPress)
                val cancel = e.actionMasked == MotionEvent.ACTION_CANCEL
                when (state) {
                    State.PENDING -> if (!cancel) click(downX, downY, 1)
                    State.HOLD, State.TWO -> if (!cancel) click(downX, downY, 2)
                    State.DRAG -> NativeDesk.nativePointer(e.x, e.y, 0)
                    else -> {}
                }
                state = State.IDLE
            }
        }
        // Re-anchor after the finger count changes, so a scroll doesn't jump.
        if (e.actionMasked == MotionEvent.ACTION_POINTER_UP) {
            val rest = (0 until n).filter { it != e.actionIndex }
            lastX = rest.map { e.getX(it) }.average().toFloat()
            lastY = rest.map { e.getY(it) }.average().toFloat()
        } else {
            lastX = cx; lastY = cy
        }
    }

    private fun click(x: Float, y: Float, button: Int) {
        NativeDesk.nativePointer(x, y, button)
        NativeDesk.nativePointer(x, y, 0)
    }

    /** The content follows the finger. */
    private fun scroll(dx: Float, dy: Float) {
        if (wheel) {
            wheelSteps += -dy * NativeDeskActivity.Touchpad.WHEEL_PER_PX
            val steps = wheelSteps.toInt()
            if (steps != 0) {
                NativeDesk.nativeScroll(0f, steps.toFloat(), true)
                wheelSteps -= steps
            }
        } else {
            NativeDesk.nativeScroll(-dx, -dy, false)
        }
    }

    companion object {
        const val LONG_PRESS_MS = 450L
    }
}

/** The phone-as-touchpad screen's touch area: a faint grid, a purple glow, a border with a cut corner. */
class TouchpadArea(c: android.content.Context) : android.view.View(c) {
    private val d = c.resources.displayMetrics.density
    private val grid = android.graphics.Paint().apply { color = 0x14FFFFFF; strokeWidth = d }
    private val glow = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG)
    private val border = io.deskdroid.app.ui.ChamferDrawable(18 * d, fill = 0xFF0B0B14.toInt(),
        stroke = io.deskdroid.app.ui.Party.BORDER, strokeWidth = d, cutTopLeft = false)

    override fun onDraw(canvas: android.graphics.Canvas) {
        val w = width.toFloat(); val h = height.toFloat()
        border.setBounds(0, 0, width, height)
        border.draw(canvas)
        canvas.save()
        canvas.clipRect(d, d, w - d, h - d)
        glow.shader = android.graphics.RadialGradient(w / 2, h / 2, maxOf(w, h) * 0.55f,
            intArrayOf(0x558B5CFF, 0x008B5CFF), null, android.graphics.Shader.TileMode.CLAMP)
        canvas.drawRect(0f, 0f, w, h, glow)
        val step = 24 * d
        var x = step
        while (x < w) { canvas.drawLine(x, 0f, x, h, grid); x += step }
        var y = step
        while (y < h) { canvas.drawLine(0f, y, w, y, grid); y += step }
        canvas.restore()
    }
}
