# DeskDroid: plasma-workspace's splash screen (ksplash/ksplashqml), the
# Global Theme's splash shown while the desktop starts, built as a library
# QtHost starts (apps/as-library.py; bin/ksplashqml, NativeDesk.kt).
# WORKSPACE_SRC is plasma-workspace's source.
cmake_minimum_required(VERSION 3.16)
project(plasma-workspace)
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
include(ECMConfiguredInstall)

find_package(Qt6 ${QT_MIN_VERSION} CONFIG REQUIRED COMPONENTS Core DBus Gui Qml Quick)
find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS Config Package WindowSystem)
find_package(PlasmaQuick 6.4.5 REQUIRED)
find_package(LibKWorkspace 6.4.5 CONFIG REQUIRED) # plasmashell's (build_plasmashell)
find_package(LayerShellQt CONFIG REQUIRED)

remove_definitions(-DQT_NO_CAST_FROM_ASCII -DQT_NO_CAST_TO_ASCII -DQT_NO_CAST_FROM_BYTEARRAY)
set(KDE_INSTALL_SYSTEMDUSERUNITDIR ${CMAKE_CURRENT_BINARY_DIR}/systemd) # no systemd here
add_subdirectory(${WORKSPACE_SRC}/ksplash/ksplashqml ksplashqml)
