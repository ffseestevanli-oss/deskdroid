package io.deskdroid.app

import android.app.Activity
import android.app.KeyguardManager
import android.hardware.biometrics.BiometricManager.Authenticators
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal

/**
 * "Lock my desktop": fingerprint, face or the phone's PIN before DeskDroid opens.
 * Unlocking lasts until the app process ends or the screen has been off a while.
 */
object LockGate {
    @Volatile private var unlockedAt = 0L
    private const val GRACE_MS = 5 * 60 * 1000L

    fun needsUnlock(a: Activity) =
        Prefs.lockDesktop(a) && System.currentTimeMillis() - unlockedAt > GRACE_MS

    /** Keeps the grace period running while the desktop is in use. */
    fun touch() { if (unlockedAt > 0) unlockedAt = System.currentTimeMillis() }

    fun unlock(a: Activity, onResult: (Boolean) -> Unit) {
        // No screen lock on the phone: nothing to check against, so don't lock the user out.
        if (!a.getSystemService(KeyguardManager::class.java).isDeviceSecure) {
            unlockedAt = System.currentTimeMillis()
            onResult(true)
            return
        }
        val builder = BiometricPrompt.Builder(a)
            .setTitle("Unlock DeskDroid")
            .setSubtitle("Your desktop is locked")
        if (Build.VERSION.SDK_INT >= 30) {
            builder.setAllowedAuthenticators(Authenticators.BIOMETRIC_WEAK or Authenticators.DEVICE_CREDENTIAL)
        } else {
            @Suppress("DEPRECATION")
            builder.setDeviceCredentialAllowed(true)
        }
        builder.build().authenticate(CancellationSignal(), a.mainExecutor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult?) {
                    unlockedAt = System.currentTimeMillis()
                    onResult(true)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence?) = onResult(false)
            })
    }
}
