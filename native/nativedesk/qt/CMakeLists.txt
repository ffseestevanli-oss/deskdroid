# Qt demo app for the native desktop test (stage 2, docs/native-plasma.md): a
# Qt platform plugin (qpa.cpp) that puts Qt windows on the nativedesk
# compositor, linked statically into a demo with a raster window, an OpenGL
# window and a Qt Quick (QML) window (main.cpp, demo.qml). Built against Qt's
# prebuilt Android libraries by ../build.sh when DESKDROID_QT_ANDROID is set.
cmake_minimum_required(VERSION 3.21)
project(nativedesk_qt LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui OpenGL Qml QmlModels QmlWorkerScript Quick)
# Qt 6.7+ keeps the QtQml module's own types here.
find_package(Qt6 QUIET COMPONENTS QmlMeta)

# A JNI library, not an executable: QtHost.kt loads it into an app_process,
# because Qt for Android needs a Java VM.
add_library(nativedesk_qt SHARED main.cpp qpa.cpp demo.qrc)
# The plugin is compiled in, not loaded: main.cpp imports it with Q_IMPORT_PLUGIN.
target_compile_definitions(nativedesk_qt PRIVATE QT_STATICPLUGIN)
target_include_directories(nativedesk_qt PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
target_link_libraries(nativedesk_qt PRIVATE
    Qt6::Core Qt6::CorePrivate Qt6::Gui Qt6::GuiPrivate Qt6::OpenGL
    Qt6::Qml Qt6::QmlModels Qt6::QmlWorkerScript Qt6::Quick
    $<TARGET_NAME_IF_EXISTS:Qt6::QmlMeta>
    EGL GLESv3 nativewindow android log)
# QML modules are found by the types their libraries register, with no
# plugins or qmldir files to install, so keep libraries the code never calls.
target_link_options(nativedesk_qt PRIVATE "LINKER:--no-as-needed")
