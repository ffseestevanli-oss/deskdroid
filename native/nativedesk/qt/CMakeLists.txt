# Qt demo app for the native desktop test (stage 2, docs/native-plasma.md): a
# Qt platform plugin (qpa.cpp) that puts Qt windows on the nativedesk
# compositor, linked statically into a demo with a raster window and an
# OpenGL window (main.cpp). Built against Qt's prebuilt Android libraries by
# ../build.sh when DESKDROID_QT_ANDROID is set.
cmake_minimum_required(VERSION 3.21)
project(nativedesk_qt LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui OpenGL)

add_executable(nativedesk_qt main.cpp qpa.cpp)
# The plugin is compiled in, not loaded: main.cpp imports it with Q_IMPORT_PLUGIN.
target_compile_definitions(nativedesk_qt PRIVATE QT_STATICPLUGIN)
target_include_directories(nativedesk_qt PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_link_libraries(nativedesk_qt PRIVATE
    Qt6::Core Qt6::CorePrivate Qt6::Gui Qt6::GuiPrivate Qt6::OpenGL
    EGL GLESv3 nativewindow android log)
