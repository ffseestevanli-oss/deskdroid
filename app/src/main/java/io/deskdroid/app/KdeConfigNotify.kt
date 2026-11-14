package io.deskdroid.app

import android.net.LocalSocket
import android.net.LocalSocketAddress
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * Tells the desktop's KDE programs (KWin, plasmashell, KDE apps) that keys of
 * a config file changed, as `kwriteconfig6 --notify` does: KConfigWatcher's
 * org.kde.kconfig.notify.ConfigChanged signal on the session bus, with the
 * groups and keys. The app has no D-Bus library, and dbus-send can't build
 * the signal's a{saay} argument, so this speaks just enough of the D-Bus
 * protocol itself: EXTERNAL auth, Hello, one signal.
 */
object KdeConfigNotify {
    /** [file] is the config's name ("kdeglobals"); [changes] maps group to keys. */
    fun send(busSocket: File, file: String, changes: Map<String, List<String>>): Boolean {
        if (!busSocket.exists()) return false
        return try {
            LocalSocket().use { s ->
                s.connect(LocalSocketAddress(busSocket.path, LocalSocketAddress.Namespace.FILESYSTEM))
                s.soTimeout = 2000
                val out = s.outputStream
                val inp = s.inputStream.bufferedReader(Charsets.US_ASCII)
                val uid = android.os.Process.myUid().toString().toByteArray().joinToString("") { "%02x".format(it) }
                out.write(0)
                out.write("AUTH EXTERNAL $uid\r\n".toByteArray())
                out.flush()
                val ok = inp.readLine() ?: return false
                if (!ok.startsWith("OK")) { AppLog.i("KDE config notify: bus said \"$ok\""); return false }
                out.write("BEGIN\r\n".toByteArray())
                out.write(message(1, 1, path = "/org/freedesktop/DBus", iface = "org.freedesktop.DBus",
                    member = "Hello", dest = "org.freedesktop.DBus", signature = null, body = ByteArray(0)))
                out.write(message(4, 2, path = "/$file", iface = "org.kde.kconfig.notify",
                    member = "ConfigChanged", dest = null, signature = "a{saay}", body = changesBody(changes)))
                out.flush()
                // Give the bus a moment to read both before the socket closes.
                Thread.sleep(100)
                true
            }
        } catch (e: Exception) {
            AppLog.i("KDE config notify: $e")
            false
        }
    }

    /** A little-endian D-Bus writer that keeps alignment from the start of its message. */
    private class W(val base: Int = 0) {
        val b = ByteArrayOutputStream()
        val pos get() = base + b.size()
        fun pad(n: Int) { while (pos % n != 0) b.write(0) }
        fun u8(v: Int) = b.write(v)
        fun u32(v: Int) { pad(4); for (i in 0 until 4) b.write(v ushr (8 * i) and 0xff) }
        fun str(s: String) { val d = s.toByteArray(); u32(d.size); b.write(d); b.write(0) }
        fun sig(s: String) { val d = s.toByteArray(); u8(d.size); b.write(d); b.write(0) }
        /** An array: its length, then the elements (aligned to [align]) written by [items]. */
        fun array(align: Int, items: W.() -> Unit) {
            u32(0)
            val lenAt = b.size() - 4
            pad(align)
            val start = b.size()
            items()
            val len = b.size() - start
            val bytes = b.toByteArray()
            for (i in 0 until 4) bytes[lenAt + i] = (len ushr (8 * i) and 0xff).toByte()
            b.reset(); b.write(bytes)
        }
    }

    private fun changesBody(changes: Map<String, List<String>>): ByteArray = W().apply {
        array(8) {
            for ((group, keys) in changes) {
                pad(8)
                str(group)
                array(4) { for (k in keys) { val d = k.toByteArray(); u32(d.size); b.write(d) } }
            }
        }
    }.b.toByteArray()

    private fun message(type: Int, serial: Int, path: String, iface: String, member: String,
                        dest: String?, signature: String?, body: ByteArray): ByteArray {
        val w = W()
        w.u8('l'.code); w.u8(type); w.u8(if (type == 4) 1 else 0); w.u8(1)
        w.u32(body.size); w.u32(serial)
        w.array(8) {
            fun field(code: Int, sigType: String, write: W.() -> Unit) { pad(8); u8(code); sig(sigType); write() }
            field(1, "o") { str(path) }
            field(2, "s") { str(iface) }
            field(3, "s") { str(member) }
            if (dest != null) field(6, "s") { str(dest) }
            if (signature != null) field(8, "g") { sig(signature) }
        }
        w.pad(8)
        w.b.write(body)
        return w.b.toByteArray()
    }
}
