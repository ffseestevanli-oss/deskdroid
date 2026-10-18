package io.deskdroid.app

import android.system.Os
import io.deskdroid.app.InstallState.Snapshot
import io.deskdroid.app.InstallState.Step
import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.FilterInputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.TimeZone

/**
 * Downloads, verifies and unpacks a prebuilt Debian rootfs (.tar.zst).
 *
 * - Download resumes where it stopped (Range requests), across app restarts,
 *   and retries flaky networks with backoff. Multi-part images are appended
 *   into one file as they arrive.
 * - Verify checks the minisign signature with the key built into the app
 *   (BuildConfig.IMAGE_PUBLIC_KEY); debug builds without a key fall back to SHA-256.
 * - Unpack streams through ddtool's zstd decoder into a staging dir that is
 *   swapped in with one rename, so a failed install never leaves a
 *   half-written rootfs behind.
 */
class RootfsInstaller(private val paths: Paths) {

    class Cancelled : IOException("Install cancelled")

    fun installEdition(baseUrl: String, edition: String) {
        update(Step.DOWNLOAD, -1f, "Getting the image list")
        val manifest = ImageManifest.fetch(baseUrl)
        val image = manifest.image(edition)
        AppLog.i("Image ${image.file} build ${manifest.version}: ${image.size} bytes, ${image.parts.size} part(s)")
        checkSpace(image)

        paths.downloads.mkdirs()
        val dest = File(paths.downloads, image.file)
        // A leftover from a different build can't be resumed.
        val stamp = File(paths.downloads, "${image.file}.sha256")
        if (!stamp.exists() || stamp.readText() != image.sha256) {
            paths.downloads.listFiles()?.forEach { it.delete() }
            stamp.writeText(image.sha256)
        }
        download(baseUrl, image, dest)
        val sig = File(paths.downloads, "${image.file}.minisig")
        verify(dest, image, sig, fetchOptional(baseUrl + image.file + ".minisig", sig))
        unpack(dest, image.unpackedSize, image.files)
        paths.downloads.deleteRecursively()
    }

    /** Install from a .tar.zst the user picked. It can't be verified, the UI says so first. */
    fun installFromFile(file: File) {
        unpack(file, file.length() * 3, 0)
    }

    private fun update(step: Step, fraction: Float, detail: String) {
        if (InstallState.cancelled) throw Cancelled()
        InstallState.update(Snapshot(step, fraction, detail))
    }

    private fun checkSpace(image: ImageManifest.Image) {
        val partial = File(paths.downloads, image.file).length()
        val need = (image.size - partial) + image.unpackedSize + 512L * 1024 * 1024
        val free = paths.files.usableSpace
        check(free >= need) {
            "Not enough space: needs ${gb(need)}, ${gb(free)} free"
        }
    }

    private fun download(baseUrl: String, image: ImageManifest.Image, dest: File) {
        var attempt = 0
        while (true) {
            val have = dest.length()
            if (have >= image.size) break
            try {
                val part = (have / image.partSize).toInt().coerceAtMost(image.parts.lastIndex)
                val within = have - part * image.partSize
                downloadPart(baseUrl + image.parts[part], within, dest, image.size)
                attempt = 0
            } catch (e: Cancelled) {
                throw e
            } catch (e: IOException) {
                attempt++
                if (attempt > 8) throw IOException("Download keeps failing: ${e.message}", e)
                val wait = (2_000L shl (attempt - 1)).coerceAtMost(60_000L)
                AppLog.i("Download interrupted (${e.message}); retrying in ${wait / 1000}s")
                update(Step.DOWNLOAD, have.toFloat() / image.size, "Connection lost, retrying")
                sleepCancellable(wait)
            }
        }
        check(dest.length() == image.size) { "Downloaded ${dest.length()} bytes, expected ${image.size}" }
    }

    /** Appends one part to [dest], starting [offset] bytes into that part. */
    private fun downloadPart(url: String, offset: Long, dest: File, total: Long) {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.instanceFollowRedirects = true
        conn.connectTimeout = 20_000
        conn.readTimeout = 30_000
        if (offset > 0) conn.setRequestProperty("Range", "bytes=$offset-")
        try {
            val code = conn.responseCode
            if (offset > 0 && code == 200) {
                // Server ignored Range: we'd duplicate data, so start this part over.
                FileOutputStream(dest, true).channel.use { it.truncate(dest.length() - offset) }
                throw IOException("Server doesn't support resume; restarting part")
            }
            if (code != 200 && code != 206) throw IOException("HTTP $code for ${url.substringAfterLast('/')}")
            var done = dest.length()
            var lastReport = 0L
            val started = System.nanoTime()
            val startBytes = done
            conn.inputStream.use { input ->
                FileOutputStream(dest, true).use { out ->
                    val buf = ByteArray(1 shl 17)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        done += n
                        val now = System.nanoTime()
                        if (now - lastReport > 250_000_000L) {
                            lastReport = now
                            val secs = (now - started) / 1e9
                            val speed = if (secs > 0) (done - startBytes) / secs else 0.0
                            update(Step.DOWNLOAD, done.toFloat() / total,
                                "${gb(done)} of ${gb(total)} · ${mb(speed.toLong())}/s")
                        }
                    }
                }
            }
        } finally {
            conn.disconnect()
        }
    }

    private fun fetchOptional(url: String, dest: File): Boolean = try {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.instanceFollowRedirects = true
        conn.connectTimeout = 15_000
        if (conn.responseCode == 200) {
            conn.inputStream.use { i -> dest.outputStream().use { i.copyTo(it) } }
            true
        } else false
    } catch (e: IOException) {
        false
    }

    private fun verify(file: File, image: ImageManifest.Image, sig: File, haveSig: Boolean) {
        val key = BuildConfig.IMAGE_PUBLIC_KEY
        if (key.isNotEmpty()) {
            update(Step.VERIFY, -1f, "Checking the signature")
            check(haveSig) { "The system image isn't signed; refusing to install it" }
            val p = ProcessBuilder(paths.ddtool.path, "verify", key, file.path, sig.path)
                .redirectErrorStream(true).start()
            val out = p.inputStream.bufferedReader().readText().trim()
            check(p.waitFor() == 0) { "Signature check failed: $out" }
            AppLog.i("Signature OK: $out")
            return
        }
        check(BuildConfig.DEBUG) { "This build has no image signing key" }
        AppLog.i("Debug build without a signing key: checking SHA-256 only")
        val md = MessageDigest.getInstance("SHA-256")
        var done = 0L
        file.inputStream().use { input ->
            val buf = ByteArray(1 shl 17)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                md.update(buf, 0, n)
                done += n
                if (done % (64L shl 20) < buf.size) update(Step.VERIFY, done.toFloat() / file.length(), "Checking the download")
            }
        }
        val actual = md.digest().joinToString("") { "%02x".format(it) }
        check(actual.equals(image.sha256, ignoreCase = true)) {
            "The download is damaged (checksum mismatch). Try again."
        }
    }

    private fun unpack(file: File, expectedBytes: Long, expectedFiles: Long) {
        update(Step.UNPACK, 0f, "Unpacking")
        val staging = paths.rootfsStaging
        staging.deleteRecursively()
        staging.mkdirs()
        val rootCanon = staging.canonicalPath + File.separator
        val proc = ProcessBuilder(paths.ddtool.path, "zstdcat", file.path).start()
        val errors = StringBuilder()
        Thread { proc.errorStream.bufferedReader().forEachLine { synchronized(errors) { errors.appendLine(it) } } }.start()
        var count = 0L
        val counted = CountingStream(BufferedInputStream(proc.inputStream, 1 shl 17))
        try {
            TarArchiveInputStream(counted).use { tar ->
                while (true) {
                    val entry: TarArchiveEntry = tar.nextEntry ?: break
                    val name = entry.name.removePrefix("./").trimEnd('/')
                    if (name.isEmpty()) continue
                    val out = File(staging, name)
                    // Refuse entries that escape the rootfs (tar-slip).
                    if (!(out.parentFile!!.canonicalPath + File.separator).startsWith(rootCanon)) {
                        AppLog.i("Skipping unsafe path $name"); continue
                    }
                    writeEntry(tar, entry, out, staging)
                    if (++count % 2000 == 0L) {
                        val f = if (expectedFiles > 0) count.toFloat() / expectedFiles
                        else counted.count.toFloat() / expectedBytes
                        update(Step.UNPACK, f.coerceAtMost(0.99f), "$count files")
                    }
                }
            }
        } catch (e: IOException) {
            proc.destroy()
            if (e is Cancelled) throw e
            throw IOException("Unpack failed: ${e.message} ${synchronized(errors) { errors }}".trim(), e)
        }
        check(proc.waitFor() == 0) { "Unpack failed: ${synchronized(errors) { errors }}".trim() }

        update(Step.ACCOUNT, 0.5f, "Setting up your account")
        writeAndroidGlue(staging)
        if (paths.rootfs.exists()) {
            // Keep /home if this is a reinstall over an older image.
            val oldHome = File(paths.rootfs, "home")
            if (oldHome.exists()) {
                File(staging, "home").deleteRecursively()
                check(oldHome.renameTo(File(staging, "home"))) { "Could not keep your home folder" }
            }
            paths.rootfs.deleteRecursively()
        }
        check(staging.renameTo(paths.rootfs)) { "Could not move the system into place" }
        InstallState.update(Snapshot(Step.DONE, 1f, "$count files"))
    }

    private fun writeEntry(tar: TarArchiveInputStream, entry: TarArchiveEntry, out: File, root: File) {
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
                val target = File(root, entry.linkName.removePrefix("./"))
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
    }

    /** Files that must reflect the Android side rather than the build machine. */
    private fun writeAndroidGlue(root: File) {
        File(root, "etc/resolv.conf").apply { delete(); writeText("nameserver 1.1.1.1\nnameserver 8.8.8.8\n") }
        File(root, "etc/hosts").writeText("127.0.0.1 localhost\n::1 localhost\n127.0.1.1 deskdroid\n")
        File(root, "tmp").apply { mkdirs(); chmod(this, 0b111_111_111) }
        val tz = TimeZone.getDefault().id
        if (File(root, "usr/share/zoneinfo/$tz").exists()) {
            File(root, "etc/timezone").writeText("$tz\n")
            File(root, "etc/localtime").delete()
            Os.symlink("/usr/share/zoneinfo/$tz", File(root, "etc/localtime").path)
        }
    }

    private fun chmod(f: File, mode: Int) {
        // Drop setuid/setgid/sticky: meaningless under proot and refused by some kernels.
        try { Os.chmod(f.path, mode and 0b111_111_111 or 0b110_000_000) } catch (_: Exception) {}
    }

    private fun sleepCancellable(ms: Long) {
        val end = System.currentTimeMillis() + ms
        while (System.currentTimeMillis() < end) {
            if (InstallState.cancelled) throw Cancelled()
            Thread.sleep(250)
        }
    }

    private class CountingStream(input: InputStream) : FilterInputStream(input) {
        var count = 0L
        override fun read(): Int = super.read().also { if (it >= 0) count++ }
        override fun read(b: ByteArray, off: Int, len: Int): Int =
            super.read(b, off, len).also { if (it > 0) count += it }
    }

    companion object {
        fun gb(b: Long) = "%.1f GB".format(b / 1e9)
        fun mb(b: Long) = "%.1f MB".format(b / 1e6)
    }
}
