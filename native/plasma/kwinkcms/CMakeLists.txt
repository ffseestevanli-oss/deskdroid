# DeskDroid: KWin's settings pages for System Settings › Apps & Windows
# (Window Decorations, Window Behavior, Window Rules, Desktop Effects,
# Task Switcher, Virtual Desktops, Screen Edges, KWin Scripts) and Workspace › Animations,
# built apart from KWin (build_kwin), which is built before KCMUtils.
# KWIN_SRC is KWin's source; the pages build against the installed KWin.
cmake_minimum_required(VERSION 3.16)
project(KWin)
set(PROJECT_VERSION "6.4.5")
set(PROJECT_VERSION_MAJOR 6)
set(PROJECT_VERSION_MINOR 4)
set(PROJECT_VERSION_PATCH 5)
set(KWin_SOURCE_DIR ${KWIN_SRC})

set(QT_MIN_VERSION "6.8.0")
set(KF6_MIN_VERSION "6.14.0")
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(KDE_COMPILERSETTINGS_LEVEL "5.82") # as KWin's own build
find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH} ${KWIN_SRC}/cmake/modules)

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQmlModule)
include(ECMQtDeclareLoggingCategory)

find_package(Qt6 ${QT_MIN_VERSION} CONFIG REQUIRED COMPONENTS Core DBus Gui Qml Quick UiTools Widgets)
find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS
    ColorScheme Config ConfigWidgets CoreAddons GlobalAccel I18n KCMUtils NewStuff Package
    Service Svg WidgetsAddons WindowSystem XmlGui)
find_package(KDecoration3 6.4.5 CONFIG REQUIRED)
find_package(KWin 6.4.5 CONFIG REQUIRED)

set(KWIN_BUILD_X11 OFF)
set(KWIN_BUILD_ACTIVITIES OFF)
set(KWIN_BUILD_TABBOX ON) # build_kwin builds the task switcher
# Window Behavior links KWin's library for its option enums.
add_library(kwin INTERFACE)
target_link_libraries(kwin INTERFACE KWin::kwin)

include_directories(BEFORE ${CMAKE_CURRENT_BINARY_DIR} ${KWIN_SRC}/src)
# KWin's installed config-kwin.h (its build's settings).
include_directories(AFTER ${KDE_INSTALL_FULL_INCLUDEDIR}/kwin)
set(kwin_effects_dbus_xml ${KWIN_SRC}/src/org.kde.kwin.Effects.xml)

add_definitions(-DQT_NO_KEYWORDS -DQT_USE_QSTRINGBUILDER)
set(KCMS ${KWIN_SRC}/src/kcms)
remove_definitions(-DQT_NO_CAST_FROM_ASCII -DQT_STRICT_ITERATORS -DQT_NO_CAST_FROM_BYTEARRAY -DQT_NO_KEYWORDS)
add_subdirectory(${KCMS}/common common)
add_subdirectory(${KCMS}/animations animations)
add_subdirectory(${KCMS}/options options)
add_subdirectory(${KCMS}/decoration decoration)
add_subdirectory(${KCMS}/rules rules)
add_subdirectory(${KCMS}/screenedges screenedges)
add_subdirectory(${KCMS}/scripts scripts)
add_subdirectory(${KCMS}/desktop desktop)
add_subdirectory(${KCMS}/effects effects)
add_subdirectory(${KCMS}/tabbox tabbox)
