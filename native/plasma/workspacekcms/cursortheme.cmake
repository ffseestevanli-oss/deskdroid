# DeskDroid: plasma-workspace's kcms/cursortheme/CMakeLists.txt for Wayland
# without X11: libXcursor and Xlib come from x11-shim/ (its README.md), and
# plasma-apply-cursortheme (which applies a theme to X11) is left out.
add_definitions(-DTRANSLATION_DOMAIN=\"kcm_cursortheme\")
kcmutils_add_qml_kcm(kcm_cursortheme)
target_sources(kcm_cursortheme PRIVATE
    xcursor/thememodel.cpp
    xcursor/themeapplicator.cpp
    xcursor/cursortheme.cpp
    xcursor/xcursortheme.cpp
    xcursor/previewwidget.cpp
    xcursor/sortproxymodel.cpp
    ../kcms-common.cpp
    kcmcursortheme.cpp
    ${X11_SHIM}/xcursor.cpp
)
target_include_directories(kcm_cursortheme BEFORE PRIVATE ${X11_SHIM})
target_compile_definitions(kcm_cursortheme PRIVATE HAVE_XFIXES=0)
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/xcursor/ ${CMAKE_CURRENT_BINARY_DIR}/../krdb/)
kcmutils_generate_module_data(kcm_cursortheme
    MODULE_DATA_HEADER cursorthemedata.h
    MODULE_DATA_CLASS_NAME CursorThemeData
    SETTINGS_HEADERS cursorthemesettings.h launchfeedbacksettings.h
    SETTINGS_CLASSES CursorThemeSettings LaunchFeedbackSettings
)
kconfig_add_kcfg_files(kcm_cursortheme cursorthemesettings.kcfgc GENERATE_MOC)
kconfig_add_kcfg_files(kcm_cursortheme launchfeedbacksettings.kcfgc GENERATE_MOC)
target_link_libraries(kcm_cursortheme PRIVATE
    Qt::DBus Qt::Quick
    KF6::Archive KF6::KCMUtils KF6::DBusAddons KF6::I18n KF6::GuiAddons KF6::WindowSystem
    KF6::KIOCore KF6::KIOWidgets KF6::NewStuffCore KF6::KCMUtilsQuick
    krdb
)
install(FILES cursorthemesettings.kcfg DESTINATION ${KDE_INSTALL_KCFGDIR})
install(FILES launchfeedbacksettings.kcfg DESTINATION ${KDE_INSTALL_KCFGDIR})
install(FILES xcursor/xcursor.knsrc DESTINATION ${KDE_INSTALL_KNSRCDIR})
