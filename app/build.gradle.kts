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
        versionCode = 2
        versionName = "0.1.0-phase1"
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

    buildFeatures { buildConfig = true }

    // Native libs are stored uncompressed: lorie System.load()s libXlorie.so
    // straight from the APK. The manifest still sets extractNativeLibs="true",
    // so the installer also copies them to nativeLibraryDir, the only place an
    // app targeting API 29+ may exec proot and its helpers from (W^X).
    packaging { jniLibs { useLegacyPackaging = false } }
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
}

// proot, its loader, talloc and ddtool, compiled from native/ with the NDK (native/README.md).
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
