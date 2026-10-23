package io.deskdroid.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.File
import java.io.Writer

/**
 * Small log shown on the main screen, mirrored to logcat and to files/session.log,
 * so it survives Android killing the app (e.g. while the desktop hangs).
 */
object AppLog {
    // Enough to hold a session's start-up plus a crash (KWin, the Venus server).
    private const val MAX_LINES = 2000
    private val lines = ArrayDeque<String>()
    private val main = Handler(Looper.getMainLooper())
    var listener: ((String) -> Unit)? = null
    var status: String = ""
        private set
    var statusListener: ((String) -> Unit)? = null
    private var file: File? = null
    private var out: Writer? = null

    /** Opens the log file; a fresh process starts with the previous run's lines. */
    @Synchronized
    fun attach(c: Context) {
        if (file != null) return
        val f = File(c.filesDir, "session.log").also { file = it }
        try {
            if (lines.isEmpty() && f.exists()) {
                lines.addLast("== Log from before the app last restarted ==")
                f.readLines().takeLast(MAX_LINES).forEach { lines.addLast(it) }
                lines.addLast("== App restarted ==")
            }
            rewrite()
        } catch (e: Exception) {
            Log.w("DeskDroid", "log file: $e")
        }
    }

    private fun rewrite() {
        out?.close()
        val f = file ?: return
        f.writeText(lines.joinToString("") { "$it\n" })
        out = java.io.FileWriter(f, true)
    }

    @Synchronized
    fun i(msg: String) {
        Log.i("DeskDroid", msg)
        lines.addLast(msg)
        while (lines.size > MAX_LINES) lines.removeFirst()
        try {
            out?.apply { write(msg); write("\n"); flush() }
            if ((file?.length() ?: 0) > 1_000_000) rewrite()
        } catch (e: Exception) {
            out = null
        }
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
