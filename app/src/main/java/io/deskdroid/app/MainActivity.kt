package io.deskdroid.app

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.hardware.display.DisplayManager
import android.net.Uri
import android.os.Bundle
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.CheckBox
import android.widget.EditText
import android.widget.Spinner
import android.widget.TextView

/** Phase 0 launcher: install the rootfs, pick GPU mode and display, start/stop. */
class MainActivity : Activity() {
    private lateinit var paths: Paths
    private lateinit var displays: List<android.view.Display>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        paths = Paths(this)

        val status = findViewById<TextView>(R.id.status)
        val log = findViewById<TextView>(R.id.log)
        val url = findViewById<EditText>(R.id.rootfsUrl)
        val edition = findViewById<Spinner>(R.id.edition)
        edition.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, EDITION_LABELS)
        edition.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(p: AdapterView<*>?, v: android.view.View?, pos: Int, id: Long) {
                url.setText("${BuildConfig.ROOTFS_BASE_URL}deskdroid-rootfs-${EDITIONS[pos]}-arm64.tar.xz")
            }
            override fun onNothingSelected(p: AdapterView<*>?) = Unit
        }
        val gpu = findViewById<Spinner>(R.id.gpuMode)
        val display = findViewById<Spinner>(R.id.display)

        gpu.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, GPU_LABELS)

        if (android.os.Build.VERSION.SDK_INT >= 33) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 0)
        }

        findViewById<Button>(R.id.installUrl).setOnClickListener {
            startForegroundService(
                Intent(this, InstallService::class.java)
                    .putExtra(InstallService.EXTRA_URL, url.text.toString().trim())
            )
        }
        findViewById<Button>(R.id.installFile).setOnClickListener {
            startActivityForResult(
                Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*"),
                PICK_ROOTFS
            )
        }
        findViewById<Button>(R.id.start).setOnClickListener {
            if (!Checks.x11Installed(this)) {
                AlertDialog.Builder(this)
                    .setMessage("Phase 0 needs the Termux:X11 app installed (github.com/termux/termux-x11 releases).")
                    .setPositiveButton("OK", null).show()
                return@setOnClickListener
            }
            if (!paths.isInstalled) {
                AppLog.setStatus("Install the system image first"); return@setOnClickListener
            }
            Prefs.setGpuMode(this, GPU_MODES[gpu.selectedItemPosition])
            startForegroundService(
                Intent(this, SessionService::class.java)
                    .putExtra(SessionService.EXTRA_GPU, GPU_MODES[gpu.selectedItemPosition])
                    .putExtra(SessionService.EXTRA_DISPLAY, displays[display.selectedItemPosition].displayId)
            )
        }
        findViewById<Button>(R.id.stop).setOnClickListener {
            startService(Intent(this, SessionService::class.java).setAction(SessionService.ACTION_STOP))
        }
        findViewById<Button>(R.id.fixes).setOnClickListener {
            if (!Checks.batteryUnrestricted(this)) Checks.requestBatteryUnrestricted(this)
            AlertDialog.Builder(this)
                .setMessage(Checks.phantomProcessHelp())
                .setPositiveButton("Open Developer options") { _, _ -> Checks.openDeveloperOptions(this) }
                .setNegativeButton("Later", null).show()
        }

        findViewById<CheckBox>(R.id.autoStart).apply {
            isChecked = Prefs.autoStart(this@MainActivity)
            setOnCheckedChangeListener { _, on ->
                Prefs.setAutoStart(this@MainActivity, on)
                if (on && !Checks.batteryUnrestricted(this@MainActivity)) {
                    Checks.requestBatteryUnrestricted(this@MainActivity)
                }
            }
        }
        gpu.setSelection(GPU_MODES.indexOf(Prefs.gpuMode(this)).coerceAtLeast(0))

        AppLog.statusListener = { status.text = it }
        AppLog.listener = { log.text = it }
        status.text = AppLog.status.ifEmpty { if (paths.isInstalled) "Ready" else "Not installed" }
        log.text = AppLog.text()
        refreshDisplays(display)
    }

    override fun onResume() {
        super.onResume()
        refreshDisplays(findViewById(R.id.display))
    }

    private fun refreshDisplays(spinner: Spinner) {
        displays = getSystemService(DisplayManager::class.java).displays.toList()
        val labels = displays.map { d ->
            val m = d.mode
            "${if (d.displayId == 0) "Phone screen" else d.name} (${m.physicalWidth}x${m.physicalHeight})"
        }
        spinner.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, labels)
        if (displays.size > 1) spinner.setSelection(displays.size - 1)
    }

    @Deprecated("Fine for the Phase 0 launcher")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        val uri: Uri = data?.data ?: return
        if (requestCode == PICK_ROOTFS && resultCode == RESULT_OK) {
            startForegroundService(
                Intent(this, InstallService::class.java).putExtra(InstallService.EXTRA_FILE, uri)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            )
        }
    }

    override fun onDestroy() {
        AppLog.listener = null
        AppLog.statusListener = null
        super.onDestroy()
    }

    companion object {
        private const val PICK_ROOTFS = 1
        private val EDITION_LABELS = listOf(
            "Light: KDE Plasma + Discover",
            "Full: Plasma + Firefox, LibreOffice, GIMP, VLC (Steam in Phase 3)",
            "Ultra-lite: MATE, native ARM apps only",
        )
        private val EDITIONS = listOf("light", "full", "ultralite")
        private val GPU_LABELS = listOf(
            "Software (llvmpipe), compositing on",
            "Software, compositing off (fastest)",
            "Zink on Turnip (Adreno only)",
            "VirGL (needs virgl server, Phase 0 test)",
        )
        private val GPU_MODES = listOf("llvmpipe", "nocomp", "turnip", "virgl")
    }
}
