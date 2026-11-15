package io.deskdroid.app

import android.content.Context
import android.os.Build
import java.io.File

/**
 * DeskDroid's log as one text file: the app's own log (AppLog) and the
 * desktop helpers' logs after it. Saved from Settings › Save log, the DD menu,
 * the phone's touchpad screen while the desktop is on a monitor, and the
 * desktop's terminal (dd-log in deskdroid-shrc, through android-open
 * deskdroid:save-log). Each save goes to Android's Downloads, like a browser
 * download, and to $HOME/deskdroid-log.txt (the app's files/), which the
 * desktop's terminal and apps can open.
 */
object LogExport {
    /** The newest saved log, where the desktop's terminal reads it. */
    const val HOME_FILE = "deskdroid-log.txt"

    /** What a save did: the Downloads file's name (null if that part failed) and a line to show. */
    class Result(val downloadsName: String?, val message: String)

    fun text(c: Context): String =
        "DeskDroid ${BuildConfig.VERSION_NAME}\n" +
            "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}) · ${Build.MANUFACTURER} ${Build.MODEL}\n" +
            "Saved " + java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US).format(java.util.Date()) + "\n\n" +
            AppLog.text() + "\n" + helperLogs(c)

    /** Saves the log to Downloads and to $HOME/deskdroid-log.txt. Any thread. */
    fun save(c: Context): Result {
        val stamp = java.text.SimpleDateFormat("yyyyMMdd-HHmmss", java.util.Locale.US).format(java.util.Date())
        val name = "deskdroid-log-$stamp.txt"
        val text = text(c)
        // The desktop's copy first: dd-log waits for it. Written whole, then
        // renamed, so the terminal never reads half a log.
        val home = File(c.filesDir, HOME_FILE)
        try {
            val tmp = File(c.filesDir, ".$HOME_FILE.tmp")
            tmp.writeText(text)
            if (!tmp.renameTo(home)) { home.writeText(text); tmp.delete() }
        } catch (e: Exception) {
            AppLog.i("Save log: couldn't write ~/$HOME_FILE: $e")
        }
        return try {
            val values = android.content.ContentValues().apply {
                put(android.provider.MediaStore.Downloads.DISPLAY_NAME, name)
                put(android.provider.MediaStore.Downloads.MIME_TYPE, "text/plain")
                put(android.provider.MediaStore.Downloads.RELATIVE_PATH, android.os.Environment.DIRECTORY_DOWNLOADS)
            }
            val uri = c.contentResolver.insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: error("no Downloads entry")
            c.contentResolver.openOutputStream(uri)!!.use { it.write(text.toByteArray()) }
            AppLog.i("Log saved to Downloads/$name")
            Result(name, "Log saved to Downloads/$name")
        } catch (e: Exception) {
            AppLog.i("Save log failed: $e")
            Result(null, "Couldn't save the log to Downloads: ${e.message}")
        }
    }

    /** Saves off the main thread, then shows what happened in a toast (on the phone's screen). */
    fun saveAndToast(c: Context) {
        val app = c.applicationContext
        Thread {
            val r = save(app)
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                android.widget.Toast.makeText(app, r.message, android.widget.Toast.LENGTH_LONG).show()
            }
        }.apply { name = "save-log" }.start()
    }

    /**
     * The desktop's helpers' own logs, at the end of the saved log: Set as Desktop
     * Wallpaper's; ddmask's journal (how Linux programs started, which couldn't
     * and why, the system calls Android blocked); the programs Flatpak couldn't
     * start; and each store app's launcher log (store/apps/<app>/run.log, or
     * flatpak-tmp/run/<app>/run.log for flatpak run), so an app that doesn't open
     * says why.
     */
    fun helperLogs(c: Context): String {
        val files = c.filesDir
        val logs = listOf("set-wallpaper.log", "ddmask.log", "glibc/exec.log").map { java.io.File(files, it) } +
            // Agora's flatpak command runs (backend.cpp): what flatpak said.
            listOf("software/flatpak.log").map { java.io.File(files, it) }.filter { it.exists() } +
            // Steam through FEX (X86.kt, assets/x86): setup, the FEX check, FEX's server, Steam itself.
            listOf("x86/install.log", "x86/run/fex-check.log", "x86/run/fexserver.log", "x86/steam.log", "x86/apps.log")
                .map { java.io.File(files, it) }.filter { it.exists() } +
            // Steam's own logs ($HOME/.local/share/Steam/logs): why its client stopped
            // (bootstrap = the updater and starter, console = the client, webhelper = its UI).
            listOf("bootstrap_log.txt", "console_log.txt", "stderr.txt", "webhelper.txt", "cef_log.txt")
                .map { java.io.File(files, ".local/share/Steam/logs/$it") }.filter { it.exists() } +
            (java.io.File(files, "store/apps").listFiles()?.sortedBy { it.name }
                ?.flatMap { listOf(java.io.File(it, "run.log"), java.io.File(it, "xwayland.log")) }
                ?.filter { it.exists() } ?: emptyList()) +
            // Apps started with flatpak run (flatpak.sh hands them to adpk-run.sh), and
            // the X server X11-only apps get.
            (java.io.File(files, "flatpak-tmp/run").listFiles()?.sortedBy { it.name }
                ?.flatMap { listOf(java.io.File(it, "run.log"), java.io.File(it, "xwayland.log")) }
                ?.filter { it.exists() } ?: emptyList())
        val blocked = java.io.File(files, "glibc/sigsys.log").takeIf { it.exists() }?.let { f ->
            try {
                "\n== system calls Android blocked (number: times)\n" + f.readLines().filter { it.isNotBlank() }
                    .groupingBy { it.trim() }.eachCount().entries.joinToString(", ") { "${it.key}: ${it.value}" } + "\n"
            } catch (e: Exception) { "\n== glibc/sigsys.log: ($e)\n" }
        } ?: ""
        return logs.joinToString("") { f ->
            val name = f.relativeTo(files).path
            if (!f.exists()) "\n== $name: none\n"
            else "\n== $name\n" + try { f.readText().takeLast(if (name == "ddmask.log") 30_000 else 10_000) } catch (e: Exception) { "($e)" } + "\n"
        } + blocked
    }
}
