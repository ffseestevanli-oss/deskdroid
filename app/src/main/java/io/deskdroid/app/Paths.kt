package io.deskdroid.app

import android.content.Context
import java.io.File

/** Where everything lives inside the app's private storage. */
class Paths(context: Context) {
    val files: File = context.filesDir
    val rootfs = File(files, "rootfs")
    val rootfsStaging = File(files, "rootfs.staging")
    /** Downloads stay here between attempts so an interrupted install resumes. */
    val downloads = File(files, "downloads")
    val prootTmp = File(files, "proot-tmp")
    val fakeProc = File(files, "fake-proc")
    val nativeLibs = File(context.applicationInfo.nativeLibraryDir)
    val proot = File(nativeLibs, "libproot.so")
    val prootLoader = File(nativeLibs, "libproot-loader.so")
    val ddtool = File(nativeLibs, "libddtool.so")
    val rootfsTmp = File(rootfs, "tmp")
    val x11Socket = File(rootfsTmp, ".X11-unix/X0")
    /** Runtime files shared with the session (audio pipe, status). */
    val runtime = File(rootfsTmp, "deskdroid")
    val audioPipe = File(runtime, "audio.pipe")
    val editionFile = File(rootfs, "etc/deskdroid/edition")

    val isInstalled: Boolean get() = File(rootfs, "usr/local/bin/deskdroid-session").exists()
    val installedEdition: String? get() = editionFile.takeIf { it.exists() }?.readText()?.trim()
}
