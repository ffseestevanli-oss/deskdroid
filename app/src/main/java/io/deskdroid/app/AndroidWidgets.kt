package io.deskdroid.app

import android.app.ActivityOptions
import android.app.Presentation
import android.appwidget.AppWidgetHost
import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.IntentSender
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.HardwareRenderer
import android.graphics.PixelFormat
import android.graphics.PorterDuff
import android.graphics.RenderNode
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.Drawable
import android.hardware.HardwareBuffer
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.os.UserHandle
import android.os.UserManager
import android.util.SizeF
import android.view.Display
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.security.MessageDigest

/**
 * The phone's widgets on the native desktop, as Plasma widgets.
 *
 * Every widget the phone's apps offer becomes a plasmoid of its own,
 * org.deskdroid.android.u<profile>.<hash> in files/.local/share/plasma/plasmoids,
 * whose main.qml is the shell's AndroidWidget.qml with the provider filled in;
 * files/android-widgets/catalog.json lists them for Add Widgets, which shows
 * them in their own section below Plasma's (explorer-android.py).
 *
 * A plasmoid on the desktop asks for its widget through android-open
 * (deskdroid:widget:show:<token>:<profile>:<provider>:<width>:<height>:<dpi>,
 * again whenever it's resized). The widget is bound here like a home screen
 * binds one (Android asks the user the first time) and runs in an
 * AppWidgetHostView in a Presentation on a private virtual display of the
 * plasmoid's size, so it's attached to a window like on a home screen: clocks
 * tick, lists load, animations run. Each time it draws, its view tree is drawn
 * again with a HardwareRenderer into an ImageReader (keeping transparency) and
 * written to files/android-widgets/<token>.png, with <token>.json saying the
 * frame's number and size. Taps, swipes and the wheel come back as
 * deskdroid:widget:tap|long|swipe and are replayed on the widget as touches.
 *
 * Nothing runs while no Android widget is on the desktop; widgets stop with the
 * desktop, and the screen being off stops their drawing (no vsync).
 */
object AndroidWidgets {
    private const val HOST_ID = 0x0DD1
    const val PLUGIN_PREFIX = "org.deskdroid.android."
    private const val MIN_FRAME_MS = 150L

    private val main = Handler(Looper.getMainLooper())
    private val io: Handler by lazy { Handler(HandlerThread("android-widgets").apply { start() }.looper) }
    private val TOKEN = Regex("[A-Za-z0-9_-]{4,64}")

    // Main thread only.
    var host: AppWidgetHost? = null
        private set
    private val live = HashMap<String, Hosted>()
    private val removals = HashMap<String, Runnable>()
    private val sizes = HashMap<String, IntArray>()       // last asked size: w, h, dpi
    private val asked = HashSet<String>()                 // permission asked this session

    fun dir(c: Context) = File(c.filesDir, "android-widgets").apply { mkdirs() }
    private fun prefs(c: Context) = c.getSharedPreferences("android-widgets", Context.MODE_PRIVATE)

    /** A plasmoid's Android widget: its id with the host, profile and provider. */
    class Entry(val id: Int, val serial: Long, val component: ComponentName)

    fun entry(c: Context, token: String): Entry? {
        val p = prefs(c).getString(token, null)?.split('|') ?: return null
        if (p.size != 3) return null
        return Entry(p[0].toIntOrNull() ?: return null, p[1].toLongOrNull() ?: return null,
            ComponentName.unflattenFromString(p[2]) ?: return null)
    }

    private fun save(c: Context, token: String, e: Entry?) {
        prefs(c).edit().apply {
            if (e == null) remove(token) else putString(token, "${e.id}|${e.serial}|${e.component.flattenToString()}")
        }.apply()
    }

    fun user(c: Context, serial: Long): UserHandle? =
        c.getSystemService(UserManager::class.java).getUserForSerialNumber(serial)

    // ---- lifecycle ---------------------------------------------------------

    private fun ensureHost(c: Context): AppWidgetHost {
        host?.let { return it }
        val app = c.applicationContext
        val h = object : AppWidgetHost(app, HOST_ID) {
            override fun onCreateView(context: Context, appWidgetId: Int, appWidget: AppWidgetProviderInfo?): AppWidgetHostView =
                AppWidgetHostView(context)
            override fun onProvidersChanged() {
                NativeDesk.refreshAndroidApps { writeCatalog(app) }
            }
        }
        try { h.startListening() } catch (e: Exception) { AppLog.i("Android widgets: couldn't start listening: $e") }
        host = h
        // Widgets left from plasmoids that are gone (removed while the desktop wasn't running).
        try {
            val known = prefs(app).all.values.mapNotNull { (it as? String)?.substringBefore('|')?.toIntOrNull() }.toSet()
            h.appWidgetIds.filter { it !in known }.forEach { h.deleteAppWidgetId(it) }
        } catch (e: Exception) {
            AppLog.i("Android widgets: couldn't tidy up: $e")
        }
        return h
    }

    /** The desktop stopped: every widget stops drawing and the host stops listening. */
    fun stop() = main.post {
        live.values.forEach { it.close() }
        live.clear()
        removals.values.forEach { main.removeCallbacks(it) }
        removals.clear()
        asked.clear()
        try { host?.stopListening() } catch (e: Exception) {}
        host = null
    }

    // ---- requests from the plasmoids (any thread) ----------------------------

    /** deskdroid:widget:<what>:<token>:... from android-open. */
    fun handle(c: Context, request: String) {
        val p = request.removePrefix("deskdroid:widget:").split(':')
        val app = c.applicationContext
        main.post {
            try {
                dispatch(app, p)
            } catch (e: Exception) {
                AppLog.i("Android widgets: $request failed: $e")
            }
        }
    }

    private fun dispatch(c: Context, p: List<String>) {
        val token = p.getOrNull(1)?.takeIf { TOKEN.matches(it) } ?: return
        fun num(i: Int) = p.getOrNull(i)?.toFloatOrNull() ?: 0f
        when (p[0]) {
            "show" -> {
                if (p.size < 7) return
                val component = ComponentName.unflattenFromString(p[3]) ?: return
                show(c, token, p[2].toLongOrNull() ?: return, component,
                    p[4].toInt().coerceIn(16, 4096), p[5].toInt().coerceIn(16, 4096), p[6].toInt().coerceIn(80, 960))
            }
            "allow" -> allow(c, token)
            "remove" -> {
                removals.remove(token)?.let { main.removeCallbacks(it) }
                // A minute later, so Undo on the desktop still finds it.
                val r = Runnable { removals.remove(token); remove(c, token) }
                removals[token] = r
                main.postDelayed(r, 60_000)
                live.remove(token)?.close()
            }
            "keep" -> removals.remove(token)?.let { main.removeCallbacks(it) }
            "tap" -> live[token]?.tap(num(2), num(3), false)
            "long" -> live[token]?.tap(num(2), num(3), true)
            "swipe" -> live[token]?.swipe(num(2), num(3), num(4), num(5), num(6).toLong().coerceIn(50, 1000))
        }
    }

    private fun show(c: Context, token: String, serial: Long, component: ComponentName, w: Int, h: Int, dpi: Int) {
        removals.remove(token)?.let { main.removeCallbacks(it) }
        sizes[token] = intArrayOf(w, h, dpi)
        val user = user(c, serial) ?: return state(c, token, "missing")
        if (c.getSystemService(UserManager::class.java).isQuietModeEnabled(user)) {
            live.remove(token)?.close()
            return state(c, token, "locked")
        }
        val host = ensureHost(c)
        val awm = AppWidgetManager.getInstance(c)
        var e = entry(c, token)
        if (e != null && (e.component != component || e.serial != serial)) {
            host.deleteAppWidgetId(e.id); e = null
        }
        if (e == null) {
            e = Entry(host.allocateAppWidgetId(), serial, component)
            save(c, token, e)
        }
        var info = awm.getAppWidgetInfo(e.id)
        if (info == null) {
            val bound = try {
                awm.bindAppWidgetIdIfAllowed(e.id, user, component, sizeOptions(w, h, dpi))
            } catch (x: Exception) {
                AppLog.i("Android widgets: binding $component failed: $x"); false
            }
            if (!bound) {
                // The first time on this desktop, Android asks; after that the plasmoid has an Allow button.
                state(c, token, "permission")
                if (asked.add(token)) allow(c, token)
                return
            }
            info = awm.getAppWidgetInfo(e.id) ?: return state(c, token, "missing")
            if (needsSetup(info)) {
                state(c, token, "starting")
                WidgetBindActivity.start(c, token, bind = false)
                return
            }
        }
        attach(c, token, e, info, w, h, dpi)
    }

    private fun attach(c: Context, token: String, e: Entry, info: AppWidgetProviderInfo, w: Int, h: Int, dpi: Int) {
        val old = live[token]
        if (old != null && old.w == w && old.h == h && old.dpi == dpi && old.id == e.id) return
        old?.close() // a Presentation can't follow its display's size: a new one
        try {
            AppWidgetManager.getInstance(c).updateAppWidgetOptions(e.id, sizeOptions(w, h, dpi))
        } catch (x: Exception) {}
        try {
            live[token] = Hosted(c, token, e.id, info, w, h, dpi)
            AppLog.i("Android widgets: showing ${info.provider.flattenToShortString()} at ${w}x$h")
        } catch (x: Exception) {
            AppLog.i("Android widgets: couldn't show ${info.provider}: $x")
            live.remove(token)
            state(c, token, "error", msg = "This widget couldn't start on the desktop.")
        }
    }

    /** The plasmoid's Allow/Unlock/Try Again button, and the first show of an unbound widget. */
    private fun allow(c: Context, token: String) {
        val e = entry(c, token) ?: return
        val user = user(c, e.serial) ?: return state(c, token, "missing")
        val users = c.getSystemService(UserManager::class.java)
        if (users.isQuietModeEnabled(user)) {
            try { users.requestQuietModeEnabled(false, user) } catch (x: Exception) {}
            return
        }
        if (AppWidgetManager.getInstance(c).getAppWidgetInfo(e.id) == null) {
            WidgetBindActivity.start(c, token, bind = true)
        } else {
            val s = sizes[token] ?: return
            live.remove(token)?.close()
            show(c, token, e.serial, e.component, s[0], s[1], s[2])
        }
    }

    /** WidgetBindActivity is done: permission given (and the widget set up), or not. */
    fun bound(c: Context, token: String, ok: Boolean) = main.post {
        val e = entry(c, token) ?: return@post
        if (!ok) return@post state(c, token, "denied")
        val info = AppWidgetManager.getInstance(c).getAppWidgetInfo(e.id) ?: return@post state(c, token, "denied")
        val s = sizes[token] ?: return@post
        attach(c, token, e, info, s[0], s[1], s[2])
    }

    fun needsSetup(info: AppWidgetProviderInfo): Boolean {
        if (info.configure == null) return false
        if (Build.VERSION.SDK_INT >= 31 &&
            info.widgetFeatures and AppWidgetProviderInfo.WIDGET_FEATURE_CONFIGURATION_OPTIONAL != 0) return false
        return true
    }

    private fun remove(c: Context, token: String) {
        live.remove(token)?.close()
        entry(c, token)?.let { e -> try { ensureHost(c).deleteAppWidgetId(e.id) } catch (x: Exception) {} }
        save(c, token, null)
        sizes.remove(token)
        val d = dir(c)
        File(d, "$token.png").delete()
        File(d, "$token.json").delete()
        AppLog.i("Android widgets: removed $token")
    }

    private fun sizeOptions(w: Int, h: Int, dpi: Int) = Bundle().apply {
        val dw = w * 160 / dpi
        val dh = h * 160 / dpi
        putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, dw)
        putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, dw)
        putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, dh)
        putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, dh)
        if (Build.VERSION.SDK_INT >= 31) {
            putParcelableArrayList(AppWidgetManager.OPTION_APPWIDGET_SIZES, arrayListOf(SizeF(dw.toFloat(), dh.toFloat())))
        }
    }

    /** files/android-widgets/<token>.json, which the plasmoid reads. */
    private fun state(c: Context, token: String, state: String, serial: Int = 0, w: Int = 0, h: Int = 0, msg: String = "") {
        val d = dir(c)
        io.post { writeState(d, token, state, serial, w, h, msg) }
    }

    private fun writeState(d: File, token: String, state: String, serial: Int, w: Int, h: Int, msg: String) {
        val json = JSONObject().put("state", state).put("serial", serial).put("w", w).put("h", h).put("msg", msg)
        val tmp = File(d, ".$token.json.tmp")
        try {
            tmp.writeText(json.toString())
            tmp.renameTo(File(d, "$token.json"))
        } catch (e: Exception) {
            AppLog.i("Android widgets: couldn't write $token's state: $e")
        }
    }

    // ---- one widget on the desktop -------------------------------------------

    /**
     * Activities a widget opens go to the phone's screen, as the menu's Android
     * apps do: left to Android they'd open on the widget's own invisible display.
     */
    private class Launching(base: Context) : ContextWrapper(base) {
        private fun options(o: Bundle?): Bundle {
            val ours = ActivityOptions.makeBasic().setLaunchDisplayId(Display.DEFAULT_DISPLAY)
            if (Build.VERSION.SDK_INT >= 34) {
                @Suppress("DEPRECATION") // ALLOW_ALWAYS is Android 16's
                ours.setPendingIntentBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
            }
            return Bundle(o ?: Bundle()).apply { putAll(ours.toBundle()) }
        }
        override fun startIntentSender(intent: IntentSender, fillInIntent: Intent?, flagsMask: Int, flagsValues: Int, extraFlags: Int, options: Bundle?) =
            super.startIntentSender(intent, fillInIntent, flagsMask, flagsValues, extraFlags, options(options))
        override fun startIntentSender(intent: IntentSender, fillInIntent: Intent?, flagsMask: Int, flagsValues: Int, extraFlags: Int) =
            startIntentSender(intent, fillInIntent, flagsMask, flagsValues, extraFlags, null)
        override fun startActivity(intent: Intent, options: Bundle?) =
            super.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK), options(options))
        override fun startActivity(intent: Intent) = startActivity(intent, null)
    }

    private class Hosted(c: Context, val token: String, val id: Int, info: AppWidgetProviderInfo, val w: Int, val h: Int, val dpi: Int) {
        private val dir = dir(c)
        // The virtual display's own frames aren't used (they'd lose transparency): thrown away.
        private val sink = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2)
        private val display: VirtualDisplay
        private val presentation: Presentation
        private val root: FrameLayout
        private val node = RenderNode("android-widget")
        private val reader = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2,
            HardwareBuffer.USAGE_GPU_COLOR_OUTPUT or HardwareBuffer.USAGE_CPU_READ_OFTEN)
        private val renderer = HardwareRenderer()
        private var closed = false
        private var queued = false
        private var lastDraw = 0L
        @Volatile private var serial = 0
        private var last: Bitmap? = null // io thread

        private val draw = Runnable {
            queued = false
            if (closed || root.width == 0) return@Runnable
            lastDraw = SystemClock.uptimeMillis()
            val canvas = node.beginRecording(w, h)
            try {
                canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
                root.draw(canvas)
            } catch (e: Exception) {
                AppLog.i("Android widgets: $token didn't draw: $e")
            } finally {
                node.endRecording()
            }
            renderer.createRenderRequest().syncAndDraw()
        }

        init {
            sink.setOnImageAvailableListener({ r -> try { r.acquireLatestImage()?.close() } catch (e: Exception) {} }, io)
            display = c.getSystemService(DisplayManager::class.java).createVirtualDisplay(
                "deskdroid-widget-$token", w, h, dpi, sink.surface, DisplayManager.VIRTUAL_DISPLAY_FLAG_OWN_CONTENT_ONLY)
            try {
                presentation = Presentation(c, display.display, android.R.style.Theme_DeviceDefault_DayNight)
                presentation.window?.apply {
                    setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
                    setFormat(PixelFormat.TRANSLUCENT)
                }
                val ctx = Launching(presentation.context)
                val view = host!!.createView(ctx, id, info)
                root = FrameLayout(ctx)
                root.addView(view, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
                presentation.setContentView(root)
                presentation.show()
            } catch (e: Exception) {
                display.release(); sink.close(); reader.close()
                throw e
            }
            node.setPosition(0, 0, w, h)
            reader.setOnImageAvailableListener({ r -> saveFrame(r) }, io)
            renderer.setContentRoot(node)
            renderer.setSurface(reader.surface)
            renderer.isOpaque = false
            val d = dpi / 160f
            renderer.setLightSourceGeometry(w / 2f, 0f, 600f * d, 8f * d)
            renderer.setLightSourceAlpha(0.04f, 0.2f)
            renderer.start()
            // Whenever the widget's window draws, a frame for the desktop (at most every MIN_FRAME_MS).
            root.viewTreeObserver.addOnDrawListener { schedule() }
            schedule()
        }

        fun schedule() {
            if (queued || closed) return
            queued = true
            main.postDelayed(draw, (lastDraw + MIN_FRAME_MS - SystemClock.uptimeMillis()).coerceAtLeast(16))
        }

        private fun saveFrame(r: ImageReader) {
            val bmp = try {
                val img = r.acquireLatestImage() ?: return
                try {
                    val plane = img.planes[0]
                    val src = plane.buffer
                    val rowBytes = img.width * 4
                    val out = ByteBuffer.allocate(rowBytes * img.height)
                    for (y in 0 until img.height) {
                        src.limit(y * plane.rowStride + rowBytes).position(y * plane.rowStride)
                        out.put(src)
                    }
                    out.rewind()
                    Bitmap.createBitmap(img.width, img.height, Bitmap.Config.ARGB_8888).apply { copyPixelsFromBuffer(out) }
                } finally {
                    img.close()
                }
            } catch (e: Exception) {
                AppLog.i("Android widgets: $token's frame couldn't be read: $e"); return
            }
            if (last?.sameAs(bmp) == true) { bmp.recycle(); return }
            last?.recycle()
            last = bmp
            val tmp = File(dir, ".$token.png.tmp")
            try {
                tmp.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
                if (closed) return
                tmp.renameTo(File(dir, "$token.png"))
                serial++
                writeState(dir, token, "ok", serial, bmp.width, bmp.height, "")
            } catch (e: Exception) {
                AppLog.i("Android widgets: couldn't write $token's frame: $e")
            }
        }

        private fun touch(action: Int, down: Long, x: Float, y: Float) {
            if (closed) return
            val e = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, x, y, 0)
            e.source = InputDevice.SOURCE_TOUCHSCREEN
            try { presentation.window?.decorView?.dispatchTouchEvent(e) } finally { e.recycle() }
        }

        fun tap(x: Float, y: Float, long: Boolean) {
            val down = SystemClock.uptimeMillis()
            touch(MotionEvent.ACTION_DOWN, down, x, y)
            main.postDelayed({ touch(MotionEvent.ACTION_UP, down, x, y) }, if (long) 800 else 50)
        }

        fun swipe(x1: Float, y1: Float, x2: Float, y2: Float, ms: Long) {
            val down = SystemClock.uptimeMillis()
            touch(MotionEvent.ACTION_DOWN, down, x1, y1)
            val steps = (ms / 16).toInt().coerceAtLeast(2)
            for (i in 1..steps) {
                val f = i / steps.toFloat()
                main.postDelayed({ touch(MotionEvent.ACTION_MOVE, down, x1 + (x2 - x1) * f, y1 + (y2 - y1) * f) }, i * 16L)
            }
            main.postDelayed({ touch(MotionEvent.ACTION_UP, down, x2, y2) }, steps * 16L + 16)
        }

        fun close() {
            if (closed) return
            closed = true
            main.removeCallbacks(draw)
            try { presentation.dismiss() } catch (e: Exception) {}
            try { renderer.destroy() } catch (e: Exception) {}
            display.release()
            io.post { reader.close(); sink.close(); last?.recycle(); last = null }
        }
    }

    // ---- the catalog for Add Widgets (background thread) ----------------------

    private fun sha(s: String) = MessageDigest.getInstance("SHA-1").digest(s.toByteArray())
        .joinToString("") { "%02x".format(it) }.take(10)

    private fun png(d: Drawable?, file: File, max: Int) {
        if (d == null) return
        val iw = d.intrinsicWidth.takeIf { it > 0 } ?: max
        val ih = d.intrinsicHeight.takeIf { it > 0 } ?: max
        val s = minOf(1f, max / maxOf(iw, ih).toFloat())
        val bw = (iw * s).toInt().coerceAtLeast(1)
        val bh = (ih * s).toInt().coerceAtLeast(1)
        val bmp = Bitmap.createBitmap(bw, bh, Bitmap.Config.ARGB_8888)
        d.setBounds(0, 0, bw, bh)
        d.draw(Canvas(bmp))
        val tmp = File(file.parentFile, ".${file.name}.tmp")
        tmp.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
        tmp.renameTo(file)
        bmp.recycle()
    }

    private fun writeIfChanged(f: File, text: String) {
        if (f.exists() && runCatching { f.readText() }.getOrNull() == text) return
        f.parentFile?.mkdirs()
        val tmp = File(f.parentFile, ".${f.name}.tmp")
        tmp.writeText(text)
        tmp.renameTo(f)
    }

    /**
     * One plasmoid per widget the phone's apps offer (in every profile that's
     * unlocked), and catalog.json listing them. Runs with the menu's listing
     * (NativeDesk.refreshAndroidApps), and again when apps change.
     */
    fun writeCatalog(c: Context) {
        val awm = AppWidgetManager.getInstance(c)
        val launcher = c.getSystemService(android.content.pm.LauncherApps::class.java)
        val users = c.getSystemService(UserManager::class.java)
        val pm = c.packageManager
        val me = android.os.Process.myUserHandle()
        val plasmoids = File(c.filesDir, ".local/share/plasma/plasmoids").apply { mkdirs() }
        val out = dir(c)
        val icons = File(out, "icons").apply { mkdirs() }
        val base = File(c.filesDir, "kwin/share/plasma/shells/org.deskdroid.desktop/contents/androidwidget")
        val density = c.resources.displayMetrics.densityDpi
        val keep = mutableSetOf<String>()
        val keepPrefixes = mutableListOf<String>() // a locked or unreadable profile's widgets stay
        val list = mutableListOf<JSONObject>()
        var failed = false
        val profiles = runCatching { launcher.profiles }.getOrElse { failed = true; emptyList() }
        for (user in profiles) {
            val serial = users.getSerialNumberForUser(user)
            val prefix = "${PLUGIN_PREFIX}u$serial."
            if (users.isQuietModeEnabled(user)) { keepPrefixes += prefix; continue }
            val private = user != me && Build.VERSION.SDK_INT >= 35 &&
                runCatching { launcher.getLauncherUserInfo(user)?.userType == UserManager.USER_TYPE_PROFILE_PRIVATE }.getOrDefault(false)
            val where = when { user == me -> ""; private -> " (Private Space)"; else -> " (Work)" }
            val providers = try { awm.getInstalledProvidersForProfile(user) } catch (e: Exception) {
                AppLog.i("Android widgets: couldn't list profile $serial: $e"); keepPrefixes += prefix; emptyList()
            }
            for (info in providers) {
                if (Build.VERSION.SDK_INT >= 28 && info.widgetCategory and AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN == 0) continue
                val comp = info.provider
                val id = prefix + sha(comp.flattenToString())
                try {
                    val label = info.loadLabel(pm).toString().replace('\n', ' ').trim()
                    val appInfo = runCatching { launcher.getApplicationInfo(comp.packageName, 0, user) }.getOrNull()
                    val appLabel = appInfo?.let { pm.getApplicationLabel(it).toString() } ?: comp.packageName
                    val updated = runCatching { pm.getPackageInfo(comp.packageName, 0).lastUpdateTime }.getOrDefault(0L)
                    val icon = File(icons, "$id.png")
                    if (!icon.exists() || icon.lastModified() < updated) {
                        val d = runCatching { info.loadIcon(c, density) }.getOrNull()
                            ?: appInfo?.let { runCatching { pm.getApplicationIcon(it) }.getOrNull() }
                        png(d?.let { if (user != me) pm.getUserBadgedIcon(it, user) else it }, icon, 128)
                    }
                    val preview = File(icons, "$id-preview.png")
                    if (info.previewImage != 0 && (!preview.exists() || preview.lastModified() < updated)) {
                        png(runCatching { info.loadPreviewImage(c, density) }.getOrNull(), preview, 320)
                    }
                    // Its size on a home screen, in dp (Plasma's units at scale 1).
                    val px2dp = 160f / density
                    var dw = (info.minWidth * px2dp).toInt()
                    var dh = (info.minHeight * px2dp).toInt()
                    if (Build.VERSION.SDK_INT >= 31 && info.targetCellWidth > 0) {
                        dw = maxOf(dw, info.targetCellWidth * 76 - 16)
                        dh = maxOf(dh, info.targetCellHeight * 96 - 16)
                    }
                    dw = dw.coerceIn(80, 800); dh = dh.coerceIn(48, 800)
                    val name = label.ifEmpty { appLabel }
                    val pkg = File(plasmoids, id)
                    writeIfChanged(File(pkg, "metadata.json"), JSONObject()
                        .put("KPackageStructure", "Plasma/Applet")
                        .put("KPlugin", JSONObject()
                            .put("Category", "Android Widgets")
                            .put("Description", "$appLabel$where")
                            .put("Icon", icon.path)
                            .put("Id", id)
                            .put("License", "Proprietary")
                            .put("Name", name))
                        .put("NoDisplay", true) // Add Widgets lists these in their own section (catalog.json)
                        .put("X-Plasma-API-Minimum-Version", "6.0")
                        .toString(4))
                    writeIfChanged(File(pkg, "contents/config/main.xml"),
                        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" +
                        "<kcfg xmlns=\"http://www.kde.org/standards/kcfg/1.0\">\n" +
                        "  <kcfgfile name=\"\"/>\n  <group name=\"General\">\n" +
                        "    <entry name=\"token\" type=\"String\"><default></default></entry>\n" +
                        "  </group>\n</kcfg>\n")
                    writeIfChanged(File(pkg, "contents/ui/main.qml"),
                        "// Written by DeskDroid (AndroidWidgets.kt): ${comp.flattenToShortString()}\n" +
                        "import QtQuick\n" +
                        "import ${JSONObject.quote("file://" + base.path)} as DeskDroid\n\n" +
                        "DeskDroid.AndroidWidget {\n" +
                        "    provider: ${JSONObject.quote(comp.flattenToString())}\n" +
                        "    profile: $serial\n" +
                        "    label: ${JSONObject.quote(name)}\n" +
                        "    defaultWidth: $dw\n" +
                        "    defaultHeight: $dh\n" +
                        "}\n")
                    keep += id
                    list += JSONObject().put("plugin", id).put("name", name).put("description", "$appLabel$where")
                        .put("icon", icon.path).put("preview", if (preview.exists()) preview.path else "")
                } catch (e: Exception) {
                    AppLog.i("Android widgets: couldn't list $comp: $e")
                }
            }
        }
        if (!failed) plasmoids.listFiles()?.forEach { f ->
            if (f.name.startsWith(PLUGIN_PREFIX) && f.name !in keep && keepPrefixes.none { f.name.startsWith(it) }) f.deleteRecursively()
        }
        list.sortWith(compareBy<JSONObject, String>(String.CASE_INSENSITIVE_ORDER) { it.getString("name") }
            .thenBy(String.CASE_INSENSITIVE_ORDER) { it.getString("description") })
        writeIfChanged(File(out, "catalog.json"), JSONObject().put("widgets", JSONArray(list)).toString())
        AppLog.i("Android widgets: ${list.size} in Add Widgets")
    }
}
