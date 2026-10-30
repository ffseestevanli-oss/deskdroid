package io.deskdroid.app

import java.io.File

/**
 * Lighter Plasma defaults for a phone. Under proot every process and system
 * call costs more than on a PC, and with software rendering (llvmpipe) every
 * animated frame and blurred panel is drawn by the CPU. So:
 * - background helpers the desktop doesn't need here don't start: Discover's
 *   update notifier (it wakes PackageKit to refresh in the background), the
 *   accessibility daemon, the GTK global-menu proxy and a few KDE daemon
 *   modules (geolocation for time zone and Night Light, the donation
 *   reminder, the automounter, the out-of-memory notifier).
 * - with software rendering, animations are instant and KWin's blur and
 *   background contrast effects are off.
 *
 * These are defaults: the files go in their own config directory, read before
 * /etc/xdg through a Plasma env file, so anything the user changes in System
 * Settings (or their own ~/.config) wins. Rewritten at each start, so existing
 * installs get them with an app update.
 */
object Tuning {
    private const val TAG = "deskdroid-tuning"
    private const val CONFIG_DIR = "/etc/deskdroid/xdg-tuning"

    private val HIDDEN_AUTOSTART = listOf(
        "org.kde.discover.notifier.desktop",
        "kaccess.desktop",
        "gmenudbusmenuproxy.desktop",
    )
    private val OFF_KDED_MODULES = listOf(
        "colorcorrectlocationupdater",
        "device_automounter",
        "donationmessage",
        "geotimezoned",
        "oom-notifier",
    )

    /** [software]: the desktop renders on the CPU (llvmpipe, or KWin's QPainter in the Wayland session). */
    fun install(paths: Paths, software: Boolean) {
        val dir = File(paths.rootfs, CONFIG_DIR.removePrefix("/"))
        val header = "# Written by the DeskDroid app (Tuning.kt) at each start; your own settings override it.\n"
        File(dir, "autostart").mkdirs()
        for (name in HIDDEN_AUTOSTART) {
            writeIfChanged(File(dir, "autostart/$name"), "$header[Desktop Entry]\nType=Application\nName=$name\nHidden=true\n")
        }
        writeIfChanged(File(dir, "kded6rc"), header + OFF_KDED_MODULES.joinToString("") { "[Module-$it]\nautoload=false\n\n" })
        val globals = File(dir, "kdeglobals")
        val kwinrc = File(dir, "kwinrc")
        if (software) {
            writeIfChanged(globals, "$header[KDE]\nAnimationDurationFactor=0\n")
            writeIfChanged(kwinrc, "$header[Plugins]\nblurEnabled=false\ncontrastEnabled=false\n")
        } else {
            globals.delete()
            kwinrc.delete()
        }
        writeIfChanged(
            File(paths.rootfs, "home/deskdroid/.config/plasma-workspace/env/$TAG.sh"),
            "# $TAG: written by the DeskDroid app (Tuning.kt) at each start.\n" +
                "export XDG_CONFIG_DIRS=\"$CONFIG_DIR:\${XDG_CONFIG_DIRS:-/etc/xdg}\"\n"
        )
    }

    /**
     * Writes [text] unless [f] already holds it, so the file's time only changes
     * with its content (deskdroid-browser-flags compares it) and nothing is
     * rewritten on flash at every start.
     */
    fun writeIfChanged(f: File, text: String) {
        writeIfChanged(f, text.toByteArray())
    }

    fun writeIfChanged(f: File, bytes: ByteArray) {
        if (f.isFile && f.length() == bytes.size.toLong() && f.readBytes().contentEquals(bytes)) return
        f.parentFile!!.mkdirs()
        f.writeBytes(bytes)
    }
}
