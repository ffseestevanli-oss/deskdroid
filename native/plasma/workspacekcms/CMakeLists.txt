# DeskDroid: plasma-workspace's settings pages for System Settings ›
# Appearance & Style: Colors, Icons, Plasma Style, Application Style,
# Fonts, Cursors, Wallpaper, System Sounds and Global Theme, with the krdb library
# they share. WORKSPACE_SRC is
# plasma-workspace's source. There's no X11 here: the pages' X11 code is
# behind HAVE_X11, and X11::X11 is an empty target for the few that link it
# unconditionally.
cmake_minimum_required(VERSION 3.16)
project(plasma-workspace)
set(PROJECT_VERSION "6.4.5")
set(PROJECT_VERSION_MAJOR 6)
set(PROJECT_VERSION_MINOR 4)
set(PROJECT_VERSION_PATCH 5)

set(QT_MIN_VERSION "6.8.0")
set(KF6_MIN_VERSION "6.14.0")
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH} ${WORKSPACE_SRC}/cmake)

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(GenerateExportHeader)
include(ECMQtDeclareLoggingCategory)

find_package(Qt6 ${QT_MIN_VERSION} CONFIG REQUIRED COMPONENTS Core DBus Gui Qml Quick Svg Widgets Xml)
find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS
    Archive ColorScheme Config CoreAddons DBusAddons GuiAddons I18n IconThemes JobWidgets
    KCMUtils KIO NewStuff Package Service Svg WindowSystem XmlGui)
find_package(KF6Config ${KF6_MIN_VERSION} REQUIRED COMPONENTS Qml)
find_package(Plasma 6.4.5 REQUIRED)
find_package(PlasmaQuick 6.4.5 REQUIRED)
find_package(PlasmaActivities 6.4.5 REQUIRED)
find_package(Breeze 6.4.5 CONFIG)
find_package(Fontconfig REQUIRED)
find_package(Canberra REQUIRED) # build_libcanberra
find_package(LibKWorkspace 6.4.5 CONFIG REQUIRED) # plasmashell's (build_plasmashell)

set(HAVE_X11 0)
set(HAVE_FONTCONFIG 1)
set(PLASMA_RELATIVE_DATA_INSTALL_DIR "plasma")
configure_file(${WORKSPACE_SRC}/config-X11.h.cmake ${CMAKE_CURRENT_BINARY_DIR}/config-X11.h)
configure_file(${WORKSPACE_SRC}/config-workspace.h.cmake ${CMAKE_CURRENT_BINARY_DIR}/config-workspace.h)
include_directories(${CMAKE_CURRENT_BINARY_DIR} ${WORKSPACE_SRC}/kcms/krdb)

add_definitions(-DQT_NO_URL_CAST_FROM_STRING)
remove_definitions(-DQT_NO_CAST_FROM_ASCII -DQT_NO_CAST_TO_ASCII -DQT_NO_CAST_FROM_BYTEARRAY)

add_library(X11::X11 INTERFACE IMPORTED)
set(KDED_DBUS_INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/org.kde.kded6.xml) # no kded here

add_subdirectory(${WORKSPACE_SRC}/kcms/krdb krdb)
add_subdirectory(${WORKSPACE_SRC}/startkde/plasmaautostart plasmaautostart)
add_subdirectory(${WORKSPACE_SRC}/kcms/colors colors)
add_subdirectory(${WORKSPACE_SRC}/kcms/icons icons)
add_subdirectory(${WORKSPACE_SRC}/kcms/desktoptheme desktoptheme)
add_subdirectory(${WORKSPACE_SRC}/kcms/style style)
add_subdirectory(${WORKSPACE_SRC}/kcms/lookandfeel lookandfeel)

# Fonts: fonts.cmake in place of kcms/fonts/CMakeLists.txt (build_kcms_workspace).
add_subdirectory(${WORKSPACE_SRC}/kcms/fonts fonts)
# Cursors: cursortheme.cmake in place of its CMakeLists.txt, with x11-shim/.
set(X11_SHIM ${CMAKE_CURRENT_SOURCE_DIR}/x11-shim)
add_subdirectory(${WORKSPACE_SRC}/kcms/cursortheme cursortheme)
# Wallpaper: the desktop's wallpaper, set in plasmashell over D-Bus.
# Its DefaultWallpaper is libkworkspace's, which doesn't install the header.
# Nor config-outputorder.h, which its installed outputorderwatcher.h includes.
configure_file(${WORKSPACE_SRC}/libkworkspace/defaultwallpaper.h ${CMAKE_CURRENT_BINARY_DIR}/defaultwallpaper.h COPYONLY)
configure_file(${WORKSPACE_SRC}/libkworkspace/config-outputorder.h.cmake ${CMAKE_CURRENT_BINARY_DIR}/config-outputorder.h)
add_subdirectory(${WORKSPACE_SRC}/kcms/wallpaper wallpaper)
# System Sounds: the sound theme for notifications (libcanberra, as KNotifications).
add_subdirectory(${WORKSPACE_SRC}/kcms/soundtheme soundtheme)
