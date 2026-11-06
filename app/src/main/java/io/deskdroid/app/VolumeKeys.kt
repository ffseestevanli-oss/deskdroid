package io.deskdroid.app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.view.KeyEvent
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin

/**
 * Volume keys on the desktop: they set the phone's media volume (the desktop's
 * sound) with Android's slider, and play a short "doot" at the new level, like
 * Plasma does when the volume changes.
 */
object VolumeKeys {
    private var track: AudioTrack? = null

    /** True when [keyCode] was a volume key and is handled here. */
    fun onKeyDown(c: Context, keyCode: Int, e: KeyEvent): Boolean {
        val dir = when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> AudioManager.ADJUST_RAISE
            KeyEvent.KEYCODE_VOLUME_DOWN -> AudioManager.ADJUST_LOWER
            KeyEvent.KEYCODE_VOLUME_MUTE -> AudioManager.ADJUST_TOGGLE_MUTE
            else -> return false
        }
        val audio = c.getSystemService(AudioManager::class.java)
        audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, dir, AudioManager.FLAG_SHOW_UI)
        if (dir != AudioManager.ADJUST_TOGGLE_MUTE && audio.getStreamVolume(AudioManager.STREAM_MUSIC) > 0) doot()
        return true
    }

    fun isVolumeKey(k: Int) =
        k == KeyEvent.KEYCODE_VOLUME_UP || k == KeyEvent.KEYCODE_VOLUME_DOWN || k == KeyEvent.KEYCODE_VOLUME_MUTE

    private fun doot() {
        try {
            val t = track ?: make().also { track = it }
            t.stop()
            t.reloadStaticData()
            t.play()
        } catch (e: Exception) {
            AppLog.i("Volume sound: $e")
            track?.release(); track = null
        }
    }

    /** About 90 ms: a soft tone that drops a little in pitch and fades out. */
    private fun make(): AudioTrack {
        val rate = 44100
        val n = rate * 90 / 1000
        val pcm = ShortArray(n)
        var phase = 0.0
        for (i in 0 until n) {
            val t = i.toDouble() / rate
            val f = 740.0 - 120.0 * (i.toDouble() / n)
            phase += 2 * PI * f / rate
            val attack = (i / (rate * 0.004)).coerceAtMost(1.0)
            val env = attack * exp(-t * 38)
            pcm[i] = (sin(phase) * env * 0.5 * Short.MAX_VALUE).toInt().toShort()
        }
        return AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            .setAudioFormat(AudioFormat.Builder()
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(rate)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(n * 2)
            .build().apply { write(pcm, 0, n) }
    }
}
