package io.deskdroid.app

import java.io.File

/**
 * Picks how Linux apps render. Plan section 1: Turnip + Zink on Adreno (through
 * /dev/kgsl, reachable without root), virgl on everything else (Mali, PowerVR),
 * llvmpipe when neither works. Vulkan forwarding (Venus) replaces virgl later.
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
            paths.virglServer.exists() -> "virgl"
            else -> "llvmpipe"
        }
    }

    fun describe(mode: String): String = when (mode) {
        "turnip" -> "Adreno GPU (Turnip + Zink)"
        "nocomp" -> "Software, effects off"
        "virgl" -> "GPU via virgl (OpenGL)"
        else -> "Software (llvmpipe)"
    }
}
