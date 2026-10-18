package io.deskdroid.app.ui

import android.content.Context
import android.view.View
import android.view.ViewGroup

/** Lays children out left to right, wrapping to new lines (the mockups' chip rows). */
class FlowLayout(c: Context, private val gap: Int) : ViewGroup(c) {
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val maxW = MeasureSpec.getSize(widthMeasureSpec) - paddingLeft - paddingRight
        var x = 0; var y = 0; var lineH = 0
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child.visibility == View.GONE) continue
            child.measure(MeasureSpec.makeMeasureSpec(maxW, MeasureSpec.AT_MOST), MeasureSpec.UNSPECIFIED)
            if (x > 0 && x + child.measuredWidth > maxW) { x = 0; y += lineH + gap; lineH = 0 }
            x += child.measuredWidth + gap
            lineH = maxOf(lineH, child.measuredHeight)
        }
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), y + lineH + paddingTop + paddingBottom)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        val maxW = r - l - paddingLeft - paddingRight
        var x = 0; var y = 0; var lineH = 0
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child.visibility == View.GONE) continue
            if (x > 0 && x + child.measuredWidth > maxW) { x = 0; y += lineH + gap; lineH = 0 }
            child.layout(paddingLeft + x, paddingTop + y, paddingLeft + x + child.measuredWidth, paddingTop + y + child.measuredHeight)
            x += child.measuredWidth + gap
            lineH = maxOf(lineH, child.measuredHeight)
        }
    }
}
