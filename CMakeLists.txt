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
    src/app/Application.cpp
    src/app/MainLoop.cpp
    src/system/SystemMonitorService.cpp
    src/debug/DebugService.cpp
    src/notification/NotificationManager.cpp
    src/dbus/SessionBus.cpp
    src/dbus/SystemBus.cpp
    src/dbus/mpris/MprisService.cpp
    src/dbus/notification/NotificationPollSource.cpp
    src/dbus/notification/NotificationService.cpp
    src/dbus/power/PowerProfilesService.cpp
    src/dbus/tray/TrayService.cpp
    src/config/ConfigService.cpp
    src/config/StateService.cpp
    src/core/Log.cpp
    src/font/FontService.cpp
    src/render/scene/Node.cpp
    src/render/animation/Animation.cpp
    src/render/animation/AnimationManager.cpp
    src/render/core/ShaderProgram.cpp
    src/render/core/TextureManager.cpp
    src/render/programs/ImageProgram.cpp
    src/render/programs/LinearGradientProgram.cpp
    src/render/programs/MsdfTextProgram.cpp
    src/render/programs/RoundedRectProgram.cpp
    src/render/programs/WallpaperProgram.cpp
    src/render/text/MsdfTextRenderer.cpp
    src/render/RenderContext.cpp
    src/render/RenderTarget.cpp
    src/render/ImageLoaders.cpp
    src/render/WallpaperRenderer.cpp
    src/shell/Bar.cpp
    src/shell/Wallpaper.cpp
    src/shell/WallpaperSurface.cpp
    src/time/TimeService.cpp
    src/shell/Widget.cpp
    src/shell/WidgetFactory.cpp
    src/ui/controls/Box.cpp
    src/ui/controls/Button.cpp
    src/ui/controls/Chip.cpp
    src/ui/controls/Dropdown.cpp
    src/ui/controls/Icon.cpp
    src/ui/controls/IconButton.cpp
    src/ui/controls/Label.cpp
    src/ui/controls/Slider.cpp
    src/ui/controls/Toggle.cpp
    src/ui/icons/IconRegistry.cpp
    src/render/scene/InputArea.cpp
    src/render/scene/InputDispatcher.cpp
    src/shell/PanelManager.cpp
    src/shell/panels/TestPanelContent.cpp
    src/shell/widgets/ClockWidget.cpp
    src/shell/widgets/NotificationWidget.cpp
    src/shell/widgets/SpacerWidget.cpp
    src/shell/widgets/TestWidget.cpp
    src/shell/widgets/TrayWidget.cpp
    src/shell/widgets/WorkspacesWidget.cpp
    src/wayland/Surface.cpp
    src/wayland/LayerSurface.cpp
    src/wayland/WaylandConnection.cpp
    src/wayland/WaylandSeat.cpp
    src/wayland/WaylandWorkspaces.cpp
    "${WLR_LAYER_SHELL_PROTOCOL_C}"
    "${XDG_OUTPUT_PROTOCOL_C}"
    "${XDG_SHELL_PROTOCOL_C}"
    "${EXT_WORKSPACE_PROTOCOL_C}"
    "${CURSOR_SHAPE_PROTOCOL_C}"
)
target_compile_definitions(noctalia PRIVATE
    NOCTALIA_ASSETS_DIR="${CMAKE_SOURCE_DIR}/assets"
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
)
target_compile_options(noctalia PRIVATE
    ${WAYLAND_CLIENT_CFLAGS_OTHER}
    ${EGL_CFLAGS_OTHER}
    ${GLES2_CFLAGS_OTHER}
    ${WAYLAND_EGL_CFLAGS_OTHER}
    ${FREETYPE2_CFLAGS_OTHER}
    ${HARFBUZZ_CFLAGS_OTHER}
    ${FONTCONFIG_CFLAGS_OTHER}
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
