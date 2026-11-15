package io.deskdroid.app

import java.io.File

/**
 * The installed ddmask module (native/ddmask/module.sh), or null when there is
 * none, it doesn't fit this APK (no api-1), or it is older than this APK: a
 * module from build 1098 would otherwise keep replacing the newer ddmask and
 * launch scripts that a build-1104 APK ships. A module of the same build with a
 * letter (1104a) is newer and is used.
 */
object DdmaskModule {
    fun dir(filesDir: File): File? {
        val module = File(filesDir, "store/apps/ddmask/program")
        if (!File(module, "api-1").exists()) return null
        val modBuild = build(File(module.parentFile, "version.txt").takeIf { it.exists() }?.readText())
        val apkBuild = build(BuildConfig.VERSION_NAME)
        if (modBuild != null && apkBuild != null && modBuild < apkBuild) return null
        return module
    }

    /** The module's version as the log names it ("build-1098a"), or "?". */
    fun version(filesDir: File): String =
        File(filesDir, "store/apps/ddmask/version.txt").takeIf { it.exists() }?.readText()?.trim() ?: "?"

    /** Whether a module is installed that [dir] passes over for being older than the APK. */
    fun stale(filesDir: File): Boolean =
        File(filesDir, "store/apps/ddmask/program/api-1").exists() && dir(filesDir) == null

    /** 1098 from "build-1098a" or "0.1.3-build.1098". */
    fun build(v: String?): Int? = v?.let { Regex("build[-.](\\d+)").find(it)?.groupValues?.get(1)?.toIntOrNull() }
}
