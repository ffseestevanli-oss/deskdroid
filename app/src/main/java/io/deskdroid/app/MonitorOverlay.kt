package io.deskdroid.app

import android.accessibilityservice.AccessibilityService
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.os.Build
import android.view.Gravity
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowManager

/**
 * The desktop drawn on the monitor above Android's own taskbar and status bar.
 *
 * Android shows its taskbar on the monitor whenever the phone's screen has
 * the focus (a phone app, or DeskDroid's touchpad screen): the monitor then
 * has no focused window to keep the bars hidden, and the taskbar lands on top
 * of KDE. The desktop helper (PowerMenuService) may put windows above the
 * system bars (accessibility overlays), so while the desktop is on a monitor
 * the compositor draws into one of those, full screen. It takes no input:
 * touches, the mouse and keys still go to the desktop's window underneath
 * (ExternalDeskActivity), as before. When the overlay goes (helper off,
 * monitor unplugged, an Android dialog on the monitor), the desktop draws
 * into that window again.
 */
object MonitorOverlay {
    /** The compositor draws into the overlay (not the desktop's window). */
    @Volatile var active = false
        private set
    private var view: SurfaceView? = null
    private var wm: WindowManager? = null
    private var display = -1
    private var paused = false

    /** Puts the overlay on [displayId], from the desktop helper (main thread). */
    fun show(s: AccessibilityService, displayId: Int) {
        if (Build.VERSION.SDK_INT < 30 || !Prefs.monitorGuard(s)) return
        if (view != null && display == displayId) return
        hide()
        val d = s.getSystemService(DisplayManager::class.java).getDisplay(displayId) ?: return
        val ctx = runCatching { s.createDisplayContext(d).createWindowContext(WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY, null) }
            .getOrElse { AppLog.i("Monitor: no overlay context: $it"); return }
        val m = ctx.getSystemService(WindowManager::class.java)
        val v = SurfaceView(ctx)
        v.holder.addCallback(callback)
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
            PixelFormat.OPAQUE).apply {
            gravity = Gravity.TOP or Gravity.START
            layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            setFitInsetsTypes(0)
            title = "DeskDroid desktop"
        }
        runCatching { m.addView(v, lp) }.onFailure { AppLog.i("Monitor: couldn't put the desktop above Android's taskbar: $it"); return }
        view = v; wm = m; display = displayId; paused = false
        AppLog.i("Monitor: the desktop draws above Android's taskbar (display $displayId)")
    }

    /**
     * An Android window the user has to see (a permission dialog) is on top
     * of the monitor: the overlay steps aside until it's gone.
     */
    fun pause(p: Boolean) {
        val v = view ?: return
        if (p == paused) return
        paused = p
        v.visibility = if (p) View.GONE else View.VISIBLE
        AppLog.i(if (p) "Monitor: an Android dialog is on the monitor, the desktop steps aside" else "Monitor: the desktop is above Android's taskbar again")
    }

    /** Takes the overlay away; the desktop's window gets the picture back (main thread). */
    fun hide() {
        val v = view ?: return
        view = null
        runCatching { wm?.removeViewImmediate(v) }
        wm = null
        display = -1
    }

    /** A phone window took the picture back (the monitor went): the overlay is done. */
    fun replaced() {
        active = false
        hide()
    }

    /** Desktop stopping: the compositor lets go of the overlay first, with nothing to go back to. */
    fun stopping() {
        if (active) { active = false; NativeDesk.nativeDetach() }
        hide()
    }

    private val callback = object : SurfaceHolder.Callback {
        override fun surfaceCreated(h: SurfaceHolder) {
            if (!NativeDesk.running) return
            if (!NativeDesk.nativeStart(h.surface)) { AppLog.i("Monitor: the compositor couldn't draw into the overlay"); return }
            active = true
            h.surfaceFrame.let { NativeDesk.surfaceW = it.width().toFloat(); NativeDesk.surfaceH = it.height().toFloat() }
        }

        override fun surfaceChanged(h: SurfaceHolder, format: Int, w: Int, hgt: Int) {
            if (!active) return
            NativeDesk.surfaceW = w.toFloat(); NativeDesk.surfaceH = hgt.toFloat()
            NativeDesk.nativeResized()
        }

        override fun surfaceDestroyed(h: SurfaceHolder) {
            if (!active) return
            active = false
            // Let go of this surface before Android takes it back, then draw
            // into the desktop's own window again if it's still there.
            NativeDesk.nativeDetach()
            (NativeDesk.owner?.get() as? NativeDeskActivity)?.reattachSurface()
        }
    }
}
