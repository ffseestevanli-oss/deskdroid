package io.deskdroid.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.view.WindowManager
import io.deskdroid.app.ui.HomeScreen
import io.deskdroid.app.ui.InstallScreen
import io.deskdroid.app.ui.InstallingScreen
import io.deskdroid.app.ui.KeepRunningScreen
import io.deskdroid.app.ui.Navigator
import io.deskdroid.app.ui.Party
import io.deskdroid.app.ui.Screen
import io.deskdroid.app.ui.WelcomeScreen

/** The launcher: setup flow (Welcome → Install → Installing → Keep it running) and Home. */
class MainActivity : Activity(), Navigator {
    private val stack = ArrayList<Screen>()
    private var locked = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppLog.attach(this)
        window.statusBarColor = Party.BG
        window.navigationBarColor = Party.BG
        window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        window.decorView.setBackgroundColor(Party.BG)
        if (android.os.Build.VERSION.SDK_INT >= 33 && !Checks.notificationsAllowed(this)) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 0)
        }
        replace(firstScreen())
    }

    private fun firstScreen(): Screen {
        val paths = Paths(this)
        return when {
            InstallState.current.running || Prefs.pendingEdition(this) != null -> InstallingScreen(this, this)
            !paths.isInstalled -> WelcomeScreen(this, this)
            !Prefs.setupDone(this) -> KeepRunningScreen(this, this)
            else -> HomeScreen(this, this)
        }
    }

    override fun onResume() {
        super.onResume()
        // An install interrupted by the app being killed resumes where it stopped.
        val pending = Prefs.pendingEdition(this)
        if (pending != null && InstallState.current == InstallState.Snapshot()) {
            InstallService.startEdition(this, pending)
        }
        if (Paths(this).isInstalled && LockGate.needsUnlock(this)) {
            if (!locked) {
                locked = true
                window.decorView.visibility = View.INVISIBLE
                LockGate.unlock(this) { ok ->
                    locked = false
                    if (ok) window.decorView.visibility = View.VISIBLE else finish()
                }
            }
        }
        stack.lastOrNull()?.onShow()
    }

    override fun onPause() {
        stack.lastOrNull()?.onHide()
        super.onPause()
    }

    private fun show(screen: Screen) {
        setContentView(screen.build())
        if (!isFinishing) screen.onShow()
    }

    override fun go(screen: Screen) {
        stack.lastOrNull()?.onHide()
        stack += screen
        show(screen)
    }

    override fun replace(screen: Screen) {
        stack.lastOrNull()?.onHide()
        stack.clear()
        stack += screen
        show(screen)
    }

    override fun back() {
        if (stack.size <= 1) { finish(); return }
        stack.removeAt(stack.lastIndex).onHide()
        show(stack.last())
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() = back()

    override fun pickImageFile() {
        @Suppress("DEPRECATION")
        startActivityForResult(
            Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*"),
            PICK_IMAGE
        )
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        val uri = data?.data ?: return
        if (requestCode == PICK_IMAGE && resultCode == RESULT_OK) {
            InstallService.startFile(this, uri)
            replace(InstallingScreen(this, this))
        }
    }

    companion object {
        private const val PICK_IMAGE = 1
    }
}
