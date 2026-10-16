plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "io.deskdroid.app"
    compileSdk = 36

    defaultConfig {
        applicationId = "io.deskdroid.app"
        minSdk = 29
        targetSdk = 35
        versionCode = 1
        versionName = "0.0.1-spike"
        ndk { abiFilters += "arm64-v8a" }
        buildConfigField(
            "String", "ROOTFS_URL",
            "\"${project.findProperty("deskdroidRootfsUrl")}\""
        )
    }

    buildFeatures { buildConfig = true }

    // proot and its loader ship as lib*.so so they land in nativeLibraryDir,
    // the only place an app targeting API 29+ may exec files from (W^X).
    packaging { jniLibs { useLegacyPackaging = true } }

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
