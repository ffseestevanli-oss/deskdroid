package io.deskdroid.app

import android.content.Context
import java.io.File

/** Where everything lives inside the app's private storage. */
class Paths(context: Context) {
    val files: File = context.filesDir
    val rootfs = File(files, "rootfs")
    val rootfsStaging = File(files, "rootfs.staging")
    val download = File(context.cacheDir, "rootfs.tar.xz")
    val prootTmp = File(files, "proot-tmp")
    val fakeProc = File(files, "fake-proc")
    val nativeLibs = File(context.applicationInfo.nativeLibraryDir)
    val proot = File(nativeLibs, "libproot.so")
    val prootLoader = File(nativeLibs, "libproot-loader.so")
    val x11Socket = File(rootfs, "tmp/.X11-unix/X0")

    val isInstalled: Boolean get() = File(rootfs, "usr/local/bin/deskdroid-session").exists()
}
