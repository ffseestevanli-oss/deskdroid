kcmutils_add_qml_kcm(kcm_gesturetaps SOURCES taps.cpp ../gesturemodule.h INSTALL_NAMESPACE "plasma/kcms/systemsettings")
target_include_directories(kcm_gesturetaps PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_link_libraries(kcm_gesturetaps PRIVATE Qt::Core Qt::Gui Qt::Quick KF6::CoreAddons KF6::I18n KF6::KCMUtilsQuick)
