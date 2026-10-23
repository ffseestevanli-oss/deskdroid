package io.deskdroid.app

import android.content.Context
import java.io.File

/**
 * Makes web browsers work under proot. Their sandboxes rely on user namespaces
 * and seccomp, which proot can only fake: Chromium-based browsers abort at
 * launch and Firefox-based ones crash every tab. Both run with their sandbox off.
 * Done from the app at session start, so existing installs get it with an app
 * update and no new system image.
 */
object Browsers {
    /** Gecko (Firefox, Floorp, LibreWolf...): turns off each child process sandbox. */
    val geckoEnv = mapOf(
        "MOZ_DISABLE_CONTENT_SANDBOX" to "1",
        "MOZ_DISABLE_GMP_SANDBOX" to "1",
        "MOZ_DISABLE_RDD_SANDBOX" to "1",
        "MOZ_DISABLE_SOCKET_PROCESS_SANDBOX" to "1",
        "MOZ_DISABLE_UTILITY_SANDBOX" to "1",
    )

    /** Runs as root before deskdroid-boot (Proot.sessionCommand). */
    const val FLAGS_SCRIPT = "/usr/local/bin/deskdroid-browser-flags"

    /**
     * Chromium has no environment switch, so the flags script (assets/linux/)
     * adds --no-sandbox to every Chromium-based browser and Electron app it
     * finds. It runs before each session and, through an apt hook, after every
     * install, so browsers installed later (apt, Discover) work too.
     */
    fun install(c: Context, paths: Paths) {
        val script = File(paths.rootfs, FLAGS_SCRIPT.removePrefix("/"))
        script.parentFile!!.mkdirs()
        c.assets.open("linux/deskdroid-browser-flags").use { input ->
            script.outputStream().use { input.copyTo(it) }
        }
        script.setExecutable(true, false)
        File(paths.rootfs, "etc/apt/apt.conf.d/99deskdroid-browser-flags").apply {
            parentFile!!.mkdirs()
            writeText(
                "// Written by the DeskDroid app (Browsers.kt): Chromium-based browsers need --no-sandbox.\n" +
                    "DPkg::Post-Invoke { \"if [ -x $FLAGS_SCRIPT ]; then $FLAGS_SCRIPT; fi\"; };\n"
            )
        }
    }
}
