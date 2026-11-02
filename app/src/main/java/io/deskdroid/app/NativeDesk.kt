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
    @JvmStatic external fun nativeScroll(dx: Float, dy: Float)
    @JvmStatic external fun nativeStats(): String
    @JvmStatic external fun nativeResized()
    @JvmStatic external fun nativeDetach()
    @JvmStatic external fun nativeSetScale(scale: Float)

    /** Plasma's usual size on a phone (about twice the panel's pixels), or the menu's choice. */
    fun desktopScale(c: android.content.Context): Float =
        Prefs.nativeScale(c).takeIf { it > 0f }
            ?: ((c.resources.displayMetrics.density / 1.75f * 4).toInt().coerceIn(4, 12) / 4f)

    /** From the compositor: a text field in the desktop took (or lost) the keyboard focus. */
    @JvmStatic @androidx.annotation.Keep
    fun onIme(show: Boolean) {
        Handler(Looper.getMainLooper()).post {
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
            if (started) { tookSurface(); main.post(tick) }
            return
        }
        started = NativeDesk.nativeStart(holder.surface)
        if (started) tookSurface()
        NativeDesk.running = started
        if (started) startForegroundService(android.content.Intent(this, NativeDeskService::class.java))
        AppLog.i(if (started) "Native desktop test started" else "Native desktop test couldn't start (see logcat: nativedesk)")
        if (!started) {
            stats.visibility = android.view.View.VISIBLE
            stats.text = "The native compositor couldn't start on this GPU."
            return
        }
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
            val fonts = File(data, "fonts.conf").apply {
                writeText("<?xml version=\"1.0\"?>\n<fontconfig>\n  <dir>/system/fonts</dir>\n" +
                    "  <cachedir>${File(cacheDir, "fontconfig").path}</cachedir>\n</fontconfig>\n")
            }
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
            File(filesDir, ".local/share/applications/org.deskdroid.store.desktop").writeText(
                "[Desktop Entry]\nType=Application\nName=App Store\nGenericName=Install KDE apps\n" +
                "Icon=plasmadiscover\nExec=android-open deskdroid:store\nCategories=System;\n")
            NativeDesk.watchOpenRequests(applicationContext)
            Thread { writeAndroidApps() }.start() // before plasmashell reads the menu (KWin starts first)
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
    private var appsWatched = false

    /** The menu follows apps installed or removed, and Private Space locking or unlocking. */
    private fun watchAndroidApps() {
        if (appsWatched) return
        appsWatched = true
        val again = Runnable { Thread { writeAndroidApps() }.start() }
        val later: () -> Unit = { main.removeCallbacks(again); main.postDelayed(again, 1500) }
        getSystemService(android.content.pm.LauncherApps::class.java).registerCallback(object : android.content.pm.LauncherApps.Callback() {
            override fun onPackageRemoved(packageName: String?, user: android.os.UserHandle?) = later()
            override fun onPackageAdded(packageName: String?, user: android.os.UserHandle?) = later()
            override fun onPackageChanged(packageName: String?, user: android.os.UserHandle?) = later()
            override fun onPackagesAvailable(packageNames: Array<out String>?, user: android.os.UserHandle?, replacing: Boolean) = later()
            override fun onPackagesUnavailable(packageNames: Array<out String>?, user: android.os.UserHandle?, replacing: Boolean) = later()
        }, main)
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
            if (Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, filter, android.content.Context.RECEIVER_EXPORTED)
            else registerReceiver(receiver, filter)
        }
    }

    private fun writeAndroidApps() {
        val dir = File(filesDir, ".local/share/applications").apply { mkdirs() }
        val icons = File(filesDir, ".local/share/deskdroid-android-icons").apply { mkdirs() }
        val launcher = getSystemService(android.content.pm.LauncherApps::class.java)
        val users = getSystemService(android.os.UserManager::class.java)
        val me = android.os.Process.myUserHandle()
        val keep = mutableSetOf<String>()
        for (user in launcher.profiles) {
            val serial = users.getSerialNumberForUser(user)
            val private = user != me && Build.VERSION.SDK_INT >= 35 &&
                runCatching { launcher.getLauncherUserInfo(user)?.userType == android.os.UserManager.USER_TYPE_PROFILE_PRIVATE }.getOrDefault(false)
            val (category, suffix) = when {
                user == me -> "X-DeskDroid-Android" to ""
                private -> "X-DeskDroid-Android-Private" to "@$serial"
                else -> "X-DeskDroid-Android-Work" to "@$serial"
            }
            val apps = try { launcher.getActivityList(null, user) } catch (e: Exception) {
                AppLog.i("Native desktop: couldn't list profile $serial: $e"); emptyList()
            }.distinctBy { it.componentName.packageName }
            for (info in apps) {
                val pkg = info.componentName.packageName
                val id = pkg + suffix
                val name = "android-$id.desktop"
                keep += name
                try {
                    val icon = File(icons, "$id.png")
                    if (!icon.exists() || icon.lastModified() < info.firstInstallTime ||
                        icon.lastModified() < runCatching { packageManager.getPackageInfo(pkg, 0).lastUpdateTime }.getOrDefault(0L)) {
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
        dir.listFiles { f -> f.name.startsWith("android-") && f.name !in keep }?.forEach { it.delete() }
        AppLog.i("Native desktop: ${keep.size} Android apps in the menu")
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
    }

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

    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (!started) return false
        when {
            e.isFromSource(InputDevice.SOURCE_MOUSE) -> mouse(e)
            // The same Touch mode setting as the desktop (Settings → Touch mode).
            Prefs.touchMode(this) == "direct" -> {
                val up = e.actionMasked == MotionEvent.ACTION_UP || e.actionMasked == MotionEvent.ACTION_CANCEL
                NativeDesk.nativePointer(e.x, e.y, if (up) 0 else 1)
            }
            else -> touchpad.onTouch(e, surfaceView.width.toFloat(), surfaceView.height.toFloat())
        }
        return true
    }

    override fun onGenericMotionEvent(e: MotionEvent): Boolean {
        if (!started) return false
        if (e.actionMasked == MotionEvent.ACTION_SCROLL) {
            // One wheel notch scrolls about three lines.
            NativeDesk.nativeScroll(-e.getAxisValue(MotionEvent.AXIS_HSCROLL) * 60f,
                -e.getAxisValue(MotionEvent.AXIS_VSCROLL) * 60f)
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
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            if (e.repeatCount == 0) showMenu(menu.visibility != android.view.View.VISIBLE)
            return true
        }
        if (started) NativeDesk.nativeKey(keyCode, e.unicodeChar, true)
        return true
    }

    override fun onKeyUp(keyCode: Int, e: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK) return true // Back opens the menu (onKeyDown)
        if (started) NativeDesk.nativeKey(keyCode, e.unicodeChar, false)
        return true
    }

    // ---- DeskDroid's menu: Back opens and closes it ----

    private lateinit var menu: FrameLayout
    private lateinit var panel: LinearLayout

    private fun buildMenu(): android.view.View {
        val ui = io.deskdroid.app.ui.Ui(this)
        menu = FrameLayout(this).apply {
            setBackgroundColor(0x55000000)
            visibility = android.view.View.GONE
            setOnClickListener { showMenu(false) } // a tap outside the panel closes it
        }
        panel = ui.column(12) {
            setPadding(dp(16), dp(14), dp(16), dp(14))
            setBackgroundColor(io.deskdroid.app.ui.Party.PANEL)
            elevation = dp(16f)
            isClickable = true // touches don't fall through to the desktop
            addView(ui.row {
                addView(ui.text("DESKDROID", 15f).apply { typeface = io.deskdroid.app.ui.Party.orbitron(context); letterSpacing = 0.08f })
                spacer()
                addView(ui.outlineButton("✕", io.deskdroid.app.ui.Party.TEXT) { showMenu(false) }, LinearLayout.LayoutParams(dp(40), dp(40)))
            }, LinearLayout.LayoutParams(-1, -2))
            addView(io.deskdroid.app.ui.Segmented(ui, listOf("Touchpad", "Direct touch"),
                if (Prefs.touchMode(context) == "direct") 1 else 0) { i ->
                Prefs.setTouchMode(context, if (i == 1) "direct" else "touchpad")
            }.view, LinearLayout.LayoutParams(-1, -2))
            val scaleTile = ui.tile(scaleLabel(), io.deskdroid.app.ui.Party.YELLOW) {}
            scaleTile.setOnClickListener {
                val i = (SCALES.indexOf(Prefs.nativeScale(context)) + 1) % SCALES.size
                Prefs.setNativeScale(context, SCALES[i])
                scaleTile.text = scaleLabel()
                // Applied now: KWin lays the desktop out again at the new scale.
                if (started) NativeDesk.nativeSetScale(NativeDesk.desktopScale(context))
            }
            val grid = listOf(
                ui.tile("Keyboard", io.deskdroid.app.ui.Party.CYAN) { showMenu(false); toggleKeyboard() },
                scaleTile,
                ui.tile("App Store", io.deskdroid.app.ui.Party.GREEN) {
                    showMenu(false)
                    startActivity(android.content.Intent(this@NativeDeskActivity, StoreActivity::class.java))
                },
            )
            addView(ui.row(6) { grid.forEach { addView(ui.weight(it)) } }, LinearLayout.LayoutParams(-1, -2))
            spacer()
            addView(ui.text("STOP DESKTOP", 12f, 0xFFFF6B82.toInt()).apply {
                typeface = io.deskdroid.app.ui.Party.orbitron(context)
                letterSpacing = 0.12f
                gravity = android.view.Gravity.CENTER
                minHeight = dp(44)
                background = io.deskdroid.app.ui.ChamferDrawable(dp(12f), stroke = io.deskdroid.app.ui.Party.RED, strokeWidth = dp(1.5f))
                setOnClickListener { confirmStop() }
            }, LinearLayout.LayoutParams(-1, -2))
        }
        menu.addView(panel, FrameLayout.LayoutParams(dp(304), -1, android.view.Gravity.END))
        return menu
    }

    private fun scaleLabel() = Prefs.nativeScale(this).let { if (it == 0f) "Scale: auto" else "Scale ${"%.2f".format(it).trimEnd('0').trimEnd('.')}×" }

    private fun showMenu(open: Boolean) {
        val w = dp(304f)
        if (open) {
            menu.visibility = android.view.View.VISIBLE
            panel.translationX = w
            panel.animate().translationX(0f).setDuration(180).start()
        } else if (menu.visibility == android.view.View.VISIBLE) {
            panel.animate().translationX(w).setDuration(150).withEndAction { menu.visibility = android.view.View.GONE }.start()
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

        fun moveTo(x: Float, y: Float) { px = x; py = y }

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
                    // Tap, then touch again and hold: drag with the left button down. The
                    // tap's own click waits for this (pendingTap), so a drag is one press,
                    // not a click and then a press (a double click: title bars maximize).
                    dragging = e.eventTime - lastTapAt < DOUBLE_TAP_MS
                    if (dragging) {
                        handler.removeCallbacks(pendingTap)
                        NativeDesk.nativePointer(px, py, 1)
                    }
                }
                MotionEvent.ACTION_POINTER_DOWN, MotionEvent.ACTION_POINTER_UP -> maxFingers = maxOf(maxFingers, n)
                MotionEvent.ACTION_MOVE -> {
                    val dx = cx - lastX
                    val dy = cy - lastY
                    travel += abs(dx) + abs(dy)
                    if (n >= 2) {
                        NativeDesk.nativeScroll(-dx * SCROLL_SPEED, -dy * SCROLL_SPEED) // natural scrolling
                    } else {
                        px = (px + dx * SPEED).coerceIn(0f, w - 1)
                        py = (py + dy * SPEED).coerceIn(0f, h - 1)
                        NativeDesk.nativePointer(px, py, if (dragging) 1 else 0)
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    val tap = travel < TAP_SLOP && e.eventTime - downAt < TAP_MS
                    when {
                        // Tap, tap: the second touch's press, its release, then one more
                        // click, so apps see a double click. Tap, hold (or move): a drag.
                        dragging && tap -> { NativeDesk.nativePointer(px, py, 0); click(1) }
                        dragging -> NativeDesk.nativePointer(px, py, 0)
                        tap && maxFingers >= 2 -> click(2)
                        tap -> handler.postDelayed(pendingTap, DOUBLE_TAP_MS)
                    }
                    lastTapAt = if (tap && maxFingers == 1 && !dragging) e.eventTime else 0L
                    dragging = false
                }
            }
            // Re-anchor after the finger count changes, so the pointer doesn't jump.
            lastX = if (e.actionMasked == MotionEvent.ACTION_POINTER_UP) avgWithout(e, e.actionIndex) { e.getX(it) } else cx
            lastY = if (e.actionMasked == MotionEvent.ACTION_POINTER_UP) avgWithout(e, e.actionIndex) { e.getY(it) } else cy
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
        }
    }

    override fun onDestroy() {
        main.removeCallbacks(tick)
        // Stop (in the menu or the notification) ends the desktop; anything else
        // that destroys the window leaves it running in the background.
        // A monitor unplugged closes its window; the desktop goes on, back on the phone.
        if (isFinishing && !external) NativeDesk.stop(this, "window closed")
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
        val hint = TextView(this).apply {
            text = "Touchpad · the desktop is on your monitor\nOne finger moves, tap clicks, two fingers scroll or right-click"
            setTextColor(0x99FFFFFF.toInt())
            textSize = 14f
            gravity = android.view.Gravity.CENTER
            setPadding(48, 48, 48, 48)
        }
        val keyboard = TextView(this).apply {
            text = "⌨  Keyboard"
            setTextColor(Color.WHITE)
            textSize = 16f
            setPadding(48, 32, 48, 32)
            setOnClickListener { softKeyboard(true) }
        }
        setContentView(FrameLayout(this).apply {
            setBackgroundColor(0xFF101018.toInt())
            addView(pad, FrameLayout.LayoutParams(-1, -1))
            addView(hint, FrameLayout.LayoutParams(-1, -2, android.view.Gravity.CENTER))
            addView(keyboard, FrameLayout.LayoutParams(-2, -2, android.view.Gravity.TOP or android.view.Gravity.END))
        })
        displays.registerDisplayListener(listener, Handler(Looper.getMainLooper()))
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (NativeDesk.surfaceW <= 0f) return false
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
