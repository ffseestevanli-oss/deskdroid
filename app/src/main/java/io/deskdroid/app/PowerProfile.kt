package io.deskdroid.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.PowerManager
import android.system.Os
import android.system.OsConstants
import java.io.File

/**
 * The desktop's power profiles: Power Save, Balanced and Performance, like a
 * Linux PC's, for everything DeskDroid runs (KWin, Plasma, the Linux and
 * Windows apps under Box64 and FEX, Flatpaks).
 *
 * Android runs the desktop as a foreground service, so its own power saving
 * (Battery Saver, the background CPU limits) never reaches it, and without root
 * an app can't touch CPU clocks. What an app may do to its own processes, and
 * what each profile does with it:
 *
 *  - Frames: the compositor hands out at most so many frames a second
 *    (nativeSetFrameCap), and KWin, Plasma and the apps draw when it does. It
 *    also asks Android to drop a 90/120 Hz screen to that rate.
 *  - CPU cores: every desktop thread may only run on some of the phone's cores
 *    (sched_setaffinity). The efficient cores use a fraction of the power of
 *    the big ones at the same work, so this is where most of the saving is.
 *    Programs that size their thread pools by core count start fewer threads.
 *  - CPU cap: an app (one process) that keeps using more than its share of
 *    CPU is paused and resumed in short slices so it averages that share
 *    (SIGSTOP/SIGCONT, like cpulimit). Light work (music, downloads, a text
 *    editor) never reaches the cap and runs untouched. KWin, Plasma, the
 *    sound server and sound effects (ViPER FX, EasyEffects), D-Bus, the GPU server, terminal programs and anything
 *    being debugged are never paused.
 *
 *                     frames/s   cores                     app CPU cap
 *    Performance      screen's   all                       none
 *    Balanced         60         all but the fastest kind  none
 *    Power Save       30         the efficient ones        1 core
 *
 * While the phone sleeps (SleepMode: screen off, "Save power when off") the
 * compositor gives 1 frame a second whatever the profile, every profile moves
 * to the efficient cores, and the cap drops to 1 core (Performance), half a
 * core (Balanced) or a quarter of one (Power Save).
 *
 * Power Save also turns KDE's animations off (System Settings' animation
 * speed set to instant, AnimationDurationFactor=0 in kdeglobals), so the
 * slower desktop doesn't spend its time animating; the other profiles put
 * back whatever speed was set before (Animations).
 *
 * Android's Battery Saver puts the desktop on Power Save while it's on, unless
 * that's turned off in the settings. The choice is in the desktop's Battery
 * item (android-open deskdroid:power:<profile>) and DeskDroid's settings.
 */
object PowerProfile {
    val NAMES = listOf("powersave", "balanced", "performance")

    private class Limits(val fps: Int, val cores: Long, val cap: Double)

    @Volatile private var app: Context? = null
    @Volatile var effective = "balanced"
        private set
    @Volatile var forcedBySaver = false
        private set
    private var asleep = false
    private val main = Handler(Looper.getMainLooper())
    private val worker by lazy { HandlerThread("power-profile").also { it.start() }.let { Handler(it.looper) } }
    private val saverReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) = apply("battery saver changed")
    }

    /** With the desktop: applies the profile now and keeps it applied. */
    fun start(c: Context) = main.post {
        if (app != null) return@post
        val a = c.applicationContext
        app = a
        a.registerReceiver(saverReceiver, IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED))
        AppLog.i("Power: cores ${Cores.describe()}")
        // Anything a crash left paused goes again before the cap takes over.
        worker.post { Throttle.resumeStragglers(a.packageName) }
        apply("desktop started")
        worker.removeCallbacks(reapply)
        worker.postDelayed(reapply, REAPPLY_MS)
        // KWin and plasmashell may not have been on the bus yet: tell them again.
        worker.postDelayed({ app?.let { Animations.notifyAgain(it) } }, 15_000)
    }

    /** The desktop stops: every paused app goes again (before it's told to quit). */
    fun stop() {
        main.post {
            val a = app ?: return@post
            app = null
            try { a.unregisterReceiver(saverReceiver) } catch (e: Exception) {}
        }
        worker.removeCallbacks(reapply)
        Throttle.setCap(0.0, asleep = false)
        Throttle.resumeAll()
    }

    /** The profile picked in the Battery item or the settings. */
    fun set(c: Context, name: String) {
        if (name !in NAMES) return
        Prefs.setPowerProfile(c, name)
        main.post { apply("chosen: $name") }
    }

    /** Settings: "Follow Battery Saver" changed. */
    fun prefChanged() = main.post { apply("setting changed") }

    /** SleepMode: the phone went to sleep or woke up. */
    fun sleepChanged(sleeping: Boolean) = main.post {
        asleep = sleeping
        apply(if (sleeping) "asleep" else "awake")
    }

    private fun apply(why: String) {
        val a = app ?: return
        val saver = Prefs.followBatterySaver(a) &&
            a.getSystemService(PowerManager::class.java)?.isPowerSaveMode == true
        val chosen = Prefs.powerProfile(a)
        val name = if (saver) "powersave" else chosen
        forcedBySaver = saver && chosen != "powersave"
        effective = name
        val l = limits(name, asleep)
        if (NativeDesk.running) NativeDesk.nativeSetFrameCap(l.fps)
        val pkg = a.packageName
        worker.post {
            Animations.apply(a, off = name == "powersave")
            Affinity.apply(pkg, l.cores)
            Throttle.setCap(l.cap, asleep)
            if (l.cap > 0) Throttle.start(pkg)
        }
        PhoneStatus.refresh()
        AppLog.i("Power: $name" + (if (forcedBySaver) " (Battery Saver)" else "") + (if (asleep) ", asleep" else "") +
            " · ${if (l.fps > 0) "${l.fps} fps" else "screen's frame rate"} · cores ${Cores.list(l.cores)}" +
            " · ${if (l.cap > 0) "apps capped at ${(l.cap * 100).toInt()}% of a core" else "no CPU cap"} ($why)")
    }

    private fun limits(name: String, sleeping: Boolean): Limits {
        val all = Cores.all
        if (sleeping) return when (name) {
            "performance" -> Limits(0, Cores.efficient, 1.0)
            "powersave" -> Limits(30, Cores.efficient, 0.25)
            else -> Limits(60, Cores.efficient, 0.5)
        }
        return when (name) {
            "performance" -> Limits(0, all, 0.0)
            "powersave" -> Limits(30, Cores.efficient, 1.0)
            else -> Limits(60, Cores.balanced, 0.0)
        }
    }

    // Android may move the desktop between its CPU groups (and older kernels
    // then forget a thread's cores), and new threads should follow too.
    private const val REAPPLY_MS = 20_000L
    private val reapply = object : Runnable {
        override fun run() {
            val a = app ?: return
            val l = limits(effective, asleep)
            Affinity.apply(a.packageName, l.cores, quiet = true)
            worker.postDelayed(this, if (asleep) REAPPLY_MS * 3 else REAPPLY_MS)
        }
    }

    /** "Power Save", "Balanced", "Performance". */
    fun label(name: String) = when (name) { "powersave" -> "Power Save"; "performance" -> "Performance"; else -> "Balanced" }

    /**
     * The desktop's processes: DeskDroid's user's processes other than the
     * Android app's own (named after the package), with their command lines.
     */
    internal fun desktopProcesses(pkg: String): List<Pair<Int, String>> {
        val me = android.os.Process.myPid()
        val uid = android.os.Process.myUid()
        val out = ArrayList<Pair<Int, String>>()
        for (dir in File("/proc").listFiles() ?: return out) {
            val pid = dir.name.toIntOrNull() ?: continue
            if (pid == me) continue
            try {
                if (Os.stat(dir.path).st_uid != uid) continue
                val raw = File(dir, "cmdline").readBytes()
                if (raw.isEmpty()) continue
                val cmd = String(raw, Charsets.UTF_8).trimEnd('\u0000')
                if (cmd.startsWith(pkg)) continue
                out += pid to cmd
            } catch (e: Exception) {
                // Gone already, or not ours to look at.
            }
        }
        return out
    }

    /** The phone's CPU cores, grouped by kind (by their top speed). */
    internal object Cores {
        private val maxFreq: Map<Int, Long> by lazy {
            val ids = possible()
            val freq = ids.associateWith { readLong("/sys/devices/system/cpu/cpu$it/cpufreq/cpuinfo_max_freq") }
            if (freq.values.all { it > 0 }) return@lazy freq
            val cap = ids.associateWith { readLong("/sys/devices/system/cpu/cpu$it/cpu_capacity") }
            if (cap.values.all { it > 0 }) return@lazy cap
            // Nothing readable: phones number their slow cores first.
            ids.associateWith { if (it < ids.size / 2) 1L else 2L }
        }
        /** Kinds of core, slowest first. */
        private val clusters: List<List<Int>> by lazy {
            maxFreq.entries.groupBy({ it.value }, { it.key }).toSortedMap().values.map { it.sorted() }
        }
        val all: Long by lazy { mask(maxFreq.keys) }
        /** The slowest kind, or with fewer than 2 of those, the next kind too; half the cores if they're all alike. */
        val efficient: Long by lazy {
            if (clusters.size <= 1) return@lazy mask(maxFreq.keys.sorted().take((maxFreq.size / 2).coerceAtLeast(1)))
            val picked = ArrayList(clusters[0])
            var i = 1
            while (picked.size < 2 && i < clusters.size - 1) picked += clusters[i++]
            mask(picked)
        }
        /** All but the fastest kind, when there are three kinds or more (the fastest is then one or two "prime" cores). */
        val balanced: Long by lazy {
            if (clusters.size < 3) all else mask(clusters.dropLast(1).flatten())
        }

        fun describe() = clusters.joinToString(" + ") { c -> "${c.size}×${maxFreq[c[0]]}" } + " (efficient ${list(efficient)})"
        fun list(m: Long) = (0 until 64).filter { m shr it and 1L == 1L }.joinToString(",")

        private fun mask(ids: Collection<Int>) = ids.fold(0L) { m, i -> if (i < 64) m or (1L shl i) else m }
        private fun readLong(path: String) = try { File(path).readText().trim().toLong() } catch (e: Exception) { 0L }
        private fun possible(): List<Int> {
            val spec = try { File("/sys/devices/system/cpu/possible").readText().trim() } catch (e: Exception) { "" }
            val ids = spec.split(',').filter { it.isNotBlank() }.flatMap { r ->
                val (a, b) = if ('-' in r) r.split('-').let { it[0].toInt() to it[1].toInt() } else r.toInt() to r.toInt()
                (a..b).toList()
            }
            return ids.ifEmpty { (0 until Runtime.getRuntime().availableProcessors()).toList() }
        }
    }

    /**
     * KDE's animation speed: off (instant) on Power Save, else what it was.
     * The speed set before Power Save is kept in config/deskdroid-animations
     * ("default" when none was set) until another profile puts it back.
     */
    private object Animations {
        private const val KEY = "AnimationDurationFactor"
        private var last: Boolean? = null

        fun apply(c: Context, off: Boolean) {
            val config = File(c.filesDir, "config")
            val globals = File(config, "kdeglobals")
            val saved = File(config, "deskdroid-animations")
            val text = if (globals.exists()) globals.readText() else ""
            val now = Ini.get(text, "KDE", KEY)
            val next = if (off) {
                if (!saved.exists()) saved.writeText(now ?: "default")
                "0"
            } else {
                if (!saved.exists()) { last = off; return } // never turned off: the person's own setting stands
                saved.readText().trim().takeUnless { it == "default" || it.isEmpty() }.also { saved.delete() }
            }
            if (next != now) {
                config.mkdirs()
                globals.writeText(Ini.set(text, "KDE", KEY, next))
                AppLog.i("Power: animations " + if (off) "off" else "back (${next ?: "default speed"})")
                notify(c)
            } else if (last != off && last != null) notify(c)
            last = off
        }

        fun notifyAgain(c: Context) { if (last == true) notify(c) }

        private fun notify(c: Context) {
            val ok = KdeConfigNotify.send(File(c.cacheDir, "runtime/bus"), "kdeglobals", mapOf("KDE" to listOf(KEY)))
            if (!ok) AppLog.i("Power: couldn't tell the desktop about the animation change (it applies on the next start)")
        }
    }

    /** Just enough of KConfig's ini format to read and change one key. */
    internal object Ini {
        fun get(text: String, group: String, key: String): String? {
            var inGroup = false
            for (line in text.lines()) {
                val t = line.trim()
                if (t.startsWith("[")) inGroup = t == "[$group]"
                else if (inGroup && t.substringBefore('=').trim() == key && '=' in t) return t.substringAfter('=').trim()
            }
            return null
        }

        /** [value] null removes the key. */
        fun set(text: String, group: String, key: String, value: String?): String {
            val lines = text.lines().toMutableList()
            var start = -1
            var end = lines.size
            for ((i, line) in lines.withIndex()) {
                val t = line.trim()
                if (t.startsWith("[")) {
                    if (start >= 0) { end = i; break }
                    if (t == "[$group]") start = i
                }
            }
            if (start < 0) {
                if (value == null) return text
                val base = text.trimEnd('\n')
                return (if (base.isEmpty()) "" else "$base\n\n") + "[$group]\n$key=$value\n"
            }
            val at = (start + 1 until end).firstOrNull { lines[it].trim().let { t -> '=' in t && t.substringBefore('=').trim() == key } }
            when {
                at != null && value != null -> lines[at] = "$key=$value"
                at != null -> lines.removeAt(at)
                value != null -> lines.add(start + 1, "$key=$value")
            }
            return lines.joinToString("\n")
        }
    }

    /** Which cores the desktop's threads may run on. */
    private object Affinity {
        fun apply(pkg: String, cores: Long, quiet: Boolean = false) {
            if (cores == 0L) return
            var changed = 0
            var refused = 0
            for ((pid, _) in desktopProcesses(pkg)) {
                val tasks = File("/proc/$pid/task").list() ?: continue
                for (t in tasks) {
                    val tid = t.toIntOrNull() ?: continue
                    val now = NativeDesk.nativeGetAffinity(tid)
                    if (now == -1L) continue
                    // Android's CPU groups bound what a thread gets, so with
                    // "all cores" a smaller mask that is all there is counts as done.
                    if (now == cores || (cores == all() && now and cores == now && !narrowed)) continue
                    if (NativeDesk.nativeSetAffinity(tid, cores) == 0) changed++ else refused++
                }
            }
            narrowed = cores != all()
            if (!quiet || refused > 0) AppLog.i("Power: $changed desktop threads to cores ${Cores.list(cores)}" +
                if (refused > 0) ", $refused refused" else "")
        }
        // The last mask applied was smaller than every core: "all" has to be set again everywhere.
        private var narrowed = false
        private fun all() = Cores.all
    }

    /**
     * The CPU cap: an app over its share of CPU, averaged over a short
     * window, is paused until the average is back under it.
     */
    internal object Throttle {
        private val handler by lazy { HandlerThread("power-cap").also { it.start() }.let { Handler(it.looper) } }
        private val ticksPerSecond by lazy {
            try { Os.sysconf(OsConstants._SC_CLK_TCK).toDouble() } catch (e: Exception) { 100.0 }
        }
        @Volatile private var cap = 0.0
        @Volatile private var sleeping = false
        @Volatile private var running = false
        private var pkg = ""
        private const val WINDOW = 5 // samples in the average
        private val samples = HashMap<Int, ArrayDeque<Pair<Long, Long>>>() // pid -> (time ns, CPU ticks)
        private val paused = HashSet<Int>()
        private var candidates = listOf<Int>()
        private var lastScan = 0L
        private var lastBusy = 0L
        private var pausesSinceLog = 0
        private var logged = false

        /** Never paused: the desktop itself, its services, and what a person is driving by hand. */
        private val EXEMPT = listOf(
            "libkwin_wayland.so", "libplasmashell.so", "pipewire", "wireplumber",
            "dbus-daemon", "virgl", "/system/bin/sh", "ksmserver", "kded",
            // Sound effects run in the sound server's cycle: pausing one stops all sound.
            "viperfx", "easyeffects"
        )

        fun setCap(c: Double, asleep: Boolean) {
            sleeping = asleep
            if (c == cap) return
            cap = c
            if (c <= 0) handler.post { resumeAll() }
        }

        fun start(p: String) = handler.post {
            pkg = p
            if (running) return@post
            running = true
            handler.post(tick)
        }

        private val tick = object : Runnable {
            override fun run() {
                if (cap <= 0) { running = false; resumeAll(); return }
                val now = System.nanoTime()
                // Fast while something is being held back, slow while nothing is.
                val period = when {
                    paused.isNotEmpty() || now - lastBusy < 3_000_000_000L -> if (sleeping) 250L else 100L
                    else -> 1000L
                }
                try { synchronized(paused) { step(now) } } catch (e: Exception) { AppLog.i("Power: CPU cap: $e") }
                handler.postDelayed(this, period)
            }
        }

        private fun step(now: Long) {
            if (now - lastScan > 2_000_000_000L) {
                lastScan = now
                candidates = desktopProcesses(pkg).filter { (pid, cmd) -> EXEMPT.none { it in cmd } && capable(pid) }.map { it.first }
                samples.keys.retainAll(candidates.toSet())
                if (!logged) { logged = true; AppLog.i("Power: CPU cap watching ${candidates.size} app process(es)") }
                paused.filter { it !in candidates }.forEach { signal(it, OsConstants.SIGCONT); paused -= it }
            }
            for (pid in candidates) {
                val ticks = cpuTicks(pid) ?: continue
                val q = samples.getOrPut(pid) { ArrayDeque() }
                q.addLast(now to ticks)
                while (q.size > WINDOW + 1) q.removeFirst()
                if (q.size < 2) continue
                val (t0, k0) = q.first()
                val secs = (now - t0) / 1e9
                if (secs <= 0) continue
                val use = (ticks - k0) / ticksPerSecond / secs // cores
                if (use > cap) {
                    lastBusy = now
                    if (paused.add(pid)) { signal(pid, OsConstants.SIGSTOP); pausesSinceLog++ }
                } else if (pid in paused) {
                    paused -= pid
                    signal(pid, OsConstants.SIGCONT)
                }
            }
            if (pausesSinceLog >= 200) {
                AppLog.i("Power: CPU cap holding back ${paused.size} app(s) (${(cap * 100).toInt()}% of a core each)")
                pausesSinceLog = 0
            }
        }

        /**
         * Safe to pause: not being traced (a debugger, or a tracer that would
         * see the stop itself) and not run from a terminal, where a shell
         * would take the pause for Ctrl+Z and put the program in the background.
         */
        private fun capable(pid: Int): Boolean = try {
            val stat = File("/proc/$pid/stat").readText()
            val f = stat.substring(stat.lastIndexOf(')') + 2).split(' ')
            val ttyNr = f[4].toInt()
            val tracer = File("/proc/$pid/status").useLines { l -> l.firstOrNull { it.startsWith("TracerPid:") } }
                ?.substringAfter(':')?.trim()?.toIntOrNull() ?: 0
            ttyNr == 0 && tracer == 0 && f[0] != "Z"
        } catch (e: Exception) { false }

        private fun cpuTicks(pid: Int): Long? = try {
            val stat = File("/proc/$pid/stat").readText()
            val f = stat.substring(stat.lastIndexOf(')') + 2).split(' ')
            f[11].toLong() + f[12].toLong()
        } catch (e: Exception) { null }

        private fun signal(pid: Int, sig: Int) {
            try { Os.kill(pid, sig) } catch (e: Exception) {}
        }

        /** Every app the cap paused goes again. */
        fun resumeAll() {
            val list = synchronized(paused) { paused.toList().also { paused.clear() } }
            list.forEach { signal(it, OsConstants.SIGCONT) }
            if (list.isNotEmpty()) AppLog.i("Power: CPU cap off, ${list.size} app(s) resumed")
        }

        /** Desktop processes left stopped (DeskDroid ended while the cap held them) go again. */
        fun resumeStragglers(pkg: String) {
            var n = 0
            for ((pid, cmd) in desktopProcesses(pkg)) {
                if (EXEMPT.any { it in cmd }) continue
                val state = try { File("/proc/$pid/stat").readText().let { it.substring(it.lastIndexOf(')') + 2).substringBefore(' ') } } catch (e: Exception) { continue }
                if (state == "T" && capable(pid)) { signal(pid, OsConstants.SIGCONT); n++ }
            }
            if (n > 0) AppLog.i("Power: $n paused app(s) left from before resumed")
        }
    }
}
