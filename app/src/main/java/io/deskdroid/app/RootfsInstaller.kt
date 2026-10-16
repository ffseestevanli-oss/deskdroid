package io.deskdroid.app

import android.system.Os
import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.xz.XZCompressorInputStream
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * Downloads, verifies and unpacks the prebuilt Debian rootfs.
 * Unpacks into a staging dir and swaps it in with one rename, so a failed
 * install never leaves a half-written rootfs behind.
 */
class RootfsInstaller(private val paths: Paths) {

    fun installFromUrl(url: String) {
        val expected = fetchChecksum("$url.sha256")
        download(url, paths.download)
        if (expected != null) {
            AppLog.setStatus("Verifying download")
            val actual = sha256(paths.download)
            check(actual.equals(expected, ignoreCase = true)) {
                "Checksum mismatch: expected $expected, got $actual"
            }
            AppLog.i("SHA-256 OK")
        } else {
            AppLog.i("No .sha256 next to the rootfs URL; skipping verification")
        }
        paths.download.inputStream().use { extract(it) }
        paths.download.delete()
    }

    fun installFromStream(input: InputStream) = extract(input)

    private fun fetchChecksum(url: String): String? = try {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.instanceFollowRedirects = true
        if (conn.responseCode == 200) conn.inputStream.bufferedReader().readText()
            .trim().split(Regex("\\s+")).first() else null
    } catch (e: Exception) {
        null
    }

    private fun download(url: String, dest: File) {
        AppLog.setStatus("Downloading system image")
        val existing = if (dest.exists()) dest.length() else 0L
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.instanceFollowRedirects = true
        if (existing > 0) conn.setRequestProperty("Range", "bytes=$existing-")
        val code = conn.responseCode
        val append = code == 206
        check(code == 200 || code == 206) { "Download failed: HTTP $code" }
        val total = conn.contentLengthLong + if (append) existing else 0
        var done = if (append) existing else 0L
        var lastPct = -1
        conn.inputStream.use { input ->
            FileOutputStream(dest, append).use { out ->
                val buf = ByteArray(1 shl 16)
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    out.write(buf, 0, n)
                    done += n
                    if (total > 0) {
                        val pct = (done * 100 / total).toInt()
                        if (pct != lastPct) {
                            lastPct = pct
                            AppLog.setStatus("Downloading system image: $pct%")
                        }
                    }
                }
            }
        }
    }

    private fun extract(raw: InputStream) {
        AppLog.setStatus("Unpacking system image")
        val staging = paths.rootfsStaging
        staging.deleteRecursively()
        staging.mkdirs()
        val rootCanon = staging.canonicalPath
        var count = 0
        TarArchiveInputStream(XZCompressorInputStream(BufferedInputStream(raw, 1 shl 16))).use { tar ->
            while (true) {
                val entry: TarArchiveEntry = tar.nextEntry ?: break
                val name = entry.name.removePrefix("./")
                if (name.isEmpty()) continue
                val out = File(staging, name)
                // Refuse entries that escape the rootfs (tar-slip).
                val parentCanon = out.parentFile!!.canonicalPath
                if (!parentCanon.startsWith(rootCanon)) {
                    AppLog.i("Skipping unsafe path $name"); continue
                }
                when {
                    entry.isDirectory -> {
                        out.mkdirs()
                        chmod(out, entry.mode or 0b111_000_000)
                    }
                    entry.isSymbolicLink -> {
                        out.parentFile!!.mkdirs()
                        out.delete()
                        Os.symlink(entry.linkName, out.path)
                    }
                    entry.isLink -> {
                        // Hardlinks are not reliable in app storage: copy instead.
                        val target = File(staging, entry.linkName.removePrefix("./"))
                        out.parentFile!!.mkdirs()
                        target.copyTo(out, overwrite = true)
                        chmod(out, entry.mode)
                    }
                    entry.isFile -> {
                        out.parentFile!!.mkdirs()
                        FileOutputStream(out).use { tar.copyTo(it, 1 shl 16) }
                        chmod(out, entry.mode)
                    }
                    else -> Unit // devices and fifos: proot binds the real /dev
                }
                if (++count % 5000 == 0) AppLog.setStatus("Unpacking system image: $count files")
            }
        }
        writeAndroidGlue(staging)
        paths.rootfs.deleteRecursively()
        check(staging.renameTo(paths.rootfs)) { "Could not move rootfs into place" }
        AppLog.setStatus("Installed ($count files)")
    }

    /** Files that must reflect the Android side rather than the build machine. */
    private fun writeAndroidGlue(root: File) {
        File(root, "etc/resolv.conf").apply { delete(); writeText("nameserver 1.1.1.1\nnameserver 8.8.8.8\n") }
        File(root, "etc/hosts").writeText("127.0.0.1 localhost\n::1 localhost\n127.0.1.1 deskdroid\n")
        File(root, "tmp").apply { mkdirs(); chmod(this, 0b111_111_111) }
    }

    private fun chmod(f: File, mode: Int) {
        // Drop setuid/setgid/sticky: meaningless under proot and refused by some kernels.
        try { Os.chmod(f.path, mode and 0b111_111_111 or 0b110_000_000) } catch (_: Exception) {}
    }

    private fun sha256(f: File): String {
        val md = MessageDigest.getInstance("SHA-256")
        f.inputStream().use { input ->
            val buf = ByteArray(1 shl 16)
            while (true) { val n = input.read(buf); if (n < 0) break; md.update(buf, 0, n) }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }
}
