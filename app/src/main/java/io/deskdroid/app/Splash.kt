package io.deskdroid.app

import android.content.Context
import java.io.File

/**
 * The desktop window shows a splash screen until the desktop shell is up. The
 * watcher script (assets/linux/) creates Paths.readyFile once plasmashell (or
 * MATE's panel) runs; Plasma's own splash is turned off, since it would only
 * show after DeskDroid's. Done from the app at session start, so existing
 * installs get it with an app update.
 */
object Splash {
    /** Runs as root, in the background, before deskdroid-boot (Proot.sessionCommand). */
    const val WATCH_SCRIPT = "/usr/local/bin/deskdroid-splash"

    fun install(c: Context, paths: Paths) {
        val script = File(paths.rootfs, WATCH_SCRIPT.removePrefix("/"))
        script.parentFile!!.mkdirs()
        c.assets.open("linux/deskdroid-splash").use { input ->
            script.outputStream().use { input.copyTo(it) }
        }
        script.setExecutable(true, false)
        File(paths.rootfs, "home/deskdroid/.config/ksplashrc").apply {
            parentFile!!.mkdirs()
            writeText("[KSplash]\nEngine=none\nTheme=None\n")
        }
    }
}
