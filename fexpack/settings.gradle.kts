// The FEX add-on APK (io.deskdroid.fex): DeskDroid's FEX-Emu build, and
// optionally its x86 system, as an APK that the app copies them from
// (X86.kt) instead of downloading the fex-latest release. A project of its
// own, so it builds without the app's submodules:
//   ./gradlew -p fexpack assembleDebug -PfexDir=<folder with fex/build.sh's output>
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "deskdroid-fex"
