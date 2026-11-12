package io.deskdroid.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd

/**
 * One clipboard for the desktop and the phone (protocol.h's CLIP and CLIPBOARD).
 *
 * Desktop to phone: a desktop app copies text, KWin hands over a pipe the
 * text comes out of, and it becomes Android's clipboard.
 *
 * Phone to desktop: when Android's clipboard changes, the desktop only hears
 * that it did. The text is read when a desktop app actually pastes (KWin
 * hands over the paste's own pipe), so Android reads its clipboard, and shows
 * its "pasted from your clipboard" notice, only when you paste.
 *
 * Android lets an app see its clipboard only while one of its windows has
 * the focus, so a copy made in another app is picked up when the desktop
 * gets the focus back.
 */
object SharedClipboard {
    // Android's clipboard entries that came from the desktop: not sent back.
    private const val LABEL = "DeskDroid desktop"
    private const val MAX_BYTES = 4 shl 20
    private const val TIMEOUT_MS = 3000

    private val main = Handler(Looper.getMainLooper())
    @Volatile private var app: Context? = null
    private var listening = false
    private var lastSeen = -1L // the timestamp of the phone's entry last announced to the desktop

    private val listener = ClipboardManager.OnPrimaryClipChangedListener { check() }

    private fun clipboard(): ClipboardManager? = app?.getSystemService(ClipboardManager::class.java)

    /** The desktop started: the phone's clipboard, as it is now, is pasteable there. */
    fun start(c: Context) {
        app = c.applicationContext
        main.post {
            if (!listening) clipboard()?.addPrimaryClipChangedListener(listener)
            listening = true
            lastSeen = -1L
            check()
        }
    }

    fun stop() {
        main.post {
            if (listening) clipboard()?.removePrimaryClipChangedListener(listener)
            listening = false
        }
    }

    /** A desktop window got the focus: Android may have a newer entry from another app by now. */
    fun focused() {
        main.post { if (listening) check() }
    }

    /** Tells the desktop when Android's clipboard has text it hasn't heard about (main thread). */
    private fun check() {
        if (!NativeDesk.running) return
        // The description alone: reading it doesn't count as reading the clipboard.
        val d = runCatching { clipboard()?.primaryClipDescription }.getOrNull() ?: return
        val stamp = d.timestamp
        if (stamp == lastSeen) return
        lastSeen = stamp
        if (d.label == LABEL) return // the desktop's own text, back from Android
        if (!d.hasMimeType("text/*")) return // images, files...: the desktop keeps what it has
        NativeDesk.nativeClipboardChanged()
    }

    /** From the compositor (any thread): a pipe from the desktop. */
    fun fromDesktop(kind: Int, fd: Int) {
        val pfd = runCatching { ParcelFileDescriptor.adoptFd(fd) }.getOrNull() ?: return
        when (kind) {
            CLIP_DESKTOP -> Thread({ copied(pfd) }, "deskdroid-clip-in").start()
            CLIP_PASTE -> main.post { paste(pfd) }
            else -> runCatching { pfd.close() }
        }
    }

    /** A desktop app copied text: it becomes Android's clipboard. */
    private fun copied(pfd: ParcelFileDescriptor) {
        val bytes = java.io.ByteArrayOutputStream()
        try {
            ParcelFileDescriptor.AutoCloseInputStream(pfd).use { input ->
                val buf = ByteArray(16384)
                while (bytes.size() < MAX_BYTES) {
                    // An app that never writes or closes its end doesn't hold this thread forever.
                    val p = StructPollfd().apply { this.fd = pfd.fileDescriptor; events = OsConstants.POLLIN.toShort() }
                    if (Os.poll(arrayOf(p), TIMEOUT_MS) <= 0) break
                    val n = input.read(buf)
                    if (n < 0) break
                    bytes.write(buf, 0, n)
                }
            }
        } catch (e: Exception) {
            AppLog.i("Shared clipboard: couldn't read the desktop's text: $e")
            return
        }
        if (bytes.size() == 0) return
        val text = String(bytes.toByteArray(), Charsets.UTF_8)
        main.post {
            runCatching { clipboard()?.setPrimaryClip(ClipData.newPlainText(LABEL, text)) }
                .onFailure { AppLog.i("Shared clipboard: Android refused the desktop's text: $it") }
        }
    }

    /** A desktop app pastes: Android's clipboard text goes into its pipe (main thread). */
    private fun paste(pfd: ParcelFileDescriptor) {
        val c = app
        val text = runCatching {
            clipboard()?.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.let { item ->
                if (c != null) item.coerceToText(c)?.toString() else item.text?.toString()
            }
        }.getOrNull()
        if (text == null) {
            // Android hides its clipboard while none of DeskDroid's windows has the focus.
            AppLog.i("Shared clipboard: Android's clipboard wasn't readable for a paste")
            runCatching { pfd.close() }
            return
        }
        Thread({
            runCatching {
                ParcelFileDescriptor.AutoCloseOutputStream(pfd).use { it.write(text.toByteArray(Charsets.UTF_8)) }
            }.onFailure { AppLog.i("Shared clipboard: the paste went away: $it") }
        }, "deskdroid-clip-out").start()
    }

    // protocol.h's NDESK_CLIP_*
    private const val CLIP_DESKTOP = 1
    private const val CLIP_PASTE = 2
}
