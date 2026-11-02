package io.deskdroid.app

import java.io.File

/**
 * Runs a Qt program of the native desktop test (the Qt demo in
 * native/nativedesk/qt, or KWin) in its own app_process, started by
 * NativeDeskActivity. The program is a library with a QtHost.run() entry point. Qt for Android expects a Java VM
 * with its Java side (Qt6Android.jar, bundled in builds made with Qt): QtCore's
 * JNI_OnLoad registers natives on those classes and asks QtNative for a class
 * loader. There is no Activity, so Qt sees no Android Context; its windows go
 * to the nativedesk compositor through DeskDroid's own platform plugin.
 *
 *   app_process / io.deskdroid.app.QtHost <nativeLibraryDir> <program.so> [arguments]
 */
object QtHost {
    @JvmStatic external fun run(args: Array<String>): Int

    @JvmStatic
    fun main(args: Array<String>) {
        val libs = args[0]
        // A Java exception here would end the process with signal 9 (Android's own
        // handler kills it) and its stack trace would only reach logcat: print it
        // to DeskDroid's log instead.
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            println("QtHost: CRASH in ${t.name}: ${android.util.Log.getStackTraceString(e).take(6000)}")
            System.out.flush()
            Runtime.getRuntime().halt(70)
        }
        // Qt's Java side makes Handlers on the main Looper (Qt Multimedia's
        // QtAudioDeviceManager), which an app_process doesn't have.
        if (android.os.Looper.getMainLooper() == null) {
            @Suppress("DEPRECATION")
            android.os.Looper.prepareMainLooper()
        }
        giveQtClassLoader()
        // Core first: only the library passed to System.load gets JNI_OnLoad.
        load(File(libs, "libc++_shared.so"))
        load(File(libs, "libQt6Core_arm64-v8a.so"))
        loadInAnyOrder(File(libs).listFiles { f -> f.name.startsWith("libQt6") }.orEmpty().sortedBy { it.name })
        // An app from DeskDroid's app store comes as a full path (qtapp.sh), its
        // own libraries next to it; the rest come from the APK.
        loadWithDependencies(File(args[1]).takeIf { it.isAbsolute } ?: File(libs, args[1]), libs)
        println("QtHost: libraries loaded, starting ${args[1]}")
        System.out.flush()
        System.exit(run(args.copyOfRange(2, args.size)))
    }

    /**
     * Loads a library after whatever it needs from the same directory, found
     * from the linker's own "library ... not found" errors.
     */
    private fun loadWithDependencies(lib: File, libs: String, tried: MutableSet<String> = mutableSetOf()) {
        while (true) {
            try {
                load(lib)
                return
            } catch (e: UnsatisfiedLinkError) {
                val missing = Regex("library \"([^\"]+)\" not found").find(e.message.orEmpty())?.groupValues?.get(1)
                val dep = missing?.let { File(lib.parentFile, it).takeIf { f -> f.exists() } ?: File(libs, it) }
                if (dep == null || !dep.exists() || !tried.add(dep.name)) throw e
                loadWithDependencies(dep, libs, tried)
            }
        }
    }

    /** Loads one library, saying so first: a crash while loading prints nothing else. */
    private fun load(lib: File) {
        println("QtHost: loading ${lib.name}")
        System.out.flush()
        System.load(lib.path)
    }

    /**
     * Loads the rest of Qt's libraries, each after the ones it needs: the
     * linker may not find them on its own from this process's class loader.
     */
    private fun loadInAnyOrder(libs: List<File>) {
        var left = libs.filter { !it.name.startsWith("libQt6Core_") }
        while (left.isNotEmpty()) {
            val failed = left.filter { lib ->
                try { load(lib); false } catch (e: UnsatisfiedLinkError) {
                    if (e.message.orEmpty().contains("JNI_OnLoad")) {
                        // Its Java side is missing or failed: never loads, so leave it
                        // out; only what needs it goes without.
                        println("QtHost: skipping ${lib.name} (${e.message?.take(120)})")
                        false
                    } else {
                        println("QtHost: ${lib.name} later (${e.message?.substringAfter("library ")?.take(80)})")
                        true
                    }
                }
            }
            if (failed.size == left.size) {
                // None of these load: say why and go on without them.
                failed.forEach { println("QtHost: couldn't load ${it.name}") }
                return
            }
            left = failed
        }
    }

    /** QtNative.classLoader() normally comes from Qt's loader; point it at ours. */
    private fun giveQtClassLoader() {
        val loader = QtHost::class.java.classLoader
        try {
            val native = Class.forName("org.qtproject.qt.android.QtNative")
            val setter = native.declaredMethods.firstOrNull {
                it.name == "setClassLoader" && it.parameterTypes.contentEquals(arrayOf(ClassLoader::class.java))
            }
            if (setter != null) {
                setter.isAccessible = true
                setter.invoke(null, loader)
                return
            }
            val field = native.declaredFields.firstOrNull { it.type == ClassLoader::class.java }
            if (field != null) {
                field.isAccessible = true
                field.set(null, loader)
            } else {
                println("QtHost: QtNative has no class loader to set")
            }
        } catch (e: Throwable) {
            println("QtHost: Qt's Java classes are missing: $e")
        }
    }
}
