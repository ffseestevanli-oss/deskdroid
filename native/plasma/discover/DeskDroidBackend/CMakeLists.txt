# DeskDroid: Flathub through the flatpak command (DeskDroidBackend.h).
kcoreaddons_add_plugin(deskdroid-backend SOURCES
    DeskDroidBackend.cpp DeskDroidResource.cpp DeskDroidTransaction.cpp
    INSTALL_NAMESPACE "discover")
target_link_libraries(deskdroid-backend PRIVATE
    Qt::Core Qt::Gui Qt::Concurrent
    KF6::CoreAddons KF6::I18n
    Discover::Common AppStreamQt)
install(FILES deskdroid-backend-categories.xml DESTINATION ${KDE_INSTALL_DATADIR}/libdiscover/categories)
