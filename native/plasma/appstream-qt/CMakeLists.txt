# AppStreamQt (AppStream's Qt library) for Android, from AppStream's qt/
# folder. Upstream builds it with Meson's Qt module, which can't find this
# cross-built Qt; this builds the same files against the libappstream that
# build_appstream installed. Configure with -DASQT_SRC=<AppStream>/qt.
cmake_minimum_required(VERSION 3.16)
project(AppStreamQt VERSION 1.2.2 LANGUAGES CXX)
set(CMAKE_AUTOMOC ON)
set(CMAKE_CXX_STANDARD 17)
find_package(Qt6 REQUIRED COMPONENTS Core)
find_package(PkgConfig REQUIRED)
pkg_check_modules(AS REQUIRED IMPORTED_TARGET appstream)

file(GLOB SRC "${ASQT_SRC}/*.cpp")
file(GLOB HDR "${ASQT_SRC}/*.h")
set(AS_MAJOR_VERSION_CONF ${PROJECT_VERSION_MAJOR})
set(AS_MINOR_VERSION_CONF ${PROJECT_VERSION_MINOR})
set(AS_MICRO_VERSION_CONF ${PROJECT_VERSION_PATCH})
configure_file("${ASQT_SRC}/version.h.in" "${CMAKE_CURRENT_BINARY_DIR}/version.h" @ONLY)

add_library(AppStreamQt SHARED ${SRC} ${HDR})
target_compile_definitions(AppStreamQt PRIVATE QT_NO_KEYWORDS)
target_include_directories(AppStreamQt PRIVATE "${ASQT_SRC}" "${ASQT_SRC}/../src" "${CMAKE_CURRENT_BINARY_DIR}"
  INTERFACE $<INSTALL_INTERFACE:include>)
target_link_libraries(AppStreamQt PUBLIC Qt6::Core PRIVATE PkgConfig::AS)
set_target_properties(AppStreamQt PROPERTIES VERSION ${PROJECT_VERSION} SOVERSION 3)

include(CMakePackageConfigHelpers)
list(REMOVE_ITEM HDR "${ASQT_SRC}/chelpers.h")
install(FILES ${HDR} "${CMAKE_CURRENT_BINARY_DIR}/version.h" DESTINATION include/AppStreamQt)
install(TARGETS AppStreamQt EXPORT AppStreamQtTargets LIBRARY DESTINATION lib)
install(EXPORT AppStreamQtTargets DESTINATION lib/cmake/AppStreamQt)
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/AppStreamQtConfig.cmake"
  "include(CMakeFindDependencyMacro)\nfind_dependency(Qt6Core)\ninclude(\"\${CMAKE_CURRENT_LIST_DIR}/AppStreamQtTargets.cmake\")\n")
write_basic_package_version_file("${CMAKE_CURRENT_BINARY_DIR}/AppStreamQtConfigVersion.cmake" COMPATIBILITY SameMajorVersion)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/AppStreamQtConfig.cmake" "${CMAKE_CURRENT_BINARY_DIR}/AppStreamQtConfigVersion.cmake"
  DESTINATION lib/cmake/AppStreamQt)
