package io.deskdroid.app

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Agora's view of all of Flathub: search, categories and the popular list,
 * from Flathub's own API (flathub.org/api/v2, what flathub.org's pages use).
 * Only the catalog: installing is the desktop's `flatpak` command
 * (native/flatpak), run by Agora itself (native/plasma/software/backend.cpp).
 * Asked through SoftwareBridge ("flathub:<category>:<query>"), answered in
 * state.json's "flathub".
 *
 * Each hit carries its architectures: aarch64 runs as it is (through ddmask),
 * x86_64 alone runs through FEX.
 */
object FlathubCatalog {
    private const val API = "https://flathub.org/api/v2/"
    const val PER_PAGE = 60

    data class Hit(
        val id: String, val name: String, val summary: String, val description: String,
        val iconUrl: String, val arches: List<String>, val developer: String, val verified: Boolean,
        val license: String, val installs: Int, val category: String, val type: String,
    ) {
        fun json(icon: String): JSONObject = JSONObject().put("id", id).put("name", name).put("summary", summary)
            .put("description", description).put("icon", icon).put("iconUrl", iconUrl).put("arches", JSONArray(arches))
            .put("developer", developer).put("verified", verified).put("license", license)
            .put("installs", installs).put("category", category).put("type", type)
    }

    /** [next]: the page "Show more" asks for, 0 when there's no more. */
    data class Page(val hits: List<Hit>, val total: Int, val next: Int)

    // Pages read at once for "fex": Flathub can't search for "not aarch64",
    // so those are picked out of every x86-64 app (about 3,400; 1 in 8 is
    // x86-64 only).
    private const val FEX_SCAN = 500

    /**
     * One page of Flathub (blocking). No query and no category: the popular
     * list, as Flathub's home page shows it. Categories: Flathub's main ones
     * ("Office"...), "native" (apps with an ARM64 build) and "fex" (apps
     * Flathub only builds for x86-64, which run through FEX). Console
     * programs are left out: they have no window to open.
     */
    fun search(query: String, category: String, page: Int = 1): Page {
        val q = query.trim()
        if (category == "fex") return fexOnly(q, page)
        val json = if (q.isEmpty() && category.isEmpty()) {
            JSONObject(get("collection/popular?page=$page&per_page=$PER_PAGE"))
        } else {
            val filters = JSONArray()
            when (category) {
                "" -> {}
                "native" -> filters.put(JSONObject().put("filterType", "arches").put("value", "aarch64"))
                else -> filters.put(JSONObject().put("filterType", "main_categories").put("value", category))
            }
            JSONObject(post("search", JSONObject().put("query", q).put("filters", filters)
                .put("hits_per_page", PER_PAGE).put("page", page).toString()))
        }
        val hits = hits(json)
        val total = json.optInt("totalHits", hits.size)
        return Page(hits, total, if (page * PER_PAGE < total) page + 1 else 0)
    }

    /** x86-64-only apps, from [page] of the x86-64 list on, until a page's worth is found. */
    private fun fexOnly(q: String, page: Int): Page {
        val found = mutableListOf<Hit>()
        var p = page
        while (true) {
            val json = JSONObject(post("search", JSONObject().put("query", q)
                .put("filters", JSONArray().put(JSONObject().put("filterType", "arches").put("value", "x86_64")))
                .put("hits_per_page", FEX_SCAN).put("page", p).toString()))
            found += hits(json).filter { "aarch64" !in it.arches }
            val more = p * FEX_SCAN < json.optInt("totalHits")
            p++
            if (!more) return Page(found, -1, 0)
            if (found.size >= PER_PAGE) return Page(found, -1, p)
        }
    }

    private fun hits(json: JSONObject): List<Hit> {
        val arr = json.optJSONArray("hits") ?: JSONArray()
        return (0 until arr.length()).mapNotNull { i ->
            val h = arr.getJSONObject(i)
            val id = h.optString("app_id")
            if (id.isEmpty() || !ID.matches(id)) return@mapNotNull null
            val type = h.optString("type")
            if (type == "console-application") return@mapNotNull null
            Hit(id, h.optString("name", id), h.optString("summary"), clean(h.optString("description")),
                h.optString("icon"), strings(h.optJSONArray("arches")), h.optString("developer_name"),
                h.optBoolean("verification_verified"), h.optString("project_license"),
                h.optInt("installs_last_month"), h.optString("main_categories"), type)
        }
    }

    /** An app's icon, as <dir>/<id>.png (blocking); the cached one if it's there. */
    fun icon(hit: Hit, dir: File): File? {
        val f = File(dir, "${hit.id}.png")
        if (f.length() > 0) return f
        if (!hit.iconUrl.startsWith("https://")) return null
        return try {
            val bytes = open(URL(hit.iconUrl)).let { c -> c.inputStream.use { it.readBytes() }.also { c.disconnect() } }
            val tmp = File(dir, ".${hit.id}.png")
            tmp.writeBytes(bytes)
            tmp.renameTo(f)
            f
        } catch (e: Exception) {
            null
        }
    }

    // Flatpak app ids: reverse DNS, letters, digits, _ and -.
    private val ID = Regex("[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+){2,}")

    private fun strings(a: JSONArray?) = a?.let { arr -> (0 until arr.length()).map { arr.getString(it) } }.orEmpty()

    // AppStream descriptions arrive with their markup's indentation.
    private fun clean(s: String) = s.lines().joinToString("\n") { it.trim() }.replace(Regex("\n{3,}"), "\n\n").trim()

    private fun get(path: String): String = open(URL(API + path)).let { c ->
        c.inputStream.use { it.readBytes() }.toString(Charsets.UTF_8).also { c.disconnect() }
    }

    private fun post(path: String, body: String): String {
        val c = URL(API + path).openConnection() as HttpURLConnection
        c.connectTimeout = 15000
        c.readTimeout = 30000
        c.requestMethod = "POST"
        c.doOutput = true
        c.setRequestProperty("Content-Type", "application/json")
        c.setRequestProperty("Accept", "application/json")
        c.outputStream.use { it.write(body.toByteArray()) }
        if (c.responseCode != 200) throw Exception("Flathub answered HTTP ${c.responseCode}")
        return c.inputStream.use { it.readBytes() }.toString(Charsets.UTF_8).also { c.disconnect() }
    }

    private fun open(url: URL): HttpURLConnection {
        val c = url.openConnection() as HttpURLConnection
        c.connectTimeout = 15000
        c.readTimeout = 30000
        c.instanceFollowRedirects = true
        c.setRequestProperty("Accept", "application/json")
        if (c.responseCode != 200) throw Exception("Flathub answered HTTP ${c.responseCode}")
        return c
    }
}
