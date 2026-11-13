# DeskDroid: Software (bin/software), the app store's desktop app, built as a
# library QtHost starts (native/plasma/kwin-nativedesk/qthost_entry.cpp). It
# shares the Steam Installation Assistant's party look (its qml/ components).
#   -DQTHOST_ENTRY=<qthost_entry.cpp> -DFONTS_DIR=<app/src/main/assets/fonts>
#   -DPARTY_DIR=<native/plasma/steamassistant/qml>
# Off the phone (-DSOFTWARE_DESKTOP=ON), an ordinary program for previews.
cmake_minimum_required(VERSION 3.16)
project(deskdroid-software LANGUAGES CXX)

set(QT_MIN_VERSION "6.8.0")
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
option(SOFTWARE_DESKTOP "Build a desktop program (previews), not a QtHost library" OFF)

find_package(Qt6 ${QT_MIN_VERSION} CONFIG REQUIRED COMPONENTS Core Gui Widgets Qml Quick QuickControls2)

# The resources: Software's pages, the assistant's party components and fonts.
set(R "${CMAKE_CURRENT_BINARY_DIR}/res")
file(REMOVE_RECURSE "${R}")
set(party Party.qml Chamfer.qml PartyButton.qml RainbowBar.qml RainbowText.qml Tile.qml PartyPage.qml PartyDialog.qml)
foreach(f ${party})
    configure_file("${PARTY_DIR}/${f}" "${R}/qml/${f}" COPYONLY)
endforeach()
file(GLOB own CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}/qml" "${CMAKE_CURRENT_SOURCE_DIR}/qml/*")
foreach(f ${own})
    configure_file("${CMAKE_CURRENT_SOURCE_DIR}/qml/${f}" "${R}/qml/${f}" COPYONLY)
endforeach()
configure_file(icon.svg "${R}/icon.svg" COPYONLY)
set(fonts Orbitron.ttf ChakraPetch-Regular.ttf ChakraPetch-SemiBold.ttf ChakraPetch-Bold.ttf)
foreach(font ${fonts})
    configure_file("${FONTS_DIR}/${font}" "${R}/fonts/${font}" COPYONLY)
endforeach()
set(qrc "<RCC>\n  <qresource prefix=\"/\">\n    <file>icon.svg</file>\n")
foreach(f ${fonts})
    string(APPEND qrc "    <file>fonts/${f}</file>\n")
endforeach()
foreach(f ${party} ${own})
    string(APPEND qrc "    <file>qml/${f}</file>\n")
endforeach()
string(APPEND qrc "  </qresource>\n</RCC>\n")
file(WRITE "${R}/software.qrc" "${qrc}")

if(SOFTWARE_DESKTOP)
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/main.cpp" main)
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/entry.cpp" "${main}\nint main(int argc, char **argv) { return softwareMain(argc, argv); }\n")
    add_executable(software "${CMAKE_CURRENT_BINARY_DIR}/entry.cpp" backend.cpp backend.h "${R}/software.qrc")
else()
    # QtHost's entry point, calling softwareMain() instead of KWin's main.
    file(READ "${QTHOST_ENTRY}" entry)
    string(REPLACE "args.push_back(\"kwin_wayland\")" "args.push_back(\"software\")" entry "${entry}")
    string(REPLACE "return kwinMain(" "return softwareMain(" entry "${entry}")
    if(entry MATCHES "kwinMain")
        message(FATAL_ERROR "QtHost entry not adapted")
    endif()
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/main.cpp" main)
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/entry.cpp" "${main}\n${entry}")
    add_library(software SHARED "${CMAKE_CURRENT_BINARY_DIR}/entry.cpp" backend.cpp backend.h "${R}/software.qrc")
    set_target_properties(software PROPERTIES CXX_VISIBILITY_PRESET default SUFFIX ".so" PREFIX "lib")
    # 16 KB pages (newer phones) need 16 KB-aligned segments, like the APK's libraries.
    target_link_options(software PRIVATE "-Wl,-z,max-page-size=16384")
    target_link_libraries(software PRIVATE log dl)
endif()
target_include_directories(software PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(software PRIVATE Qt6::Widgets Qt6::Qml Qt6::Quick Qt6::QuickControls2)

install(TARGETS software LIBRARY DESTINATION lib RUNTIME DESTINATION bin)
install(FILES org.deskdroid.software.desktop DESTINATION share/applications)
install(FILES icon.svg DESTINATION share/icons/hicolor/scalable/apps RENAME org.deskdroid.software.svg)
# .adpk, DeskDroid's package file: a MIME type, so a double-click opens Software.
install(FILES deskdroid-adpk.xml DESTINATION share/mime/packages)
