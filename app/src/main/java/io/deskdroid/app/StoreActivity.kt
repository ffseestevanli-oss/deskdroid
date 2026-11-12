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
            addView(ui.text("Apps built for DeskDroid. Installed apps show up in the desktop's menu.", 14f, Party.TEXT_SOFT))
            addView(ui.outlineButton("Install from a file (.adpk)…", Party.CYAN, Party.CYAN) { chooseFile() },
                LinearLayout.LayoutParams(-2, dp(40)))
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
                result.onSuccess { apps ->
                    status.text = if (apps.isEmpty()) "No apps in the store yet." else ""
                    status.visibility = if (apps.isEmpty()) View.VISIBLE else View.GONE
                    list.removeAllViews()
                    apps.forEach { list.addView(row(it), LinearLayout.LayoutParams(-1, -2)) }
                    // Installed from a file, not in the catalog: listed to remove.
                    (Store.installed(this) - apps.map { it.id }.toSet()).sorted().forEach { id ->
                        list.addView(row(Store.App(id, id, "Installed from a file", Store.installedVersion(this, id).orEmpty(), 0, "", "", "")),
                            LinearLayout.LayoutParams(-1, -2))
                    }
                }.onFailure {
                    status.visibility = View.VISIBLE
                    status.text = "Couldn't load the catalog: ${it.message}"
                    AppLog.i("Software: catalog failed: $it")
                }
            }
        }
    }

    private fun row(app: Store.App) = ui.accentRow(Party.CYAN) {
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
