package io.deskdroid.app

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.zip.ZipInputStream

/**
 * Software, DeskDroid's app store: KDE apps built for Android like the ones in the APK
 * (libraries started by QtHost), downloaded instead of shipped. CI publishes
 * each app as <id>.zip with index.json, the catalog (native/nativedesk/build.sh):
 *
 *   lib/    the app's library and the libraries only it needs. They live in
 *           store/apps/<id>/lib, read-only (Android loads app code only from
 *           read-only files); qtapp.sh starts the app from there.
 *   share/  its menu entry, icons and data, into ~/.local/share, where KDE
 *           looks first and Plasma's menu sees new apps at once. The files an
 *           app put there are listed in store/apps/<id>/files.txt.
 *
 * Or, for a program like GIMP, a whole folder instead of lib/:
 *
 *   program/      its programs, plug-ins, libraries and data, into
 *                 store/apps/<id>/program, read-only, the ELF files marked
 *                 executable (GIMP looks for its plug-ins that way). Android
 *                 runs them through its linker (store-program.sh).
 *   program.txt   its main program, relative to program/.
 *   program.env   variables it needs, @PROGRAM@ standing for program/'s path.
 *
 * Or, for a theme, share/ alone, with open.txt: the command Open runs
 * (Global Theme, to pick it).
 *
 * Every package also has app.txt (its id) and app.json (id, name, summary,
 * version). A package on its own, as a file, is an .adpk ("DeskDroid
 * package", like a .deb): the same zip. Software installs one from a file
 * (installFile), on the phone (StoreActivity) and on the desktop (the
 * desktop's Software app, through SoftwareBridge).
 */
object Store {
    data class App(
        val id: String, val name: String, val summary: String, val version: String,
        val size: Long, val sha256: String, val file: String, val icon: String,
        // Packages it needs installed first (a Flathub app's runtimes), and
        // "runtime" for those: Software installs them when an app needs them.
        val needs: List<String> = emptyList(), val kind: String = "",
        // Where it comes from: "flathub" (Flathub's own ARM64 build, run
        // through ddmask), else DeskDroid's own builds. See [section].
        val source: String = "",
    )

    /**
     * Software's tabs: "deskdroid" (DeskDroid Repo: apps built for DeskDroid),
     * "flathub" (Flathub's builds, unchanged, run through ddmask) and
     * "dependencies" (runtimes those apps need). A catalog entry may say
     * "source": "flathub"; one that needs a runtime is a Flathub app too.
     */
    fun section(a: App): String = when {
        a.kind == "runtime" || a.id.startsWith("runtime-") -> "dependencies"
        a.source == "flathub" || a.needs.any { it.startsWith("runtime-") } -> "flathub"
        else -> "deskdroid"
    }

    private fun ids(a: JSONObject?, key: String): List<String> =
        a?.optJSONArray(key)?.let { arr -> (0 until arr.length()).map { arr.getString(it) } }.orEmpty()

    /**
     * Where the catalog is, in order: the build's own (store-latest, or a pull
     * request's store-pr-N), then the copy published with pull request 31,
     * which is where the store has been since main stopped being built on
     * GitHub. The first that answers is used until the next catalog read.
     */
    val baseUrls: List<String> get() = listOf(BuildConfig.STORE_BASE_URL, FALLBACK_URL).distinct()
    private const val FALLBACK_URL = "https://github.com/ffseestevanli-oss/deskdroid/releases/download/store-pr-31/"
    @Volatile private var activeUrl: String? = null
    val baseUrl: String get() = activeUrl ?: BuildConfig.STORE_BASE_URL

    private fun root(c: Context) = File(c.filesDir, "store/apps")
    private fun dataHome(c: Context) = File(c.filesDir, ".local/share")

    fun installed(c: Context): Set<String> =
        root(c).listFiles { f -> File(f, "app.txt").exists() }?.map { it.name }?.toSet().orEmpty()

    /** The catalog (blocking: call off the main thread), from the first of [baseUrls] that has one. */
    fun catalog(): List<App> {
        var failure: Exception? = null
        for (url in baseUrls) {
            val json = try {
                JSONObject(fetch(url + "index.json").toString(Charsets.UTF_8))
            } catch (e: Exception) {
                AppLog.i("Agora: no catalog at $url: ${e.message}")
                if (failure == null) failure = e
                continue
            }
            if (activeUrl != url) AppLog.i("Agora: catalog from $url")
            activeUrl = url
            val apps = json.getJSONArray("apps")
            return (0 until apps.length()).map { i ->
                val a = apps.getJSONObject(i)
                App(a.getString("id"), a.optString("name", a.getString("id")), a.optString("summary"),
                    a.optString("version"), a.optLong("size"), a.getString("sha256"), a.getString("file"), a.optString("icon"),
                    ids(a, "needs"), a.optString("kind"), a.optString("source"))
            }.sortedBy { it.name.lowercase() }
        }
        throw failure ?: Exception("no catalog")
    }

    fun installedVersion(c: Context, id: String): String? =
        File(root(c), "$id/version.txt").takeIf { File(root(c), "$id/app.txt").exists() && it.exists() }?.readText()?.trim()

    /** What an .adpk file is, from its app.json (or app.txt and its menu entry, for older packages). */
    data class Package(val id: String, val name: String, val summary: String, val version: String, val icon: ByteArray?,
                       val needs: List<String> = emptyList())

    private val ID = Regex("[A-Za-z0-9][A-Za-z0-9._+-]{0,63}")

    fun inspect(file: File): Package {
        var manifest: JSONObject? = null
        var id: String? = null
        var desktop: String? = null
        var metainfo: String? = null
        val icons = sortedMapOf<Int, ByteArray>()
        var hasCode = false
        ZipInputStream(file.inputStream().buffered()).use { z ->
            while (true) {
                val e = z.nextEntry ?: break
                if (e.isDirectory) continue
                val n = e.name
                when {
                    n == "app.json" -> manifest = JSONObject(z.readBytes().toString(Charsets.UTF_8))
                    n == "app.txt" -> id = z.readBytes().toString(Charsets.UTF_8).trim()
                    n.startsWith("share/applications/") && n.endsWith(".desktop") && desktop == null -> desktop = z.readBytes().toString(Charsets.UTF_8)
                    n.startsWith("share/metainfo/") && metainfo == null -> metainfo = z.readBytes().toString(Charsets.UTF_8)
                    n.startsWith("share/icons/hicolor/") && n.endsWith(".png") && "/apps/" in n ->
                        n.split('/').getOrNull(3)?.substringBefore('x')?.toIntOrNull()?.let { icons[it] = z.readBytes() }
                    n.startsWith("lib/") || n.startsWith("program/") -> hasCode = true
                }
            }
        }
        val m = manifest
        val pkgId = m?.optString("id")?.ifEmpty { null } ?: id
        if (pkgId == null || !ID.matches(pkgId) || !hasCode) throw Exception("this isn't a DeskDroid package (.adpk)")
        fun entry(key: String) = desktop?.lineSequence()?.firstOrNull { it.startsWith("$key=") }?.substringAfter('=')
        val version = m?.optString("version")?.ifEmpty { null }
            ?: metainfo?.let { Regex("<release[^>]*version=\"([^\"]+)\"").find(it)?.groupValues?.get(1) } ?: ""
        // The icon nearest 128 px, as the catalog's.
        val icon = icons.entries.minByOrNull { kotlin.math.abs(it.key - 128) }?.value
        return Package(pkgId, m?.optString("name")?.ifEmpty { null } ?: entry("Name") ?: pkgId,
            m?.optString("summary")?.ifEmpty { null } ?: entry("GenericName") ?: entry("Comment") ?: "", version, icon,
            ids(m, "needs"))
    }

    /** Installs an .adpk file (blocking). The file itself is left where it is. */
    fun installFile(c: Context, file: File): Package {
        val pkg = inspect(file)
        installNeeds(c, pkg.id, pkg.needs, mutableSetOf(pkg.id))
        val copy = File(c.cacheDir, "adpk-${pkg.id}.zip")
        file.inputStream().use { i -> copy.outputStream().use { i.copyTo(it) } }
        installZip(c, App(pkg.id, pkg.name, pkg.summary, pkg.version, copy.length(), "", copy.name, ""), copy)
        return pkg
    }

    fun icon(app: App): ByteArray? = if (app.icon.isEmpty()) null else try { fetch(baseUrl + app.icon) } catch (e: Exception) { null }

    /** Downloads, checks and installs an app (blocking). [progress] gets 0..1. */
    fun install(c: Context, app: App, progress: (Float) -> Unit = {}) = install(c, app, progress, mutableSetOf(app.id))

    private fun install(c: Context, app: App, progress: (Float) -> Unit, seen: MutableSet<String>) {
        val zip = File(c.cacheDir, "store-${app.id}.zip")
        if (!ID.matches(app.id)) throw Exception("bad app id")
        installNeeds(c, app.id, app.needs, seen, progress)
        download(baseUrl + app.file, zip, app.size, progress)
        if (sha256(zip) != app.sha256) {
            // The store may have been republished since the catalog was read
            // (a new build replaces every package): read it again and retry once.
            val fresh = runCatching { catalog().firstOrNull { it.id == app.id } }.getOrNull()
            if (fresh == null || fresh.sha256 == app.sha256) { zip.delete(); throw Exception("the download is damaged (checksum)") }
            AppLog.i("Store: ${app.id} changed on the server; downloading it again")
            download(baseUrl + fresh.file, zip, fresh.size, progress)
            if (sha256(zip) != fresh.sha256) { zip.delete(); throw Exception("the download is damaged (checksum)") }
            return installZip(c, fresh, zip)
        }
        installZip(c, app, zip)
    }

    /**
     * The packages [forId] needs (its runtimes), from the catalog, each before
     * it and only when it isn't installed yet. [seen] stops a loop.
     */
    private fun installNeeds(c: Context, forId: String, needs: List<String>, seen: MutableSet<String>,
                            progress: (Float) -> Unit = {}) {
        val missing = needs.filter { it !in installed(c) && seen.add(it) }
        if (missing.isEmpty()) return
        val cat = try { catalog() } catch (e: Exception) {
            throw Exception("it needs ${missing.joinToString()} first, and the catalog can't be reached (${e.message})")
        }
        for (id in missing) {
            val dep = cat.firstOrNull { it.id == id }
                ?: throw Exception("it needs $id, which isn't in the catalog (install $id.adpk from a file first)")
            AppLog.i("Agora: installing ${dep.id} ${dep.version} first, for $forId")
            install(c, dep, progress, seen)
        }
    }

    private fun sha256(f: File): String = MessageDigest.getInstance("SHA-256").let { md ->
        f.inputStream().use { s -> val b = ByteArray(1 shl 16); while (true) { val n = s.read(b); if (n < 0) break; md.update(b, 0, n) } }
        md.digest().joinToString("") { "%02x".format(it) }
    }

    private fun installZip(c: Context, app: App, zip: File) {
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
                    e.name.startsWith("program/") || e.name == "program.txt" || e.name == "program.env" || e.name == "open.txt" -> File(dir, e.name)
                    e.name.startsWith("share/") -> File(share, e.name.removePrefix("share/")).also { files += it.path }
                    e.name == "app.txt" || e.name == "app.json" -> null
                    else -> null
                } ?: continue
                out.parentFile?.mkdirs()
                out.outputStream().use { z.copyTo(it) }
                if (out.parentFile == lib) out.setReadOnly()
                if (e.name.startsWith("program/")) {
                    if (isElf(out)) out.setExecutable(true, false)
                    out.setReadOnly()
                }
            }
        }
        zip.delete()
        File(dir, "files.txt").writeText(files.joinToString("\n"))
        File(dir, "version.txt").writeText(app.version)
        if (app.id == "firefox") Etherium.applySettings(c) // its current settings, over the ones it was built with
        File(dir, "app.txt").writeText(app.id) // last: the app counts as installed from here on
        linkCommand(c, app.id)
        AppLog.i("Agora: installed ${app.id} ${app.version}")
    }

    fun uninstall(c: Context, id: String) {
        val dir = File(root(c), id)
        if (!dir.exists()) return
        File(dir, "app.txt").delete()
        File(dir, "files.txt").takeIf { it.exists() }?.readLines()?.forEach { if (it.isNotBlank()) File(it).delete() }
        File(dir, "lib").listFiles()?.forEach { it.setWritable(true) }
        File(dir, "program").walkTopDown().forEach { it.setWritable(true) }
        dir.deleteRecursively()
        File(c.filesDir, "kwin/bin/$id").delete()
        AppLog.i("Store: removed $id")
    }

    /** The app's command (bin/<id>, what its menu entry runs) while the desktop runs. */
    fun linkCommand(c: Context, id: String) {
        val bin = File(c.filesDir, "kwin/bin")
        if (!bin.isDirectory) return // linked when the desktop starts (NativeDesk.linkApps)
        if (openCommand(c, id) != null) return // a theme or other data: Open runs its open.txt
        val cmd = File(bin, id)
        if (cmd.exists()) return
        try {
            // A program (GIMP...) starts through store-program.sh, a library through QtHost (qtapp.sh).
            val launcher = if (File(root(c), "$id/program.txt").exists()) "libdd_store-program.so" else "libdd_qtapp.so"
            android.system.Os.symlink(File(c.applicationInfo.nativeLibraryDir, launcher).path, cmd.path)
        } catch (e: Exception) {
            AppLog.i("Store: couldn't link $id: $e")
        }
    }

    /** What Open runs for a package with no program of its own (a theme: open.txt), or null. */
    fun openCommand(c: Context, id: String): String? =
        File(root(c), "$id/open.txt").takeIf { it.exists() }?.readText()?.trim()?.takeIf { it.isNotEmpty() }

    private fun isElf(f: File): Boolean = try {
        f.inputStream().use { s -> val b = ByteArray(4); s.read(b) == 4 && b[0] == 0x7f.toByte() && b[1] == 'E'.code.toByte() && b[2] == 'L'.code.toByte() && b[3] == 'F'.code.toByte() }
    } catch (e: Exception) { false }

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
