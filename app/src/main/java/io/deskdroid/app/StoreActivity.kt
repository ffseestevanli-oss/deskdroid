package io.deskdroid.app

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import io.deskdroid.app.ui.Party
import io.deskdroid.app.ui.Ui
import io.deskdroid.app.ui.dp
import io.deskdroid.app.ui.spacer
import java.io.File
import kotlin.concurrent.thread

/**
 * Software, the app store's window on the phone (Store.kt): the catalog, A to
 * Z, with Install, Update and Remove, and .adpk packages (DeskDroid's own
 * package files) installed from a file: "Install from a file…", or opening
 * one in a file manager. Opened from the desktop's menu and, when the desktop
 * has no Software app of its own, from Plasma's menu. The desktop's version
 * is native/plasma/software.
 */
class StoreActivity : Activity() {
    private val main = Handler(Looper.getMainLooper())
    private lateinit var ui: Ui
    private lateinit var list: LinearLayout
    private lateinit var status: TextView
    private lateinit var tabs: LinearLayout
    private lateinit var intro: TextView
    private var catalog: List<Store.App>? = null
    private var tab = "deskdroid"

    /** Software's tabs (Store.section), as on the desktop: id, label, accent, what it is. */
    private val tabList = listOf(
        Triple("deskdroid", "DeskDroid Repo", Party.CYAN) to "Apps built for DeskDroid: KDE apps, DeskDroid's own, and themes.",
        Triple("flathub", "Flathub", Party.GREEN) to "Flathub's own ARM64 builds, unchanged. ddmask translates them as they run, so nothing is recompiled. Software installs the runtime each one needs with it.",
        Triple("dependencies", "Dependencies", Party.PURPLE) to "Runtimes: the shared libraries Flathub apps run on. Software installs them when an app needs them.",
        Triple("about", "About", Party.YELLOW) to "",
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ui = Ui(this)
        status = ui.text("Loading the catalog…", 14f, Party.MUTED)
        list = ui.column(12)
        val content = ui.column(16, dp(20)) {
            addView(ui.row(8) {
                gravity = Gravity.CENTER_VERTICAL
                addView(ui.heading("Software", 24f))
                spacer()
                addView(ui.outlineButton("✕", Party.TEXT) { finish() }, LinearLayout.LayoutParams(dp(40), dp(40)))
            }, LinearLayout.LayoutParams(-1, -2))
            addView(ui.text("Find, install and update apps for DeskDroid. Installed apps show up in the desktop's menu.", 14f, Party.TEXT_SOFT))
            addView(ui.outlineButton("Install from a file (.adpk)…", Party.CYAN, Party.CYAN) { chooseFile() },
                LinearLayout.LayoutParams(-2, dp(40)))
            tabs = ui.row(8)
            addView(android.widget.HorizontalScrollView(context).apply {
                isHorizontalScrollBarEnabled = false
                addView(tabs)
            }, LinearLayout.LayoutParams(-1, -2))
            intro = ui.text("", 13f, Party.MUTED)
            addView(intro)
            addView(status)
            addView(list, LinearLayout.LayoutParams(-1, -2))
        }
        content.setPadding(dp(20), dp(36), dp(20), dp(20))
        setContentView(ui.screen(emptyList(), ScrollView(this).apply { addView(content) }))
        load()
        handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    private fun chooseFile() {
        val pick = Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*")
        try { startActivityForResult(pick, PICK) } catch (e: Exception) {
            Toast.makeText(this, "No file picker on this phone", Toast.LENGTH_LONG).show()
        }
    }

    @Deprecated("Activity result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == PICK && resultCode == RESULT_OK) data?.data?.let { offer(it) }
    }

    /** An .adpk opened from a file manager. */
    private fun handle(intent: Intent?) {
        if (intent?.action == Intent.ACTION_VIEW) intent.data?.let { offer(it) }
    }

    /** Copies the package in, shows what it is, and installs it when confirmed. */
    private fun offer(uri: Uri) {
        thread {
            val r = runCatching {
                val file = File(cacheDir, "opened.adpk")
                (contentResolver.openInputStream(uri) ?: throw Exception("can't read it")).use { i -> file.outputStream().use { i.copyTo(it) } }
                file to Store.inspect(file)
            }
            main.post {
                r.onFailure {
                    AppLog.i("Software: couldn't open $uri: $it")
                    AlertDialog.Builder(this).setTitle("Can't install this file").setMessage(it.message).setPositiveButton("OK", null).show()
                }
                r.onSuccess { (file, pkg) ->
                    val have = Store.installedVersion(this, pkg.id)
                    val verb = if (have == null) "Install" else if (have == pkg.version) "Reinstall" else "Update"
                    val icon = pkg.icon?.let { b -> BitmapFactory.decodeByteArray(b, 0, b.size) }
                    AlertDialog.Builder(this)
                        .setTitle("$verb ${pkg.name}?")
                        .apply { icon?.let { setIcon(android.graphics.drawable.BitmapDrawable(resources, it)) } }
                        .setMessage(listOfNotNull(pkg.summary.ifEmpty { null },
                            pkg.version.ifEmpty { null }?.let { "Version $it" + (have?.let { h -> " (installed: ${h.ifEmpty { "unknown" }})" } ?: "") },
                            "From a file, not from the Software catalog: install packages only from people you trust.")
                            .joinToString("\n\n"))
                        .setPositiveButton(verb) { _, _ -> installFile(file, pkg) }
                        .setNegativeButton("Cancel") { _, _ -> file.delete() }
                        .show()
                }
            }
        }
    }

    private fun installFile(file: File, pkg: Store.Package) {
        status.visibility = View.VISIBLE
        status.text = "Installing ${pkg.name}…"
        thread {
            val r = runCatching { Store.installFile(this, file) }
            file.delete()
            main.post {
                r.onSuccess { Toast.makeText(this, "${pkg.name} is installed", Toast.LENGTH_LONG).show() }
                r.onFailure {
                    Toast.makeText(this, "Couldn't install ${pkg.name}: ${it.message}", Toast.LENGTH_LONG).show()
                    AppLog.i("Software: install of ${pkg.id} from a file failed: $it")
                }
                load()
            }
        }
    }

    private fun load() {
        thread {
            val result = runCatching { Store.catalog() }
            main.post {
                result.onSuccess { catalog = it; show() }.onFailure {
                    status.visibility = View.VISIBLE
                    status.text = "Couldn't load the catalog: ${it.message}"
                    AppLog.i("Software: catalog failed: $it")
                    show()
                }
            }
        }
    }

    /** The tab row, then the current tab's apps (or About). */
    private fun show() {
        val apps = catalog.orEmpty()
        // Installed from a file, not in the catalog: listed to remove.
        val local = (Store.installed(this) - apps.map { it.id }.toSet()).sorted().map { id ->
            Store.App(id, id, "Installed from a file", Store.installedVersion(this, id).orEmpty(), 0, "", "", "",
                kind = if (id.startsWith("runtime-")) "runtime" else "")
        }
        val all = apps + local
        tabs.removeAllViews()
        for ((t, _) in tabList) {
            val (id, label, accent) = t
            val n = if (id == "about") 0 else all.count { Store.section(it) == id }
            val active = id == tab
            tabs.addView(ui.outlineButton(if (n > 0) "$label  $n" else label,
                if (active) accent else Party.TEXT_SOFT, if (active) accent else Party.BORDER) { tab = id; show() },
                LinearLayout.LayoutParams(-2, dp(40)))
        }
        intro.text = tabList.first { it.first.first == tab }.second
        intro.visibility = if (intro.text.isEmpty()) View.GONE else View.VISIBLE
        list.removeAllViews()
        if (tab == "about") {
            about(all)
            return
        }
        val shown = all.filter { Store.section(it) == tab }
        if (catalog != null) {
            status.text = if (shown.isEmpty()) "Nothing here yet." else ""
            status.visibility = if (shown.isEmpty()) View.VISIBLE else View.GONE
        }
        shown.forEach { list.addView(row(it, all), LinearLayout.LayoutParams(-1, -2)) }
    }

    private fun about(all: List<Store.App>) {
        status.visibility = View.GONE
        val installed = Store.installed(this)
        val counts = listOf("deskdroid" to "DeskDroid Repo", "flathub" to "Flathub", "dependencies" to "Dependencies")
            .joinToString("  ·  ") { (id, label) -> "$label ${all.count { Store.section(it) == id }}" } +
            "  ·  Installed ${all.count { it.id in installed }}"
        fun section(title: String, color: Int, body: String) {
            list.addView(ui.text(title, 13f, color, 700))
            list.addView(ui.text(body, 14f, Party.TEXT_SOFT))
        }
        list.addView(ui.text(counts, 13f, Party.MUTED))
        section("WHERE APPS COME FROM", Party.CYAN,
            "DeskDroid Repo has apps built for DeskDroid itself: KDE apps compiled for Android, DeskDroid's own apps like Sasha, and themes.\n\n" +
            "Flathub has Flathub's own ARM64 Linux builds, repackaged without changes. ddmask, DeskDroid's compatibility layer, translates what they ask of Linux into what Android allows while they run.\n\n" +
            "Dependencies are the runtimes Flathub apps share (KDE, GNOME, Freedesktop, Mesa). Installing an app installs the runtimes it needs first.")
        section(".ADPK PACKAGES", Party.PURPLE,
            "An .adpk is a DeskDroid package, like a .deb: one file with the app, its menu entry and icons, and an app.json saying what it is and what it needs. " +
            "Open one from a file manager, or use Install from a file. Install packages only from people you trust.")
        section("CATALOG", Party.GREEN, Store.baseUrl)
    }

    private fun row(app: Store.App, all: List<Store.App>) = ui.accentRow(Party.CYAN) {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(14), dp(12), dp(14), dp(12))
        val icon = ImageView(context)
        addView(icon, LinearLayout.LayoutParams(dp(48), dp(48)))
        if (app.icon.isNotEmpty()) thread { Store.icon(app)?.let { b -> BitmapFactory.decodeByteArray(b, 0, b.size) }?.let { bmp -> main.post { icon.setImageBitmap(bmp) } } }
        val local = app.file.isEmpty()
        addView(ui.column(2) {
            addView(ui.text(app.name, 16f, Party.TEXT, 700))
            if (app.summary.isNotEmpty()) addView(ui.text(app.summary, 13f, Party.MUTED))
            addView(ui.text(listOfNotNull(app.version.ifEmpty { null }, if (local) null else "%.1f MB".format(app.size / 1e6)).joinToString(" · "), 12f, Party.DIM))
            // A Flathub app's runtimes, a runtime's apps.
            val names = all.associate { it.id to it.name }
            val usedBy = all.filter { app.id in it.needs }.map { it.name }
            val line = if (app.needs.isNotEmpty()) "Needs " + app.needs.joinToString { names[it] ?: it }
                else if (usedBy.isNotEmpty()) "Used by " + usedBy.joinToString() else ""
            if (line.isNotEmpty()) addView(ui.text(line, 12f, Party.PURPLE))
        }, LinearLayout.LayoutParams(0, -2, 1f))
        val installed = app.id in Store.installed(context)
        val current = installed && (local || Store.installedVersion(context, app.id) == app.version)
        val button = ui.outlineButton(if (!installed) "Install" else if (current) "Remove" else "Update", if (installed && current) Party.RED else Party.GREEN) {}
        button.setOnClickListener {
            button.isEnabled = false
            if (installed && current) {
                thread {
                    Store.uninstall(context, app.id)
                    main.post { load() }
                }
            } else {
                button.text = "0%"
                thread {
                    val r = runCatching { Store.install(context, app) { p -> main.post { button.text = "${(p * 100).toInt()}%" } } }
                    main.post {
                        r.onFailure {
                            Toast.makeText(context, "Couldn't install ${app.name}: ${it.message}", Toast.LENGTH_LONG).show()
                            AppLog.i("Software: install of ${app.id} failed: $it")
                        }
                        load()
                    }
                }
            }
        }
        addView(button, LinearLayout.LayoutParams(-2, dp(40)))
    }

    private companion object { const val PICK = 7 }
}
