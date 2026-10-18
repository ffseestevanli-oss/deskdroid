package io.deskdroid.app

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * deskdroid-images.json, published next to the images by the rootfs CI
 * (.github/workflows/rootfs.yml). One entry per edition.
 */
class ImageManifest(val version: String, val images: List<Image>) {

    class Image(
        val edition: String,
        val file: String,
        val size: Long,
        val unpackedSize: Long,
        val files: Long,
        val sha256: String,
        /** Release assets max out at 2 GB, so big images come in parts of [partSize]. */
        val parts: List<String>,
        val partSize: Long,
    )

    fun image(edition: String): Image =
        images.firstOrNull { it.edition == edition } ?: error("No $edition image in the manifest")

    companion object {
        const val FILE = "deskdroid-images.json"

        fun fetch(baseUrl: String): ImageManifest {
            val conn = URL(baseUrl + FILE).openConnection() as HttpURLConnection
            conn.instanceFollowRedirects = true
            conn.connectTimeout = 15_000
            conn.readTimeout = 30_000
            try {
                check(conn.responseCode == 200) { "Couldn't get the image list (HTTP ${conn.responseCode})" }
                return parse(conn.inputStream.bufferedReader().readText())
            } finally {
                conn.disconnect()
            }
        }

        fun parse(json: String): ImageManifest {
            val root = JSONObject(json)
            val arr = root.getJSONArray("images")
            val images = (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                val file = o.getString("file")
                val partsJson = o.optJSONArray("parts")
                Image(
                    edition = o.getString("edition"),
                    file = file,
                    size = o.getLong("size"),
                    unpackedSize = o.optLong("unpackedSize", o.getLong("size") * 3),
                    files = o.optLong("files", 0),
                    sha256 = o.getString("sha256"),
                    parts = partsJson?.let { p -> (0 until p.length()).map { p.getString(it) } } ?: listOf(file),
                    partSize = o.optLong("partSize", root.optLong("partSize", 1900L * 1024 * 1024)),
                )
            }
            return ImageManifest(root.optString("version", "?"), images)
        }
    }
}
