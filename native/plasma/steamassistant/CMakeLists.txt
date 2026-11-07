# DeskDroid: the Steam Installation Assistant (bin/steam-assistant), built as
# a library QtHost starts (native/plasma/kwin-nativedesk/qthost_entry.cpp).
#   -DQTHOST_ENTRY=<qthost_entry.cpp> -DFONTS_DIR=<app/src/main/assets/fonts>
cmake_minimum_required(VERSION 3.16)
project(deskdroid-steam-assistant LANGUAGES CXX)

set(QT_MIN_VERSION "6.8.0")
set(KF6_MIN_VERSION "6.14.0")
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 ${QT_MIN_VERSION} CONFIG REQUIRED COMPONENTS Core Gui Widgets Qml Quick QuickControls2)

# QtHost's entry point, calling assistantMain() instead of KWin's main.
file(READ "${QTHOST_ENTRY}" entry)
string(REPLACE "args.push_back(\"kwin_wayland\")" "args.push_back(\"steam-assistant\")" entry "${entry}")
string(REPLACE "return kwinMain(" "return assistantMain(" entry "${entry}")
if(entry MATCHES "kwinMain")
    message(FATAL_ERROR "QtHost entry not adapted")
endif()
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/main.cpp" main)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/entry.cpp" "${main}\n${entry}")

foreach(font Orbitron.ttf ChakraPetch-Regular.ttf ChakraPetch-SemiBold.ttf ChakraPetch-Bold.ttf)
    configure_file("${FONTS_DIR}/${font}" "${CMAKE_CURRENT_SOURCE_DIR}/fonts/${font}" COPYONLY)
endforeach()

add_library(steam-assistant SHARED "${CMAKE_CURRENT_BINARY_DIR}/entry.cpp" backend.cpp backend.h assistant.qrc)
target_include_directories(steam-assistant PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
set_target_properties(steam-assistant PROPERTIES CXX_VISIBILITY_PRESET default SUFFIX ".so" PREFIX "lib")
# 16 KB pages (newer phones) need 16 KB-aligned segments, like the APK's libraries.
target_link_options(steam-assistant PRIVATE "-Wl,-z,max-page-size=16384")
target_link_libraries(steam-assistant PRIVATE Qt6::Widgets Qt6::Qml Qt6::Quick Qt6::QuickControls2 log dl)

install(TARGETS steam-assistant LIBRARY DESTINATION lib)
install(FILES org.deskdroid.steamassistant.desktop DESTINATION share/applications)
install(FILES icon.svg DESTINATION share/icons/hicolor/scalable/apps RENAME org.deskdroid.steamassistant.svg)
