package io.deskdroid.app

import android.os.Handler
import android.os.Looper
import android.util.Log

/** Small in-memory log shown on the main screen, mirrored to logcat. */
object AppLog {
    private const val MAX_LINES = 400
    private val lines = ArrayDeque<String>()
    private val main = Handler(Looper.getMainLooper())
    var listener: ((String) -> Unit)? = null
    var status: String = ""
        private set
    var statusListener: ((String) -> Unit)? = null

    @Synchronized
    fun i(msg: String) {
        Log.i("DeskDroid", msg)
        lines.addLast(msg)
        while (lines.size > MAX_LINES) lines.removeFirst()
        val text = lines.joinToString("\n")
        main.post { listener?.invoke(text) }
    }

    @Synchronized
    fun text(): String = lines.joinToString("\n")

    fun setStatus(s: String) {
        status = s
        i("== $s")
        main.post { statusListener?.invoke(s) }
    }
}
