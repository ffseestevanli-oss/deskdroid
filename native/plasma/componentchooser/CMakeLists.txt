# DeskDroid: builds only plasma-workspace's Default Applications page
# (kcm_componentchooser) for System Settings. WORKSPACE_SRC is
# plasma-workspace's source.
cmake_minimum_required(VERSION 3.16)
project(deskdroid-componentchooser)

set(QT_MIN_VERSION "6.8.0")
set(KF6_MIN_VERSION "6.14.0")
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 ${QT_MIN_VERSION} CONFIG REQUIRED COMPONENTS Core DBus Gui Qml Quick Widgets)
find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS
    Config CoreAddons I18n KCMUtils KIO Service)

add_subdirectory(${WORKSPACE_SRC}/kcms/componentchooser componentchooser)
