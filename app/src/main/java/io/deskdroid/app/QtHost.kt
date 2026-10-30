package io.deskdroid.app

import java.io.File

/**
 * Runs the native desktop test's Qt demo (native/nativedesk/qt) in its own
 * app_process, started by NativeDeskActivity. Qt for Android expects a Java VM
 * with its Java side (Qt6Android.jar, bundled in builds made with Qt): QtCore's
 * JNI_OnLoad registers natives on those classes and asks QtNative for a class
 * loader. There is no Activity, so Qt sees no Android Context; its windows go
 * to the nativedesk compositor through DeskDroid's own platform plugin.
 *
 *   app_process / io.deskdroid.app.QtHost <nativeLibraryDir> [Qt arguments]
 */
object QtHost {
    @JvmStatic external fun run(args: Array<String>): Int

    @JvmStatic
    fun main(args: Array<String>) {
        val libs = args[0]
        giveQtClassLoader()
        // Core first: only the library passed to System.load gets JNI_OnLoad.
        for (lib in listOf("libc++_shared.so", "libQt6Core_arm64-v8a.so", "libQt6Gui_arm64-v8a.so",
                "libQt6OpenGL_arm64-v8a.so", "libnativedesk_qt.so")) {
            System.load(File(libs, lib).path)
        }
        System.exit(run(args.copyOfRange(1, args.size)))
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
