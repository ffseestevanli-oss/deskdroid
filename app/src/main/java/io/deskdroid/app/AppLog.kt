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
    private const val MAX_LINES = 6000
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
                lastExit(c)?.let { lines.addLast(it) }
            }
            rewrite()
        } catch (e: Exception) {
            Log.w("DeskDroid", "log file: $e")
        }
    }

    /** Why Android ended the app's previous process (low memory, a crash, a permission change...). */
    private fun lastExit(c: Context): String? {
        if (android.os.Build.VERSION.SDK_INT < 30) return null
        return try {
            val am = c.getSystemService(android.app.ActivityManager::class.java)
            val e = am.getHistoricalProcessExitReasons(c.packageName, 0, 1).firstOrNull() ?: return null
            val reasons = mapOf(
                1 to "exited by itself", 2 to "killed by a signal", 3 to "low memory", 4 to "crash",
                5 to "native crash", 6 to "not responding", 7 to "init failure", 8 to "permission change",
                9 to "too much resource use", 10 to "user request", 11 to "user stopped", 12 to "dependency died",
                13 to "other", 14 to "freezer", 15 to "package state change", 16 to "package updated",
            )
            "Previous process ended: ${reasons[e.reason] ?: "reason ${e.reason}"} (status ${e.status}, " +
                "importance ${e.importance}, ${(e.pss / 1024)} MB) ${e.description ?: ""} at " +
                java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US).format(java.util.Date(e.timestamp))
        } catch (e: Exception) {
            null
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
        // The main screen's view of the log: at most five updates a second, and
        // none while nothing shows it. Joining every line and posting it for
        // each new line kept the main thread so busy, when the desktop logged a
        // lot, that Android reported the app as not responding.
        if (listener != null && !updatePending) {
            updatePending = true
            main.postDelayed({
                synchronized(this) { updatePending = false }
                listener?.invoke(text())
            }, 200)
        }
    }
    private var updatePending = false

    @Synchronized
    fun text(): String = lines.joinToString("\n")

    fun setStatus(s: String) {
        status = s
        i("== $s")
        main.post { statusListener?.invoke(s) }
    }
}
