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
 * Plays the desktop's sound. The sound server (native/sound, PipeWire) writes
 * 48 kHz stereo s16le into a FIFO (its pipe tunnel sink, "Phone"); this thread
 * reads it and feeds an AudioTrack, which pauses while the desktop
 * is quiet. Nothing native to build, so it stays F-Droid friendly.
 *
 * While the phone sleeps (SleepMode, setPowerSave) the track is a
 * power-saving one with a second of buffer, which Android can play from its
 * deep buffer with the processor asleep in between, instead of the
 * low-latency path that wakes it every few milliseconds; the sound server
 * meanwhile writes big chunks (PowerProfile's sleep quantum), so the pipe grows to hold them.
 */
class AudioBridge(private val pipe: File) {
    @Volatile private var running = false
    @Volatile private var powerSave = false

    /** Sleep (true) or awake: the track is rebuilt for it with the next sound. */
    fun setPowerSave(on: Boolean) { powerSave = on }
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
                // open() blocks until the sound server opens the other end.
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
        while (running) if (!playMode(input, powerSave)) return
    }

    /** Plays until the writer closes (false) or the power mode changes (true). */
    private fun playMode(input: FileInputStream, saving: Boolean): Boolean {
        // Shrinking fails while more than the new size is waiting: it's tried again next change.
        try { Os.fcntlInt(input.fd, F_SETPIPE_SZ, if (saving) SLEEP_PIPE else AWAKE_PIPE) } catch (_: Exception) {}
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
                    .setContentType(if (saving) AudioAttributes.CONTENT_TYPE_MUSIC else AudioAttributes.CONTENT_TYPE_UNKNOWN)
                    .build()
            )
            .setAudioFormat(format)
            .setBufferSizeInBytes(if (saving) maxOf(minBuf * 2, RATE * FRAME_BYTES) else minBuf * 2)
            .setPerformanceMode(if (saving) AudioTrack.PERFORMANCE_MODE_POWER_SAVING else AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            .build()
        AppLog.i("audio: " + if (saving) "power-saving track (1 s buffer) while asleep" else "low-latency track")
        // The server only writes while something plays. A playing AudioTrack
        // keeps Android's audio output powered even when starved, so the track
        // pauses after a quiet spell and starts again with the next sound.
        var playing = false
        val poll = arrayOf(StructPollfd().apply { fd = input.fd; events = OsConstants.POLLIN.toShort() })
        try {
            val buf = ByteArray(if (saving) 64 * 1024 else FRAME_BYTES * 256)
            while (running) {
                if (powerSave != saving) return true
                if (Os.poll(poll, if (playing) IDLE_MS else -1) == 0) {
                    track.pause()
                    track.flush()
                    playing = false
                    continue
                }
                val n = input.read(buf)
                if (n < 0) return false // writer closed; reopen
                if (n > 0) {
                    if (!playing) { track.play(); playing = true }
                    track.write(buf, 0, n - n % FRAME_BYTES)
                }
            }
        } finally {
            track.stop()
            track.release()
        }
        return false
    }

    /** The pipe's size is the sound server's latency: 64 KiB default is ~340 ms, 16 KiB ~85 ms. */
    private fun shrinkPipe(input: FileInputStream) {
        try { Os.fcntlInt(input.fd, F_SETPIPE_SZ, AWAKE_PIPE) } catch (_: Exception) {}
    }

    companion object {
        const val RATE = 48_000
        private const val FRAME_BYTES = 4
        private const val F_SETPIPE_SZ = 1031
        private const val AWAKE_PIPE = 16 * 1024
        /** Asleep: room for a few of the sound server's 8192-frame (32 KiB) chunks; Linux allows up to 1 MiB. */
        private const val SLEEP_PIPE = 256 * 1024
        /** Silence after which the track pauses. */
        private const val IDLE_MS = 3000
    }
}
