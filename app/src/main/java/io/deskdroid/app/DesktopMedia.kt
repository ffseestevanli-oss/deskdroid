package io.deskdroid.app

import android.content.Context
import android.content.Intent
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent

/**
 * The phone's media buttons for desktop apps: a Bluetooth earpiece, a remote,
 * a headset's button. Android only hands those to a media session, so while a
 * desktop app plays (KWin watches its MPRIS players, protocol.h's PLAYING)
 * DeskDroid keeps one that does nothing but pass the keys on. KWin sends them
 * to the player (MPRIS), the way Plasma's own media keys work.
 *
 * Only the keys go this way. Desktop apps play their own sound as before:
 * the session asks for no audio focus, plays nothing and shows no
 * notification, so Android's apps and desktop apps don't pause each other.
 * With nothing playing or paused on the desktop it goes away, and the
 * buttons belong to Android's apps again.
 */
object DesktopMedia {
    private val main = Handler(Looper.getMainLooper())
    private var session: MediaSession? = null
    private var state = 0

    private const val ACTIONS = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
        PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_STOP or
        PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS or
        PlaybackState.ACTION_FAST_FORWARD or PlaybackState.ACTION_REWIND

    private val MEDIA_KEYS = setOf(
        KeyEvent.KEYCODE_HEADSETHOOK, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, KeyEvent.KEYCODE_MEDIA_STOP,
        KeyEvent.KEYCODE_MEDIA_NEXT, KeyEvent.KEYCODE_MEDIA_PREVIOUS, KeyEvent.KEYCODE_MEDIA_REWIND,
        KeyEvent.KEYCODE_MEDIA_FAST_FORWARD, KeyEvent.KEYCODE_MEDIA_PLAY, KeyEvent.KEYCODE_MEDIA_PAUSE)

    private val callback = object : MediaSession.Callback() {
        override fun onMediaButtonEvent(intent: Intent): Boolean {
            @Suppress("DEPRECATION")
            val e = intent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT) ?: return false
            if (e.keyCode !in MEDIA_KEYS || !NativeDesk.running) return false
            when (e.action) {
                KeyEvent.ACTION_DOWN -> if (e.repeatCount == 0) NativeDesk.nativeKey(e.keyCode, 0, true)
                KeyEvent.ACTION_UP -> NativeDesk.nativeKey(e.keyCode, 0, false)
            }
            return true
        }
        // The same, from controls that call the session directly.
        override fun onPlay() = tap(KeyEvent.KEYCODE_MEDIA_PLAY)
        override fun onPause() = tap(KeyEvent.KEYCODE_MEDIA_PAUSE)
        override fun onStop() = tap(KeyEvent.KEYCODE_MEDIA_STOP)
        override fun onSkipToNext() = tap(KeyEvent.KEYCODE_MEDIA_NEXT)
        override fun onSkipToPrevious() = tap(KeyEvent.KEYCODE_MEDIA_PREVIOUS)
        override fun onFastForward() = tap(KeyEvent.KEYCODE_MEDIA_FAST_FORWARD)
        override fun onRewind() = tap(KeyEvent.KEYCODE_MEDIA_REWIND)
    }

    private fun tap(code: Int) {
        if (!NativeDesk.running) return
        NativeDesk.nativeKey(code, 0, true)
        NativeDesk.nativeKey(code, 0, false)
    }

    @Volatile private var app: Context? = null

    /** The desktop started. */
    fun start(c: Context) {
        app = c.applicationContext
    }

    /** From the compositor (any thread): protocol.h's NDESK_PLAYING_* (0 none, 1 paused, 2 playing). */
    fun desktopState(playing: Int) {
        main.post { apply(app, playing) }
    }

    /** The desktop stopped. */
    fun stop() {
        main.post { apply(null, 0) }
    }

    private fun apply(c: Context?, playing: Int) {
        if (playing == state && (playing == 0 || session != null)) return
        state = playing
        if (playing == 0 || c == null) {
            session?.run { isActive = false; release() }
            session = null
            return
        }
        val s = session ?: MediaSession(c, "DeskDroid desktop").also {
            it.setCallback(callback, main)
            session = it
        }
        s.setPlaybackState(PlaybackState.Builder()
            .setActions(ACTIONS)
            .setState(if (playing == 2) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                PlaybackState.PLAYBACK_POSITION_UNKNOWN, if (playing == 2) 1f else 0f)
            .build())
        s.isActive = true
    }
}
