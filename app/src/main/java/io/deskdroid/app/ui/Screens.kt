package io.deskdroid.app.ui

import android.app.Activity
import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.os.Build
import android.hardware.display.DisplayManager
import android.view.Display
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.io.File
import java.util.concurrent.TimeUnit
import io.deskdroid.app.AppLog
import io.deskdroid.app.BuildConfig
import io.deskdroid.app.Checks
import io.deskdroid.app.DesktopDefaults
import io.deskdroid.app.GpuProfile
import io.deskdroid.app.InstallService
import io.deskdroid.app.InstallState
import io.deskdroid.app.InstallState.Step
import io.deskdroid.app.Paths
import io.deskdroid.app.Prefs
import io.deskdroid.app.R
import io.deskdroid.app.SessionService
import io.deskdroid.app.VirglServer

/** One full-screen page of the launcher. MainActivity swaps between them. */
abstract class Screen(protected val activity: Activity, protected val nav: Navigator) {
    protected val ui = Ui(activity)
    protected val c = activity
    abstract fun build(): View
    open fun onShow() = Unit
    open fun onHide() = Unit

    /** Standard page: scrolling column with the mockups' padding. */
    protected fun page(glows: List<Triple<Float, Float, Int>>, top: Int = 44, block: LinearLayout.() -> Unit): View {
        val col = ui.column(14) {
            setPadding(c.dp(20), c.dp(top), c.dp(20), c.dp(28))
            block()
        }
        val scroll = ScrollView(c).apply {
            isFillViewport = true
            addView(col, FrameLayout.LayoutParams(-1, -2))
        }
        return ui.screen(glows, scroll)
    }

    protected fun backButton() = ImageView(c).apply {
        setImageResource(android.R.drawable.ic_media_previous)
        setColorFilter(Party.TEXT)
        contentDescription = "Back"
        setPadding(c.dp(10), c.dp(10), c.dp(10), c.dp(10))
        layoutParams = LinearLayout.LayoutParams(c.dp(44), c.dp(44))
        setOnClickListener { nav.back() }
    }
}

interface Navigator {
    fun go(screen: Screen)
    fun replace(screen: Screen)
    fun back()
    fun pickImageFile()
}

class WelcomeScreen(a: Activity, n: Navigator) : Screen(a, n) {
    override fun build() = page(listOf(Triple(0.1f, 0.3f, Party.PURPLE), Triple(0.95f, 0.45f, Party.CYAN)), top = 72) {
        gravity = Gravity.CENTER_HORIZONTAL
        spacer()
        addView(ui.logo(148), LinearLayout.LayoutParams(-2, -2).apply { gravity = Gravity.CENTER_HORIZONTAL })
        addView(ui.column(12) {
            gravity = Gravity.CENTER_HORIZONTAL
            addView(ui.text("WELCOME TO", 14f, Party.MUTED, 600).apply { letterSpacing = 0.3f })
            addView(ui.rainbowTitle("DeskDroid!", 40f))
            addView(ui.text("Your computer in your pocket!", 17f, Party.TEXT_SOFT, 600))
        }, LinearLayout.LayoutParams(-2, -2).apply { gravity = Gravity.CENTER_HORIZONTAL })
        addView(ui.column(8) {
            addView(ui.accentRow(Party.CYAN) { addView(ui.text("A full KDE Plasma desktop", 15f)) })
            addView(ui.accentRow(Party.GREEN) { addView(ui.text("Linux and Windows apps and games", 15f)) })
            addView(ui.accentRow(Party.PURPLE) { addView(ui.text("Monitor, keyboard, mouse, gamepad", 15f)) })
        }, LinearLayout.LayoutParams(-1, -2))
        spacer()
        addView(ui.primaryButton("Let's go") { nav.go(InstallScreen(activity, nav)) }, LinearLayout.LayoutParams(-1, -2))
        addView(ui.text("Free and open source · GPL-3.0", 13f, Party.MUTED).apply { gravity = Gravity.CENTER },
            LinearLayout.LayoutParams(-1, -2))
    }
}

class InstallScreen(a: Activity, n: Navigator) : Screen(a, n) {
    private var tier = "full"
    private var more = false
    private lateinit var cards: LinearLayout
    private lateinit var dl: TextView
    private lateinit var need: TextView
    private lateinit var free: TextView
    private lateinit var cta: TextView

    private val sizes = mapOf(
        "full" to Triple("~3.5 GB", "~12 GB", 12_000_000_000L),
        "light" to Triple("~1.2 GB", "~4 GB", 4_000_000_000L),
        "ultralite" to Triple("~0.6 GB", "~2 GB", 2_000_000_000L),
    )
    private val names = mapOf("full" to "Full", "light" to "Light", "ultralite" to "Ultra-lite")

    override fun build() = page(listOf(Triple(0.9f, 0.15f, Party.PINK))) {
        addView(backButton())
        addView(ui.column(6) {
            addView(ui.kicker("Step 1 / 3"))
            addView(ui.heading("Pick your loadout"))
            addView(ui.text("Both get you a Debian desktop with KDE Plasma. Add more later from Discover, Flathub included.",
                14f, Party.MUTED))
        })
        cards = ui.column(10)
        addView(cards, LinearLayout.LayoutParams(-1, -2))
        spacer()
        addView(ui.row(6) {
            dl = stat("DOWNLOAD", Party.ORANGE)
            need = stat("NEEDS", Party.CYAN)
            free = stat("FREE", Party.GREEN)
        }, LinearLayout.LayoutParams(-1, -2))
        cta = ui.primaryButton("Install Full") { start() }
        addView(cta, LinearLayout.LayoutParams(-1, -2))
        addView(ui.linkButton("Install from a file instead") { confirmFile() }, LinearLayout.LayoutParams(-1, -2))
        render()
    }

    private fun LinearLayout.stat(label: String, accent: Int): TextView {
        val value = ui.text("", 15f, Party.TEXT).apply { typeface = Party.orbitron(c) }
        addView(ui.weight(ui.column(2) {
            setPadding(c.dp(10), c.dp(8), c.dp(10), c.dp(8))
            background = ChamferDrawable(0f, fill = Party.SURFACE, cutTopLeft = false, cutBottomRight = false,
                accent = accent, accentEdge = Gravity.TOP, accentWidth = c.dp(2f))
            addView(ui.text(label, 12f, Party.MUTED).apply { letterSpacing = 0.08f })
            addView(value)
        }))
        return value
    }

    private fun render() {
        cards.removeAllViews()
        cards.addView(ui.card(tier == "full") {
            setOnClickListener { tier = "full"; render() }
            addView(ui.row(10) {
                addView(ui.text("FULL", 18f).apply { typeface = Party.orbitron(c); letterSpacing = 0.06f })
                addView(ui.text("RECOMMENDED", 10f, Party.BG, 700).apply {
                    letterSpacing = 0.14f
                    setPadding(c.dp(8), c.dp(2), c.dp(8), c.dp(2))
                    background = ChamferDrawable(0f, rainbowFill = true, cutTopLeft = false, cutBottomRight = false)
                })
                spacer()
                addView(ui.text("~3.5 GB", 13f, Party.MUTED))
            }, LinearLayout.LayoutParams(-1, -2))
            addView(ui.text("Jump right in. Gaming and work apps ready to go.", 13f, Party.TEXT_SOFT))
            addView(chips(listOf(
                "Steam" to (Party.GREEN to 0xFFB8F5CF.toInt()), "Lutris" to (Party.PINK to 0xFFFFC2F0.toInt()),
                "GIMP" to (Party.YELLOW to 0xFFFFF0A8.toInt()), "LibreOffice" to (Party.CYAN to 0xFFB5E8FF.toInt()),
                "Firefox" to (Party.ORANGE to 0xFFFFD6A0.toInt()), "Box64 + Wine" to (Party.PURPLE to 0xFFD2C2FF.toInt()),
                "+ all of Light" to (0xFF3A3A55.toInt() to Party.MUTED),
            )))
        })
        cards.addView(ui.card(tier == "light") {
            setOnClickListener { tier = "light"; render() }
            addView(ui.row {
                addView(ui.text("LIGHT", 18f).apply { typeface = Party.orbitron(c); letterSpacing = 0.06f })
                spacer()
                addView(ui.text("~1.2 GB", 13f, Party.MUTED))
            }, LinearLayout.LayoutParams(-1, -2))
            addView(ui.text("Just the desktop. Pick your own apps in Discover.", 13f, Party.TEXT_SOFT))
            addView(chips(listOf(
                "Plasma 6" to (Party.RED to 0xFFFFC2CC.toInt()), "Discover + Flathub" to (Party.CYAN to 0xFFB5E8FF.toInt()),
                "Files" to (0xFF3A3A55.toInt() to Party.MUTED), "Terminal" to (0xFF3A3A55.toInt() to Party.MUTED),
            )))
        })
        if (more) {
            cards.addView(ui.card(tier == "ultralite") {
                setOnClickListener { tier = "ultralite"; render() }
                addView(ui.row {
                    addView(ui.text("ULTRA-LITE", 16f).apply { typeface = Party.orbitron(c); letterSpacing = 0.06f })
                    spacer()
                    addView(ui.text("~0.6 GB", 13f, Party.MUTED))
                }, LinearLayout.LayoutParams(-1, -2))
                addView(ui.text("MATE desktop, ARM apps only. For older or low-storage phones.", 13f, Party.TEXT_SOFT))
            })
        } else {
            cards.addView(ui.text("…or there's this", 14f, Party.CYAN, 600).apply {
                minHeight = c.dp(40)
                gravity = Gravity.CENTER_VERTICAL
                setOnClickListener { more = true; render() }
            })
        }
        val (d, n, needBytes) = sizes.getValue(tier)
        dl.text = d
        need.text = n
        val freeBytes = Paths(c).files.usableSpace
        free.text = "%.0f GB".format(freeBytes / 1e9)
        free.setTextColor(if (freeBytes >= needBytes) Party.GREEN else Party.RED)
        cta.text = "INSTALL ${names.getValue(tier).uppercase()}"
    }

    private fun chips(items: List<Pair<String, Pair<Int, Int>>>) = FlowLayout(c, c.dp(5)).apply {
        for ((label, colors) in items) addView(ui.chip(label, colors.first, colors.second))
    }

    private fun start() {
        InstallService.startEdition(c, tier)
        nav.replace(InstallingScreen(activity, nav))
    }

    private fun confirmFile() {
        AlertDialog.Builder(c)
            .setTitle("Install from a file")
            .setMessage("Pick a DeskDroid system image (.tar.zst). Files you pick can't be checked for tampering, so only use ones you built or trust.")
            .setPositiveButton("Pick file") { _, _ -> nav.pickImageFile() }
            .setNegativeButton("Cancel", null)
            .show()
    }
}

class InstallingScreen(a: Activity, n: Navigator) : Screen(a, n) {
    private lateinit var percent: TextView
    private lateinit var detail: TextView
    private lateinit var bar: SegmentedProgress
    private lateinit var steps: LinearLayout
    private lateinit var title: TextView
    private lateinit var action: TextView
    private val listener: (InstallState.Snapshot) -> Unit = { render(it) }

    private val stepInfo = listOf(
        Triple(Step.DOWNLOAD, "Download", "Resumes if the connection drops"),
        Triple(Step.VERIFY, "Verify", "Checks the image is genuine"),
        Triple(Step.UNPACK, "Unpack", "Sets up Debian and Plasma"),
        Triple(Step.ACCOUNT, "Create your account", "Uses your phone's language and time zone"),
    )

    override fun build() = page(listOf(Triple(0.5f, 0.15f, Party.PINK)), top = 96) {
        addView(ui.column(10) {
            addView(ui.kicker("Step 2 / 3"))
            title = ui.heading("Loading…")
            addView(title)
            addView(ui.row {
                percent = ui.text("0%", 64f).apply { typeface = Party.orbitron(c) }
                addView(percent)
                spacer()
                detail = ui.text("", 14f, Party.MUTED).apply { gravity = Gravity.END }
                addView(detail)
            }, LinearLayout.LayoutParams(-1, -2))
            bar = SegmentedProgress(c)
            addView(bar, LinearLayout.LayoutParams(-1, c.dp(22)))
        })
        steps = ui.column(6)
        addView(steps, LinearLayout.LayoutParams(-1, -2))
        addView(ui.text("Go do something else. We'll ping you when it's ready.", 14f, Party.MUTED))
        spacer()
        action = ui.outlineButton("Cancel", Party.TEXT) { onAction() }
        addView(action, LinearLayout.LayoutParams(-1, -2))
    }

    override fun onShow() = InstallState.listen(listener)
    override fun onHide() = InstallState.unlisten(listener)

    private fun render(s: InstallState.Snapshot) {
        val pct = (s.overall * 100).toInt()
        percent.text = "$pct%"
        bar.indeterminate = s.fraction < 0 && s.running
        bar.fraction = s.overall
        detail.text = s.error ?: s.detail
        detail.setTextColor(if (s.error != null) Party.RED else Party.MUTED)
        title.text = when (s.step) {
            Step.FAILED -> "Hit a snag"
            Step.DONE -> "Ready!"
            Step.IDLE -> "Paused"
            else -> "Loading…"
        }.uppercase()
        action.text = when (s.step) {
            Step.FAILED, Step.IDLE -> "Try again"
            Step.DONE -> "Continue"
            else -> "Cancel"
        }
        steps.removeAllViews()
        val current = stepInfo.indexOfFirst { it.first == s.step }.let { if (s.step == Step.DONE) stepInfo.size else it }
        stepInfo.forEachIndexed { i, (_, name, sub) ->
            val active = i == current
            val done = i < current
            val color = when { active -> Party.CYAN; done -> Party.GREEN; else -> Party.DIM }
            steps.addView(ui.accentRow(if (active || done) color else Party.BORDER, if (active) Party.SURFACE else Party.SURFACE_DIM) {
                addView(ui.text("%02d".format(i + 1), 13f, color).apply {
                    typeface = Party.orbitron(c); layoutParams = LinearLayout.LayoutParams(c.dp(22), -2)
                })
                addView(ui.column(2) {
                    addView(ui.text(if (done) "$name ✓" else name, 15f, if (active || done) Party.TEXT else Party.DIM, 700))
                    addView(ui.text(sub, 13f, if (active) Party.MUTED else Party.DIM))
                })
            }, LinearLayout.LayoutParams(-1, -2))
        }
        if (s.step == Step.DONE) Prefs.setPendingEdition(c, null)
    }

    private fun onAction() {
        val s = InstallState.current
        when {
            s.step == Step.DONE -> nav.replace(KeepRunningScreen(activity, nav))
            s.running -> InstallService.cancel(c)
            else -> {
                val edition = Prefs.pendingEdition(c)
                if (edition != null) InstallService.startEdition(c, edition)
                else nav.replace(InstallScreen(activity, nav))
            }
        }
    }
}

class KeepRunningScreen(a: Activity, n: Navigator) : Screen(a, n) {
    private lateinit var childStatus: TextView
    private lateinit var batteryStatus: TextView

    override fun build() = page(listOf(Triple(0.85f, 0.2f, Party.GREEN))) {
        addView(ui.column(6) {
            addView(ui.row {
                addView(ui.kicker("Step 3 / 3 · "))
                addView(ui.kicker("Installed", Party.GREEN))
            })
            addView(ui.heading("Don't let Android kill the party"))
            addView(ui.text("Android shuts down apps that run lots of programs. A desktop does exactly that.", 14f, Party.MUTED))
        })
        addView(ui.column(10) {
            setPadding(c.dp(14), c.dp(14), c.dp(14), c.dp(14))
            background = ChamferDrawable(c.dp(14f), fill = Party.CARD, stroke = Party.ORANGE, strokeWidth = c.dp(1.5f), cutTopLeft = false)
            addView(ui.row(12) {
                addView(ui.text("!", 20f, Party.BG).apply {
                    typeface = Party.orbitron(c); gravity = Gravity.CENTER
                    background = ChamferDrawable(0f, fill = Party.ORANGE, cutTopLeft = false, cutBottomRight = false)
                    layoutParams = LinearLayout.LayoutParams(c.dp(32), c.dp(32))
                })
                addView(ui.weight(ui.column(2) {
                    addView(ui.text("Child process limit", 15f, Party.TEXT, 700))
                    childStatus = ui.text("", 13f, Party.MUTED)
                    addView(childStatus)
                }))
            })
            if (Checks.phantomFixIsToggle()) {
                addView(ui.outlineButton("Open Developer options", Party.ORANGE, Party.ORANGE) { openDevOptions() },
                    LinearLayout.LayoutParams(-1, -2))
            } else {
                addView(ui.outlineButton("Copy the fix command", Party.ORANGE, Party.ORANGE) { copyAdbCommand() },
                    LinearLayout.LayoutParams(-1, -2))
                addView(ui.text("Android 12 or 13: there's no switch for this, so it's fixed once with ADB " +
                    "(from a computer, or Wireless debugging with a local ADB app).", 12f, Party.MUTED))
            }
        }, LinearLayout.LayoutParams(-1, -2))
        addView(ui.accentRow(Party.CYAN, Party.CARD) {
            addView(ui.weight(ui.column(2) {
                addView(ui.text("Background + notifications", 15f, Party.TEXT, 700))
                batteryStatus = ui.text("", 13f, Party.MUTED)
                addView(batteryStatus)
            }))
            setOnClickListener { fixBattery() }
        }, LinearLayout.LayoutParams(-1, -2))
        addView(ui.switchRow("OPTIONAL", "Start on phone boot",
            "Desktop warms up in the background so it opens instantly. Uses some battery and about 1 GB of memory.",
            Prefs.autoStart(c)) { on ->
            Prefs.setAutoStart(c, on)
            if (on && !Checks.batteryUnrestricted(c)) Checks.requestBatteryUnrestricted(c)
        }, LinearLayout.LayoutParams(-1, -2))
        addView(ui.switchRow("OPTIONAL", "Lock my desktop",
            "Fingerprint or PIN to open DeskDroid.", Prefs.lockDesktop(c)) { on -> Prefs.setLockDesktop(c, on) },
            LinearLayout.LayoutParams(-1, -2))
        spacer()
        addView(ui.primaryButton("Continue") { finish() }, LinearLayout.LayoutParams(-1, -2))
        addView(ui.linkButton("Skip for now", Party.MUTED) { finish() }, LinearLayout.LayoutParams(-1, -2))
    }

    override fun onShow() = refresh()

    private fun refresh() {
        childStatus.text = when (Checks.phantomProcesses(c)) {
            Checks.State.OK -> "Fixed. Android won't stop the desktop for running too many programs."
            Checks.State.NOT_NEEDED -> "Not needed on this Android version."
            else -> if (Checks.phantomFixIsToggle())
                "Turn on “Disable child process restrictions” in Developer options. We'll jump you straight there."
            else "Needs a one-time fix with ADB."
        }
        val battery = Checks.batteryUnrestricted(c)
        val notes = Checks.notificationsAllowed(c)
        batteryStatus.text = when {
            battery && notes -> "All set"
            !battery -> "Tap to turn battery optimization off"
            else -> "Tap to allow the status notification"
        }
        batteryStatus.setTextColor(if (battery && notes) Party.GREEN else Party.MUTED)
    }

    private fun openDevOptions() {
        if (!Checks.developerOptionsEnabled(c)) {
            AlertDialog.Builder(c)
                .setTitle("Turn on Developer options first")
                .setMessage("In About phone, tap “Build number” 7 times. Then come back here.")
                .setPositiveButton("Open About phone") { _, _ -> Checks.openAboutPhone(c) }
                .setNegativeButton("Later", null).show()
        } else Checks.openDeveloperOptions(c)
    }

    private fun copyAdbCommand() {
        c.getSystemService(ClipboardManager::class.java)
            .setPrimaryClip(ClipData.newPlainText("ADB command", Checks.PHANTOM_ADB_COMMAND))
        AlertDialog.Builder(c).setMessage("Copied:\n\n${Checks.PHANTOM_ADB_COMMAND}")
            .setPositiveButton("OK", null).show()
    }

    private fun fixBattery() {
        if (!Checks.batteryUnrestricted(c)) Checks.requestBatteryUnrestricted(c)
        else if (android.os.Build.VERSION.SDK_INT >= 33)
            c.requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 0)
    }

    private fun finish() {
        Prefs.setSetupDone(c, true)
        nav.replace(HomeScreen(activity, nav))
    }
}

class HomeScreen(a: Activity, n: Navigator) : Screen(a, n) {
    private var onMonitor = false
    private lateinit var monitorInfo: LinearLayout
    private lateinit var status: TextView
    private lateinit var startButton: TextView
    private val statusListener: (String) -> Unit = { refreshStatus() }

    override fun build() = page(listOf(Triple(0.15f, 0.25f, Party.PURPLE)), top = 48) {
        addView(ui.row(10) {
            addView(ImageView(c).apply { setImageResource(R.drawable.ic_logo) }, LinearLayout.LayoutParams(c.dp(36), c.dp(36)))
            addView(ui.text("DESKDROID", 18f).apply { typeface = Party.orbitron(c); letterSpacing = 0.04f })
            spacer()
            addView(ui.text("⚙", 22f).apply {
                contentDescription = "Settings"
                setPadding(c.dp(10), c.dp(6), c.dp(10), c.dp(6))
                setOnClickListener { nav.go(SettingsScreen(activity, nav)) }
            })
        }, LinearLayout.LayoutParams(-1, -2))

        addView(ui.column(12) {
            setPadding(c.dp(12), c.dp(12), c.dp(12), c.dp(12))
            background = ChamferDrawable(c.dp(18f), fill = Party.CARD, stroke = Party.BORDER_SOFT, strokeWidth = c.dp(1f), cutTopLeft = false)
            addView(FrameLayout(c).apply {
                addView(ImageView(c).apply {
                    setImageResource(R.drawable.desktop_preview)
                    scaleType = ImageView.ScaleType.CENTER_CROP
                }, FrameLayout.LayoutParams(-1, -1))
                status = ui.text("READY", 12f, Party.GREEN, 700).apply {
                    letterSpacing = 0.14f
                    setPadding(c.dp(8), c.dp(3), c.dp(8), c.dp(3))
                    setBackgroundColor(0xCC07070D.toInt())
                }
                addView(status, FrameLayout.LayoutParams(-2, -2, Gravity.TOP or Gravity.END).apply {
                    setMargins(c.dp(8), c.dp(8), c.dp(8), c.dp(8))
                })
            }, LinearLayout.LayoutParams(-1, c.dp(150)))
            addView(ui.text("PLAY ON", 12f, Party.MUTED, 700).apply { letterSpacing = 0.14f })
            addView(Segmented(ui, listOf("This phone", "Monitor"), if (onMonitor) 1 else 0) { i ->
                onMonitor = i == 1; renderMonitor()
            }.view, LinearLayout.LayoutParams(-1, -2))
            monitorInfo = ui.column(6)
            addView(monitorInfo, LinearLayout.LayoutParams(-1, -2))
            startButton = ui.primaryButton("Start desktop") { startOrOpen() }
            addView(startButton, LinearLayout.LayoutParams(-1, -2))
        }, LinearLayout.LayoutParams(-1, -2))

        addView(ui.column(8) {
            addView(ui.text("QUICK SETTINGS", 12f, Party.MUTED, 700).apply { letterSpacing = 0.14f })
            addView(settingRow("Touch mode", if (Prefs.touchMode(c) == "direct") "Direct touch" else "Touchpad") {
                nav.go(SettingsScreen(activity, nav))
            })
            addView(settingRow("Graphics", GpuProfile.describe(GpuProfile.resolve(Prefs.gpuMode(c), Paths(c)))
                .let { if (Prefs.gpuMode(c) == "auto") "Automatic · $it" else it }) {
                nav.go(SettingsScreen(activity, nav))
            })
            addView(settingRow("System", "${Paths(c).installedEdition ?: "?"} edition") {
                nav.go(SettingsScreen(activity, nav))
            })
        }, LinearLayout.LayoutParams(-1, -2))
        renderMonitor()
    }

    private fun settingRow(label: String, value: String, onClick: () -> Unit) = ui.row {
        setPadding(c.dp(14), c.dp(12), c.dp(14), c.dp(12))
        background = ChamferDrawable(0f, fill = Party.SURFACE, cutTopLeft = false, cutBottomRight = false)
        addView(ui.text(label, 14f, Party.TEXT, 600))
        spacer()
        addView(ui.text("$value ›", 14f, Party.MUTED))
        setOnClickListener { onClick() }
    }

    private fun externalDisplay(): Display? =
        c.getSystemService(DisplayManager::class.java).displays.firstOrNull { it.displayId != Display.DEFAULT_DISPLAY }

    private fun renderMonitor() {
        monitorInfo.removeAllViews()
        if (!onMonitor) return
        val d = externalDisplay()
        monitorInfo.addView(
            if (d == null) ui.text("No monitor connected. Plug one in with USB-C.", 13f, Party.ORANGE)
            else ui.text("Monitor connected · ${d.mode.physicalWidth} × ${d.mode.physicalHeight}", 13f, Party.GREEN, 600)
        )
        monitorInfo.addView(ui.text("Full screen on the monitor. Phone touchpad mode and DeX-style windows come next.", 12f, Party.MUTED))
    }

    private fun startOrOpen() {
        val display = if (onMonitor) externalDisplay()?.displayId ?: Display.DEFAULT_DISPLAY else Display.DEFAULT_DISPLAY
        SessionService.start(c, display)
    }

    override fun onShow() {
        AppLog.statusListener = statusListener
        refreshStatus()
        renderMonitor()
    }

    override fun onHide() {
        if (AppLog.statusListener === statusListener) AppLog.statusListener = null
    }

    private fun refreshStatus() {
        val running = SessionService.running
        status.text = if (running) "LIVE" else "READY"
        startButton.text = if (running) "OPEN DESKTOP" else "START DESKTOP"
    }
}

class SettingsScreen(a: Activity, n: Navigator) : Screen(a, n) {
    private lateinit var log: TextView

    override fun build() = page(emptyList()) {
        addView(backButton())
        addView(ui.heading("Settings", 22f))

        addView(ui.text("TOUCH MODE", 12f, Party.MUTED, 700).apply { letterSpacing = 0.14f })
        addView(Segmented(ui, listOf("Touchpad", "Direct touch"), if (Prefs.touchMode(c) == "direct") 1 else 0) { i ->
            Prefs.setTouchMode(c, if (i == 1) "direct" else "touchpad")
            DesktopDefaults.applyTouchMode(c)
        }.view, LinearLayout.LayoutParams(-1, -2))

        addView(ui.text("DESKTOP SCALE", 12f, Party.MUTED, 700).apply { letterSpacing = 0.14f })
        val scales = listOf(1f, 1.25f, 1.5f, 0f)
        addView(Segmented(ui, listOf("100%", "125%", "150%", "Auto"), scales.indexOf(Prefs.scale(c)).coerceAtLeast(0)) { i ->
            Prefs.setScale(c, scales[i])
        }.view, LinearLayout.LayoutParams(-1, -2))
        addView(ui.text("Applies the next time the desktop starts. Zoom in the desktop's side drawer enlarges " +
            "everything on top of this. Auto picks from your screen's density.", 13f, Party.MUTED))

        addView(ui.text("GRAPHICS", 12f, Party.MUTED, 700).apply { letterSpacing = 0.14f })
        val modes = listOf("auto", "virgl", "llvmpipe", "nocomp", "turnip")
        val labels = listOf("Automatic", "GPU via virgl (experimental)", "Software (llvmpipe)", "Software, effects off",
            "Adreno (Turnip + Zink)")
        val gpuGroup = ui.column(6)
        fun renderGpu() {
            gpuGroup.removeAllViews()
            modes.forEachIndexed { i, m ->
                val on = Prefs.gpuMode(c) == m
                gpuGroup.addView(ui.text(labels[i], 14f, if (on) Party.TEXT else Party.MUTED, if (on) 700 else 400).apply {
                    setPadding(c.dp(14), c.dp(10), c.dp(14), c.dp(10))
                    background = ChamferDrawable(0f, fill = if (on) Party.CARD_ON else Party.SURFACE,
                        stroke = if (on) Party.PINK else null, strokeWidth = c.dp(1f), cutTopLeft = false, cutBottomRight = false)
                    setOnClickListener { Prefs.setGpuMode(c, m); renderGpu() }
                }, LinearLayout.LayoutParams(-1, -2))
            }
        }
        renderGpu()
        addView(gpuGroup, LinearLayout.LayoutParams(-1, -2))
        addView(ui.text("VIRGL BACKEND", 12f, Party.MUTED, 700).apply { letterSpacing = 0.14f })
        val backends = listOf("auto", "angle", "gles")
        addView(Segmented(ui, listOf("Automatic", "ANGLE", "Vendor GLES"),
            backends.indexOf(Prefs.virglBackend(c)).coerceAtLeast(0)) { i ->
            Prefs.setVirglBackend(c, backends[i])
        }.view, LinearLayout.LayoutParams(-1, -2))
        val angle = VirglServer.angleDir()
        addView(ui.text("Changes apply the next time the desktop starts. Automatic uses Turnip on Adreno and software " +
            "rendering on other GPUs. virgl gives apps the GPU on Mali and PowerVR but can crash them; the " +
            "desktop itself stays on software rendering. " +
            (if (angle != null) "This phone has ANGLE, which virgl uses by default." else "This phone has no ANGLE, so virgl uses the vendor driver."),
            12f, Party.MUTED))
        addView(ui.outlineButton("GPU report", Party.CYAN, Party.CYAN) { nav.go(GpuReportScreen(activity, nav)) },
            LinearLayout.LayoutParams(-1, -2))

        addView(ui.switchRow(null, "Start on phone boot", "Desktop starts in the background after you unlock.", Prefs.autoStart(c)) {
            Prefs.setAutoStart(c, it)
            if (it && !Checks.batteryUnrestricted(c)) Checks.requestBatteryUnrestricted(c)
        }, LinearLayout.LayoutParams(-1, -2))
        addView(ui.switchRow(null, "Lock my desktop", "Fingerprint or PIN to open DeskDroid.", Prefs.lockDesktop(c)) {
            Prefs.setLockDesktop(c, it)
        }, LinearLayout.LayoutParams(-1, -2))
        addView(ui.outlineButton("Background limits", Party.ORANGE, Party.ORANGE) { nav.go(KeepRunningScreen(activity, nav)) },
            LinearLayout.LayoutParams(-1, -2))
        addView(ui.outlineButton("Reinstall the system", Party.RED, Party.RED) { confirmReinstall() },
            LinearLayout.LayoutParams(-1, -2))

        addView(ui.text("LOG", 12f, Party.MUTED, 700).apply { letterSpacing = 0.14f })
        addView(ui.outlineButton("Share log", Party.CYAN, Party.CYAN) {
            c.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain")
                .putExtra(Intent.EXTRA_SUBJECT, "DeskDroid log")
                .putExtra(Intent.EXTRA_TEXT, "DeskDroid ${BuildConfig.VERSION_NAME}\n\n${AppLog.text()}"), "Share log"))
        }, LinearLayout.LayoutParams(-1, -2))
        log = ui.text(AppLog.text(), 11f, Party.MUTED).apply {
            typeface = android.graphics.Typeface.MONOSPACE
            setTextIsSelectable(true)
        }
        addView(log, LinearLayout.LayoutParams(-1, -2))
        addView(ui.text("DeskDroid ${BuildConfig.VERSION_NAME} · GPL-3.0", 12f, Party.DIM))
    }

    private val logListener: (String) -> Unit = { log.text = it }
    override fun onShow() { AppLog.listener = logListener }
    override fun onHide() { if (AppLog.listener === logListener) AppLog.listener = null }

    private fun confirmReinstall() {
        AlertDialog.Builder(c)
            .setTitle("Reinstall the system?")
            .setMessage("Downloads a fresh image. Your home folder is kept; apps you installed are removed.")
            .setPositiveButton("Reinstall") { _, _ ->
                SessionService.stop(c)
                nav.replace(InstallScreen(activity, nav))
            }
            .setNegativeButton("Cancel", null).show()
    }
}

/** What the phone's GPU drivers offer (native/gpureport), to copy or share when reporting GPU problems. */
class GpuReportScreen(a: Activity, n: Navigator) : Screen(a, n) {
    private lateinit var out: TextView
    @Volatile private var report = ""

    override fun build() = page(emptyList()) {
        addView(backButton())
        addView(ui.heading("GPU report", 22f))
        addView(ui.text("Your GPU, its drivers and what DeskDroid can use. Share it when reporting graphics problems.",
            14f, Party.MUTED))
        addView(ui.row(8) {
            addView(ui.weight(ui.outlineButton("Copy", Party.CYAN, Party.CYAN) {
                c.getSystemService(ClipboardManager::class.java)
                    .setPrimaryClip(ClipData.newPlainText("DeskDroid GPU report", report))
            }))
            addView(ui.weight(ui.outlineButton("Share", Party.PINK, Party.PINK) {
                c.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain")
                    .putExtra(Intent.EXTRA_SUBJECT, "DeskDroid GPU report")
                    .putExtra(Intent.EXTRA_TEXT, report), "Share GPU report"))
            }))
        }, LinearLayout.LayoutParams(-1, -2))
        out = ui.text("Collecting\u2026", 11f, Party.MUTED).apply {
            typeface = android.graphics.Typeface.MONOSPACE
            setTextIsSelectable(true)
        }
        addView(out, LinearLayout.LayoutParams(-1, -2))
        Thread {
            report = collect()
            activity.runOnUiThread { out.text = report }
        }.start()
    }

    private fun collect(): String {
        val paths = Paths(c)
        val angle = VirglServer.angleDir()
        val sb = StringBuilder()
        sb.appendLine("DeskDroid ${BuildConfig.VERSION_NAME}")
        sb.appendLine("Device: ${Build.MANUFACTURER} ${Build.MODEL} (${Build.DEVICE})")
        if (Build.VERSION.SDK_INT >= 31) sb.appendLine("SoC: ${Build.SOC_MANUFACTURER} ${Build.SOC_MODEL}")
        sb.appendLine("Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT}), build ${Build.DISPLAY}")
        for (dev in listOf("/dev/kgsl-3d0", "/dev/mali0", "/dev/pvr_sync", "/dev/dri")) {
            sb.appendLine("$dev: ${if (File(dev).exists()) "present" else "absent"}")
        }
        sb.appendLine("ANGLE: ${angle?.path ?: "not found"}")
        sb.appendLine("virgl server: ${if (paths.virglServer.exists()) "bundled" else "missing"}")
        val mode = Prefs.gpuMode(c)
        sb.appendLine("Graphics setting: $mode -> ${GpuProfile.resolve(mode, paths)}, virgl backend " +
            "${Prefs.virglBackend(c)} -> ${VirglServer.backend(c)}")
        sb.appendLine()
        sb.append(run(listOf(paths.gpuReport.path)))
        if (angle != null) sb.append(run(listOf(paths.gpuReport.path, "--angle", angle.path)))
        return sb.toString()
    }

    private fun run(cmd: List<String>): String = try {
        val p = ProcessBuilder(cmd).redirectErrorStream(true).start()
        val text = StringBuilder()
        val reader = Thread { text.append(p.inputStream.bufferedReader().readText()) }.apply { start() }
        if (!p.waitFor(20, TimeUnit.SECONDS)) p.destroy()
        reader.join(2_000)
        val code = runCatching { p.exitValue() }.getOrNull()
        text.toString() + if (code != 0) "(${cmd.drop(1).joinToString(" ").ifEmpty { "report" }} exited with ${code ?: "timeout"})\n\n" else ""
    } catch (e: Exception) {
        "(could not run ${cmd[0]}: ${e.message})\n\n"
    }
}
