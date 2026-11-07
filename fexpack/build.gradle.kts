plugins {
    id("com.android.application") version "9.3.1"
}

// fex/build.sh's output (deskdroid-fex-arm64.tar.zst, .sha256, .version);
// with -PwithRootfs=true also fex/rootfs.sh's (deskdroid-x86-rootfs.*,
// about 1.2 GB more).
val fexDir = file((findProperty("fexDir") as String?) ?: "fex-out")
val withRootfs = (findProperty("withRootfs") as String?) == "true"
val fexVersion = rootDir.resolve("../fex/VERSION").readText().trim()            // FEX-2610
val build = (findProperty("deskdroidBuildNumber") as String?)?.toIntOrNull() ?: 0

val stageAssets by tasks.registering(Sync::class) {
    from(fexDir) {
        include("deskdroid-fex-arm64.tar.zst", "deskdroid-fex-arm64.tar.zst.sha256", "deskdroid-fex-arm64.version")
        if (withRootfs) include("deskdroid-x86-rootfs.*")
    }
    into(layout.buildDirectory.dir("fex-assets"))
    doLast {
        check(destinationDir.resolve("deskdroid-fex-arm64.tar.zst").exists()) {
            "no deskdroid-fex-arm64.tar.zst in $fexDir (pass -PfexDir=<fex/build.sh's output folder>)"
        }
    }
}

android {
    namespace = "io.deskdroid.fex"
    compileSdk = 36

    defaultConfig {
        applicationId = "io.deskdroid.fex"
        minSdk = 29
        targetSdk = 35
        // FEX-2610, build 3 -> 261000003
        versionCode = fexVersion.removePrefix("FEX-").toInt() * 100_000 + build
        versionName = fexVersion + if (build > 0) "-build.$build" else ""
    }

    // DeskDroid only takes FEX from an add-on signed with its own key, the
    // app's fixed debug key (app/build.gradle.kts).
    signingConfigs.getByName("debug") {
        storeFile = rootDir.resolve("../app/debug.keystore")
        storePassword = "android"
        keyAlias = "androiddebugkey"
        keyPassword = "android"
    }

    // Stored, not deflated: they're compressed already, and the app streams them.
    androidResources { noCompress += listOf("zst", "sha256", "version", "files") }
    sourceSets.getByName("main").assets.srcDir(layout.buildDirectory.dir("fex-assets").get().asFile)
}

tasks.named("preBuild") { dependsOn(stageAssets) }
