cmake_minimum_required(VERSION 3.20)
project(Noctalia VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Export compile_commands.json for tooling
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# --- Sanitizers (on by default for Debug builds) ---
option(SANITIZE "Enable AddressSanitizer + UndefinedBehaviorSanitizer" OFF)
if(SANITIZE OR (CMAKE_BUILD_TYPE STREQUAL "Debug"))
  add_compile_options(-fsanitize=address,undefined -fno-omit-frame-pointer)
  add_link_options(-fsanitize=address,undefined)
  set(SANITIZE_ACTIVE TRUE)
endif()

# --- Dependencies ---
find_package(PkgConfig REQUIRED)
find_package(sdbus-c++ REQUIRED)
pkg_check_modules(WAYLAND_CLIENT REQUIRED wayland-client)
pkg_check_modules(WAYLAND_PROTOCOLS REQUIRED wayland-protocols)
pkg_check_modules(EGL REQUIRED egl)
pkg_check_modules(GLES2 REQUIRED glesv2)
pkg_check_modules(WAYLAND_EGL REQUIRED wayland-egl)
pkg_check_modules(FREETYPE2 REQUIRED freetype2)
pkg_check_modules(HARFBUZZ REQUIRED harfbuzz)
pkg_check_modules(FONTCONFIG REQUIRED fontconfig)
pkg_check_modules(XKBCOMMON REQUIRED xkbcommon)
pkg_check_modules(LIBPIPEWIRE REQUIRED libpipewire-0.3)

# --- msdfgen (vendored) ---
set(MSDFGEN_CORE_ONLY OFF CACHE BOOL "" FORCE)
set(MSDFGEN_BUILD_STANDALONE OFF CACHE BOOL "" FORCE)
set(MSDFGEN_USE_VCPKG OFF CACHE BOOL "" FORCE)
set(MSDFGEN_USE_SKIA OFF CACHE BOOL "" FORCE)
set(MSDFGEN_DISABLE_SVG ON CACHE BOOL "" FORCE)
set(MSDFGEN_DISABLE_PNG ON CACHE BOOL "" FORCE)
set(MSDFGEN_INSTALL OFF CACHE BOOL "" FORCE)
add_subdirectory(third_party/msdfgen)
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
set(EXT_WORKSPACE_XML
    "${WAYLAND_PROTOCOLS_PKGDATADIR}/staging/ext-workspace/ext-workspace-v1.xml")
set(CURSOR_SHAPE_XML
    "${CMAKE_CURRENT_SOURCE_DIR}/protocols/cursor-shape-v1.xml")

set(XDG_OUTPUT_PROTOCOL_C
    "${GENERATED_PROTOCOL_DIR}/xdg-output-unstable-v1-client-protocol.c")
set(XDG_OUTPUT_PROTOCOL_H
    "${GENERATED_PROTOCOL_DIR}/xdg-output-unstable-v1-client-protocol.h")
set(XDG_SHELL_PROTOCOL_C
    "${GENERATED_PROTOCOL_DIR}/xdg-shell-client-protocol.c")
set(XDG_SHELL_PROTOCOL_H
    "${GENERATED_PROTOCOL_DIR}/xdg-shell-client-protocol.h")
set(EXT_WORKSPACE_PROTOCOL_C
    "${GENERATED_PROTOCOL_DIR}/ext-workspace-v1-client-protocol.c")
set(EXT_WORKSPACE_PROTOCOL_H
    "${GENERATED_PROTOCOL_DIR}/ext-workspace-v1-client-protocol.h")

set(CURSOR_SHAPE_PROTOCOL_C
    "${GENERATED_PROTOCOL_DIR}/cursor-shape-v1-client-protocol.c")
set(CURSOR_SHAPE_PROTOCOL_H
    "${GENERATED_PROTOCOL_DIR}/cursor-shape-v1-client-protocol.h")

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

add_custom_command(
    OUTPUT "${EXT_WORKSPACE_PROTOCOL_C}"
    COMMAND "${WAYLAND_SCANNER_EXECUTABLE}" private-code "${EXT_WORKSPACE_XML}" "${EXT_WORKSPACE_PROTOCOL_C}"
    DEPENDS "${EXT_WORKSPACE_XML}"
    VERBATIM
)

add_custom_command(
    OUTPUT "${EXT_WORKSPACE_PROTOCOL_H}"
    COMMAND "${WAYLAND_SCANNER_EXECUTABLE}" client-header "${EXT_WORKSPACE_XML}" "${EXT_WORKSPACE_PROTOCOL_H}"
    DEPENDS "${EXT_WORKSPACE_XML}"
    VERBATIM
)

add_custom_command(
    OUTPUT "${CURSOR_SHAPE_PROTOCOL_C}"
    COMMAND "${WAYLAND_SCANNER_EXECUTABLE}" private-code "${CURSOR_SHAPE_XML}" "${CURSOR_SHAPE_PROTOCOL_C}"
    DEPENDS "${CURSOR_SHAPE_XML}"
    VERBATIM
)

add_custom_command(
    OUTPUT "${CURSOR_SHAPE_PROTOCOL_H}"
    COMMAND "${WAYLAND_SCANNER_EXECUTABLE}" client-header "${CURSOR_SHAPE_XML}" "${CURSOR_SHAPE_PROTOCOL_H}"
    DEPENDS "${CURSOR_SHAPE_XML}"
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
        "${EXT_WORKSPACE_PROTOCOL_C}"
        "${EXT_WORKSPACE_PROTOCOL_H}"
        "${CURSOR_SHAPE_PROTOCOL_C}"
        "${CURSOR_SHAPE_PROTOCOL_H}"
)

# --- Target ---
add_executable(noctalia
    src/main.cpp
    src/app/application.cpp
    src/app/main_loop.cpp
    src/system/system_monitor_service.cpp
    src/debug/debug_service.cpp
    src/notification/notification_manager.cpp
    src/dbus/session_bus.cpp
    src/dbus/system_bus.cpp
    src/dbus/mpris/mpris_service.cpp
    src/dbus/notification/notification_poll_source.cpp
    src/dbus/notification/notification_service.cpp
    src/dbus/power/power_profiles_service.cpp
    src/dbus/tray/tray_service.cpp
    src/dbus/upower/upower_service.cpp
    src/config/config_service.cpp
    src/config/state_service.cpp
    src/core/deferred_call.cpp
    src/core/log.cpp
    src/font/font_service.cpp
    src/render/scene/node.cpp
    src/render/animation/animation.cpp
    src/render/animation/animation_manager.cpp
    src/render/core/shader_program.cpp
    src/render/core/texture_manager.cpp
    src/render/programs/image_program.cpp
    src/render/programs/linear_gradient_program.cpp
    src/render/programs/msdf_text_program.cpp
    src/render/programs/rounded_rect_program.cpp
    src/render/programs/spinner_program.cpp
    src/render/programs/wallpaper_program.cpp
    src/render/text/msdf_text_renderer.cpp
    src/render/render_context.cpp
    src/render/render_target.cpp
    src/render/image_loaders.cpp
    src/render/wallpaper_renderer.cpp
    src/shell/bar/bar.cpp
    src/shell/wallpaper/wallpaper.cpp
    src/shell/wallpaper/wallpaper_surface.cpp
    src/time/time_service.cpp
    src/shell/widget/widget.cpp
    src/shell/widget/widget_factory.cpp
    src/ui/controls/box.cpp
    src/ui/controls/flex.cpp
    src/ui/controls/button.cpp
    src/ui/controls/progress_bar.cpp
    src/ui/controls/input.cpp
    src/ui/controls/scroll_view.cpp
    src/ui/controls/chip.cpp
    src/ui/controls/select.cpp
    src/ui/controls/icon.cpp
    src/ui/controls/label.cpp
    src/ui/controls/slider.cpp
    src/ui/controls/spinner.cpp
    src/ui/controls/toggle.cpp
    src/ui/icons/icon_registry.cpp
    src/render/scene/input_area.cpp
    src/render/scene/input_dispatcher.cpp
    src/shell/notification/notification_popup.cpp
    src/shell/tray/tray_menu.cpp
    src/shell/panel/panel_manager.cpp
    src/shell/panels/notification_history_panel.cpp
    src/shell/panels/test_panel.cpp
    src/shell/widgets/clock_widget.cpp
    src/shell/widgets/notification_widget.cpp
    src/shell/widgets/spacer_widget.cpp
    src/shell/widgets/test_widget.cpp
    src/shell/widgets/tray_widget.cpp
    src/shell/widgets/battery_widget.cpp
    src/shell/widgets/sysmon_widget.cpp
    src/shell/widgets/volume_widget.cpp
    src/shell/widgets/workspaces_widget.cpp
    src/pipewire/pipewire_service.cpp
    $<$<BOOL:${SANITIZE_ACTIVE}>:src/pipewire/pipewire_lsan.cpp>
    src/wayland/surface.cpp
    src/wayland/layer_surface.cpp
    src/wayland/wayland_connection.cpp
    src/wayland/wayland_seat.cpp
    src/wayland/wayland_workspaces.cpp
    "${WLR_LAYER_SHELL_PROTOCOL_C}"
    "${XDG_OUTPUT_PROTOCOL_C}"
    "${XDG_SHELL_PROTOCOL_C}"
    "${EXT_WORKSPACE_PROTOCOL_C}"
    "${CURSOR_SHAPE_PROTOCOL_C}"
)
target_compile_definitions(noctalia PRIVATE
    NOCTALIA_ASSETS_DIR="${CMAKE_SOURCE_DIR}/assets"
    NOCTALIA_VERSION="${PROJECT_VERSION}"
)

add_dependencies(noctalia noctalia_wayland_protocols)

target_include_directories(noctalia PRIVATE
    src
    third_party/stb
    third_party/nanosvg
    third_party/tomlplusplus
    "${GENERATED_PROTOCOL_DIR}"
    ${WAYLAND_CLIENT_INCLUDE_DIRS}
    ${EGL_INCLUDE_DIRS}
    ${GLES2_INCLUDE_DIRS}
    ${WAYLAND_EGL_INCLUDE_DIRS}
    ${FREETYPE2_INCLUDE_DIRS}
    ${HARFBUZZ_INCLUDE_DIRS}
    ${FONTCONFIG_INCLUDE_DIRS}
    ${XKBCOMMON_INCLUDE_DIRS}
)
# PipeWire/SPA headers use GCC extensions (compound-literals, statement-
# expressions) that trigger -Wpedantic/-Wconversion. Mark them as system
# headers so the compiler suppresses those warnings.
target_include_directories(noctalia SYSTEM PRIVATE
    ${LIBPIPEWIRE_INCLUDE_DIRS}
)
target_link_libraries(noctalia PRIVATE
    SDBusCpp::sdbus-c++
    msdfgen::msdfgen-core
    msdfgen::msdfgen-ext
    ${WAYLAND_CLIENT_LIBRARIES}
    ${EGL_LIBRARIES}
    ${GLES2_LIBRARIES}
    ${WAYLAND_EGL_LIBRARIES}
    ${FREETYPE2_LIBRARIES}
    ${HARFBUZZ_LIBRARIES}
    ${FONTCONFIG_LIBRARIES}
    ${XKBCOMMON_LIBRARIES}
    ${LIBPIPEWIRE_LIBRARIES}
)
target_compile_options(noctalia PRIVATE
    ${WAYLAND_CLIENT_CFLAGS_OTHER}
    ${EGL_CFLAGS_OTHER}
    ${GLES2_CFLAGS_OTHER}
    ${WAYLAND_EGL_CFLAGS_OTHER}
    ${FREETYPE2_CFLAGS_OTHER}
    ${HARFBUZZ_CFLAGS_OTHER}
    ${FONTCONFIG_CFLAGS_OTHER}
    ${LIBPIPEWIRE_CFLAGS_OTHER}
)

target_compile_options(noctalia PRIVATE
    -Wall
    -Wextra
    -Wpedantic
    -Wconversion
    -Wshadow
)

if(CMAKE_BUILD_TYPE STREQUAL "Release")
    target_compile_options(noctalia PRIVATE
        -O3
        -march=native
        -mtune=native
        -flto=auto
        -fomit-frame-pointer
        -ffunction-sections
        -fdata-sections
    )
    target_link_options(noctalia PRIVATE -flto=auto -Wl,--gc-sections -Wl,--as-needed)
endif()
