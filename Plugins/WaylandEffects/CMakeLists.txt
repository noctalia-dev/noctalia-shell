cmake_minimum_required(VERSION 3.20)
project(noctalia-wayland-effects VERSION 1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick WaylandClient)
find_package(Qt6GuiPrivate REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(WAYLAND_CLIENT REQUIRED wayland-client)

qt_add_library(noctaliawayland SHARED)

qt_add_qml_module(noctaliawayland
    URI Noctalia.Wayland
    VERSION 1.0
    OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/Noctalia/Wayland"
    SOURCES
        BackgroundEffectManager.h BackgroundEffectManager.cpp
        BackgroundBlur.h BackgroundBlur.cpp
)

qt_generate_wayland_protocol_client_sources(noctaliawayland
    FILES
        "${CMAKE_CURRENT_SOURCE_DIR}/protocols/ext-background-effect-v1.xml"
)

# The Qt macro generates the C protocol file but doesn't compile it.
# Add it manually so the interface structs are defined.
target_sources(noctaliawayland PRIVATE
    "${CMAKE_CURRENT_BINARY_DIR}/wayland-ext-background-effect-v1-protocol.c"
)

target_link_libraries(noctaliawayland PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::GuiPrivate
    Qt6::Quick
    Qt6::WaylandClient
    ${WAYLAND_CLIENT_LIBRARIES}
)

target_include_directories(noctaliawayland PRIVATE
    ${WAYLAND_CLIENT_INCLUDE_DIRS}
    "${CMAKE_CURRENT_BINARY_DIR}"
)

install(
    DIRECTORY "${CMAKE_BINARY_DIR}/Noctalia/"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/qt6/qml/Noctalia"
)
