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
rootProject.name = "DeskDroid"
include(":app")

// Embedded X server: Termux:X11's lorie library module, a git submodule
// (git submodule update --init --recursive). See external/README.md.
include(":lorie")
project(":lorie").projectDir = file("external/termux-x11/lorie")
include(":shell-loader:stub")
project(":shell-loader:stub").projectDir = file("external/termux-x11/shell-loader/stub")
project(":shell-loader").projectDir = file("external/shell-loader-parent")
