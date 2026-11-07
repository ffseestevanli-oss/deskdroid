package io.deskdroid.app

import android.content.Context
import java.io.File

/**
 * Etherium's settings (native/firefox/etherium: Startpage instead of Google,
 * tracking protection, nothing phoning home), copied into the installed
 * browser's folder: its policies in distribution/, its preferences as an
 * AutoConfig file. They ship in the APK's desktop data
 * (share/deskdroid/etherium, native/firefox/etherium/settings.sh), so a
 * browser installed from an older build gets the current ones too.
 */
object Etherium {
    fun applySettings(c: Context) {
        val program = File(c.filesDir, "store/apps/firefox/program")
        val settings = File(c.filesDir, "kwin/share/deskdroid/etherium")
        if (!File(program, "application.ini").exists() || !settings.isDirectory) return
        try {
            var changed = 0
            settings.walkTopDown().filter { it.isFile }.forEach { from ->
                val to = File(program, from.relativeTo(settings).path)
                val bytes = from.readBytes()
                if (to.exists() && to.readBytes().contentEquals(bytes)) return@forEach
                to.parentFile?.mkdirs()
                to.setWritable(true) // the store installs the browser's files read-only
                to.writeBytes(bytes)
                to.setReadOnly()
                changed++
            }
            if (changed > 0) AppLog.i("Etherium: $changed settings file(s) updated")
        } catch (e: Exception) {
            AppLog.i("Etherium: couldn't update its settings: $e")
        }
    }
}
