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
        // A crash's stack trace in the log, before Android's own handler ends the app.
        val android = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            try { i("CRASH in ${t.name}: ${Log.getStackTraceString(e).take(4000)}") } catch (_: Throwable) {}
            android?.uncaughtException(t, e)
        }
        watchMainThread()
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
                java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US).format(java.util.Date(e.timestamp)) +
                (if (e.reason == 6) anrMainThread(e) else "")
        } catch (e: Exception) {
            null
        }
    }

    // "Not responding": where the main thread was, from Android's own trace.
    @android.annotation.TargetApi(30)
    private fun anrMainThread(e: android.app.ApplicationExitInfo): String = try {
        val trace = e.traceInputStream?.bufferedReader()?.readLines().orEmpty()
        val start = trace.indexOfFirst { it.startsWith("\"main\"") }
        if (start < 0) "" else "\nMain thread when Android gave up on it:\n" +
            trace.drop(start).takeWhile { it.isNotBlank() }.take(60).joinToString("\n")
    } catch (x: Exception) {
        ""
    }

    /**
     * A main thread that doesn't answer for 3 seconds gets its stack in the log,
     * before Android reports the app as not responding (at 5).
     */
    fun watchMainThread() {
        Thread {
            val looper = Looper.getMainLooper()
            while (true) {
                val answered = java.util.concurrent.atomic.AtomicBoolean(false)
                main.post { answered.set(true) }
                Thread.sleep(3000)
                if (!answered.get()) {
                    i("Main thread busy for 3 s, at:\n" + looper.thread.stackTrace.take(40).joinToString("\n") { "  at $it" })
                    while (!answered.get()) Thread.sleep(500)
                }
            }
        }.apply { isDaemon = true; name = "main-watch" }.start()
    }

    /**
     * The phone's memory when a desktop process is killed (signal 9): Android's
     * memory numbers and the kernel's out-of-memory events for the app's group.
     */
    fun memoryReport(c: Context): String = try {
        val am = c.getSystemService(android.app.ActivityManager::class.java)
        val mi = android.app.ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        val cg = File("/proc/self/cgroup").readLines().firstOrNull { it.startsWith("0::") }?.substringAfter("0::")
        val events = cg?.let { p -> listOf("memory.events", "memory.max", "memory.peak").joinToString(", ") { n ->
            "$n=" + (runCatching { File("/sys/fs/cgroup$p/$n").readText().trim().replace("\n", " ") }.getOrNull() ?: "?")
        } }
        "memory: ${mi.availMem shr 20} MB free of ${mi.totalMem shr 20} MB, low=${mi.lowMemory}; child process limit: ${Checks.phantomProcesses(c)}; cgroup $cg: $events"
    } catch (e: Exception) {
        "memory: $e"
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
