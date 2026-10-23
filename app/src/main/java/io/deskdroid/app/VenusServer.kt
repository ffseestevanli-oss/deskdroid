package io.deskdroid.app

import android.content.Context
import android.system.Os
import java.io.File

/**
 * GPU for non-Adreno phones (Mali, PowerVR): Venus Vulkan forwarding.
 *
 * Linux apps use Mesa's Venus driver (VN_DEBUG=vtest), which sends Vulkan
 * commands over /tmp/.virgl_test to virglrenderer's vtest server in the APK
 * (native/virgl/). The server's render server runs them on Android's own Vulkan
 * driver. OpenGL goes through Zink on top of Venus. Replaces the virgl (OpenGL
 * over GLES) path, which crashed KWin on the Pixel 10 Pro.
 */
object VenusServer {
    private const val TAG = "deskdroid-gpu"

    /**
     * How the render server shares GPU memory with the rootfs side: "dmabuf" is
     * upstream Venus, "ahb" uses AHardwareBuffers (patch 0011) for drivers
     * without VK_EXT_external_memory_dma_buf.
     */
    fun memoryMode(c: Context, paths: Paths): String = when (val m = Prefs.venusMemory(c)) {
        "dmabuf", "ahb" -> m
        else -> detectMemoryMode(paths)
    }

    /** Asks gpureport whether the Vulkan driver can export dma-bufs. */
    fun detectMemoryMode(paths: Paths): String = try {
        val p = ProcessBuilder(paths.gpuReport.path, "--venus-memory").redirectErrorStream(true).start()
        val out = p.inputStream.bufferedReader().readText().trim()
        p.waitFor()
        if (out == "ahb") "ahb" else "dmabuf"
    } catch (e: Exception) {
        "dmabuf"
    }

    fun describeMemory(m: String) = if (m == "ahb") "AHardwareBuffer" else "dma-buf"

    /** Mesa's Venus ICD in the rootfs; Debian ships it in mesa-vulkan-drivers. */
    fun venusIcd(paths: Paths): File? = File(paths.rootfs, "usr/share/vulkan/icd.d")
        .listFiles { f -> f.name.startsWith("virtio_icd") && f.name.endsWith(".json") }
        ?.firstOrNull()

    /**
     * Starts the server and waits for its socket. Returns null if it can't run,
     * so the session falls back to software rendering.
     */
    fun start(c: Context, paths: Paths, log: (Process) -> Unit): Process? {
        if (venusIcd(paths) == null) {
            AppLog.i("Mesa's Venus driver (virtio_icd) is missing from the system image")
            return null
        }
        val mode = memoryMode(c, paths)
        val suffix = if (mode == "ahb") "_ahb" else ""
        val server = File(paths.nativeLibs, "libvirgl_test_server$suffix.so")
        val renderServer = File(paths.nativeLibs, "libvirgl_render_server$suffix.so")
        if (!server.exists()) return null
        paths.virglSocket.delete()

        // The server was built with prefix /proc/self/cwd (native/virgl/build.sh),
        // so it execs the render server from libexec/ under its working directory.
        val work = paths.virglDir.apply { mkdirs() }
        val libexec = File(work, "libexec").apply { mkdirs() }
        val link = File(libexec, "virgl_render_server")
        link.delete()
        if (renderServer.exists()) Os.symlink(renderServer.path, link.path)

        AppLog.i("Starting Venus server (${describeMemory(mode)} memory)")
        val p = ProcessBuilder(server.path, "--venus", "--socket-path", paths.virglSocket.path)
            .directory(work).redirectErrorStream(true).also { pb ->
                pb.environment().apply {
                    remove("LD_PRELOAD"); remove("LD_LIBRARY_PATH")
                    put("TMPDIR", work.path)
                    put("RENDER_SERVER_EXEC_PATH", link.path)
                }
            }.start()
        log(p)

        val end = System.currentTimeMillis() + 5_000
        while (!paths.virglSocket.exists()) {
            if (!p.isAlive || System.currentTimeMillis() > end) {
                AppLog.i("Venus server did not start (exit ${if (p.isAlive) "timeout" else p.exitValue()})")
                p.destroy()
                return null
            }
            Thread.sleep(100)
        }
        return p
    }

    /**
     * Writes the GPU environment for the Plasma session. startplasma sources
     * ~/.config/plasma-workspace/env/*.sh, so this reaches KWin, plasmashell and
     * every app, and works on system images that predate Venus (their
     * deskdroid-session doesn't know the mode). Removed in other modes.
     */
    fun writeSessionEnv(c: Context, paths: Paths, on: Boolean) {
        val f = File(paths.rootfs, "home/deskdroid/.config/plasma-workspace/env/deskdroid-gpu.sh")
        if (!on) {
            if (f.exists() && f.readText().contains(TAG)) f.delete()
            setKwinWrapper(paths, false)
            return
        }
        val icd = venusIcd(paths) ?: return
        f.parentFile!!.mkdirs()
        f.writeText(
            """
            |# $TAG: written by the DeskDroid app (VenusServer.kt) at each start in Venus mode.
            |export VN_DEBUG=vtest
            |export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/${icd.name}
            |# No DRI3 device behind Venus over vtest: present through the X server in software.
            |export MESA_VK_WSI_DEBUG=sw
            |# OpenGL through Zink on Venus.
            |export MESA_LOADER_DRIVER_OVERRIDE=zink
            |export GALLIUM_DRIVER=zink
            |export ZINK_DESCRIPTORS=lazy
            |""".trimMargin()
        )
        setKwinWrapper(paths, !Prefs.gpuDesktop(c))
    }

    /**
     * KWin on the GPU is opt-in (virgl crashed it on the Pixel 10 Pro): by default
     * it composites with llvmpipe while apps use Venus. ksmserver starts kwin_x11
     * through PATH, so a wrapper in /usr/local/bin (ahead of /usr/bin) does that.
     */
    private fun setKwinWrapper(paths: Paths, on: Boolean) {
        val f = File(paths.rootfs, "usr/local/bin/kwin_x11")
        if (on) {
            f.writeText(
                "#!/bin/sh\n# $TAG: written by the DeskDroid app (VenusServer.kt) in Venus mode.\n" +
                    "# KWin composites in software; apps keep the GPU through Venus.\n" +
                    "unset MESA_LOADER_DRIVER_OVERRIDE VN_DEBUG VK_ICD_FILENAMES\n" +
                    "LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe exec /usr/bin/kwin_x11 \"\$@\"\n"
            )
            f.setExecutable(true, false)
        } else if (f.exists() && f.readText().let { it.contains(TAG) || it.contains("deskdroid-virgl-kwin") }) {
            f.delete()
        }
    }
}
