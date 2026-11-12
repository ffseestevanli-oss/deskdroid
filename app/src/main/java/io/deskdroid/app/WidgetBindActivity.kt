package io.deskdroid.app

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Bundle

/**
 * An Android widget on the desktop that isn't bound yet: Android's "Allow
 * DeskDroid to create widgets?" dialog, then the widget's own setup screen if
 * it has one, then back to AndroidWidgets. Invisible itself.
 */
class WidgetBindActivity : Activity() {
    private lateinit var token: String
    private var reported = false

    companion object {
        private const val BIND = 1
        private const val SETUP = 2

        fun start(c: Context, token: String, bind: Boolean) {
            val i = Intent(c, WidgetBindActivity::class.java)
                .putExtra("token", token).putExtra("bind", bind)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                // Over the desktop, wherever it is (phone screen or monitor).
                (NativeDesk.activity?.get() ?: c).startActivity(i)
            } catch (e: Exception) {
                AppLog.i("Android widgets: couldn't ask about $token: $e")
                AndroidWidgets.bound(c.applicationContext, token, false)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        token = intent.getStringExtra("token") ?: return finish()
        if (savedInstanceState != null) return
        val e = AndroidWidgets.entry(this, token) ?: return done(false)
        if (!intent.getBooleanExtra("bind", true) || AppWidgetManager.getInstance(this).getAppWidgetInfo(e.id) != null) return setup(e.id)
        val user = AndroidWidgets.user(this, e.serial) ?: return done(false)
        try {
            startActivityForResult(Intent(AppWidgetManager.ACTION_APPWIDGET_BIND)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, e.id)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER, e.component)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_PROVIDER_PROFILE, user), BIND)
        } catch (x: Exception) {
            AppLog.i("Android widgets: no bind dialog: $x")
            done(false)
        }
    }

    private fun setup(id: Int) {
        val info = AppWidgetManager.getInstance(this).getAppWidgetInfo(id) ?: return done(false)
        val host = AndroidWidgets.host
        if (host == null || !AndroidWidgets.needsSetup(info)) return done(true)
        try {
            host.startAppWidgetConfigureActivityForResult(this, id, 0, SETUP, null)
        } catch (x: Exception) {
            AppLog.i("Android widgets: ${info.provider} has no setup screen to open: $x")
            done(true)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            BIND -> if (resultCode == RESULT_OK) AndroidWidgets.entry(this, token)?.let { setup(it.id) } ?: done(false) else done(false)
            // A widget left unset still shows (most say "tap to set up").
            SETUP -> done(true)
        }
    }

    private fun done(ok: Boolean) {
        if (!reported) { reported = true; AndroidWidgets.bound(applicationContext, token, ok) }
        finish()
    }
}
