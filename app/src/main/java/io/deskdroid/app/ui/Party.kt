package io.deskdroid.app.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RadialGradient
import android.graphics.Rect
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/**
 * The approved "party" look (ui/README.md): near-black, rainbow accents on
 * strips, borders and main buttons, chamfered corners, Orbitron headings and
 * Chakra Petch body text. Plain views, no AndroidX.
 */
object Party {
    const val BG = 0xFF07070D.toInt()
    const val SURFACE = 0xFF12121E.toInt()
    const val SURFACE_DIM = 0xFF0D0D16.toInt()
    const val CARD = 0xFF10101B.toInt()
    const val CARD_ON = 0xFF1A0F22.toInt()
    const val PANEL = 0xFF0C0C16.toInt()
    const val BORDER = 0xFF2A2A3D.toInt()
    const val BORDER_SOFT = 0xFF262638.toInt()
    const val TEXT = 0xFFF2F2F7.toInt()
    const val TEXT_SOFT = 0xFFC9C9DC.toInt()
    const val MUTED = 0xFFA6A6C0.toInt()
    const val DIM = 0xFF8A8AA6.toInt()
    const val EMPTY = 0xFF1E1E2E.toInt()

    const val RED = 0xFFFF3B5C.toInt()
    const val ORANGE = 0xFFFF9F1C.toInt()
    const val YELLOW = 0xFFFFE14D.toInt()
    const val GREEN = 0xFF3DFF8B.toInt()
    const val CYAN = 0xFF2EC5FF.toInt()
    const val PURPLE = 0xFF8B5CFF.toInt()
    const val PINK = 0xFFFF4FD8.toInt()
    val RAINBOW = intArrayOf(RED, ORANGE, YELLOW, GREEN, CYAN, PURPLE, PINK)

    private var orbitron: Typeface? = null
    private val orbitronWeights = HashMap<Int, Typeface>()
    private val chakra = HashMap<Int, Typeface>()

    /** Orbitron is a variable font; weight 900 is the mockups' heading weight. */
    fun orbitron(c: Context, weight: Int = 900): Typeface = orbitronWeights.getOrPut(weight) {
        try {
            Typeface.Builder(c.assets, "fonts/Orbitron.ttf")
                .setFontVariationSettings("'wght' $weight")
                .build()
        } catch (e: Exception) {
            Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        }
    }

    fun chakra(c: Context, weight: Int = 400): Typeface = chakra.getOrPut(weight) {
        val file = when {
            weight >= 700 -> "ChakraPetch-Bold.ttf"
            weight >= 600 -> "ChakraPetch-SemiBold.ttf"
            else -> "ChakraPetch-Regular.ttf"
        }
        try {
            Typeface.createFromAsset(c.assets, "fonts/$file")
        } catch (e: Exception) {
            Typeface.DEFAULT
        }
    }

    fun rainbowShader(w: Float, h: Float, vertical: Boolean = false, colors: IntArray = RAINBOW): Shader =
        if (vertical) LinearGradient(0f, 0f, 0f, h, colors, null, Shader.TileMode.CLAMP)
        else LinearGradient(0f, 0f, w, 0f, colors, null, Shader.TileMode.CLAMP)
}

fun Context.dp(v: Float): Float = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, resources.displayMetrics)
fun Context.dp(v: Int): Int = dp(v.toFloat()).toInt()

/**
 * A rectangle with the top-left and/or bottom-right corner cut off (the
 * mockups' clip-path polygons). Fill and stroke can each be a color or the rainbow.
 */
class ChamferDrawable(
    private val cut: Float,
    private val fill: Int? = null,
    private val rainbowFill: Boolean = false,
    private val stroke: Int? = null,
    private val rainbowStroke: Boolean = false,
    private val strokeWidth: Float = 0f,
    private val cutTopLeft: Boolean = true,
    private val cutBottomRight: Boolean = true,
    /** Colored bar on one edge, like the mockups' border-left / border-bottom accents. */
    private val accent: Int? = null,
    private val accentEdge: Int = Gravity.START,
    private val accentWidth: Float = 0f,
) : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val path = Path()

    override fun onBoundsChange(bounds: Rect) {
        val l = bounds.left.toFloat(); val t = bounds.top.toFloat()
        val r = bounds.right.toFloat(); val b = bounds.bottom.toFloat()
        val inset = strokeWidth / 2
        path.reset()
        if (cutTopLeft) { path.moveTo(l + inset, t + cut); path.lineTo(l + cut, t + inset) }
        else path.moveTo(l + inset, t + inset)
        path.lineTo(r - inset, t + inset)
        if (cutBottomRight) { path.lineTo(r - inset, b - cut); path.lineTo(r - cut, b - inset) }
        else path.lineTo(r - inset, b - inset)
        path.lineTo(l + inset, b - inset)
        path.close()
    }

    override fun draw(canvas: Canvas) {
        val w = bounds.width().toFloat(); val h = bounds.height().toFloat()
        if (fill != null || rainbowFill) {
            paint.style = Paint.Style.FILL
            paint.shader = if (rainbowFill) Party.rainbowShader(w, h) else null
            paint.color = fill ?: 0xFFFFFFFF.toInt()
            canvas.drawPath(path, paint)
        }
        if (accent != null && accentWidth > 0) {
            canvas.save()
            canvas.clipPath(path)
            paint.shader = null
            paint.style = Paint.Style.FILL
            paint.color = accent
            val r = bounds
            when (accentEdge) {
                Gravity.BOTTOM -> canvas.drawRect(r.left.toFloat(), r.bottom - accentWidth, r.right.toFloat(), r.bottom.toFloat(), paint)
                Gravity.TOP -> canvas.drawRect(r.left.toFloat(), r.top.toFloat(), r.right.toFloat(), r.top + accentWidth, paint)
                else -> canvas.drawRect(r.left.toFloat(), r.top.toFloat(), r.left + accentWidth, r.bottom.toFloat(), paint)
            }
            canvas.restore()
        }
        if ((stroke != null || rainbowStroke) && strokeWidth > 0) {
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = strokeWidth
            paint.shader = if (rainbowStroke) Party.rainbowShader(w, h) else null
            paint.color = stroke ?: 0xFFFFFFFF.toInt()
            canvas.drawPath(path, paint)
        }
    }

    override fun setAlpha(alpha: Int) { paint.alpha = alpha }
    override fun setColorFilter(colorFilter: ColorFilter?) { paint.colorFilter = colorFilter }
    @Deprecated("Deprecated in Java")
    override fun getOpacity() = PixelFormat.TRANSLUCENT
}

/** The 4dp rainbow line at the top of every screen. */
class RainbowStrip(c: Context, private val vertical: Boolean = false) : View(c) {
    private val paint = Paint()
    override fun onDraw(canvas: Canvas) {
        paint.shader = Party.rainbowShader(width.toFloat(), height.toFloat(), vertical)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
    }
}

/** Soft colored glows behind the content (the mockups' blurred circles). */
class GlowBackground(c: Context, private val glows: List<Triple<Float, Float, Int>>) : View(c) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    init { setBackgroundColor(Party.BG) }
    override fun onDraw(canvas: Canvas) {
        val radius = width * 0.55f
        for ((fx, fy, color) in glows) {
            val cx = width * fx; val cy = height * fy
            val faint = (color and 0x00FFFFFF) or (0x40 shl 24)
            paint.shader = RadialGradient(cx, cy, radius, intArrayOf(faint, color and 0x00FFFFFF), null, Shader.TileMode.CLAMP)
            canvas.drawCircle(cx, cy, radius, paint)
        }
    }
}

/** 20-segment rainbow progress bar from the Installing mockup. */
class SegmentedProgress(c: Context) : View(c) {
    private val paint = Paint()
    private val segments = 20
    var fraction = 0f
        set(v) { field = v; invalidate() }
    var indeterminate = false
        set(v) { field = v; invalidate(); if (v) postInvalidateOnAnimation() }

    override fun onDraw(canvas: Canvas) {
        val pad = context.dp(4f); val gap = context.dp(3f)
        paint.color = Party.SURFACE
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
        paint.color = Party.BORDER
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = context.dp(1f)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)
        paint.style = Paint.Style.FILL
        val segW = (width - 2 * pad - gap * (segments - 1)) / segments
        val lit = (fraction.coerceIn(0f, 1f) * segments).toInt()
        val pulse = if (indeterminate) ((System.currentTimeMillis() / 90) % segments).toInt() else -1
        for (i in 0 until segments) {
            val on = if (indeterminate) (i - pulse + segments) % segments < 4 else i < lit
            paint.color = if (on) rainbowAt(i / (segments - 1f)) else Party.EMPTY
            val x = pad + i * (segW + gap)
            canvas.drawRect(x, pad, x + segW, height - pad, paint)
        }
        if (indeterminate) postInvalidateDelayed(90)
    }

    private fun rainbowAt(t: Float): Int {
        val colors = Party.RAINBOW
        val pos = t * (colors.size - 1)
        val i = pos.toInt().coerceAtMost(colors.size - 2)
        return blend(colors[i], colors[i + 1], pos - i)
    }

    private fun blend(a: Int, b: Int, t: Float): Int {
        fun ch(shift: Int) = (((a shr shift) and 0xFF) * (1 - t) + ((b shr shift) and 0xFF) * t).toInt()
        return (0xFF shl 24) or (ch(16) shl 16) or (ch(8) shl 8) or ch(0)
    }
}

/** Small builders used by every screen. */
class Ui(val c: Context) {
    fun column(gap: Int = 0, padding: Int = 0, block: LinearLayout.() -> Unit = {}) = LinearLayout(c).apply {
        orientation = LinearLayout.VERTICAL
        if (padding > 0) setPadding(c.dp(padding), c.dp(padding), c.dp(padding), c.dp(padding))
        if (gap > 0) {
            showDividers = LinearLayout.SHOW_DIVIDER_MIDDLE
            dividerDrawable = Spacer(c.dp(gap))
        }
        block()
    }

    fun row(gap: Int = 0, block: LinearLayout.() -> Unit = {}) = LinearLayout(c).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        if (gap > 0) {
            showDividers = LinearLayout.SHOW_DIVIDER_MIDDLE
            dividerDrawable = Spacer(c.dp(gap))
        }
        block()
    }

    fun text(s: CharSequence, size: Float = 14f, color: Int = Party.TEXT, weight: Int = 400) = TextView(c).apply {
        text = s
        textSize = size
        setTextColor(color)
        typeface = Party.chakra(c, weight)
        setLineSpacing(0f, 1.2f)
    }

    fun heading(s: String, size: Float = 26f) = TextView(c).apply {
        text = s.uppercase()
        textSize = size
        setTextColor(Party.TEXT)
        typeface = Party.orbitron(c)
        setLineSpacing(0f, 1.1f)
    }

    /** "STEP 1 / 3" style kicker. */
    fun kicker(s: String, color: Int = Party.PINK) = text(s.uppercase(), 13f, color, 700).apply {
        letterSpacing = 0.25f
    }

    fun primaryButton(label: String, onClick: () -> Unit) = TextView(c).apply {
        text = label.uppercase()
        textSize = 16f
        letterSpacing = 0.1f
        gravity = Gravity.CENTER
        setTextColor(Party.BG)
        typeface = Party.orbitron(c)
        background = ChamferDrawable(c.dp(16f), rainbowFill = true)
        minimumHeight = c.dp(58)
        isClickable = true
        isFocusable = true
        setOnClickListener { onClick() }
        foreground = c.getDrawable(android.R.drawable.list_selector_background)
    }

    fun linkButton(label: String, color: Int = Party.CYAN, onClick: () -> Unit) = text(label, 14f, color, 600).apply {
        gravity = Gravity.CENTER
        minHeight = c.dp(44)
        isClickable = true
        setOnClickListener { onClick() }
    }

    fun outlineButton(label: String, color: Int = Party.TEXT, border: Int = Party.BORDER, onClick: () -> Unit) =
        text(label, 14f, color, 700).apply {
            gravity = Gravity.CENTER
            minHeight = c.dp(44)
            setPadding(c.dp(12), 0, c.dp(12), 0)
            background = ChamferDrawable(c.dp(10f), stroke = border, strokeWidth = c.dp(1.5f))
            isClickable = true
            setOnClickListener { onClick() }
        }

    fun chip(s: String, border: Int, color: Int) = text(s, 12f, color, 600).apply {
        setPadding(c.dp(8), c.dp(3), c.dp(8), c.dp(3))
        background = ChamferDrawable(0f, stroke = border, strokeWidth = c.dp(1f), cutTopLeft = false, cutBottomRight = false)
    }

    /** Dark panel with a colored left bar, like the Welcome and Installing list items. */
    fun accentRow(accent: Int, bg: Int = Party.SURFACE, block: LinearLayout.() -> Unit) = row(14) {
        setPadding(c.dp(14), c.dp(12), c.dp(14), c.dp(12))
        background = ChamferDrawable(c.dp(10f), fill = bg, cutTopLeft = false, accent = accent, accentWidth = c.dp(3f))
        block()
    }

    fun card(selected: Boolean, block: LinearLayout.() -> Unit) = column(8) {
        setPadding(c.dp(14), c.dp(14), c.dp(14), c.dp(14))
        background = ChamferDrawable(
            c.dp(14f), fill = if (selected) Party.CARD_ON else Party.CARD,
            stroke = if (selected) Party.PINK else Party.BORDER, strokeWidth = c.dp(1.5f), cutTopLeft = false
        )
        block()
    }

    /** Wraps content with the top rainbow strip and glow background. */
    fun screen(glows: List<Triple<Float, Float, Int>>, content: View) = FrameLayout(c).apply {
        addView(GlowBackground(c, glows), FrameLayout.LayoutParams(-1, -1))
        addView(content, FrameLayout.LayoutParams(-1, -1))
        addView(RainbowStrip(c), FrameLayout.LayoutParams(-1, c.dp(4)))
        fitsSystemWindows = false
    }

    fun ellipsize(t: TextView) = t.apply { maxLines = 1; ellipsize = TextUtils.TruncateAt.END }

    fun matchWidth(v: View, height: Int = ViewGroup.LayoutParams.WRAP_CONTENT) =
        v.also { it.layoutParams = LinearLayout.LayoutParams(-1, height) }

    fun weight(v: View, w: Float = 1f) =
        v.also { it.layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, w) }
}

/** Transparent divider drawable used for LinearLayout gaps. */
private class Spacer(private val size: Int) : Drawable() {
    override fun getIntrinsicWidth() = size
    override fun getIntrinsicHeight() = size
    override fun draw(canvas: Canvas) = Unit
    override fun setAlpha(alpha: Int) = Unit
    override fun setColorFilter(colorFilter: ColorFilter?) = Unit
    @Deprecated("Deprecated in Java")
    override fun getOpacity() = PixelFormat.TRANSPARENT
}
