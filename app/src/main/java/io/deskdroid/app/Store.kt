package io.deskdroid.app

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.zip.ZipInputStream

/**
 * DeskDroid's app store: KDE apps built for Android like the ones in the APK
 * (libraries started by QtHost), downloaded instead of shipped. CI publishes
 * each app as <id>.zip with index.json, the catalog (native/nativedesk/build.sh):
 *
 *   lib/    the app's library and the libraries only it needs. They live in
 *           store/apps/<id>/lib, read-only (Android loads app code only from
 *           read-only files); qtapp.sh starts the app from there.
 *   share/  its menu entry, icons and data, into ~/.local/share, where KDE
 *           looks first and Plasma's menu sees new apps at once. The files an
 *           app put there are listed in store/apps/<id>/files.txt.
 */
object Store {
    data class App(
        val id: String, val name: String, val summary: String, val version: String,
        val size: Long, val sha256: String, val file: String, val icon: String,
    )

    val baseUrl: String get() = BuildConfig.STORE_BASE_URL

    private fun root(c: Context) = File(c.filesDir, "store/apps")
    private fun dataHome(c: Context) = File(c.filesDir, ".local/share")

    fun installed(c: Context): Set<String> =
        root(c).listFiles { f -> File(f, "app.txt").exists() }?.map { it.name }?.toSet().orEmpty()

    /** The catalog (blocking: call off the main thread). */
    fun catalog(): List<App> {
        val json = JSONObject(fetch(baseUrl + "index.json").toString(Charsets.UTF_8))
        val apps = json.getJSONArray("apps")
        return (0 until apps.length()).map { i ->
            val a = apps.getJSONObject(i)
            App(a.getString("id"), a.optString("name", a.getString("id")), a.optString("summary"),
                a.optString("version"), a.optLong("size"), a.getString("sha256"), a.getString("file"), a.optString("icon"))
        }
    }

    fun icon(app: App): ByteArray? = if (app.icon.isEmpty()) null else try { fetch(baseUrl + app.icon) } catch (e: Exception) { null }

    /** Downloads, checks and installs an app (blocking). [progress] gets 0..1. */
    fun install(c: Context, app: App, progress: (Float) -> Unit = {}) {
        val zip = File(c.cacheDir, "store-${app.id}.zip")
        download(baseUrl + app.file, zip, app.size, progress)
        val sha = MessageDigest.getInstance("SHA-256").let { md ->
            zip.inputStream().use { s -> val b = ByteArray(1 shl 16); while (true) { val n = s.read(b); if (n < 0) break; md.update(b, 0, n) } }
            md.digest().joinToString("") { "%02x".format(it) }
        }
        if (sha != app.sha256) { zip.delete(); throw Exception("the download is damaged (checksum)") }
        uninstall(c, app.id) // an update replaces the old files
        val dir = File(root(c), app.id).apply { mkdirs() }
        val lib = File(dir, "lib").apply { mkdirs() }
        val share = dataHome(c)
        val files = mutableListOf<String>()
        ZipInputStream(zip.inputStream().buffered()).use { z ->
            while (true) {
                val e = z.nextEntry ?: break
                if (e.isDirectory || e.name.contains("..")) continue
                val out = when {
                    e.name.startsWith("lib/") -> File(lib, e.name.removePrefix("lib/"))
                    e.name.startsWith("share/") -> File(share, e.name.removePrefix("share/")).also { files += it.path }
                    e.name == "app.txt" -> null
                    else -> null
                } ?: continue
                out.parentFile?.mkdirs()
                out.outputStream().use { z.copyTo(it) }
                if (out.parentFile == lib) out.setReadOnly()
            }
        }
        zip.delete()
        File(dir, "files.txt").writeText(files.joinToString("\n"))
        File(dir, "version.txt").writeText(app.version)
        File(dir, "app.txt").writeText(app.id) // last: the app counts as installed from here on
        linkCommand(c, app.id)
        AppLog.i("Store: installed ${app.id} ${app.version}")
    }

    fun uninstall(c: Context, id: String) {
        val dir = File(root(c), id)
        if (!dir.exists()) return
        File(dir, "app.txt").delete()
        File(dir, "files.txt").takeIf { it.exists() }?.readLines()?.forEach { if (it.isNotBlank()) File(it).delete() }
        File(dir, "lib").listFiles()?.forEach { it.setWritable(true) }
        dir.deleteRecursively()
        File(c.filesDir, "kwin/bin/$id").delete()
        AppLog.i("Store: removed $id")
    }

    /** The app's command (bin/<id>, what its menu entry runs) while the desktop runs. */
    fun linkCommand(c: Context, id: String) {
        val bin = File(c.filesDir, "kwin/bin")
        if (!bin.isDirectory) return // linked when the desktop starts (NativeDesk.linkApps)
        val cmd = File(bin, id)
        if (cmd.exists()) return
        try {
            android.system.Os.symlink(File(c.applicationInfo.nativeLibraryDir, "libdd_qtapp.so").path, cmd.path)
        } catch (e: Exception) {
            AppLog.i("Store: couldn't link $id: $e")
        }
    }

    private fun connect(url: String): HttpURLConnection {
        var u = URL(url)
        repeat(5) {
            val conn = u.openConnection() as HttpURLConnection
            conn.connectTimeout = 15000
            conn.readTimeout = 30000
            conn.instanceFollowRedirects = true
            val code = conn.responseCode
            if (code in 300..399) { u = URL(u, conn.getHeaderField("Location")); conn.disconnect(); return@repeat }
            if (code != 200) throw Exception("HTTP $code for ${u.path.substringAfterLast('/')}")
            return conn
        }
        throw Exception("too many redirects")
    }

    private fun fetch(url: String): ByteArray = connect(url).let { c -> c.inputStream.use { it.readBytes() }.also { c.disconnect() } }

    private fun download(url: String, to: File, size: Long, progress: (Float) -> Unit) {
        val conn = connect(url)
        val total = conn.contentLengthLong.takeIf { it > 0 } ?: size
        conn.inputStream.use { input ->
            to.outputStream().use { out ->
                val b = ByteArray(1 shl 16)
                var done = 0L
                while (true) {
                    val n = input.read(b)
                    if (n < 0) break
                    out.write(b, 0, n)
                    done += n
                    if (total > 0) progress(done.toFloat() / total)
                }
            }
        }
        conn.disconnect()
    }
}
