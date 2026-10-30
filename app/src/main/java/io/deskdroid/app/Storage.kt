package io.deskdroid.app

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.system.Os
import java.io.File

/**
 * Shows the phone's storage (/storage/emulated/0) on the desktop like a USB
 * drive: with "All files access" granted, proot binds it at [MOUNT] (also
 * /sdcard), and Phone and Camera are added to the Places panel of Dolphin and
 * the file dialogs. Linux keeps its own home folder (Desktop, Documents,
 * Downloads, ... in /home/deskdroid); nothing in it is shared. Android's own
 * folder is listed in a .hidden file, which Dolphin and GTK file pickers hide
 * until "Show hidden files" is on. Android itself blocks Android/data and
 * Android/obb whatever this app does.
 */
object Storage {
    /** Where the phone's storage shows up inside Debian, as udisks would mount a USB drive. */
    const val MOUNT = "/media/deskdroid/Phone"
    private val HOME_DIRS = listOf("Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos", "Templates", "Public")

    /** Folders in the storage root hidden from the desktop's file managers by default. */
    private val HIDDEN = listOf("Android")

    private const val HOME = "home/deskdroid"

    /**
     * Logs, as the desktop user, what the phone storage looks like from inside
     * Debian and whether a file can be created in it, so the log shows why it
     * is read-only or empty. Runs in the background while deskdroid-boot starts
     * (Proot.sessionCommand), so it doesn't hold up the desktop.
     */
    val PROBE_SCRIPT = "( runuser -u deskdroid -- sh -c 'ls -ldn $MOUNT $MOUNT/${Environment.DIRECTORY_DOWNLOADS} " +
        "&& echo \"\$(ls -A $MOUNT | wc -l) entries in $MOUNT\" " +
        "&& touch $MOUNT/${Environment.DIRECTORY_DOWNLOADS}/.deskdroid-rw-test " +
        "&& rm -f $MOUNT/${Environment.DIRECTORY_DOWNLOADS}/.deskdroid-rw-test && echo writable || echo not writable' " +
        "2>&1 | sed 's/^/storage check: /' ) & "
    /** Marks the Places entries this app adds, so they can be told apart from the user's. */
    private const val PLACE_ID = "deskdroid/"

    @Suppress("DEPRECATION")
    val root: File get() = Environment.getExternalStorageDirectory()

    fun granted(c: Context): Boolean =
        if (Build.VERSION.SDK_INT >= 30) Environment.isExternalStorageManager()
        else c.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED

    /** Android 11+: the "All files access" page in Settings. Android 10: the storage permission prompt. */
    fun request(a: Activity) {
        if (Build.VERSION.SDK_INT >= 30) {
            try {
                a.startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:${a.packageName}")))
            } catch (_: Exception) {
                a.startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
            }
        } else {
            a.requestPermissions(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE), 0)
        }
    }

    /**
     * Sets up the home folder and, if access is granted, the phone storage.
     * Called at session start, before proot runs. Returns proot binds as
     * (phone path, Linux path).
     */
    fun prepare(c: Context, paths: Paths): List<Pair<String, String>> {
        val home = File(paths.rootfs, HOME)
        writeUserDirs(home)
        for (d in HOME_DIRS) File(home, d).mkdirs()
        // Places used to be added by a script in the rootfs, racing KDE for the file.
        File(paths.rootfs, "usr/local/bin/deskdroid-storage").delete()
        // Earlier versions linked ~/Phone to the storage; it's a separate drive now.
        File(home, "Phone").let { if (isSymlink(it)) it.delete() }

        val phone = root
        val sdcard = File(paths.rootfs, "sdcard")
        if (!granted(c) || !phone.canWrite()) {
            AppLog.i("Phone storage not shown on the desktop (no All files access)")
            if (isSymlink(sdcard)) sdcard.delete()
            writePlaces(home, emptyList())
            return emptyList()
        }

        File(paths.rootfs, MOUNT.removePrefix("/")).mkdirs()
        symlink(MOUNT, sdcard)
        writeHidden(phone)
        writePlaces(home, listOfNotNull(
            Triple("phone", "Phone", MOUNT) to "smartphone",
            File(phone, Environment.DIRECTORY_DCIM).takeIf { it.isDirectory }
                ?.let { Triple("camera", "Camera", "$MOUNT/${it.name}") to "camera-photo" },
        ))
        AppLog.i("Phone storage ${phone.path} shown at $MOUNT")
        for (f in listOf(phone, File(phone, Environment.DIRECTORY_DOWNLOADS))) try {
            val st = Os.stat(f.path)
            AppLog.i("  ${f.path}: uid ${st.st_uid} gid ${st.st_gid} mode ${Integer.toOctalString(st.st_mode and 0xfff)}, " +
                "${f.list()?.size ?: "unlistable"} entries")
        } catch (e: Exception) {
            AppLog.i("  ${f.path}: ${e.message}")
        }
        return listOf(phone.path to MOUNT)
    }

    private fun writeUserDirs(home: File) {
        val f = File(home, ".config/user-dirs.dirs")
        if (f.exists()) return
        f.parentFile!!.mkdirs()
        f.writeText(
            "# Written by the DeskDroid app (Storage.kt). The phone's storage is at $MOUNT.\n" +
                listOf("DESKTOP" to "Desktop", "DOCUMENTS" to "Documents", "DOWNLOAD" to "Downloads",
                    "MUSIC" to "Music", "PICTURES" to "Pictures", "VIDEOS" to "Videos",
                    "TEMPLATES" to "Templates", "PUBLICSHARE" to "Public")
                    .joinToString("") { (k, d) -> "XDG_${k}_DIR=\"\$HOME/$d\"\n" }
        )
    }

    /** Adds [HIDDEN] to the storage root's .hidden file, keeping lines the user added. */
    private fun writeHidden(phone: File) {
        val f = File(phone, ".hidden")
        try {
            val lines = if (f.exists()) f.readLines() else emptyList()
            val missing = HIDDEN.filter { it !in lines }
            if (missing.isNotEmpty()) f.writeText((lines.filter { it.isNotBlank() } + missing).joinToString("\n", postfix = "\n"))
        } catch (e: Exception) {
            AppLog.i("Couldn't write ${f.path}: ${e.message}")
        }
    }

    /** Home folders KDE shows in Places, in its order, with its icons. */
    private val PLACES_DIRS = listOf(
        "Desktop" to "user-desktop", "Documents" to "folder-documents", "Downloads" to "folder-downloads",
        "Music" to "folder-music", "Pictures" to "folder-pictures", "Videos" to "folder-videos",
    )

    /**
     * Updates KDE's Places (~/.local/share/user-places.xbel) before the desktop
     * starts, so nothing in KDE has the file open:
     * - Desktop, Documents, Downloads, Music, Pictures and Videos, once each
     *   (removing one afterwards sticks). KDE only adds these when it first
     *   writes the file, and older images had no such folders then.
     * - [devices] ((id, title, Linux path) to icon) right after them, replacing
     *   the ones added before. KDE's Devices group only lists drives it
     *   detects itself (udisks, which proot can't run), so they stay in Places.
     * With no file yet, Home goes in too and there's no kde_places_version, so
     * KDE adds the rest of its defaults (Network, Trash) below.
     */
    private fun writePlaces(home: File, devices: List<Pair<Triple<String, String, String>, String>>) {
        val f = File(home, ".local/share/user-places.xbel")
        val added = File(home, ".config/deskdroid/places-added")
        try {
            var xml = if (f.exists()) f.readText() else ""
            val old = xml
            if (!xml.contains("</xbel>")) {
                xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE xbel>\n" +
                    "<xbel xmlns:bookmark=\"http://www.freedesktop.org/standards/desktop-bookmarks\" " +
                    "xmlns:kdepriv=\"http://www.kde.org/kdepriv\" " +
                    "xmlns:mime=\"http://www.freedesktop.org/standards/shared-mime-info\">\n" +
                    bookmark("file:///$HOME", "Home", "user-home", "deskdroid-xdg/home", system = true) + "</xbel>\n"
            }
            val homeUrl = "file:///$HOME"
            val dirUrls = PLACES_DIRS.map { "$homeUrl/${it.first}" }
            val done = (if (added.exists()) added.readLines() else emptyList()).toMutableSet()
            for ((i, d) in PLACES_DIRS.withIndex()) {
                val (name, icon) = d
                if (name in done) continue
                if (!xml.contains("href=\"${dirUrls[i]}\"")) {
                    xml = insertAfterLast(xml, listOf(homeUrl) + dirUrls.take(i),
                        bookmark(dirUrls[i], name, icon, "deskdroid-xdg/${name.lowercase()}", system = true))
                }
                done += name
            }
            // This app's device entries: drop them, then add the current ones back (the phone path can change).
            xml = Regex("""[ \t]*<bookmark\s(?:(?!</bookmark>).)*?<ID>${Regex.escape(PLACE_ID)}[^<]*</ID>.*?</bookmark>[ \t]*\n?""",
                RegexOption.DOT_MATCHES_ALL).replace(xml, "")
            xml = insertAfterLast(xml, listOf(homeUrl) + dirUrls, devices.joinToString("") { (place, icon) ->
                bookmark(Uri.fromFile(File(place.third)).toString(), place.second, icon, PLACE_ID + place.first, system = false)
            })
            if (xml != old) {
                f.parentFile!!.mkdirs()
                f.writeText(xml)
                AppLog.i("Places updated; phone entries: ${devices.joinToString { it.first.second }.ifEmpty { "none" }}")
            }
            added.parentFile!!.mkdirs()
            added.writeText(done.joinToString("\n", postfix = "\n"))
        } catch (e: Exception) {
            AppLog.i("Couldn't update ${f.path}: ${e.message}")
        }
    }

    private fun bookmark(href: String, title: String, icon: String, id: String, system: Boolean) =
        " <bookmark href=\"$href\">\n  <title>$title</title>\n  <info>\n" +
            "   <metadata owner=\"http://freedesktop.org\">\n    <bookmark:icon name=\"$icon\"/>\n   </metadata>\n" +
            "   <metadata owner=\"http://www.kde.org\">\n    <ID>$id</ID>\n" +
            (if (system) "    <isSystemItem>true</isSystemItem>\n" else "") +
            "   </metadata>\n  </info>\n </bookmark>\n"

    /** Inserts [entry] after the last bookmark whose href is in [after]; else before the first bookmark (or </xbel>). */
    private fun insertAfterLast(xml: String, after: List<String>, entry: String): String {
        if (entry.isEmpty()) return xml
        val blocks = Regex("""[ \t]*<bookmark\s+href="([^"]*)".*?</bookmark>[ \t]*\n?""", RegexOption.DOT_MATCHES_ALL)
            .findAll(xml).toList()
        val at = blocks.lastOrNull { it.groupValues[1] in after }?.range?.let { it.last + 1 }
            ?: blocks.firstOrNull()?.range?.first ?: xml.lastIndexOf("</xbel>")
        return xml.substring(0, at) + entry + xml.substring(at)
    }

    private fun isSymlink(f: File) = try {
        android.system.OsConstants.S_ISLNK(Os.lstat(f.path).st_mode)
    } catch (_: Exception) {
        false
    }

    private fun symlink(target: String, link: File) {
        if (isSymlink(link)) {
            if (Os.readlink(link.path) == target) return
            link.delete()
        } else if (link.exists()) {
            return // a real file or folder the user made; leave it
        }
        try {
            Os.symlink(target, link.path)
        } catch (e: Exception) {
            AppLog.i("Couldn't link ${link.path}: ${e.message}")
        }
    }
}
