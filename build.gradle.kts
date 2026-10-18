buildscript {
    dependencies {
        // AGP 9 compiles Kotlin itself ("built-in Kotlin"); this picks the Kotlin
        // version. It must read the kotlin-stdlib that Termux:X11's lorie module uses.
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.21")
    }
}

plugins {
    // Same AGP as external/termux-x11, so its lorie module builds unchanged.
    id("com.android.application") version "9.3.1" apply false
    id("com.android.library") version "9.3.1" apply false
}
