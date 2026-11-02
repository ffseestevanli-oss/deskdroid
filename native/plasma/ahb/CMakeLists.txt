# Qt Wayland's client buffer integration for deskdroid_ahb_v1: Qt apps
# (plasmashell, Dolphin...) draw with the phone's GPU into AHardwareBuffers
# and hand them to KWin. Picked with QT_WAYLAND_CLIENT_BUFFER_INTEGRATION=deskdroid-ahb.
cmake_minimum_required(VERSION 3.22)
project(deskdroid-ahb LANGUAGES CXX)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 REQUIRED COMPONENTS Core Gui OpenGL WaylandClient)
find_package(PkgConfig REQUIRED)
pkg_check_modules(WaylandClient REQUIRED IMPORTED_TARGET wayland-client)

qt_add_plugin(deskdroid_ahb_plugin
    OUTPUT_NAME deskdroid-ahb
    PLUGIN_TYPE wayland-graphics-integration-client
    plugin.cpp
)
target_link_libraries(deskdroid_ahb_plugin PRIVATE
    Qt6::Core Qt6::Gui Qt6::GuiPrivate Qt6::OpenGL Qt6::WaylandClient Qt6::WaylandClientPrivate
    PkgConfig::WaylandClient EGL GLESv3 android)
install(TARGETS deskdroid_ahb_plugin LIBRARY DESTINATION plugins/wayland-graphics-integration-client)
