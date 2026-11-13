package io.deskdroid.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

/**
 * The desktop's Software app (native/plasma/software) and Store.kt, which
 * does the work: the desktop app asks with a request, like android-open
 * (`deskdroid:software:<what>` in $HOME/open-requests, NativeDesk.kt), and
 * reads the answer from $HOME/software/state.json, which this rewrites after
 * every change. Downloads stay in the app, which already reaches the store.
 *
 *   refresh             read the catalog again (and fetch the icons)
 *   install:<id>        install or update an app from the catalog
 *   remove:<id>         remove an installed app
 *   inspect:<path>      what the .adpk at <path> is: state.json's "package"
 *   adpk:<path>         install the .adpk at <path>
 *   flathub:<category>:<page>:<query>
 *                       a page of all of Flathub (FlathubCatalog): state.json's
 *                       "flathub". No category and no query: the popular list;
 *                       category "native" (ARM64 builds) or "fex" (x86-64 only).
 *                       Installing those is the desktop's flatpak command, which
 *                       Agora runs itself (backend.cpp), so nothing else here.
 *
 * state.json: {"apps": [{id, name, summary, version, size, installed, icon, open,
 * section ("deskdroid" | "flathub" | "dependencies", Software's tabs), kind,
 * needs, neededBy, neededByInstalled (names of the apps that need it)}],
 * "busy": {id: progress 0..1 or -1}, "error": "...", "catalogError": "...",
 * "package": {path, id, name, summary, version, installed, icon} or absent,
 * "flathub": {category, query, page, next (the page "Show more" asks for, 0 at
 * the end), total (-1 for "fex": not known), loading, error, results: [{id, name,
 * summary, description, icon (a file, or ""), arches, developer, verified,
 * license, installs, category}]}, "serial": n}. Icons are files in
 * $HOME/software/icons (Flathub's in icons/flathub).
 */
object SoftwareBridge {
    private val worker = Executors.newSingleThreadExecutor()
    private val lock = Any()
    private var catalog: List<Store.App> = emptyList()
    private var catalogError = ""
    private var error = ""
    private val busy = linkedMapOf<String, Float>()
    private var pkg: JSONObject? = null
    private var serial = 0L
    private var lastWrite = 0L

    // All of Flathub (FlathubCatalog), on threads of its own: a search never
    // waits behind an install. Only the latest search's answer is kept.
    private val flathubWorker = Executors.newSingleThreadExecutor()
    private val iconWorkers = Executors.newFixedThreadPool(4)
    private var flathub = JSONObject().put("results", JSONArray()).put("loading", false)
    private var flathubAsk = 0L

    private fun dir(c: Context) = File(c.filesDir, "software").apply { mkdirs() }
    private fun icons(c: Context) = File(dir(c), "icons").apply { mkdirs() }

    /** A request from the desktop ("deskdroid:software:..."); false if it isn't one. */
    fun handle(c: Context, path: String): Boolean {
        if (!path.startsWith("deskdroid:software")) return false
        val req = path.removePrefix("deskdroid:software").removePrefix(":")
        val what = req.substringBefore(':')
        val arg = req.substringAfter(':', "")
        val app = c.applicationContext
        AppLog.i("Agora: desktop asks for $req")
        when (what) {
            "", "refresh" -> worker.execute { refresh(app) }
            "install" -> { setBusy(app, arg, 0f); worker.execute { install(app, arg) } }
            "remove" -> { setBusy(app, arg, -1f); worker.execute { remove(app, arg) } }
            "inspect" -> worker.execute { inspect(app, arg) }
            "adpk" -> { setBusy(app, "file:$arg", -1f); worker.execute { installFile(app, arg) } }
            "dismiss" -> synchronized(lock) { pkg = null; error = "" }.also { write(app) }
            "flathub" -> {
                // <category>:<page>:<query>, the query last: it may hold colons.
                val parts = arg.split(':', limit = 3)
                flathub(app, parts.getOrElse(0) { "" }, parts.getOrElse(2) { "" }, parts.getOrElse(1) { "1" }.toIntOrNull() ?: 1)
            }
            else -> AppLog.i("Agora: unknown request $req")
        }
        return true
    }

    private fun refresh(c: Context) {
        val r = runCatching { Store.catalog() }
        synchronized(lock) {
            r.onSuccess { catalog = it; catalogError = "" }
            r.onFailure { catalogError = it.message ?: it.toString() }
        }
        write(c)
        // The icons, then the state again with them.
        val dir = icons(c)
        var fetched = false
        for (app in r.getOrNull().orEmpty()) {
            val f = File(dir, "${app.id}.png")
            if (f.exists() && File(dir, "${app.id}.version").takeIf { it.exists() }?.readText() == app.version) continue
            Store.icon(app)?.let { f.writeBytes(it); File(dir, "${app.id}.version").writeText(app.version); fetched = true }
        }
        if (fetched) write(c)
    }

    private fun install(c: Context, id: String) {
        val app = synchronized(lock) { catalog.firstOrNull { it.id == id } }
            ?: runCatching { Store.catalog() }.getOrNull()?.also { synchronized(lock) { catalog = it } }?.firstOrNull { it.id == id }
        if (app == null) {
            finish(c, id, "$id isn't in the catalog")
            return
        }
        val r = runCatching {
            Store.install(c, app) { p ->
                // At most a few writes a second: the desktop app watches the file.
                val now = System.currentTimeMillis()
                if (now - lastWrite > 250) { setBusy(c, id, p) }
            }
        }
        finish(c, id, r.exceptionOrNull()?.let { "Couldn't install ${app.name}: ${it.message}" })
    }

    private fun remove(c: Context, id: String) {
        val r = runCatching { Store.uninstall(c, id) }
        finish(c, id, r.exceptionOrNull()?.let { "Couldn't remove $id: ${it.message}" })
    }

    private fun inspect(c: Context, path: String) {
        val r = runCatching { Store.inspect(File(path)) }
        synchronized(lock) {
            r.onSuccess { p ->
                val icon = p.icon?.let { File(icons(c), "adpk-${p.id}.png").apply { writeBytes(it) }.path } ?: ""
                pkg = JSONObject().put("path", path).put("id", p.id).put("name", p.name).put("summary", p.summary)
                    .put("version", p.version).put("installed", Store.installedVersion(c, p.id) ?: JSONObject.NULL)
                    .put("icon", icon)
                error = ""
            }
            r.onFailure {
                pkg = JSONObject().put("path", path).put("invalid", true)
                error = "Can't open ${File(path).name}: ${it.message}"
            }
        }
        write(c)
    }

    private fun installFile(c: Context, path: String) {
        val r = runCatching { Store.installFile(c, File(path)) }
        r.onSuccess { synchronized(lock) { pkg?.put("installed", it.version)?.put("done", true) } }
        finish(c, "file:$path", r.exceptionOrNull()?.let { "Couldn't install ${File(path).name}: ${it.message}" })
    }

    private fun flathub(c: Context, category: String, query: String, page: Int) {
        val ask = synchronized(lock) {
            flathubAsk++
            flathub.put("category", category).put("query", query).put("page", page).put("loading", true).put("error", "")
            flathubAsk
        }
        write(c)
        flathubWorker.execute {
            if (synchronized(lock) { ask != flathubAsk }) return@execute // a newer search came in
            val r = runCatching { FlathubCatalog.search(query, category, page) }
            val dir = File(icons(c), "flathub").apply { mkdirs() }
            synchronized(lock) {
                if (ask != flathubAsk) return@execute
                r.onSuccess { p ->
                    // A later page adds to what's shown.
                    val results = if (page > 1) flathub.optJSONArray("results") ?: JSONArray() else JSONArray()
                    for (h in p.hits) results.put(h.json(File(dir, "${h.id}.png").takeIf { it.length() > 0 }?.path ?: ""))
                    flathub.put("results", results).put("total", p.total)
                        .put("next", p.next).put("loading", false).put("error", "")
                }
                r.onFailure {
                    flathub.put("loading", false).put("error", it.message ?: it.toString())
                    AppLog.i("Agora: Flathub search failed: $it")
                }
            }
            write(c)
            // The icons, then the state again with them.
            val hits = r.getOrNull()?.hits.orEmpty().filter { !File(dir, "${it.id}.png").exists() }
            if (hits.isEmpty()) return@execute
            val left = java.util.concurrent.atomic.AtomicInteger(hits.size)
            for (h in hits) iconWorkers.execute {
                val f = FlathubCatalog.icon(h, dir)
                synchronized(lock) {
                    val results = flathub.optJSONArray("results") ?: JSONArray()
                    if (f != null) for (i in 0 until results.length()) results.optJSONObject(i)?.let { o ->
                        if (o.optString("id") == h.id) o.put("icon", f.path)
                    }
                }
                // At most a few writes a second, and one at the end.
                if (left.decrementAndGet() == 0 || System.currentTimeMillis() - lastWrite > 300) write(c)
            }
        }
    }

    private fun setBusy(c: Context, id: String, p: Float) {
        synchronized(lock) { busy[id] = p }
        write(c)
    }

    private fun finish(c: Context, id: String, failure: String?) {
        synchronized(lock) {
            busy.remove(id)
            error = failure ?: ""
        }
        if (failure != null) AppLog.i("Agora: $failure")
        write(c)
    }

    /** state.json, written to a temporary file and renamed, so it's never read half written. */
    fun write(c: Context) {
        val json = synchronized(lock) {
            val installed = Store.installed(c)
            val dir = icons(c)
            val apps = JSONArray()
            // Every entry, with its tab (Store.section). Runtimes are listed too,
            // under Dependencies, with the apps that need them.
            for (a in catalog) apps.put(JSONObject().put("id", a.id).put("name", a.name).put("summary", a.summary)
                .put("version", a.version).put("size", a.size)
                .put("installed", if (a.id in installed) Store.installedVersion(c, a.id) ?: "" else JSONObject.NULL)
                .put("icon", File(dir, "${a.id}.png").takeIf { it.exists() }?.path ?: "")
                .put("open", Store.openCommand(c, a.id) ?: "")
                .put("section", Store.section(a)).put("kind", a.kind)
                .put("needs", JSONArray(a.needs))
                .put("neededBy", JSONArray(catalog.filter { a.id in it.needs }.map { it.name }))
                .put("neededByInstalled", JSONArray(catalog.filter { a.id in it.needs && it.id in installed }.map { it.name })))
            // Installed from a file (.adpk) and not in the catalog: listed too, to remove.
            for (id in installed.sorted()) if (catalog.none { it.id == id }) apps.put(JSONObject().put("id", id).put("name", id)
                .put("summary", "Installed from a file").put("version", Store.installedVersion(c, id) ?: "").put("size", 0)
                .put("installed", Store.installedVersion(c, id) ?: "").put("icon", "").put("local", true)
                .put("open", Store.openCommand(c, id) ?: "")
                .put("section", if (id.startsWith("runtime-")) "dependencies" else "deskdroid")
                .put("needs", JSONArray()).put("neededBy", JSONArray()).put("neededByInstalled", JSONArray()))
            val b = JSONObject()
            busy.forEach { (k, v) -> b.put(k, v.toDouble()) }
            serial++
            JSONObject().put("apps", apps).put("busy", b).put("error", error).put("catalogError", catalogError)
                .put("source", Store.baseUrl).put("flathub", JSONObject(flathub.toString())).put("serial", serial).apply { pkg?.let { put("package", it) } }.toString()
        }
        lastWrite = System.currentTimeMillis()
        try {
            val tmp = File(dir(c), ".state.json.tmp")
            tmp.writeText(json)
            tmp.renameTo(File(dir(c), "state.json"))
        } catch (e: Exception) {
            AppLog.i("Agora: couldn't write the state: $e")
        }
    }
}
