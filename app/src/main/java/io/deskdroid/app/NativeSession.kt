package io.deskdroid.app

import android.app.ActivityOptions
import android.content.Context
import android.content.Intent
import android.view.Display
import java.io.File

/**
 * The native Plasma session: KWin (and, next, Plasma's shell) built for
 * Android, shown by NativeDeskActivity, with no Linux system underneath.
 * Builds made with DeskDroid's own Qt carry it; others only have the Debian
 * desktop.
 */
object NativeSession {
    fun available(c: Context) = File(c.applicationInfo.nativeLibraryDir, "libkwin_wayland.so").exists()

    /** Starts (or brings back) the session, on the given display. */
    fun start(c: Context, display: Int = Display.DEFAULT_DISPLAY) {
        // A monitor gets its own window (ExternalDeskActivity); the phone keeps its touchpad.
        val cls = if (display != Display.DEFAULT_DISPLAY) ExternalDeskActivity::class.java else NativeDeskActivity::class.java
        val intent = Intent(c, cls).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val options = ActivityOptions.makeBasic().setLaunchDisplayId(display)
        c.startActivity(intent, options.toBundle())
    }
}
