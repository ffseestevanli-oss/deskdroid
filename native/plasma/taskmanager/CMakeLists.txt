# DeskDroid: builds only plasma-desktop's task manager plugin
# (org.kde.plasma.private.taskmanager) and installs its package
# (org.kde.plasma.taskmanager, "Icons-and-Text Task Manager"). The
# icons-only task manager (org.kde.plasma.icontasks) is that package's files
# under another name, copied by build-deps.sh. DESKTOP_SRC is
# plasma-desktop's source, cut down by patch.py.
cmake_minimum_required(VERSION 3.16)
project(deskdroid-taskmanager)

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

find_package(Qt6 ${QT_MIN_VERSION} CONFIG REQUIRED COMPONENTS Core DBus Gui Qml Quick Widgets)
find_package(KF6 ${KF6_MIN_VERSION} REQUIRED COMPONENTS
    Config CoreAddons I18n KIO Notifications Service WindowSystem)
find_package(Plasma ${PROJECT_DEP_VERSION} REQUIRED)
find_package(PlasmaActivities ${PROJECT_DEP_VERSION} REQUIRED)
find_package(PlasmaActivitiesStats ${PROJECT_DEP_VERSION} REQUIRED)

add_definitions(-DQT_NO_URL_CAST_FROM_STRING)

# Stand-ins for libnotificationmanager (job progress and badge settings) and
# libksysguard (process parents), which aren't built here.
include_directories(BEFORE ${CMAKE_CURRENT_SOURCE_DIR}/stubs)
add_library(PW::LibNotificationManager INTERFACE IMPORTED)
add_library(KSysGuard::ProcessCore INTERFACE IMPORTED)

add_subdirectory(${DESKTOP_SRC}/applets/taskmanager taskmanager)
target_sources(taskmanagerplugin PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/stubs/settings.h)
