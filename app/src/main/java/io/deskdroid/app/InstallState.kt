package io.deskdroid.app

import android.os.Handler
import android.os.Looper

/** Install progress shared by InstallService and the Installing screen. */
object InstallState {
    enum class Step { IDLE, DOWNLOAD, VERIFY, UNPACK, ACCOUNT, DONE, FAILED }

    data class Snapshot(
        val step: Step = Step.IDLE,
        /** 0..1 within the current step, or -1 when unknown. */
        val fraction: Float = -1f,
        val detail: String = "",
        val error: String? = null,
    ) {
        val running get() = step != Step.IDLE && step != Step.DONE && step != Step.FAILED

        /** Whole-install progress for the ring: download is most of the time. */
        val overall: Float get() {
            val f = fraction.coerceIn(0f, 1f)
            return when (step) {
                Step.IDLE -> 0f
                Step.DOWNLOAD -> 0.60f * f
                Step.VERIFY -> 0.60f + 0.08f * f
                Step.UNPACK -> 0.68f + 0.28f * f
                Step.ACCOUNT -> 0.96f + 0.04f * f
                Step.DONE -> 1f
                Step.FAILED -> 0f
            }
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private val listeners = mutableSetOf<(Snapshot) -> Unit>()

    @Volatile var current = Snapshot()
        private set

    /** Set by the cancel button; checked between chunks. */
    @Volatile var cancelled = false

    fun update(s: Snapshot) {
        val stepChanged = s.step != current.step
        current = s
        if (stepChanged || s.error != null) AppLog.i("install: ${s.step} ${s.detail} ${s.error ?: ""}")
        main.post { synchronized(listeners) { listeners.toList() }.forEach { it(s) } }
    }

    fun listen(l: (Snapshot) -> Unit) {
        synchronized(listeners) { listeners += l }
        main.post { l(current) }
    }

    fun unlisten(l: (Snapshot) -> Unit) = synchronized(listeners) { listeners -= l }
}
