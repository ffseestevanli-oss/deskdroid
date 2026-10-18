package io.deskdroid.app.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import io.deskdroid.app.R

/** Square on/off switch in the party look: pink when on. */
class PartySwitch(c: Context) : View(c) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    var checked = false
        set(v) { field = v; invalidate() }
    var onChange: ((Boolean) -> Unit)? = null

    init {
        isClickable = true
        isFocusable = true
        setOnClickListener { checked = !checked; onChange?.invoke(checked) }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) =
        setMeasuredDimension(context.dp(48), context.dp(26))

    override fun onDraw(canvas: Canvas) {
        val w = width.toFloat(); val h = height.toFloat(); val s = context.dp(1.5f)
        paint.style = Paint.Style.FILL
        paint.color = if (checked) 0xFF3A1236.toInt() else Party.SURFACE
        canvas.drawRect(0f, 0f, w, h, paint)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = s
        paint.color = if (checked) Party.PINK else Party.BORDER
        canvas.drawRect(s / 2, s / 2, w - s / 2, h - s / 2, paint)
        paint.style = Paint.Style.FILL
        paint.color = if (checked) Party.PINK else Party.MUTED
        val knob = h - context.dp(8f)
        val x = if (checked) w - knob - context.dp(4f) else context.dp(4f)
        canvas.drawRect(x, context.dp(4f), x + knob, context.dp(4f) + knob, paint)
    }
}

/** The DeskDroid logo with its rainbow ring and a soft purple glow. */
fun Ui.logo(sizeDp: Int): View = FrameLayout(c).apply {
    val img = ImageView(c).apply { setImageResource(R.drawable.ic_logo) }
    addView(img, FrameLayout.LayoutParams(c.dp(sizeDp), c.dp(sizeDp), Gravity.CENTER))
    elevation = c.dp(12f)
    outlineAmbientShadowColor = Party.PURPLE
    outlineSpotShadowColor = Party.PURPLE
    clipToOutline = false
}

/** Title text filled with the rainbow, like "DeskDroid!" on the Welcome screen. */
fun Ui.rainbowTitle(s: String, size: Float): TextView = heading(s, size).apply {
    addOnLayoutChangeListener { v, l, _, r, _, _, _, _, _ ->
        (v as TextView).paint.shader =
            LinearGradient(0f, 0f, (r - l).toFloat(), 0f, Party.RAINBOW, null, Shader.TileMode.CLAMP)
        v.invalidate()
    }
}

/** Title + subtitle on the left, a switch on the right. */
fun Ui.switchRow(
    kickerText: String?, title: String, subtitle: String, checked: Boolean, onChange: (Boolean) -> Unit,
): View = row(12) {
    setPadding(c.dp(14), c.dp(12), c.dp(14), c.dp(12))
    background = ChamferDrawable(c.dp(12f), fill = Party.CARD, stroke = Party.BORDER, strokeWidth = c.dp(1f), cutTopLeft = false)
    addView(weight(column(2) {
        if (kickerText != null) addView(text(kickerText, 11f, Party.CYAN, 700).apply { letterSpacing = 0.18f })
        addView(text(title, 15f, Party.TEXT, 700))
        addView(text(subtitle, 13f, Party.MUTED))
    }))
    addView(PartySwitch(c).apply { this.checked = checked; this.onChange = onChange })
}

/** A tile button with an accent bar at the bottom (the drawer's control grid). */
fun Ui.tile(label: String, accent: Int, onClick: () -> Unit): TextView = text(label, 13f, Party.TEXT, 700).apply {
    gravity = Gravity.CENTER
    minHeight = c.dp(62)
    background = ChamferDrawable(
        0f, fill = Party.SURFACE, stroke = Party.BORDER_SOFT, strokeWidth = c.dp(1f),
        cutTopLeft = false, cutBottomRight = false, accent = accent, accentEdge = Gravity.BOTTOM, accentWidth = c.dp(2f)
    )
    isClickable = true
    setOnClickListener { onClick() }
}

/** Two-option toggle (Touchpad / Direct touch, This phone / Monitor). */
class Segmented(private val ui: Ui, private val labels: List<String>, selected: Int, private val onPick: (Int) -> Unit) {
    private val buttons = labels.map { ui.text(it, 14f, Party.MUTED, 600) }
    val view: LinearLayout = ui.row(6) {
        buttons.forEachIndexed { i, b ->
            b.gravity = Gravity.CENTER
            b.minHeight = ui.c.dp(40)
            b.isClickable = true
            b.setOnClickListener { select(i); onPick(i) }
            addView(ui.weight(b))
        }
    }
    init { select(selected) }

    fun select(index: Int) = buttons.forEachIndexed { i, b ->
        val on = i == index
        b.setTextColor(if (on) 0xFFFFFFFF.toInt() else Party.MUTED)
        b.typeface = Party.chakra(ui.c, if (on) 700 else 600)
        b.background = ChamferDrawable(
            0f, fill = if (on) 0xFF24102A.toInt() else null, stroke = if (on) Party.PINK else Party.BORDER,
            strokeWidth = ui.c.dp(1.5f), cutTopLeft = false, cutBottomRight = false
        )
    }
}

fun LinearLayout.spacer(weight: Float = 1f) = addView(View(context), LinearLayout.LayoutParams(0, 0, weight).apply {
    if (orientation == LinearLayout.VERTICAL) { width = 1; height = 0 }
})
