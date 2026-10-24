package io.deskdroid.app

import android.content.Context
import java.io.File

/**
 * Makes Flatpak (Flathub) the default way to install apps in Discover. The
 * setup script (assets/linux/) adds Flathub for the deskdroid user and makes
 * it Discover's default source; the Plasma env file lets the app menu and
 * Discover's Launch button find the apps it installs. Done from the app at
 * session start, so existing installs get it with an app update.
 */
object Flatpak {
    /** Runs as root before deskdroid-boot (Proot.sessionCommand). */
    const val SETUP_SCRIPT = "/usr/local/bin/deskdroid-flatpak"
    private const val TAG = "deskdroid-flatpak"

    fun install(c: Context, paths: Paths) {
        val script = File(paths.rootfs, SETUP_SCRIPT.removePrefix("/"))
        script.parentFile!!.mkdirs()
        c.assets.open("linux/deskdroid-flatpak").use { input ->
            script.outputStream().use { input.copyTo(it) }
        }
        script.setExecutable(true, false)
        // No login shell or systemd runs /etc/profile.d/flatpak.sh, so without
        // this Flatpak apps install but never show up in the menu.
        File(paths.rootfs, "home/deskdroid/.config/plasma-workspace/env/$TAG.sh").apply {
            parentFile!!.mkdirs()
            writeText(
                "# $TAG: written by the DeskDroid app (Flatpak.kt) at each start.\n" +
                    "export XDG_DATA_DIRS=\"\$HOME/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:" +
                    "\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}\"\n"
            )
        }
    }
}
