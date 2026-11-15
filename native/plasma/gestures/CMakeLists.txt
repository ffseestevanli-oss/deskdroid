# DeskDroid: System Settings › Gestures. The phone's touch gestures on the
# desktop: swipes in from the corners and edges (Edge Swipes) and a triple
# tap (Taps). The pages save $HOME/gestures.json, which the app watches
# (app/.../Gestures.kt) and applies to the next touch.
cmake_minimum_required(VERSION 3.16)
project(deskdroid-gestures)

set(QT_MIN_VERSION "6.8.0")
set(KF6_MIN_VERSION "6.14.0")
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 ${QT_MIN_VERSION} CONFIG REQUIRED COMPONENTS Core Gui Qml Quick)
find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS CoreAddons I18n KCMUtils)

# Both pages show the same QML (a row per gesture); kcmutils takes each
# page's QML from its own ui/ folder.
foreach(page swipes taps)
    file(COPY ${CMAKE_CURRENT_SOURCE_DIR}/main.qml DESTINATION ${CMAKE_CURRENT_SOURCE_DIR}/${page}/ui)
endforeach()

add_subdirectory(swipes)
add_subdirectory(taps)

# Gestures: a top-level category in System Settings' sidebar, after Input & Output.
install(FILES settings-gestures.desktop DESTINATION ${KDE_INSTALL_DATADIR}/systemsettings/categories)
