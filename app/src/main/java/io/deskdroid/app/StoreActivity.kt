package io.deskdroid.app

import android.app.Activity
import android.graphics.BitmapFactory
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import io.deskdroid.app.ui.Party
import io.deskdroid.app.ui.Ui
import io.deskdroid.app.ui.dp
import io.deskdroid.app.ui.spacer
import kotlin.concurrent.thread

/**
 * The app store's window (Store.kt): the catalog, with Install, Update and
 * Remove. Opened from the desktop's menu and from Plasma's menu (App Store).
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
                addView(ui.heading("App Store", 24f))
                spacer()
                addView(ui.outlineButton("✕", Party.TEXT) { finish() }, LinearLayout.LayoutParams(dp(40), dp(40)))
            }, LinearLayout.LayoutParams(-1, -2))
            addView(ui.text("KDE apps built for your phone. Installed apps show up in the desktop's menu.", 14f, Party.TEXT_SOFT))
            addView(status)
            addView(list, LinearLayout.LayoutParams(-1, -2))
        }
        content.setPadding(dp(20), dp(36), dp(20), dp(20))
        setContentView(ui.screen(emptyList(), ScrollView(this).apply { addView(content) }))
        load()
    }

    private fun load() {
        thread {
            val result = runCatching { Store.catalog() }
            main.post {
                result.onSuccess { apps ->
                    status.text = if (apps.isEmpty()) "No apps in the store yet." else ""
                    status.visibility = if (apps.isEmpty()) android.view.View.VISIBLE else android.view.View.GONE
                    list.removeAllViews()
                    apps.forEach { list.addView(row(it), LinearLayout.LayoutParams(-1, -2)) }
                }.onFailure {
                    status.text = "Couldn't load the catalog: ${it.message}"
                    AppLog.i("Store: catalog failed: $it")
                }
            }
        }
    }

    private fun row(app: Store.App) = ui.accentRow(Party.CYAN) {
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(14), dp(12), dp(14), dp(12))
        val icon = ImageView(context)
        addView(icon, LinearLayout.LayoutParams(dp(48), dp(48)))
        thread { Store.icon(app)?.let { b -> BitmapFactory.decodeByteArray(b, 0, b.size) }?.let { bmp -> main.post { icon.setImageBitmap(bmp) } } }
        addView(ui.column(2) {
            addView(ui.text(app.name, 16f, Party.TEXT, 700))
            if (app.summary.isNotEmpty()) addView(ui.text(app.summary, 13f, Party.MUTED))
            addView(ui.text(listOfNotNull(app.version.ifEmpty { null }, "%.1f MB".format(app.size / 1e6)).joinToString(" · "), 12f, Party.DIM))
        }, LinearLayout.LayoutParams(0, -2, 1f))
        val installed = app.id in Store.installed(context)
        val current = installed && java.io.File(filesDir, "store/apps/${app.id}/version.txt").takeIf { it.exists() }?.readText() == app.version
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
                            android.widget.Toast.makeText(context, "Couldn't install ${app.name}: ${it.message}", android.widget.Toast.LENGTH_LONG).show()
                            AppLog.i("Store: install of ${app.id} failed: $it")
                        }
                        load()
                    }
                }
            }
        }
        addView(button, LinearLayout.LayoutParams(-2, dp(40)))
    }
}
