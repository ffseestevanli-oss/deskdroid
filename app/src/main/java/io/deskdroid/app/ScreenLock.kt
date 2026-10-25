package io.deskdroid.app

import java.io.File

/**
 * Keeps Plasma's lock screen off by default. The deskdroid user has no
 * password unless they set one with passwd, and a lock screen with nothing to
 * unlock it with shuts them out of their desktop. So with no password, idle
 * locking is forced off and Lock Screen is removed from the menus and Meta+L;
 * with a password, locking is only off by default and can be turned on in
 * System Settings. The app's own "Lock my desktop" (LockGate) covers locking
 * without a Linux password. There is no login screen: SDDM can't run under
 * proot and isn't installed.
 *
 * The files go in their own config directory, read before /etc/xdg through a
 * Plasma env file, and are rewritten at each start, so existing installs get
 * them with an app update and a new password counts from the next start.
 */
object ScreenLock {
    private const val TAG = "deskdroid-screenlock"
    private const val CONFIG_DIR = "/etc/deskdroid/xdg"

    fun install(paths: Paths) {
        val locked = !hasPassword(paths)
        val dir = File(paths.rootfs, CONFIG_DIR.removePrefix("/")).apply { mkdirs() }
        // [$i] makes the group immutable, so the user's own kscreenlockerrc can't turn locking back on.
        File(dir, "kscreenlockerrc").writeText(
            "# Written by the DeskDroid app (ScreenLock.kt) at each start.\n" +
                "[Daemon]${if (locked) "[\$i]" else ""}\nAutolock=false\nLockOnResume=false\n"
        )
        val globals = File(dir, "kdeglobals")
        if (locked) {
            globals.writeText(
                "# Written by the DeskDroid app (ScreenLock.kt) while the deskdroid user has no password.\n" +
                    "[KDE Action Restrictions][\$i]\nlock_screen=false\naction/lock_screen=false\n"
            )
        } else {
            globals.delete()
        }
        File(paths.rootfs, "home/deskdroid/.config/plasma-workspace/env/$TAG.sh").apply {
            parentFile!!.mkdirs()
            writeText(
                "# $TAG: written by the DeskDroid app (ScreenLock.kt) at each start.\n" +
                    "export XDG_CONFIG_DIRS=\"$CONFIG_DIR:\${XDG_CONFIG_DIRS:-/etc/xdg}\"\n"
            )
        }
        AppLog.i(if (locked) "No Linux password set; screen locking disabled" else "Linux password set; screen locking off by default")
    }

    /** A crypt hash ("$y$..."); useradd leaves "!" and "passwd -d" leaves it empty. */
    private fun hasPassword(paths: Paths): Boolean = try {
        File(paths.rootfs, "etc/shadow").useLines { lines ->
            lines.firstOrNull { it.startsWith("deskdroid:") }?.split(':')?.getOrNull(1)?.startsWith("$") == true
        }
    } catch (_: Exception) {
        false
    }
}
