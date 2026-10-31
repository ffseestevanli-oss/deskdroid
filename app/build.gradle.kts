plugins {
    id("com.android.application")
}

android {
    namespace = "io.deskdroid.app"
    compileSdk = 36
    // Same NDK as Termux:X11's lorie module (external/termux-x11/lorie/version.gradle),
    // pinned so F-Droid's build server uses what CI uses.
    ndkVersion = "29.0.14206865"

    defaultConfig {
        applicationId = "io.deskdroid.app"
        minSdk = 29
        targetSdk = 35
        // CI passes its run number, so every build has its own version and file name.
        val build = (project.findProperty("deskdroidBuildNumber") as String?)?.toIntOrNull()
        versionCode = if (build != null) 1000 + build else 5
        versionName = "0.1.3" + (build?.let { "-build.$it" } ?: "")
        ndk { abiFilters += "arm64-v8a" }
        buildConfigField(
            "String", "ROOTFS_BASE_URL",
            "\"${project.findProperty("deskdroidRootfsBaseUrl")}\""
        )
        buildConfigField(
            "String", "IMAGE_PUBLIC_KEY",
            "\"${project.findProperty("deskdroidImagePublicKey") ?: ""}\""
        )
    }

    // A fixed debug key (not a secret), so each CI debug build installs over
    // the last one instead of needing an uninstall that wipes the desktop.
    signingConfigs.getByName("debug") {
        storeFile = file("debug.keystore")
        storePassword = "android"
        keyAlias = "androiddebugkey"
        keyPassword = "android"
    }

    buildFeatures { buildConfig = true }

    // Native libs are extracted at install time to nativeLibraryDir, the only
    // place an app targeting API 29+ may exec proot and its helpers from (W^X).
    // The X server finds the extracted libXlorie.so via SessionService's class path.
    packaging { jniLibs { useLegacyPackaging = true } }
    sourceSets.getByName("main").jniLibs.srcDir("build/generated/nativeTools/lib")

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation(project(":lorie"))
    // DesktopActivity extends lorie's MainActivity, an AppCompatActivity; lorie only
    // has appcompat as an implementation dependency, so name it here too.
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("org.apache.commons:commons-compress:1.27.1")
    // Native desktop test, stage 2: the Java side of Qt for Android, which
    // QtHost.kt's Qt demo needs (Qt Quick's library registers natives on
    // QtQuickView when it loads). Only in builds made with Qt (native/nativedesk/build.sh).
    System.getenv("DESKDROID_QT_ANDROID")?.let { qt ->
        implementation(files("$qt/jar/Qt6Android.jar", "$qt/jar/Qt6AndroidQuick.jar"))
    }
}

// proot, its loader, talloc, ddtool, the GPU report tool and the virgl server,
// compiled from native/ with the NDK (native/README.md).
val buildNativeTools by tasks.registering(Exec::class) {
    val script = rootProject.file("native/build.sh")
    val abiDir = layout.buildDirectory.dir("generated/nativeTools/lib/arm64-v8a")
    val ndkDir = androidComponents.sdkComponents.ndkDirectory
    inputs.dir(rootProject.file("native"))
    outputs.dir(abiDir)
    doFirst {
        commandLine(script.path, abiDir.get().asFile.path, ndkDir.get().asFile.path, "29")
    }
}
tasks.named("preBuild") { dependsOn(buildNativeTools) }
