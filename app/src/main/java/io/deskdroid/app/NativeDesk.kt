package io.deskdroid.app

import android.app.Activity
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
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
    @JvmStatic external fun nativeStats(): String
}

class NativeDeskActivity : Activity(), SurfaceHolder.Callback {
    private lateinit var surfaceView: SurfaceView
    private lateinit var stats: TextView
    private val apps = mutableListOf<Process>()
    private val main = Handler(Looper.getMainLooper())
    private var started = false

    private val tick = object : Runnable {
        override fun run() {
            if (started) stats.text = NativeDesk.nativeStats().ifEmpty { "Starting…" } +
                "\nDrag title bars to move windows. + and - on a keyboard change the load."
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
        startApp("Light app", "640x420", 16)
        startApp("Heavy app", "900x600", 1024)
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

    private fun stopApps() {
        apps.forEach { it.destroy() }
        apps.clear()
    }

    override fun onTouchEvent(e: MotionEvent) = pointer(e)
    override fun onGenericMotionEvent(e: MotionEvent) = pointer(e)

    private fun pointer(e: MotionEvent): Boolean {
        if (!started) return false
        // Touch acts as the left button; a mouse reports its own buttons.
        val buttons = when {
            e.isFromSource(android.view.InputDevice.SOURCE_MOUSE) -> e.buttonState
            e.actionMasked == MotionEvent.ACTION_UP || e.actionMasked == MotionEvent.ACTION_CANCEL -> 0
            else -> 1
        }
        NativeDesk.nativePointer(e.x, e.y, buttons)
        return true
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

    override fun onDestroy() {
        main.removeCallbacks(tick)
        stopApps()
        super.onDestroy()
    }
}
