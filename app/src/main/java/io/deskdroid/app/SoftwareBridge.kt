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
 *
 * state.json: {"apps": [{id, name, summary, version, size, installed, icon, open,
 * section ("deskdroid" | "flathub" | "dependencies", Software's tabs), kind,
 * needs, neededBy, neededByInstalled (names of the apps that need it)}],
 * "busy": {id: progress 0..1 or -1}, "error": "...", "catalogError": "...",
 * "package": {path, id, name, summary, version, installed, icon} or absent,
 * "serial": n}. Icons are files in $HOME/software/icons.
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
                .put("source", Store.baseUrl).put("serial", serial).apply { pkg?.let { put("package", it) } }.toString()
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
