package io.deskdroid.app

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.StatFs
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * System Settings › About This Phone (native/plasma/aboutphone) shows
 * files/phone-info.json, written here at each desktop start: Android's
 * version, the ROM or skin (One UI, GrapheneOS, LineageOS...), memory,
 * storage, processor and kernel.
 */
object PhoneInfo {
    fun write(c: Context) {
        try {
            File(c.filesDir, "phone-info.json").writeText(json(c).toString(2))
        } catch (e: Exception) {
            AppLog.i("About This Phone: $e")
        }
    }

    private fun json(c: Context): JSONObject {
        val name = deviceName()
        val rom = rom()
        val sections = JSONArray()
        fun section(title: String, vararg rows: Pair<String, String?>) {
            val r = JSONArray()
            rows.filter { !it.second.isNullOrBlank() }.forEach { r.put(JSONArray().put(it.first).put(it.second)) }
            if (r.length() > 0) sections.put(JSONObject().put("title", title).put("rows", r))
        }
        section("Software",
            "Android" to "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
            "ROM" to rom,
            "Build" to Build.DISPLAY,
            "Security patch" to Build.VERSION.SECURITY_PATCH,
            "Kernel" to kernel(),
            "DeskDroid" to try {
                c.packageManager.getPackageInfo(c.packageName, 0).versionName
            } catch (e: Exception) { null },
        )
        val mem = ActivityManager.MemoryInfo().also { c.getSystemService(ActivityManager::class.java).getMemoryInfo(it) }
        val data = StatFs(c.filesDir.path)
        section("Hardware",
            "Model" to "${Build.MANUFACTURER.replaceFirstChar { it.uppercase() }} ${Build.MODEL} (${Build.DEVICE})",
            "Processor" to processor(),
            "Graphics" to gpu(),
            "Memory" to "${gb(mem.totalMem)} RAM (${gb(mem.availMem)} free now)",
            "Storage" to "${gb(data.totalBytes)} (${gb(data.availableBytes)} free)",
            "Architecture" to Build.SUPPORTED_ABIS.joinToString(", "),
        )
        section("Build details",
            "Fingerprint" to Build.FINGERPRINT,
            "Bootloader" to Build.BOOTLOADER,
            "Radio" to Build.getRadioVersion(),
        )
        return JSONObject()
            .put("title", name)
            .put("subtitle", "Android ${Build.VERSION.RELEASE}" + (rom?.let { " · $it" } ?: ""))
            .put("sections", sections)
    }

    private fun deviceName(): String {
        val m = Build.MANUFACTURER.replaceFirstChar { it.uppercase() }
        return if (Build.MODEL.startsWith(m, ignoreCase = true)) Build.MODEL else "$m ${Build.MODEL}"
    }

    /** The ROM or the maker's skin, from the properties each one sets. */
    private fun rom(): String? {
        prop("ro.build.version.oneui").toIntOrNull()?.let { v ->
            // 60100 is One UI 6.1, 70000 is One UI 7.
            val minor = v / 100 % 100
            return "Samsung One UI ${v / 10000}" + if (minor != 0) ".$minor" else ""
        }
        val user = prop("ro.build.user") + " " + prop("ro.build.host") + " " + Build.FINGERPRINT
        if ("grapheneos" in user.lowercase() || prop("ro.grapheneos.release").isNotEmpty()) return "GrapheneOS"
        prop("ro.calyxos.version").takeIf { it.isNotEmpty() }?.let { return "CalyxOS $it" }
        prop("org.pixelexperience.version").ifEmpty { prop("ro.custom.version") }.takeIf { it.isNotEmpty() }?.let {
            return if ("pixel" in it.lowercase()) it else "Pixel Experience $it"
        }
        prop("ro.crdroid.version").takeIf { it.isNotEmpty() }?.let { return "crDroid $it" }
        prop("ro.evolution.version").takeIf { it.isNotEmpty() }?.let { return "Evolution X $it" }
        prop("ro.lineage.version").takeIf { it.isNotEmpty() }?.let {
            return if (prop("ro.build.flavor").startsWith("e_") || prop("ro.elegal.url").isNotEmpty()) "/e/OS ($it)" else "LineageOS $it"
        }
        prop("ro.mi.os.version.name").takeIf { it.isNotEmpty() }?.let { return "Xiaomi HyperOS $it" }
        prop("ro.miui.ui.version.name").takeIf { it.isNotEmpty() }?.let { return "Xiaomi MIUI $it" }
        prop("ro.build.version.oplusrom").ifEmpty { prop("ro.build.version.opporom") }.takeIf { it.isNotEmpty() }?.let {
            return if (Build.MANUFACTURER.equals("OnePlus", true)) "OnePlus OxygenOS ($it)" else "ColorOS $it"
        }
        prop("ro.oxygen.version").takeIf { it.isNotEmpty() }?.let { return "OnePlus OxygenOS $it" }
        prop("ro.build.version.emui").takeIf { it.isNotEmpty() }?.let { return it.replace('_', ' ') }
        prop("ro.vivo.os.build.display.id").takeIf { it.isNotEmpty() }?.let { return it }
        prop("ro.build.version.magic").takeIf { it.isNotEmpty() }?.let { return "Honor MagicOS $it" }
        if (Build.MANUFACTURER.equals("Google", true) && Build.TAGS == "release-keys") return "Pixel (stock Android)"
        if (Build.TAGS == "release-keys") return "${Build.MANUFACTURER.replaceFirstChar { it.uppercase() }} stock Android"
        return null
    }

    private fun processor(): String? {
        val soc = if (Build.VERSION.SDK_INT >= 31) "${Build.SOC_MANUFACTURER} ${Build.SOC_MODEL}".trim() else Build.HARDWARE
        val cores = Runtime.getRuntime().availableProcessors()
        return "$soc, $cores cores"
    }

    /** The GPU KWin last reported (deskdroid-ahb's log line), if any. */
    private fun gpu(): String? = prop("ro.hardware.egl").takeIf { it.isNotEmpty() }?.let {
        when (it.lowercase()) {
            "mali" -> "Arm Mali"
            "adreno" -> "Qualcomm Adreno"
            "powervr" -> "Imagination PowerVR"
            else -> it
        }
    }

    private fun kernel(): String? = try {
        File("/proc/version").readText().trim().removePrefix("Linux version ").substringBefore(" (")
    } catch (e: Exception) {
        System.getProperty("os.version")
    }

    private fun gb(bytes: Long) = String.format(java.util.Locale.US, "%.1f GB", bytes / 1e9)

    private fun prop(name: String): String = try {
        @Suppress("PrivateApi")
        Class.forName("android.os.SystemProperties").getMethod("get", String::class.java).invoke(null, name) as String
    } catch (e: Exception) {
        ""
    }
}
