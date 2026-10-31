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
import android.widget.TextView
import java.io.File
import kotlin.math.abs

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
}

class NativeDeskActivity : Activity(), SurfaceHolder.Callback {
    private lateinit var surfaceView: SurfaceView
    private lateinit var stats: TextView
    private val apps = mutableListOf<Process>()
    private val main = Handler(Looper.getMainLooper())
    private var started = false
    // The Qt demo's last output lines, shown in the overlay so its errors are visible.
    private val qtLines = ArrayDeque<String>()
    @Volatile private var qtStatus = "Qt demo: not in this build"

    private val tick = object : Runnable {
        override fun run() {
            if (started) stats.text = NativeDesk.nativeStats().ifEmpty { "Starting…" } +
                "\n$qtStatus\n" + synchronized(qtLines) { qtLines.joinToString("\n") } +
                "\n\nTouchpad: tap to click, two-finger tap to right-click, two fingers to scroll, tap then hold to drag " +
                "(title bars move windows). Settings → Touch mode switches to direct touch. + and - on a keyboard change the load."
            main.postDelayed(this, 500)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppLog.attach(this)
        surfaceView = SurfaceView(this).apply {
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
        }
        setContentView(FrameLayout(this).apply {
            addView(surfaceView, FrameLayout.LayoutParams(-1, -1))
            addView(stats, FrameLayout.LayoutParams(-2, -2))
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
        started = NativeDesk.nativeStart(holder.surface)
        AppLog.i(if (started) "Native desktop test started" else "Native desktop test couldn't start (see logcat: nativedesk)")
        if (!started) {
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

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        main.removeCallbacks(tick)
        stopApps()
        if (started) NativeDesk.nativeStop()
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
                p.inputStream.bufferedReader().forEachLine { AppLog.i("[nativedesk] $it") }
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
    private fun startQtApp() {
        val libs = applicationInfo.nativeLibraryDir
        val exe = File(libs, "libnativedesk_qt.so")
        if (!exe.exists()) return
        qtStatus = "Qt demo: starting"
        try {
            val p = ProcessBuilder(
                "/system/bin/app_process", "-Xnoimage-dex2oat", "/",
                QtHost::class.java.name, libs, exe.name, "-platform", "deskdroid"
            ).redirectErrorStream(true).also { pb ->
                pb.environment().apply {
                    remove("LD_PRELOAD")
                    put("CLASSPATH", applicationInfo.sourceDir)
                    put("LD_LIBRARY_PATH", libs)
                    put("QT_QPA_PLATFORM", "deskdroid")
                    put("QT_QPA_FONTDIR", "/system/fonts")
                    put("HOME", filesDir.path)
                    put("TMPDIR", cacheDir.path)
                    put("XDG_RUNTIME_DIR", cacheDir.path)
                }
            }.start()
            apps += p
            qtStatus = "Qt demo: running"
            Thread {
                p.inputStream.bufferedReader().forEachLine {
                    AppLog.i("[nativedesk-qt] $it")
                    synchronized(qtLines) {
                        qtLines.addLast(it.take(160))
                        while (qtLines.size > 14) qtLines.removeFirst()
                    }
                }
                val code = p.waitFor()
                qtStatus = "Qt demo: exited with code $code" + if (code > 128) " (signal ${code - 128})" else ""
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
            val runtime = File(cacheDir, "runtime").apply { mkdirs(); setReadable(true, true); setWritable(true, true); setExecutable(true, true) }
            val fonts = File(data, "fonts.conf").apply {
                writeText("<?xml version=\"1.0\"?>\n<fontconfig>\n  <dir>/system/fonts</dir>\n" +
                    "  <cachedir>${File(cacheDir, "fontconfig").path}</cachedir>\n</fontconfig>\n")
            }
            // Plasma's usual size on a phone: about twice the panel's pixels.
            val scale = (resources.displayMetrics.density / 1.75f * 4).toInt().coerceIn(4, 12) / 4.0
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
                    put("XDG_CONFIG_HOME", File(filesDir, "config").path)
                    put("XKB_CONFIG_ROOT", File(data, "share/X11/xkb").path)
                    put("FONTCONFIG_FILE", fonts.path)
                    put("QT_QPA_FONTDIR", "/system/fonts")
                    put("KWIN_COMPOSE", "Q") // QPainter: the backend draws on the CPU for now
                    put("KDE_DEBUG", "1") // no KCrash handler: our own prints where a crash happened
                    put("KWIN_FORCE_OWN_QPA", "1") // KWin only takes its own Qt platform plugin when the program is named kwin_wayland; ours is app_process
                }
            }.start()
            apps += p
            qtStatus = "KWin: running"
            Thread {
                p.inputStream.bufferedReader().forEachLine {
                    AppLog.i("[kwin] $it")
                    synchronized(qtLines) {
                        qtLines.addLast(it.take(160))
                        while (qtLines.size > 40) qtLines.removeFirst()
                    }
                }
                val code = p.waitFor()
                qtStatus = "KWin: exited with code $code" + if (code > 128) " (signal ${code - 128})" else ""
                AppLog.i("[kwin] exited ($code)")
            }.apply { isDaemon = true }.start()
        } catch (e: Exception) {
            qtStatus = "KWin: couldn't start: $e"
            AppLog.i("Native desktop test: couldn't start KWin: $e")
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

    private fun stopApps() {
        apps.forEach { it.destroy() }
        apps.clear()
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
        if (keyCode == KeyEvent.KEYCODE_BACK) return super.onKeyDown(keyCode, e)
        if (started) NativeDesk.nativeKey(keyCode, e.unicodeChar, true)
        return true
    }

    override fun onKeyUp(keyCode: Int, e: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK) return super.onKeyUp(keyCode, e)
        if (started) NativeDesk.nativeKey(keyCode, e.unicodeChar, false)
        return true
    }

    /**
     * The phone screen as a laptop touchpad, like the desktop's Touchpad mode:
     * one finger moves the pointer, a tap clicks, a two-finger tap right-clicks,
     * two fingers scroll, and tap then hold drags.
     */
    private class Touchpad {
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
                    // Tap, then touch again and hold: drag with the left button down.
                    dragging = e.eventTime - lastTapAt < DOUBLE_TAP_MS
                    if (dragging) NativeDesk.nativePointer(px, py, 1)
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
                        dragging -> NativeDesk.nativePointer(px, py, 0)
                        tap && maxFingers >= 2 -> click(2)
                        tap -> click(1)
                    }
                    lastTapAt = if (tap && maxFingers == 1 && !dragging) e.eventTime else 0L
                    dragging = false
                }
            }
            // Re-anchor after the finger count changes, so the pointer doesn't jump.
            lastX = if (e.actionMasked == MotionEvent.ACTION_POINTER_UP) avgWithout(e, e.actionIndex) { e.getX(it) } else cx
            lastY = if (e.actionMasked == MotionEvent.ACTION_POINTER_UP) avgWithout(e, e.actionIndex) { e.getY(it) } else cy
        }

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
        stopApps()
        super.onDestroy()
    }
}
