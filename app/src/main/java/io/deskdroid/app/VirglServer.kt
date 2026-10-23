package io.deskdroid.app

import android.content.Context
import android.system.Os
import java.io.File

/**
 * The virgl server (virglrenderer's vtest server, native/virgl/). Linux apps
 * use Mesa's virgl driver (GALLIUM_DRIVER=virpipe), which sends OpenGL work over
 * /tmp/.virgl_test; the server runs it on Android's GPU driver, either the
 * vendor's OpenGL ES or ANGLE (GLES on top of Vulkan), which behaves better on
 * Mali according to Termux users. Opt-in GPU path for non-Adreno phones until
 * Vulkan forwarding (Venus) lands.
 */
object VirglServer {
    private const val KWIN_WRAPPER_TAG = "deskdroid-virgl-kwin"

    /**
     * KWin crashed repeatedly on virgl (Pixel 10 Pro), so in virgl mode it keeps
     * compositing with llvmpipe while apps use the GPU. ksmserver starts kwin_x11
     * through PATH, so a wrapper in /usr/local/bin (ahead of /usr/bin) sets that.
     * Written into the rootfs at session start so existing installs get it too,
     * and removed in other modes.
     */
    fun setKwinWrapper(paths: Paths, on: Boolean) {
        val f = File(paths.rootfs, "usr/local/bin/kwin_x11")
        if (on) {
            f.writeText(
                "#!/bin/sh\n# $KWIN_WRAPPER_TAG: written by the DeskDroid app (VirglServer.kt) in virgl mode.\n" +
                    "# KWin composites in software; apps keep the GPU through virgl.\n" +
                    "GALLIUM_DRIVER=llvmpipe exec /usr/bin/kwin_x11 \"\$@\"\n"
            )
            f.setExecutable(true, false)
        } else if (f.exists() && f.readText().contains(KWIN_WRAPPER_TAG)) {
            f.delete()
        }
    }

    private val angleDirs = listOf("/system/lib64", "/system_ext/lib64", "/product/lib64", "/vendor/lib64")

    /** The system's ANGLE build, if the phone ships one. */
    fun angleDir(): File? = angleDirs.map(::File).firstOrNull {
        File(it, "libEGL_angle.so").exists() && File(it, "libGLESv2_angle.so").exists()
    }

    /** Backend the server will use: "angle" or "gles" (the vendor driver). */
    fun backend(c: Context): String = when (Prefs.virglBackend(c)) {
        "gles" -> "gles"
        else -> if (angleDir() != null) "angle" else "gles" // "auto" and "angle"
    }

    fun describeBackend(b: String) = if (b == "angle") "ANGLE" else "vendor OpenGL ES"

    /**
     * Starts the server and waits for its socket. Returns null if it can't run,
     * so the session falls back to software rendering.
     */
    fun start(c: Context, paths: Paths, log: (Process) -> Unit): Process? {
        if (!paths.virglServer.exists()) return null
        paths.virglSocket.delete()
        // The server loads ANGLE from "angle/" relative to its working directory
        // (native/virgl/patches/0007), so link that to the system's ANGLE.
        val work = paths.virglDir.apply { mkdirs() }
        val link = File(work, "angle")
        link.delete()
        val angle = if (backend(c) == "angle") angleDir() else null
        if (angle != null) Os.symlink(angle.path, link.path)

        val args = mutableListOf(paths.virglServer.path, "--socket-path", paths.virglSocket.path)
        if (angle != null) args += "--angle-vulkan"
        AppLog.i("Starting virgl server on ${describeBackend(if (angle != null) "angle" else "gles")}")
        val p = ProcessBuilder(args).directory(work).redirectErrorStream(true).also { pb ->
            pb.environment().apply {
                remove("LD_PRELOAD"); remove("LD_LIBRARY_PATH")
                put("TMPDIR", work.path)
            }
        }.start()
        log(p)

        val end = System.currentTimeMillis() + 5_000
        while (!paths.virglSocket.exists()) {
            if (!p.isAlive || System.currentTimeMillis() > end) {
                AppLog.i("virgl server did not start (exit ${if (p.isAlive) "timeout" else p.exitValue()})")
                p.destroy()
                return null
            }
            Thread.sleep(100)
        }
        return p
    }
}
