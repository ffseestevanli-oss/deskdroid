# DeskDroid: builds only plasma-desktop's folder view plugin
# (org.kde.private.desktopcontainment.folder), which Plasma's desktop
# containment (org.kde.desktopcontainment, QML) needs: the desktop's files and
# icons, drag and drop, and its right-click menu. DESKTOP_SRC is
# plasma-desktop's source.
cmake_minimum_required(VERSION 3.16)
project(deskdroid-folderview)

set(QT_MIN_VERSION "6.8.0")
set(KF6_MIN_VERSION "6.14.0")
set(PROJECT_DEP_VERSION "6.4.5")
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQmlModule)
include(ECMQtDeclareLoggingCategory)

find_package(Qt6 ${QT_MIN_VERSION} CONFIG REQUIRED COMPONENTS Core Gui Qml Quick Widgets)
find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS
    Config CoreAddons I18n KIO Notifications XmlGui)
find_package(Plasma ${PROJECT_DEP_VERSION} REQUIRED)
find_package(PlasmaQuick ${PROJECT_DEP_VERSION} REQUIRED)
find_package(PlasmaActivities ${PROJECT_DEP_VERSION} REQUIRED)

add_definitions(-DTRANSLATION_DOMAIN=\"plasma_applet_org.kde.desktopcontainment\")
add_definitions(-DQT_NO_URL_CAST_FROM_STRING)

add_subdirectory(${DESKTOP_SRC}/containments/desktop/plugins/folder folder)
