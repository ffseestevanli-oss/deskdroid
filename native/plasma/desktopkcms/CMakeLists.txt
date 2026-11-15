# DeskDroid: plasma-desktop's settings pages for System Settings: Workspace ›
# General Behavior (kcm_workspace), the Quick Settings start page
# (kcm_landingpage), Colors & Themes › Splash Screen (kcm_splashscreen),
# Keyboard › Shortcuts (kcm_keys) and Accessibility (kcm_access).
# DESKTOP_SRC is plasma-desktop's source.
cmake_minimum_required(VERSION 3.16)
project(plasma-desktop)
set(PROJECT_VERSION "6.4.5")

set(QT_MIN_VERSION "6.8.0")
set(KF6_MIN_VERSION "6.14.0")
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQtDeclareLoggingCategory)

find_package(Qt6 ${QT_MIN_VERSION} CONFIG REQUIRED COMPONENTS Core DBus Gui Qml Quick Widgets)
find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS Config CoreAddons GlobalAccel GuiAddons I18n KCMUtils KIO
    NewStuff NotifyConfig Package Service WindowSystem)
find_package(Plasma 6.4.5 REQUIRED)
find_package(PlasmaQuick 6.4.5 REQUIRED)
find_package(LibKWorkspace 6.4.5 CONFIG REQUIRED) # plasmashell's (build_plasmashell)
find_package(PlasmaActivitiesStats 6.4.5 CONFIG REQUIRED)

remove_definitions(-DQT_NO_CAST_FROM_ASCII -DQT_STRICT_ITERATORS -DQT_NO_CAST_FROM_BYTEARRAY -DQT_NO_KEYWORDS)
add_subdirectory(${DESKTOP_SRC}/kcms/workspaceoptions workspaceoptions)
add_subdirectory(${DESKTOP_SRC}/kcms/landingpage landingpage)
add_subdirectory(${DESKTOP_SRC}/kcms/ksplash ksplash)
add_subdirectory(${DESKTOP_SRC}/kcms/keys keys)
# Accessibility: KWin's Sticky, Bounce and Mouse Keys plugins, its shake-cursor
# and colour-blindness effects read what it saves. It links X11 for nothing
# it does on Wayland: an empty target here.
add_library(X11::X11 INTERFACE IMPORTED)
add_subdirectory(${DESKTOP_SRC}/kcms/access access)
