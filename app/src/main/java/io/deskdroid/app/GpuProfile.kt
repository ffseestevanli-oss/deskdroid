package io.deskdroid.app

import java.io.File

/**
 * Picks how Linux apps render. Plan section 1: Turnip + Zink on Adreno (through
 * /dev/kgsl, reachable without root), llvmpipe everywhere else. virgl (Mali,
 * PowerVR) is opt-in: on the Pixel 10 Pro it crashed KWin and Firefox tabs
 * (2026-10-23). Vulkan forwarding (Venus) is the next try.
 */
object GpuProfile {
    /** Mesa built with Turnip's kgsl backend, installed by the deskdroid-mesa package. */
    private const val KGSL_MESA = "opt/deskdroid-mesa/lib"

    fun hasKgsl() = File("/dev/kgsl-3d0").exists()

    /** Resolves "auto" to a concrete mode the session script understands. */
    fun resolve(mode: String, paths: Paths): String {
        if (mode != "auto") return mode
        return when {
            hasKgsl() && File(paths.rootfs, KGSL_MESA).exists() -> "turnip"
            else -> "llvmpipe"
        }
    }

    fun describe(mode: String): String = when (mode) {
        "turnip" -> "Adreno GPU (Turnip + Zink)"
        "nocomp" -> "Software, effects off"
        "virgl" -> "GPU via virgl (experimental)"
        else -> "Software (llvmpipe)"
    }
}
