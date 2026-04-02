cmake_minimum_required(VERSION 3.20)
project(Noctalia VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Export compile_commands.json for tooling
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# --- Dependencies ---
find_package(PkgConfig REQUIRED)
find_package(sdbus-c++ REQUIRED)
pkg_check_modules(WAYLAND_CLIENT REQUIRED wayland-client)
pkg_check_modules(WAYLAND_PROTOCOLS REQUIRED wayland-protocols)
pkg_get_variable(WAYLAND_PROTOCOLS_PKGDATADIR wayland-protocols pkgdatadir)
file(REAL_PATH "${WAYLAND_PROTOCOLS_PKGDATADIR}" WAYLAND_PROTOCOLS_PKGDATADIR)

find_program(WAYLAND_SCANNER_EXECUTABLE wayland-scanner REQUIRED)

set(GENERATED_PROTOCOL_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
file(MAKE_DIRECTORY "${GENERATED_PROTOCOL_DIR}")
set(PROTOCOL_PREPARE_SCRIPT
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/PrepareWaylandProtocol.cmake")

set(WLR_LAYER_SHELL_SOURCE_XML
    "${CMAKE_CURRENT_SOURCE_DIR}/protocols/wlr-layer-shell-unstable-v1.xml")
set(WLR_LAYER_SHELL_XML
    "${GENERATED_PROTOCOL_DIR}/wlr-layer-shell-unstable-v1.scanner.xml")
set(XDG_OUTPUT_XML
    "${WAYLAND_PROTOCOLS_PKGDATADIR}/unstable/xdg-output/xdg-output-unstable-v1.xml")
set(XDG_SHELL_XML
    "${WAYLAND_PROTOCOLS_PKGDATADIR}/stable/xdg-shell/xdg-shell.xml")

set(XDG_OUTPUT_PROTOCOL_C
    "${GENERATED_PROTOCOL_DIR}/xdg-output-unstable-v1-client-protocol.c")
set(XDG_OUTPUT_PROTOCOL_H
    "${GENERATED_PROTOCOL_DIR}/xdg-output-unstable-v1-client-protocol.h")
set(XDG_SHELL_PROTOCOL_C
    "${GENERATED_PROTOCOL_DIR}/xdg-shell-client-protocol.c")
set(XDG_SHELL_PROTOCOL_H
    "${GENERATED_PROTOCOL_DIR}/xdg-shell-client-protocol.h")

set(WLR_LAYER_SHELL_PROTOCOL_C
    "${GENERATED_PROTOCOL_DIR}/wlr-layer-shell-unstable-v1-client-protocol.c")
set(WLR_LAYER_SHELL_PROTOCOL_H
    "${GENERATED_PROTOCOL_DIR}/wlr-layer-shell-unstable-v1-client-protocol.h")

add_custom_command(
    OUTPUT "${WLR_LAYER_SHELL_XML}"
    COMMAND "${CMAKE_COMMAND}"
            -DINPUT_XML=${WLR_LAYER_SHELL_SOURCE_XML}
            -DOUTPUT_XML=${WLR_LAYER_SHELL_XML}
            -P "${PROTOCOL_PREPARE_SCRIPT}"
    DEPENDS
        "${WLR_LAYER_SHELL_SOURCE_XML}"
        "${PROTOCOL_PREPARE_SCRIPT}"
    VERBATIM
)

add_custom_command(
    OUTPUT "${WLR_LAYER_SHELL_PROTOCOL_C}"
    COMMAND "${WAYLAND_SCANNER_EXECUTABLE}" private-code "${WLR_LAYER_SHELL_XML}" "${WLR_LAYER_SHELL_PROTOCOL_C}"
    DEPENDS "${WLR_LAYER_SHELL_XML}"
    VERBATIM
)

add_custom_command(
    OUTPUT "${WLR_LAYER_SHELL_PROTOCOL_H}"
    COMMAND "${WAYLAND_SCANNER_EXECUTABLE}" client-header "${WLR_LAYER_SHELL_XML}" "${WLR_LAYER_SHELL_PROTOCOL_H}"
    DEPENDS "${WLR_LAYER_SHELL_XML}"
    VERBATIM
)

add_custom_command(
    OUTPUT "${XDG_OUTPUT_PROTOCOL_C}"
    COMMAND "${WAYLAND_SCANNER_EXECUTABLE}" private-code "${XDG_OUTPUT_XML}" "${XDG_OUTPUT_PROTOCOL_C}"
    DEPENDS "${XDG_OUTPUT_XML}"
    VERBATIM
)

add_custom_command(
    OUTPUT "${XDG_OUTPUT_PROTOCOL_H}"
    COMMAND "${WAYLAND_SCANNER_EXECUTABLE}" client-header "${XDG_OUTPUT_XML}" "${XDG_OUTPUT_PROTOCOL_H}"
    DEPENDS "${XDG_OUTPUT_XML}"
    VERBATIM
)

add_custom_command(
    OUTPUT "${XDG_SHELL_PROTOCOL_C}"
    COMMAND "${WAYLAND_SCANNER_EXECUTABLE}" private-code "${XDG_SHELL_XML}" "${XDG_SHELL_PROTOCOL_C}"
    DEPENDS "${XDG_SHELL_XML}"
    VERBATIM
)

add_custom_command(
    OUTPUT "${XDG_SHELL_PROTOCOL_H}"
    COMMAND "${WAYLAND_SCANNER_EXECUTABLE}" client-header "${XDG_SHELL_XML}" "${XDG_SHELL_PROTOCOL_H}"
    DEPENDS "${XDG_SHELL_XML}"
    VERBATIM
)

add_custom_target(noctalia_wayland_protocols
    DEPENDS
        "${WLR_LAYER_SHELL_PROTOCOL_C}"
        "${WLR_LAYER_SHELL_PROTOCOL_H}"
        "${XDG_OUTPUT_PROTOCOL_C}"
        "${XDG_OUTPUT_PROTOCOL_H}"
        "${XDG_SHELL_PROTOCOL_C}"
        "${XDG_SHELL_PROTOCOL_H}"
)

# --- Target ---
add_executable(noctalia
    src/main.cpp
    src/app/Application.cpp
    src/notification/NotificationManager.cpp
    src/dbus/notification/NotificationService.cpp
    src/shell/BarShell.cpp
    src/wayland/LayerSurface.cpp
    src/wayland/WaylandConnection.cpp
    "${WLR_LAYER_SHELL_PROTOCOL_C}"
    "${XDG_OUTPUT_PROTOCOL_C}"
    "${XDG_SHELL_PROTOCOL_C}"
)
target_compile_definitions(noctalia PRIVATE NOCTALIA_HAVE_WLR_LAYER_SHELL=1)

add_dependencies(noctalia noctalia_wayland_protocols)

target_include_directories(noctalia PRIVATE
    src
    "${GENERATED_PROTOCOL_DIR}"
    ${WAYLAND_CLIENT_INCLUDE_DIRS}
)
target_link_libraries(noctalia PRIVATE
    SDBusCpp::sdbus-c++
    ${WAYLAND_CLIENT_LIBRARIES}
)
target_compile_options(noctalia PRIVATE
    ${WAYLAND_CLIENT_CFLAGS_OTHER}
)

target_compile_options(noctalia PRIVATE
    -Wall
    -Wextra
    -Wpedantic
    -Wconversion
    -Wshadow
)
