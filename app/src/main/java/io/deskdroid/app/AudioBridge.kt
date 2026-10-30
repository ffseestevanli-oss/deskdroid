package io.deskdroid.app

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.system.Os
import android.system.OsConstants
import android.system.StructPollfd
import java.io.File
import java.io.FileInputStream

/**
 * Plays the desktop's sound. PulseAudio inside Debian writes 48 kHz stereo
 * s16le into a FIFO (module-pipe-sink, rootfs/overlay/etc/deskdroid/pulse.pa);
 * this thread reads it and feeds an AudioTrack, which pauses while the desktop
 * is quiet. Nothing native to build, so it stays F-Droid friendly.
 */
class AudioBridge(private val pipe: File) {
    @Volatile private var running = false
    private var thread: Thread? = null

    fun start() {
        pipe.parentFile!!.mkdirs()
        if (!pipe.exists()) Os.mkfifo(pipe.path, 0b110_110_000)
        running = true
        thread = Thread(::loop, "deskdroid-audio").apply { isDaemon = true; start() }
    }

    fun stop() {
        running = false
        // Unblock a reader waiting in open() for a writer. Non-blocking, so this
        // fails fast (ENXIO) instead of hanging when nobody is reading.
        try {
            Os.close(Os.open(pipe.path, OsConstants.O_WRONLY or OsConstants.O_NONBLOCK, 0))
        } catch (_: Exception) {}
        thread?.interrupt()
        thread = null
    }

    private fun loop() {
        while (running) {
            try {
                // open() blocks until PulseAudio opens the other end.
                FileInputStream(pipe).use { input ->
                    shrinkPipe(input)
                    play(input)
                }
            } catch (e: Exception) {
                if (running) AppLog.i("audio: ${e.message}")
                Thread.sleep(500)
            }
        }
    }

    private fun play(input: FileInputStream) {
        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(RATE)
            .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
            .build()
        val minBuf = AudioTrack.getMinBufferSize(RATE, AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT)
        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_UNKNOWN)
                    .build()
            )
            .setAudioFormat(format)
            .setBufferSizeInBytes(minBuf * 2)
            .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            .build()
        // PulseAudio only writes while something plays. A playing AudioTrack
        // keeps Android's audio output powered even when starved, so the track
        // pauses after a quiet spell and starts again with the next sound.
        var playing = false
        val poll = arrayOf(StructPollfd().apply { fd = input.fd; events = OsConstants.POLLIN.toShort() })
        try {
            val buf = ByteArray(FRAME_BYTES * 256)
            while (running) {
                if (Os.poll(poll, if (playing) IDLE_MS else -1) == 0) {
                    track.pause()
                    track.flush()
                    playing = false
                    continue
                }
                val n = input.read(buf)
                if (n < 0) break // writer closed; reopen
                if (n > 0) {
                    if (!playing) { track.play(); playing = true }
                    track.write(buf, 0, n - n % FRAME_BYTES)
                }
            }
        } finally {
            track.stop()
            track.release()
        }
    }

    /** The pipe's size is PulseAudio's latency: 64 KiB default is ~340 ms, 16 KiB ~85 ms. */
    private fun shrinkPipe(input: FileInputStream) {
        try { Os.fcntlInt(input.fd, F_SETPIPE_SZ, 16 * 1024) } catch (_: Exception) {}
    }

    companion object {
        const val RATE = 48_000
        private const val FRAME_BYTES = 4
        private const val F_SETPIPE_SZ = 1031
        /** Silence after which the track pauses. */
        private const val IDLE_MS = 3000
    }
}
