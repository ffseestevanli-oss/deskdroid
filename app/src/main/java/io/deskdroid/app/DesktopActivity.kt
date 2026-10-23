package io.deskdroid.app

import android.app.ActivityOptions
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.view.Display
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import io.deskdroid.app.ui.ChamferDrawable
import io.deskdroid.app.ui.Party
import io.deskdroid.app.ui.RainbowStrip
import io.deskdroid.app.ui.Segmented
import io.deskdroid.app.ui.Ui
import io.deskdroid.app.ui.dp
import io.deskdroid.app.ui.spacer
import io.deskdroid.app.ui.tile

/**
 * The desktop window: Termux:X11's activity (X server view, touch/mouse/keyboard
 * input, extra keys bar, clipboard) with DeskDroid's overlay drawer on top.
 * The drawer opens from a handle on the right edge.
 */
class DesktopActivity : com.termux.x11.MainActivity() {
    private lateinit var drawer: View
    private lateinit var handle: View
    private lateinit var segmented: Segmented

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppLog.attach(this)
        if (isFinishing) return
        hideTermuxChrome()
        addContentView(buildOverlay(), ViewGroup.LayoutParams(-1, -1))
    }

    override fun onResume() {
        super.onResume()
        if (!SessionService.running) {
            // Reopened from recents after the desktop stopped: lorie would only
            // show "Not connected". Go back to the launcher instead.
            startActivity(Intent(this, MainActivity::class.java))
            finish()
            return
        }
        if (LockGate.needsUnlock(this)) {
            // Opened from the notification while locked: unlock in the launcher first.
            startActivity(Intent(this, MainActivity::class.java))
            finish()
        }
    }

    override fun onUserInteraction() {
        super.onUserInteraction()
        LockGate.touch()
    }

    /** lorie's "not connected" page has Termux:X11 help and settings buttons; DeskDroid has its own. */
    private fun hideTermuxChrome() {
        for (name in listOf("help_button", "preferences_button")) {
            val id = resources.getIdentifier(name, "id", packageName)
            if (id != 0) findViewById<View>(id)?.visibility = View.GONE
        }
    }

    private fun buildOverlay(): View {
        val ui = Ui(this)
        val root = FrameLayout(this)

        handle = FrameLayout(this).apply {
            addView(RainbowStrip(context, vertical = true), FrameLayout.LayoutParams(dp(4), -1, Gravity.END))
            background = ChamferDrawable(dp(8f), fill = 0x99101018.toInt(), cutBottomRight = false)
            contentDescription = "Open controls"
            setOnClickListener { openDrawer(true) }
            setOnTouchListener(EdgeSwipe { openDrawer(true) })
        }
        root.addView(handle, FrameLayout.LayoutParams(dp(22), dp(72), Gravity.END or Gravity.CENTER_VERTICAL))

        // Tapping outside the open drawer closes it.
        val scrim = View(this).apply {
            setBackgroundColor(0x55000000)
            visibility = View.GONE
            setOnClickListener { openDrawer(false) }
        }
        root.addView(scrim, FrameLayout.LayoutParams(-1, -1))

        drawer = ui.column(12) {
            setPadding(dp(16), dp(14), dp(16), dp(14))
            setBackgroundColor(Party.PANEL)
            elevation = dp(16f)
            outlineSpotShadowColor = Party.PURPLE
            isClickable = true // don't let touches fall through to the desktop

            addView(ui.row {
                addView(ui.column(2) {
                    addView(ui.text("CONTROLS", 15f).apply { typeface = Party.orbitron(context); letterSpacing = 0.08f })
                    addView(ui.text("● Desktop live", 12f, Party.GREEN, 600))
                })
                spacer()
                addView(ui.outlineButton("✕", Party.TEXT) { openDrawer(false) }, LinearLayout.LayoutParams(dp(40), dp(40)))
            }, LinearLayout.LayoutParams(-1, -2))

            segmented = Segmented(ui, listOf("Touchpad", "Direct touch"), if (Prefs.touchMode(context) == "direct") 1 else 0) { i ->
                Prefs.setTouchMode(context, if (i == 1) "direct" else "touchpad")
                DesktopDefaults.applyTouchMode(context)
            }
            addView(segmented.view, LinearLayout.LayoutParams(-1, -2))

            val zoomTile = ui.tile(zoomLabel(), Party.YELLOW) {}
            zoomTile.setOnClickListener { cycleZoom(); zoomTile.text = zoomLabel() }
            val grid = listOf(
                ui.tile("Keyboard", Party.CYAN) { openDrawer(false); toggleKeyboardVisibility() },
                ui.tile("Extra keys", Party.GREEN) { openDrawer(false); toggleExtraKeys() },
                zoomTile,
                ui.tile(if (onExternalDisplay()) "To phone" else "To monitor", Party.PURPLE) { moveDisplay() },
            )
            for (pair in grid.chunked(2)) {
                addView(ui.row(6) { pair.forEach { addView(ui.weight(it)) } }, LinearLayout.LayoutParams(-1, -2))
            }
            spacer()
            addView(ui.text("STOP DESKTOP", 12f, 0xFFFF6B82.toInt()).apply {
                typeface = Party.orbitron(context)
                letterSpacing = 0.12f
                gravity = Gravity.CENTER
                minHeight = dp(44)
                background = ChamferDrawable(dp(12f), stroke = Party.RED, strokeWidth = dp(1.5f))
                setOnClickListener { stopDesktop() }
            }, LinearLayout.LayoutParams(-1, -2))
        }
        root.addView(drawer, FrameLayout.LayoutParams(dp(304), -1, Gravity.END))
        drawer.addOnLayoutChangeListener { v, _, _, _, _, _, _, _, _ -> if (v.visibility != View.VISIBLE) v.translationX = v.width.toFloat() }
        (drawer as LinearLayout).let { col ->
            // Rainbow edge on the drawer's left side, drawn over its background.
            col.overlay.add(object : android.graphics.drawable.Drawable() {
                private val p = android.graphics.Paint()
                override fun draw(canvas: android.graphics.Canvas) {
                    p.shader = Party.rainbowShader(0f, col.height.toFloat(), vertical = true)
                    canvas.drawRect(0f, 0f, dp(3f), col.height.toFloat(), p)
                }
                override fun setAlpha(alpha: Int) = Unit
                override fun setColorFilter(colorFilter: android.graphics.ColorFilter?) = Unit
                @Deprecated("Deprecated in Java")
                override fun getOpacity() = android.graphics.PixelFormat.TRANSLUCENT
            }.also { d -> col.addOnLayoutChangeListener { _, _, _, r, b, _, _, _, _ -> d.setBounds(0, 0, r, b) } })
        }
        drawer.visibility = View.GONE
        scrimView = scrim
        return root
    }

    private var scrimView: View? = null

    private fun openDrawer(open: Boolean) {
        val w = drawer.width.takeIf { it > 0 }?.toFloat() ?: dp(304f)
        if (open) {
            drawer.visibility = View.VISIBLE
            scrimView?.visibility = View.VISIBLE
            handle.visibility = View.GONE
            drawer.translationX = w
            drawer.animate().translationX(0f).setDuration(180).start()
            segmented.select(if (Prefs.touchMode(this) == "direct") 1 else 0)
        } else {
            drawer.animate().translationX(w).setDuration(150).withEndAction {
                drawer.visibility = View.GONE
                scrimView?.visibility = View.GONE
                handle.visibility = View.VISIBLE
            }.start()
        }
    }

    private fun lorie() = getSharedPreferences("${packageName}_preferences", Context.MODE_PRIVATE)

    private fun zoomLevel(): Int =
        if (lorie().getString("displayResolutionMode", "native") == "scaled") lorie().getInt("displayScale", 100) else 100

    private fun zoomLabel() = "Zoom ${ZOOMS_LABEL[ZOOMS.indexOf(zoomLevel()).coerceAtLeast(0)]}"

    /** Extra zoom on top of Plasma's own scale: the X screen renders smaller and is stretched. */
    private fun cycleZoom() {
        val next = ZOOMS[(ZOOMS.indexOf(zoomLevel()) + 1) % ZOOMS.size]
        lorie().edit()
            .putString("displayResolutionMode", if (next == 100) "native" else "scaled")
            .putInt("displayScale", next)
            .apply()
    }

    @Suppress("DEPRECATION")
    private fun onExternalDisplay() = windowManager.defaultDisplay.displayId != Display.DEFAULT_DISPLAY

    /** Moves the desktop window between the phone and a connected monitor. The X session keeps running. */
    private fun moveDisplay() {
        val target = if (onExternalDisplay()) Display.DEFAULT_DISPLAY
        else getSystemService(DisplayManager::class.java).displays
            .firstOrNull { it.displayId != Display.DEFAULT_DISPLAY }?.displayId
        if (target == null) {
            android.widget.Toast.makeText(this, "No monitor connected", android.widget.Toast.LENGTH_SHORT).show()
            return
        }
        val opts = ActivityOptions.makeBasic().setLaunchDisplayId(target)
        finish()
        startActivity(Intent(this, DesktopActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), opts.toBundle())
    }

    private fun stopDesktop() {
        android.app.AlertDialog.Builder(this)
            .setTitle("Stop the desktop?")
            .setMessage("Unsaved work in Linux apps will be lost.")
            .setPositiveButton("Stop") { _, _ ->
                SessionService.stop(this)
                finish()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    /** Swipe in from the handle opens the drawer. */
    private class EdgeSwipe(private val open: () -> Unit) : View.OnTouchListener {
        private var startX = 0f
        override fun onTouch(v: View, e: MotionEvent): Boolean {
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> startX = e.rawX
                MotionEvent.ACTION_MOVE -> if (startX - e.rawX > v.context.dp(24f)) { open(); return true }
                MotionEvent.ACTION_UP -> if (startX - e.rawX < v.context.dp(8f)) v.performClick()
            }
            return true
        }
    }

    companion object {
        private val ZOOMS = listOf(100, 125, 150, 200)
        private val ZOOMS_LABEL = listOf("1×", "1.25×", "1.5×", "2×")
    }
}
