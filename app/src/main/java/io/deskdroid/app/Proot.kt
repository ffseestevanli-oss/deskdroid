package io.deskdroid.app

import java.io.File

/** Builds the proot command line that enters the Debian rootfs as the desktop user. */
object Proot {
    const val USER = "deskdroid"
    const val UID = 1000

    fun sessionCommand(paths: Paths, gpuMode: String): ProcessBuilder {
        paths.prootTmp.mkdirs()
        val args = mutableListOf(
            paths.proot.path,
            "--kill-on-exit",
            "--link2symlink",
            "--sysvipc",
            "-L",
            "--change-id=$UID:$UID",
            "-r", paths.rootfs.path,
            "-b", "/dev",
            "-b", "/proc",
            "-b", "/sys",
            "-b", "${paths.rootfs.path}/tmp:/dev/shm",
            "-w", "/home/$USER",
        )
        // Android hides some /proc files from apps; bind harmless stand-ins.
        for ((name, content) in fakeProcFiles()) {
            if (!File("/proc/$name").canRead()) {
                val f = File(paths.fakeProc, name)
                f.parentFile!!.mkdirs()
                f.writeText(content)
                args += listOf("-b", "${f.path}:/proc/$name")
            }
        }
        args += listOf(
            "/usr/bin/env", "-i",
            "HOME=/home/$USER",
            "USER=$USER",
            "LANG=C.UTF-8",
            "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "TMPDIR=/tmp",
            "DISPLAY=:0",
            "DESKDROID_GPU=$gpuMode",
            "/bin/sh", "/usr/local/bin/deskdroid-session",
        )
        return ProcessBuilder(args).redirectErrorStream(true).also { pb ->
            pb.environment().apply {
                clear()
                put("PROOT_TMP_DIR", paths.prootTmp.path)
                put("PROOT_LOADER", paths.prootLoader.path)
                put("LD_LIBRARY_PATH", paths.nativeLibs.path)
            }
        }
    }

    private fun fakeProcFiles() = mapOf(
        "loadavg" to "0.12 0.07 0.02 2/165 765\n",
        "stat" to "cpu  1957 0 2877 93280 262 342 254 87 0 0\n" +
            "cpu0 31 0 226 12027 82 10 4 9 0 0\n" +
            "intr 63361 0 0\nctxt 38014093\nbtime 1694292441\n" +
            "processes 26442\nprocs_running 1\nprocs_blocked 0\n",
        "uptime" to "124.08 932.80\n",
        "vmstat" to "nr_free_pages 1743136\nnr_zone_inactive_anon 179281\n",
    )
}
