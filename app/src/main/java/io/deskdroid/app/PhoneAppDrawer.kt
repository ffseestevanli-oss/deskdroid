package io.deskdroid.app

import android.app.Activity
import android.app.ActivityOptions
import android.content.pm.LauncherActivityInfo
import android.content.pm.LauncherApps
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.UserHandle
import android.os.UserManager
import android.text.Editable
import android.text.TextWatcher
import android.view.Display
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.GridView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import io.deskdroid.app.ui.ChamferDrawable
import io.deskdroid.app.ui.Party
import io.deskdroid.app.ui.Ui

/**
 * The phone's app drawer while the desktop is on a monitor
 * (PhoneTouchpadActivity's APPS button). Plasma keeps the monitor and the
 * phone's own apps open on the phone's screen, each doing its own thing:
 * Android's apps are out of Plasma's menus meanwhile (NativeDesk.onMonitor).
 * Work and Private Space apps are here too, with their badges; a locked or
 * paused profile shows one tile that asks Android to unlock it.
 */
class PhoneAppDrawer(private val activity: Activity, private val onClose: () -> Unit) {
    private class Entry(val label: String, val icon: Drawable?, val info: LauncherActivityInfo?, val user: UserHandle)

    private val ui = Ui(activity)
    private val launcher = activity.getSystemService(LauncherApps::class.java)
    private val users = activity.getSystemService(UserManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private var all = listOf<Entry>()
    private var shown = listOf<Entry>()
    private fun dp(v: Int) = (v * activity.resources.displayMetrics.density).toInt()

    private val adapter = object : BaseAdapter() {
        override fun getCount() = shown.size
        override fun getItem(i: Int) = shown[i]
        override fun getItemId(i: Int) = i.toLong()
        override fun getView(i: Int, convert: View?, parent: ViewGroup?): View {
            val cell = (convert as? LinearLayout) ?: ui.column(4) {
                gravity = Gravity.CENTER_HORIZONTAL
                setPadding(dp(4), dp(10), dp(4), dp(10))
                addView(ImageView(context), LinearLayout.LayoutParams(dp(52), dp(52)))
                addView(ui.text("", 12f, Party.TEXT_SOFT).apply {
                    gravity = Gravity.CENTER
                    maxLines = 2
                    ellipsize = android.text.TextUtils.TruncateAt.END
                }, LinearLayout.LayoutParams(-1, -2))
            }
            val e = shown[i]
            (cell.getChildAt(0) as ImageView).setImageDrawable(e.icon)
            (cell.getChildAt(1) as TextView).text = e.label
            return cell
        }
    }

    private val search = EditText(activity).apply {
        hint = "Search apps"
        setHintTextColor(Party.DIM)
        setTextColor(Party.TEXT)
        textSize = 15f
        setSingleLine(true)
        setPadding(dp(14), dp(10), dp(14), dp(10))
        background = ChamferDrawable(0f, fill = Party.SURFACE, stroke = Party.BORDER_SOFT, strokeWidth = dp(1).toFloat(),
            cutTopLeft = false, cutBottomRight = false)
        addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun afterTextChanged(s: Editable?) = filter()
        })
    }

    private val grid = GridView(activity).apply {
        numColumns = GridView.AUTO_FIT
        columnWidth = dp(84)
        stretchMode = GridView.STRETCH_COLUMN_WIDTH
        verticalSpacing = dp(2)
        selector = android.graphics.drawable.ColorDrawable(0x22FF4FD8)
        adapter = this@PhoneAppDrawer.adapter
        setOnItemClickListener { _, _, i, _ -> open(shown[i]) }
    }

    val view: View = FrameLayout(activity).apply {
        setBackgroundColor(Party.BG)
        isClickable = true // touches stay in the drawer, off the touchpad behind it
        addView(ui.column(10) {
            setPadding(dp(16), dp(20), dp(16), dp(16))
            addView(ui.row(8) {
                gravity = Gravity.CENTER_VERTICAL
                addView(ui.column(2) {
                    addView(ui.text("PHONE APPS", 15f).apply { typeface = Party.orbitron(context); letterSpacing = 0.06f })
                    addView(ui.text("They open here, on the phone · Plasma stays on the monitor", 12f, Party.MUTED))
                }, LinearLayout.LayoutParams(0, -2, 1f))
                addView(ui.outlineButton("TOUCHPAD", Party.TEXT) { close() }, LinearLayout.LayoutParams(-2, dp(44)))
            }, LinearLayout.LayoutParams(-1, -2))
            addView(search, LinearLayout.LayoutParams(-1, -2))
            addView(grid, LinearLayout.LayoutParams(-1, 0, 1f))
        }, FrameLayout.LayoutParams(-1, -1))
    }

    // Apps installed, removed or a profile unlocked while the drawer is open.
    private val reload = Runnable { load() }
    private val callback = object : LauncherApps.Callback() {
        private fun later() { main.removeCallbacks(reload); main.postDelayed(reload, 500) }
        override fun onPackageRemoved(p: String?, u: UserHandle?) = later()
        override fun onPackageAdded(p: String?, u: UserHandle?) = later()
        override fun onPackageChanged(p: String?, u: UserHandle?) = later()
        override fun onPackagesAvailable(p: Array<out String>?, u: UserHandle?, r: Boolean) = later()
        override fun onPackagesUnavailable(p: Array<out String>?, u: UserHandle?, r: Boolean) = later()
    }
    private var watching = false

    fun show() {
        if (!watching) { launcher.registerCallback(callback, main); watching = true }
        search.setText("")
        load()
    }

    fun close() {
        if (watching) { launcher.unregisterCallback(callback); watching = false }
        main.removeCallbacks(reload)
        activity.getSystemService(android.view.inputmethod.InputMethodManager::class.java)
            .hideSoftInputFromWindow(search.windowToken, 0)
        onClose()
    }

    private fun load() {
        Thread {
            val me = android.os.Process.myUserHandle()
            val list = mutableListOf<Entry>()
            for (user in runCatching { launcher.profiles }.getOrDefault(listOf(me))) {
                val kind = when {
                    user == me -> ""
                    Build.VERSION.SDK_INT >= 35 && runCatching {
                        launcher.getLauncherUserInfo(user)?.userType == UserManager.USER_TYPE_PROFILE_PRIVATE
                    }.getOrDefault(false) -> "Private Space"
                    else -> "Work apps"
                }
                if (user != me && runCatching { users.isQuietModeEnabled(user) }.getOrDefault(false)) {
                    list += Entry("Unlock $kind", activity.getDrawable(android.R.drawable.ic_lock_lock), null, user)
                    continue
                }
                val apps = runCatching { launcher.getActivityList(null, user) }.getOrDefault(emptyList())
                    .filter { it.componentName.packageName != activity.packageName || user != me }
                list += apps.map { Entry(it.label.toString().replace("\n", " "), runCatching { it.getBadgedIcon(0) }.getOrNull(), it, user) }
                    .sortedBy { it.label.lowercase() }
            }
            main.post { all = list; filter() }
        }.start()
    }

    private fun filter() {
        val q = search.text.toString().trim().lowercase()
        shown = if (q.isEmpty()) all else all.filter { q in it.label.lowercase() }
        adapter.notifyDataSetChanged()
    }

    private fun open(e: Entry) {
        val info = e.info
        if (info == null) {
            // A locked Private Space or paused work profile: Android asks to unlock it.
            runCatching { users.requestQuietModeEnabled(false, e.user) }
                .onFailure { AppLog.i("Phone apps: couldn't unlock a profile: $it") }
            return
        }
        // Always on the phone's own screen, never the monitor.
        val opts = ActivityOptions.makeBasic().setLaunchDisplayId(Display.DEFAULT_DISPLAY).toBundle()
        try {
            launcher.startMainActivity(info.componentName, e.user, null, opts)
            AppLog.i("Phone apps: opened ${info.componentName.packageName}")
        } catch (ex: Exception) {
            AppLog.i("Phone apps: couldn't open ${info.componentName.packageName}: $ex")
        }
    }
}
