# DeskDroid: System Settings › System › About This Phone, in place of KDE's
# About this System (kinfocenter, which reads a Linux PC's hardware). The
# app writes files/phone-info.json at each desktop start; this shows it.
cmake_minimum_required(VERSION 3.16)
project(deskdroid-aboutphone)

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

kcmutils_add_qml_kcm(kcm_aboutphone SOURCES aboutphone.cpp INSTALL_NAMESPACE "plasma/kcms/systemsettings")
target_link_libraries(kcm_aboutphone PRIVATE Qt::Core Qt::Gui Qt::Quick KF6::CoreAddons KF6::I18n KF6::KCMUtilsQuick)
