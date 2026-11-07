# DeskDroid: plasma-workspace's kcms/fonts/CMakeLists.txt without kfontinst
# (X11 only) and the Xft previews patch.py takes out.
add_definitions(-DTRANSLATION_DOMAIN=\"kcm_fonts\")
kcmutils_add_qml_kcm(kcm_fonts SOURCES fonts.cpp fontsaasettings.cpp kxftconfig.cpp ../kcms-common.cpp)
kcmutils_generate_module_data(kcm_fonts
    MODULE_DATA_HEADER fontsdata.h
    MODULE_DATA_CLASS_NAME FontsData
    SETTINGS_HEADERS fontssettings.h fontsaasettings.h
    SETTINGS_CLASSES FontsSettings FontsAASettings
)
kconfig_add_kcfg_files(kcm_fonts fontssettings.kcfgc fontsaasettingsbase.kcfgc GENERATE_MOC)
target_link_libraries(kcm_fonts PRIVATE Qt::DBus Qt::Quick Qt::Xml KF6::I18n KF6::WindowSystem KF6::KCMUtils
    KF6::KCMUtilsQuick Fontconfig::Fontconfig krdb)
install(FILES fontssettings.kcfg DESTINATION ${KDE_INSTALL_KCFGDIR})
