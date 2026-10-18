plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "io.deskdroid.app"
    compileSdk = 36
    // Pinned so F-Droid's build server uses the same NDK as CI.
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "io.deskdroid.app"
        minSdk = 29
        targetSdk = 35
        versionCode = 1
        versionName = "0.0.1-spike"
        ndk { abiFilters += "arm64-v8a" }
        buildConfigField(
            "String", "ROOTFS_BASE_URL",
            "\"${project.findProperty("deskdroidRootfsBaseUrl")}\""
        )
    }

    buildFeatures { buildConfig = true }

    // proot and its loader ship as lib*.so so they land in nativeLibraryDir,
    // the only place an app targeting API 29+ may exec files from (W^X).
    packaging { jniLibs { useLegacyPackaging = true } }
    sourceSets["main"].jniLibs.srcDir(layout.buildDirectory.dir("generated/nativeTools/lib"))

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    implementation("org.apache.commons:commons-compress:1.27.1")
    implementation("org.tukaani:xz:1.10")
}

// proot, its loader and talloc, compiled from native/ with the NDK (native/README.md).
val buildNativeTools by tasks.registering(Exec::class) {
    val script = rootProject.file("native/build.sh")
    val abiDir = layout.buildDirectory.dir("generated/nativeTools/lib/arm64-v8a")
    inputs.dir(rootProject.file("native"))
    outputs.dir(abiDir)
    doFirst {
        commandLine(script.path, abiDir.get().asFile.path, android.ndkDirectory.path, "29")
    }
}
tasks.named("preBuild") { dependsOn(buildNativeTools) }
