package io.deskdroid.app

import android.annotation.SuppressLint
import android.app.Activity
import android.app.ActivityOptions
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.BaseAdapter
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.TextView
import io.deskdroid.app.ui.ChamferDrawable
import io.deskdroid.app.ui.Party
import io.deskdroid.app.ui.Ui
import kotlin.math.abs

/**
 * The phone's app drawer, like Launcher3's all-apps list: a search box, every
 * app of the phone A to Z, then the Work apps and the Private Space, each in
 * its own section at the bottom.
 *
 * Two places show it:
 * - The phone's own desktop (NativeDeskActivity): a swipe up from the bottom
 *   edge (System Settings › Gestures › Edge Swipes, action app_drawer) or the
 *   DD menu's Apps tile. It slides up over Plasma, and a swipe down from the
 *   top of the list (or Back, or Home) puts it away. An app opens on the phone
 *   and the drawer closes, so coming back lands on the desktop.
 * - The phone's touchpad screen while the desktop is on a monitor
 *   (PhoneTouchpadActivity's APPS button): there it stays open behind the app,
 *   and TOUCHPAD goes back.
 *
 * Private Space (Android 15+, listed only while DeskDroid is the home app):
 * locked, it's one header with an Unlock button, which asks Android for the
 * phone's lock screen; unlocked, its apps follow the header, which has Lock
 * and the Private Space's settings. Search finds its apps only while it's
 * unlocked, and with Android's "Hide private space when it's locked" on, a
 * locked Private Space leaves no trace here. The Edge Swipes page's
 * private_space switch takes it out of the drawer altogether.
 */
class PhoneAppDrawer(
    private val activity: Activity,
    /** On the phone's own desktop (true) or the touchpad screen (false). */
    private val onDesktop: Boolean = false,
    private val onClose: () -> Unit,
) {
    private class Entry(val label: String, val icon: Drawable?, val info: LauncherActivityInfo, val user: UserHandle)

    /** A profile other than the phone's own: Work, or the Private Space. */
    private class Profile(val user: UserHandle, val private: Boolean, val locked: Boolean, val apps: List<Entry>)

    /** One line of the list: a row of app cells, a section header, or a line of text. */
    private sealed class Line {
        class Apps(val entries: List<Entry>) : Line()
        class Header(val profile: Profile) : Line()
        class Note(val text: String) : Line()
    }

    private val ui = Ui(activity)
    private val launcher = activity.getSystemService(LauncherApps::class.java)
    private val users = activity.getSystemService(UserManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private var personal = listOf<Entry>()
    private var profiles = listOf<Profile>()
    private var lines = listOf<Line>()
    private var columns = 4
    private fun dp(v: Int) = (v * activity.resources.displayMetrics.density).toInt()

    // ---- The list

    private val adapter = object : BaseAdapter() {
        override fun getCount() = lines.size
        override fun getItem(i: Int) = lines[i]
        override fun getItemId(i: Int) = i.toLong()
        override fun getViewTypeCount() = 3
        override fun getItemViewType(i: Int) = when (lines[i]) { is Line.Apps -> 0; is Line.Header -> 1; is Line.Note -> 2 }
        override fun isEnabled(i: Int) = false // the cells and buttons take their own taps
        override fun getView(i: Int, convert: View?, parent: ViewGroup?): View = when (val l = lines[i]) {
            is Line.Apps -> appRow(convert as? LinearLayout, l.entries)
            is Line.Header -> header(l.profile)
            is Line.Note -> (convert as? TextView ?: ui.text("", 13f, Party.MUTED).apply {
                gravity = Gravity.CENTER
                setPadding(dp(16), dp(24), dp(16), dp(24))
            }).apply { text = l.text }
        }
    }

    /** A row of up to [columns] app cells. */
    private fun appRow(convert: LinearLayout?, entries: List<Entry>): View {
        val row = convert?.takeIf { it.childCount == columns } ?: LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            repeat(columns) { addView(cell(), LinearLayout.LayoutParams(0, -2, 1f)) }
        }
        for (c in 0 until columns) {
            val cell = row.getChildAt(c) as LinearLayout
            val e = entries.getOrNull(c)
            cell.visibility = if (e == null) View.INVISIBLE else View.VISIBLE
            if (e == null) { cell.setOnClickListener(null); cell.setOnLongClickListener(null); continue }
            (cell.getChildAt(0) as ImageView).setImageDrawable(e.icon)
            (cell.getChildAt(1) as TextView).text = e.label
            cell.setOnClickListener { open(e) }
            cell.setOnLongClickListener { appInfo(e); true }
        }
        return row
    }

    private fun cell() = ui.column(4) {
        gravity = Gravity.CENTER_HORIZONTAL
        setPadding(dp(4), dp(10), dp(4), dp(10))
        isClickable = true
        isLongClickable = true
        foreground = activity.getDrawable(android.R.drawable.list_selector_background)
        addView(ImageView(context), LinearLayout.LayoutParams(dp(52), dp(52)))
        addView(ui.text("", 12f, Party.TEXT_SOFT).apply {
            gravity = Gravity.CENTER
            maxLines = 2
            ellipsize = android.text.TextUtils.TruncateAt.END
        }, LinearLayout.LayoutParams(-1, -2))
    }

    /**
     * A section's header, like Launcher3's Private Space bar: the name, then
     * (unlocked) the settings button and Lock, or (locked) Unlock. A locked
     * section's whole bar unlocks it.
     */
    private fun header(p: Profile): View {
        val accent = if (p.private) Party.PURPLE else Party.CYAN
        val name = if (p.private) "Private" else "Work"
        return FrameLayout(activity).apply {
            setPadding(dp(4), dp(18), dp(4), dp(6))
            addView(ui.row(10) {
                setPadding(dp(14), dp(8), dp(8), dp(8))
                background = ChamferDrawable(dp(10).toFloat(), fill = Party.SURFACE, stroke = Party.BORDER_SOFT,
                    strokeWidth = dp(1).toFloat(), cutTopLeft = false, accent = accent, accentWidth = dp(3).toFloat())
                addView(ImageView(context).apply {
                    setImageResource(if (p.locked) android.R.drawable.ic_lock_lock else android.R.drawable.ic_lock_idle_lock)
                    setColorFilter(accent)
                }, LinearLayout.LayoutParams(dp(22), dp(22)))
                addView(ui.column(0) {
                    addView(ui.text(name, 15f, Party.TEXT, 700))
                    addView(ui.text(when {
                        p.locked && p.private -> "Locked · its apps are hidden"
                        p.locked -> "Paused"
                        else -> "${p.apps.size} apps"
                    }, 12f, Party.MUTED))
                }, LinearLayout.LayoutParams(0, -2, 1f))
                if (p.private && !p.locked) addView(ImageView(context).apply {
                    setImageResource(android.R.drawable.ic_menu_manage)
                    setColorFilter(Party.TEXT_SOFT)
                    setPadding(dp(10), dp(10), dp(10), dp(10))
                    contentDescription = "Private Space settings"
                    isClickable = true
                    foreground = activity.getDrawable(android.R.drawable.list_selector_background)
                    setOnClickListener { privateSettings(p.user) }
                }, LinearLayout.LayoutParams(dp(44), dp(44)))
                val label = when {
                    p.locked && p.private -> "UNLOCK"
                    p.locked -> "TURN ON"
                    p.private -> "LOCK"
                    else -> "PAUSE"
                }
                addView(ui.outlineButton(label, accent, accent) { setLocked(p, !p.locked) }, LinearLayout.LayoutParams(-2, dp(40)))
                if (p.locked) {
                    isClickable = true
                    setOnClickListener { setLocked(p, false) }
                }
            }, FrameLayout.LayoutParams(-1, -2))
        }
    }

    private val search = EditText(activity).apply {
        hint = "Search apps"
        setHintTextColor(Party.DIM)
        setTextColor(Party.TEXT)
        textSize = 15f
        setSingleLine(true)
        imeOptions = EditorInfo.IME_ACTION_GO
        setPadding(dp(14), dp(10), dp(14), dp(10))
        background = ChamferDrawable(0f, fill = Party.SURFACE, stroke = Party.BORDER_SOFT, strokeWidth = dp(1).toFloat(),
            cutTopLeft = false, cutBottomRight = false)
        addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun afterTextChanged(s: Editable?) = build()
        })
        // Enter opens the first app found, as on a phone's home screen.
        setOnEditorActionListener { _, action, ev ->
            val enter = action == EditorInfo.IME_ACTION_GO ||
                (ev?.keyCode == KeyEvent.KEYCODE_ENTER && ev.action == KeyEvent.ACTION_DOWN)
            if (enter) (lines.firstOrNull() as? Line.Apps)?.entries?.firstOrNull()?.let { open(it) }
            enter
        }
    }

    private val list = ListView(activity).apply {
        divider = null
        dividerHeight = 0
        selector = android.graphics.drawable.ColorDrawable(0)
        isVerticalScrollBarEnabled = true
        isFastScrollEnabled = true
        clipToPadding = false
        adapter = this@PhoneAppDrawer.adapter
        // The keyboard goes when the list scrolls, like Launcher3's.
        setOnScrollListener(object : android.widget.AbsListView.OnScrollListener {
            override fun onScrollStateChanged(v: android.widget.AbsListView?, state: Int) {
                if (state == android.widget.AbsListView.OnScrollListener.SCROLL_STATE_TOUCH_SCROLL) hideKeyboard()
            }
            override fun onScroll(v: android.widget.AbsListView?, first: Int, visible: Int, total: Int) {}
        })
    }

    private val panel = ui.column(10) {
        setPadding(dp(16), dp(16), dp(16), 0)
        addView(ui.row(8) {
            gravity = Gravity.CENTER_VERTICAL
            if (onDesktop) {
                addView(search, LinearLayout.LayoutParams(0, -2, 1f))
                addView(ui.outlineButton("DESKTOP", Party.TEXT) { close() }, LinearLayout.LayoutParams(-2, dp(44)))
            } else {
                addView(ui.column(2) {
                    addView(ui.text("PHONE APPS", 15f).apply { typeface = Party.orbitron(context); letterSpacing = 0.06f })
                    addView(ui.text("They open here, on the phone · Plasma stays on the monitor", 12f, Party.MUTED))
                }, LinearLayout.LayoutParams(0, -2, 1f))
                addView(ui.outlineButton("TOUCHPAD", Party.TEXT) { close() }, LinearLayout.LayoutParams(-2, dp(44)))
            }
        }, LinearLayout.LayoutParams(-1, -2))
        if (!onDesktop) addView(search, LinearLayout.LayoutParams(-1, -2))
        addView(list, LinearLayout.LayoutParams(-1, 0, 1f))
        // A grab handle: the drawer slides down to close.
        if (onDesktop) addView(View(context).apply {
            background = ChamferDrawable(0f, fill = Party.BORDER, cutTopLeft = false, cutBottomRight = false)
        }, 0, LinearLayout.LayoutParams(dp(40), dp(4)).apply { gravity = Gravity.CENTER_HORIZONTAL })
    }

    /** The drawer: it takes every touch (none reach the desktop behind it), and a pull down from the top of the list closes it. */
    val view: View = object : FrameLayout(activity) {
        private val slop = ViewConfiguration.get(activity).scaledTouchSlop
        private var startX = 0f
        private var startY = 0f
        private var pulling = false

        override fun onInterceptTouchEvent(e: MotionEvent): Boolean {
            if (!onDesktop) return false
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> { startX = e.rawX; startY = e.rawY; pulling = false }
                MotionEvent.ACTION_MOVE -> {
                    val dy = e.rawY - startY
                    if (dy > slop * 2 && dy > abs(e.rawX - startX) * 1.5f && !list.canScrollVertically(-1)) {
                        pulling = true
                        hideKeyboard()
                    }
                }
            }
            return pulling
        }

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouchEvent(e: MotionEvent): Boolean {
            if (!pulling) return true
            val dy = (e.rawY - startY).coerceAtLeast(0f)
            when (e.actionMasked) {
                MotionEvent.ACTION_MOVE -> { panel.translationY = dy; alpha = 1f - (dy / height).coerceIn(0f, 0.6f) }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    pulling = false
                    if (dy > height * 0.2f) close()
                    else { panel.animate().translationY(0f).setDuration(150).start(); animate().alpha(1f).setDuration(150).start() }
                }
            }
            return true
        }
    }.apply {
        setBackgroundColor(Party.BG)
        isClickable = true // touches stay in the drawer, off the desktop or touchpad behind it
        addView(panel, FrameLayout.LayoutParams(-1, -1))
        addOnLayoutChangeListener { v, l, _, r, _, oldL, _, oldR, _ ->
            if (r - l != oldR - oldL) { fitColumns(v.width); build() }
        }
    }

    private fun fitColumns(width: Int) {
        val inner = width - view.paddingLeft - view.paddingRight - panel.paddingLeft - panel.paddingRight
        columns = (inner / dp(84)).coerceIn(3, 12)
    }

    // ---- Open, close, follow changes

    // Apps installed, removed, or a profile locked or unlocked while the drawer is open.
    private val reload = Runnable { load() }
    private fun later() { main.removeCallbacks(reload); main.postDelayed(reload, 400) }
    private val callback = object : LauncherApps.Callback() {
        override fun onPackageRemoved(p: String?, u: UserHandle?) = later()
        override fun onPackageAdded(p: String?, u: UserHandle?) = later()
        override fun onPackageChanged(p: String?, u: UserHandle?) = later()
        override fun onPackagesAvailable(p: Array<out String>?, u: UserHandle?, r: Boolean) = later()
        override fun onPackagesUnavailable(p: Array<out String>?, u: UserHandle?, r: Boolean) = later()
    }
    private val profileReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) = later()
    }
    private var watching = false
    val isOpen get() = view.visibility == View.VISIBLE

    fun show() {
        if (!watching) {
            launcher.registerCallback(callback, main)
            val filter = IntentFilter().apply {
                if (Build.VERSION.SDK_INT >= 31) {
                    addAction(Intent.ACTION_PROFILE_AVAILABLE)
                    addAction(Intent.ACTION_PROFILE_UNAVAILABLE)
                    addAction(Intent.ACTION_PROFILE_ADDED)
                    addAction(Intent.ACTION_PROFILE_REMOVED)
                }
                addAction(Intent.ACTION_MANAGED_PROFILE_AVAILABLE)
                addAction(Intent.ACTION_MANAGED_PROFILE_UNAVAILABLE)
            }
            if (Build.VERSION.SDK_INT >= 33) activity.registerReceiver(profileReceiver, filter, Context.RECEIVER_EXPORTED)
            else activity.registerReceiver(profileReceiver, filter)
            watching = true
        }
        search.setText("")
        list.setSelection(0)
        view.alpha = 1f
        if (onDesktop) {
            panel.translationY = activity.resources.displayMetrics.heightPixels * 0.35f
            view.alpha = 0f
            panel.animate().translationY(0f).setDuration(220).setInterpolator(android.view.animation.DecelerateInterpolator()).start()
            view.animate().alpha(1f).setDuration(180).start()
        } else panel.translationY = 0f
        if (view.width > 0) fitColumns(view.width)
        load()
    }

    fun close() {
        if (watching) {
            launcher.unregisterCallback(callback)
            runCatching { activity.unregisterReceiver(profileReceiver) }
            watching = false
        }
        main.removeCallbacks(reload)
        hideKeyboard()
        if (onDesktop && isOpen) {
            panel.animate().translationY(view.height * 0.35f).setDuration(160).start()
            view.animate().alpha(0f).setDuration(160).withEndAction { onClose() }.start()
        } else onClose()
    }

    /** A key typed on a real keyboard while the list has the focus: it goes to the search box. */
    fun typed(keyCode: Int, e: KeyEvent): Boolean {
        if (search.hasFocus() || e.unicodeChar == 0 || e.isCtrlPressed || e.isAltPressed || e.isMetaPressed) return false
        search.requestFocus()
        return search.dispatchKeyEvent(e)
    }

    private fun hideKeyboard() {
        activity.getSystemService(android.view.inputmethod.InputMethodManager::class.java)
            .hideSoftInputFromWindow(search.windowToken, 0)
        search.clearFocus()
    }

    // ---- The apps

    private fun isPrivate(user: UserHandle) = Build.VERSION.SDK_INT >= 35 && runCatching {
        launcher.getLauncherUserInfo(user)?.userType == UserManager.USER_TYPE_PROFILE_PRIVATE
    }.getOrDefault(false)

    /** Android's Settings › Security › Private space › "Hide private space when it's locked". */
    private fun hideLockedPrivateSpace() = runCatching {
        android.provider.Settings.Secure.getInt(activity.contentResolver, "hide_privatespace_entry_point", 0) == 1
    }.getOrDefault(false)

    private fun load() {
        val withPrivate = Gestures.switch(Gestures.PRIVATE_SPACE)
        Thread {
            val me = android.os.Process.myUserHandle()
            var mine = listOf<Entry>()
            val others = mutableListOf<Profile>()
            for (user in runCatching { launcher.profiles }.getOrDefault(listOf(me))) {
                val private = user != me && isPrivate(user)
                if (private && !withPrivate) continue
                val locked = user != me && runCatching { users.isQuietModeEnabled(user) }.getOrDefault(false)
                if (private && locked && hideLockedPrivateSpace()) continue
                val apps = if (locked) emptyList() else runCatching { launcher.getActivityList(null, user) }.getOrDefault(emptyList())
                    .filter { it.componentName.packageName != activity.packageName || user != me }
                    .map { Entry(it.label.toString().replace("\n", " "), runCatching { it.getBadgedIcon(0) }.getOrNull(), it, user) }
                    .sortedBy { it.label.lowercase() }
                if (user == me) mine = apps else others += Profile(user, private, locked, apps)
            }
            // Work before the Private Space, which is last, as in Launcher3.
            others.sortBy { it.private }
            main.post { personal = mine; profiles = others; build() }
        }.start()
    }

    private fun build() {
        val q = search.text.toString().trim().lowercase()
        val out = mutableListOf<Line>()
        fun rows(entries: List<Entry>) = entries.chunked(columns).forEach { out += Line.Apps(it) }
        if (q.isNotEmpty()) {
            // Search: every app that's open to see (a locked profile's are hidden), A to Z.
            val found = (personal + profiles.filter { !it.locked }.flatMap { it.apps })
                .filter { q in it.label.lowercase() }.sortedBy { it.label.lowercase() }
            rows(found)
            if (found.isEmpty()) out += Line.Note("No apps match \"${search.text.trim()}\"")
        } else {
            rows(personal)
            for (p in profiles) {
                out += Line.Header(p)
                rows(p.apps)
            }
        }
        lines = out
        adapter.notifyDataSetChanged()
    }

    /** Lock or unlock (Private Space), pause or turn on (Work). Unlocking asks for the phone's lock screen. */
    private fun setLocked(p: Profile, lock: Boolean) {
        runCatching { users.requestQuietModeEnabled(lock, p.user) }
            .onSuccess { AppLog.i("Phone apps: ${if (p.private) "Private Space" else "Work profile"} ${if (lock) "locked" else "unlocking"}") }
            .onFailure { AppLog.i("Phone apps: couldn't ${if (lock) "lock" else "unlock"} a profile: $it") }
        later()
    }

    private fun launchOptions() =
        ActivityOptions.makeBasic().setLaunchDisplayId(
            (if (Build.VERSION.SDK_INT >= 30) activity.display?.displayId else null) ?: android.view.Display.DEFAULT_DISPLAY).toBundle()

    /** The Private Space's page in Android's settings, as Launcher3 opens it. */
    private fun privateSettings(user: UserHandle) {
        val tries = listOf(
            Intent("android.intent.action.SAFETY_CENTER").putExtra(":settings:fragment_args_key", "AndroidPrivateSpace_personal"),
            Intent(android.provider.Settings.ACTION_SECURITY_SETTINGS),
        )
        for (i in tries) {
            if (runCatching { activity.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), launchOptions()) }.isSuccess) return
        }
        AppLog.i("Phone apps: no Private Space settings to open for $user")
    }

    private fun appInfo(e: Entry) {
        runCatching { launcher.startAppDetailsActivity(e.info.componentName, e.user, null, launchOptions()) }
            .onFailure { AppLog.i("Phone apps: couldn't show ${e.info.componentName.packageName}'s info: $it") }
    }

    private fun open(e: Entry) {
        // On the screen the drawer is on: the phone's, never the monitor.
        try {
            launcher.startMainActivity(e.info.componentName, e.user, null, launchOptions())
            AppLog.i("Phone apps: opened ${e.info.componentName.packageName}")
        } catch (ex: Exception) {
            AppLog.i("Phone apps: couldn't open ${e.info.componentName.packageName}: $ex")
            return
        }
        // On the desktop, coming back from the app lands on Plasma, not here.
        if (onDesktop) main.postDelayed({ if (isOpen) close() }, 300)
    }
}
