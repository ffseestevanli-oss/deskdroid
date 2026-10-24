package io.deskdroid.app

import android.content.Context
import java.io.File

/**
 * Steam and other x86 Linux apps, through FEX-Emu (plan section 6b). The
 * scripts (assets/linux/) download FEX, its x86 rootfs and Valve's Steam
 * bootstrap the first time Steam starts, so the image stays small and existing
 * installs get Steam with an app update. Ultra-lite has no x86 support.
 */
object Steam {
    private val SCRIPTS = listOf("deskdroid-fex", "deskdroid-steam")
    private const val DESKTOP = "usr/local/share/applications/deskdroid-steam.desktop"

    fun install(c: Context, paths: Paths) {
        val desktop = File(paths.rootfs, DESKTOP)
        if (paths.installedEdition == "ultralite") {
            desktop.delete()
            return
        }
        for (name in SCRIPTS) {
            val script = File(paths.rootfs, "usr/local/bin/$name")
            script.parentFile!!.mkdirs()
            c.assets.open("linux/$name").use { input ->
                script.outputStream().use { input.copyTo(it) }
            }
            script.setExecutable(true, false)
        }
        desktop.parentFile!!.mkdirs()
        desktop.writeText(
            """
            |[Desktop Entry]
            |# Written by the DeskDroid app (Steam.kt) at each start.
            |Type=Application
            |Name=Steam
            |Comment=Application for managing and playing games on Steam (x86, runs under FEX-Emu)
            |Exec=/usr/local/bin/deskdroid-steam %U
            |Icon=steam
            |Terminal=false
            |Categories=Network;FileTransfer;Game;
            |MimeType=x-scheme-handler/steam;x-scheme-handler/steamlink;
            |StartupWMClass=steam
            |PrefersNonDefaultGPU=true
            |Actions=BigPicture;Library;
            |
            |[Desktop Action BigPicture]
            |Name=Big Picture
            |Exec=/usr/local/bin/deskdroid-steam steam://open/bigpicture
            |
            |[Desktop Action Library]
            |Name=Library
            |Exec=/usr/local/bin/deskdroid-steam steam://open/games
            |""".trimMargin()
        )
    }
}
