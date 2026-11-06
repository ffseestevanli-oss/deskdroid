package io.deskdroid.app

import android.content.Context
import android.os.StatFs
import android.system.Os
import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * x86 and x86-64 Linux programs on the native desktop (no proot), and Steam
 * through them (experimental). FEX-Emu runs them: it is an ordinary ARM64
 * Linux (glibc) program, which ddmask starts through DeskDroid's glibc, and
 * ddmask hands it every x86 program it is asked to start (DDMASK_X86_64,
 * DDMASK_I386). FEX's patch (fex/patches) makes its own execs go through
 * ddmask too.
 *
 * Both parts come from the fex-latest release (.github/workflows/fex.yml) the
 * first time they're needed, not with the APK:
 *
 *   files/x86/fex     FEX (fex/build.sh: its usr/local)
 *   files/x86/rootfs  the x86 system x86 programs see as / (fex/rootfs.sh:
 *                     FEX's Ubuntu 24.04 image with Xwayland, about 4 GB)
 *   files/x86/bin     deskdroid-steam (the menu entry's launcher) and
 *                     steam-x86.sh (its x86 half), from assets/x86
 *
 * deskdroid-steam asks for the download with `android-open deskdroid:x86-install`
 * and follows install.log until install.state says done or failed.
 */
object X86 {
    private const val RELEASE = "https://github.com/ffseestevanli-oss/deskdroid/releases/download/fex-latest/"
    private const val FEX = "deskdroid-fex-arm64.tar.zst"
    private const val ROOTFS = "deskdroid-x86-rootfs.tar.zst"
    // The rootfs unpacks to about 4 GB; the download is kept until it's unpacked.
    private const val NEED_BYTES = 6_000_000_000L
    private val SCRIPTS = listOf("deskdroid-steam", "steam-x86.sh")

    fun dir(c: Context) = File(c.filesDir, "x86")
    private fun fexDir(c: Context) = File(dir(c), "fex")
    fun rootfs(c: Context) = File(dir(c), "rootfs")
    fun interpreter(c: Context) = File(fexDir(c), "bin/FEXInterpreter")
    fun installed(c: Context) = File(dir(c), "ready").exists() && interpreter(c).exists()

    @Volatile private var installing = false

    /** ddmask's settings for x86 programs, for the desktop's environment. */
    fun env(c: Context, env: MutableMap<String, String>) {
        env["DESKDROID_X86"] = dir(c).path
        if (!installed(c)) return
        env["DDMASK_X86_64"] = interpreter(c).path
        env["DDMASK_I386"] = interpreter(c).path
        env["FEX_ROOTFS"] = rootfs(c).path
    }

    /** At each desktop start: the launchers, the menu entry, and the x86 system's /etc for this phone. */
    fun prepare(c: Context) {
        try {
            val bin = File(dir(c), "bin").apply { mkdirs() }
            for (name in SCRIPTS) {
                val f = File(bin, name)
                c.assets.open("x86/$name").use { input -> f.outputStream().use { input.copyTo(it) } }
                f.setExecutable(true, false)
            }
            File(c.filesDir, ".local/share/applications").apply { mkdirs() }
                .resolve("deskdroid-steam.desktop").writeText(
                    "[Desktop Entry]\n# Written by DeskDroid (X86.kt) at each start.\nType=Application\n" +
                    "Name=Steam (experimental)\nComment=Valve's x86 Steam client through FEX-Emu\n" +
                    "Exec=${File(bin, "deskdroid-steam").path} %U\nIcon=applications-games\nTerminal=false\n" +
                    "Categories=Game;\nMimeType=x-scheme-handler/steam;x-scheme-handler/steamlink;\n" +
                    "StartupWMClass=Xwayland\nKeywords=games;x86;FEX;\n")
            if (installed(c)) writeEtc(c)
        } catch (e: Exception) {
            AppLog.i("x86: couldn't prepare: $e")
        }
    }

    /** /etc files FEX's image leaves to the host, which Android doesn't have. */
    private fun writeEtc(c: Context) {
        val etc = File(rootfs(c), "etc").apply { mkdirs() }
        val uid = android.os.Process.myUid()
        val home = c.filesDir.path
        fun withBase(name: String, line: String) {
            val base = File(etc, "$name.deskdroid-base").takeIf { it.exists() }?.readText().orEmpty()
            File(etc, name).writeText(base.trimEnd('\n') + "\n" + line + "\n")
        }
        withBase("passwd", "deskdroid:x:$uid:$uid:DeskDroid:$home:/bin/bash")
        withBase("group", "deskdroid:x:$uid:")
        val dns = try {
            val cm = c.getSystemService(android.net.ConnectivityManager::class.java)
            cm.getLinkProperties(cm.activeNetwork)?.dnsServers?.mapNotNull { it.hostAddress?.substringBefore('%') }.orEmpty()
        } catch (e: Exception) { emptyList() }
        File(etc, "resolv.conf").writeText(dns.ifEmpty { listOf("8.8.8.8", "1.1.1.1") }.joinToString("") { "nameserver $it\n" })
        File(etc, "hosts").writeText("127.0.0.1 localhost\n::1 localhost\n127.0.1.1 deskdroid\n")
        File(etc, "hostname").writeText("deskdroid\n")
        File(etc, "machine-id").takeIf { !it.exists() }?.writeText(java.util.UUID.randomUUID().toString().replace("-", "") + "\n")
        File(rootfs(c), "tmp").mkdirs()
    }

    /** Downloads and unpacks FEX and the x86 system, off the main thread (deskdroid:x86-install). */
    fun installAsync(c: Context) {
        synchronized(this) {
            if (installing) return
            installing = true
        }
        val app = c.applicationContext
        Thread {
            val log = File(dir(app), "install.log")
            val state = File(dir(app), "install.state")
            try {
                dir(app).mkdirs()
                log.writeText("")
                state.writeText("running\n")
                install(app) { line ->
                    AppLog.i("x86: $line")
                    log.appendText(line + "\n")
                }
                state.writeText("done\n")
            } catch (e: Exception) {
                AppLog.i("x86: install failed: $e")
                log.appendText("failed: ${e.message ?: e}\n")
                state.writeText("failed: ${e.message ?: e}\n")
            } finally {
                installing = false
            }
        }.apply { isDaemon = true }.start()
    }

    private fun install(c: Context, say: (String) -> Unit) {
        File(dir(c), "ready").delete()
        val cache = File(c.cacheDir, "x86").apply { mkdirs() }

        say("Downloading FEX-Emu")
        val fex = download(c, FEX, cache, say)
        say("Unpacking FEX-Emu")
        val fexStaging = File(dir(c), "fex.new").also { removeTree(it) }
        untar(c, fex, fexStaging, strip = "usr/local/", files = 0, say = say)
        fex.delete()
        removeTree(fexDir(c))
        check(fexStaging.renameTo(fexDir(c))) { "couldn't move FEX-Emu into place" }
        check(interpreter(c).exists()) { "no FEXInterpreter in the download" }

        val version = try { fetch("$RELEASE${ROOTFS.removeSuffix(".tar.zst")}.version").trim() } catch (e: Exception) { "" }
        val current = File(rootfs(c), "etc/deskdroid-x86-version").takeIf { it.exists() }?.readText()?.trim()
        if (current != null && current == version) {
            say("The x86 system ($current) is up to date")
        } else {
            // A new x86 system replaces the old one: make room first.
            removeTree(rootfs(c))
            val free = StatFs(c.filesDir.path).availableBytes
            check(free >= NEED_BYTES) { "the x86 system needs about ${NEED_BYTES / 1_000_000_000} GB free, only ${free / 1_000_000_000} GB left" }
            val files = try { fetch("$RELEASE${ROOTFS.removeSuffix(".tar.zst")}.files").trim().toLong() } catch (e: Exception) { 0L }
            say("Downloading the x86 system (Ubuntu 24.04 for x86, about 1.2 GB)")
            val tar = download(c, ROOTFS, cache, say)
            say("Unpacking the x86 system (about 4 GB, this takes a few minutes)")
            val staging = File(dir(c), "rootfs.new").also { removeTree(it) }
            untar(c, tar, staging, strip = "", files = files, say = say)
            tar.delete()
            check(staging.renameTo(rootfs(c))) { "couldn't move the x86 system into place" }
        }
        writeEtc(c)
        File(dir(c), "ready").writeText(File(fexDir(c), "share/deskdroid-fex/version").takeIf { it.exists() }?.readText() ?: "")
        say("Ready")
    }

    // ---- downloads ----

    private fun connect(url: String): HttpURLConnection {
        var u = URL(url)
        repeat(6) {
            val conn = u.openConnection() as HttpURLConnection
            conn.connectTimeout = 20000
            conn.readTimeout = 60000
            conn.instanceFollowRedirects = false
            val code = conn.responseCode
            if (code in 300..399) { u = URL(u, conn.getHeaderField("Location")); conn.disconnect(); return@repeat }
            if (code != 200) throw Exception("HTTP $code for ${u.path.substringAfterLast('/')} (is the fex-latest release published?)")
            return conn
        }
        throw Exception("too many redirects")
    }

    private fun fetch(url: String): String = connect(url).let { c -> c.inputStream.use { it.readBytes() }.also { c.disconnect() }.toString(Charsets.UTF_8) }

    /** Downloads RELEASE/name into dir and checks it against name.sha256. */
    private fun download(c: Context, name: String, dir: File, say: (String) -> Unit): File {
        val expected = fetch("$RELEASE$name.sha256").trim().substringBefore(' ').lowercase()
        val out = File(dir, name)
        val md = MessageDigest.getInstance("SHA-256")
        val conn = connect("$RELEASE$name")
        val total = conn.contentLengthLong
        var done = 0L
        var lastPercent = -10
        conn.inputStream.use { input ->
            FileOutputStream(out).use { o ->
                val b = ByteArray(1 shl 16)
                while (true) {
                    val n = input.read(b)
                    if (n < 0) break
                    o.write(b, 0, n)
                    md.update(b, 0, n)
                    done += n
                    val percent = if (total > 0) (done * 100 / total).toInt() else -1
                    if (percent >= lastPercent + 10) {
                        lastPercent = percent
                        say("  $percent% of ${total / 1_000_000} MB")
                    }
                }
            }
        }
        conn.disconnect()
        val actual = md.digest().joinToString("") { "%02x".format(it) }
        if (actual != expected) {
            out.delete()
            throw Exception("$name is damaged (checksum), try again")
        }
        return out
    }

    // ---- unpacking ----

    /** Unpacks a .tar.zst (ddtool zstdcat) into dest, dropping `strip` from names. */
    private fun untar(c: Context, file: File, dest: File, strip: String, files: Long, say: (String) -> Unit) {
        dest.mkdirs()
        val root = dest.canonicalPath + File.separator
        val ddtool = File(c.applicationInfo.nativeLibraryDir, "libddtool.so")
        val proc = ProcessBuilder(ddtool.path, "zstdcat", file.path).start()
        val errors = StringBuilder()
        Thread { proc.errorStream.bufferedReader().forEachLine { synchronized(errors) { errors.appendLine(it) } } }.start()
        var count = 0L
        var lastPercent = -10
        try {
            TarArchiveInputStream(BufferedInputStream(proc.inputStream, 1 shl 17)).use { tar ->
                while (true) {
                    val entry: TarArchiveEntry = tar.nextEntry ?: break
                    var name = entry.name.removePrefix("./").trimEnd('/')
                    if (strip.isNotEmpty()) {
                        if (!name.startsWith(strip)) continue
                        name = name.removePrefix(strip)
                    }
                    if (name.isEmpty()) continue
                    val out = File(dest, name)
                    if (!(out.parentFile!!.canonicalPath + File.separator).startsWith(root)) continue // tar-slip
                    write(tar, entry, out, dest, strip)
                    count++
                    if (files > 0) {
                        val percent = (count * 100 / files).toInt()
                        if (percent >= lastPercent + 10) { lastPercent = percent; say("  $percent%") }
                    }
                }
            }
        } catch (e: Exception) {
            proc.destroy()
            throw Exception("unpacking ${file.name} failed: ${e.message} ${synchronized(errors) { errors }}".trim(), e)
        }
        check(proc.waitFor() == 0) { "unpacking ${file.name} failed: ${synchronized(errors) { errors }}".trim() }
    }

    private fun write(tar: TarArchiveInputStream, entry: TarArchiveEntry, out: File, root: File, strip: String) {
        when {
            entry.isDirectory -> { out.mkdirs(); chmod(out, entry.mode or 0b111_000_000) }
            entry.isSymbolicLink -> {
                out.parentFile!!.mkdirs()
                out.delete()
                // Absolute links point into the x86 system: FEX resolves them inside it.
                Os.symlink(entry.linkName, out.path)
            }
            entry.isLink -> {
                // Hard links aren't reliable in app storage: a copy.
                val target = File(root, entry.linkName.removePrefix("./").removePrefix(strip))
                out.parentFile!!.mkdirs()
                if (target.exists()) { target.copyTo(out, overwrite = true); chmod(out, entry.mode) }
            }
            entry.isFile -> {
                out.parentFile!!.mkdirs()
                FileOutputStream(out).use { tar.copyTo(it, 1 shl 16) }
                chmod(out, entry.mode)
            }
            else -> Unit // device nodes and fifos: FEX passes the host's /dev through
        }
    }

    /** Deletes a folder without following its symlinks (the x86 system's absolute ones point outside it). */
    private fun removeTree(f: File) {
        val path = f.toPath()
        if (!java.nio.file.Files.exists(path, java.nio.file.LinkOption.NOFOLLOW_LINKS)) return
        java.nio.file.Files.walkFileTree(path, object : java.nio.file.SimpleFileVisitor<java.nio.file.Path>() {
            override fun visitFile(file: java.nio.file.Path, attrs: java.nio.file.attribute.BasicFileAttributes): java.nio.file.FileVisitResult {
                java.nio.file.Files.deleteIfExists(file)
                return java.nio.file.FileVisitResult.CONTINUE
            }
            override fun visitFileFailed(file: java.nio.file.Path, exc: java.io.IOException): java.nio.file.FileVisitResult {
                java.nio.file.Files.deleteIfExists(file)
                return java.nio.file.FileVisitResult.CONTINUE
            }
            override fun postVisitDirectory(dir: java.nio.file.Path, exc: java.io.IOException?): java.nio.file.FileVisitResult {
                java.nio.file.Files.deleteIfExists(dir)
                return java.nio.file.FileVisitResult.CONTINUE
            }
        })
    }

    private fun chmod(f: File, mode: Int) {
        // No setuid/setgid/sticky (meaningless here); always readable and writable by the app.
        try { Os.chmod(f.path, mode and 0b111_111_111 or 0b110_000_000) } catch (_: Exception) {}
    }
}
