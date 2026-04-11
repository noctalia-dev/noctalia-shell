project('noctalia', ['c', 'cpp'],
  version: '0.1.0',
  default_options: [
    'cpp_std=c++20',
    'cpp_extensions=false',
    'warning_level=0',   # applied selectively to our target; avoids noise in vendored code
    'b_ndebug=if-release',
  ],
)

cc  = meson.get_compiler('c')
cpp = meson.get_compiler('cpp')

# Sanitizers are enabled via meson's built-in -Db_sanitize=address,undefined.
# pipewire_lsan.cpp is only needed when address sanitizer is active.
sanitize = get_option('b_sanitize') != 'none'

# ── Release-only optimizations ────────────────────────────────────────────────
if get_option('buildtype') == 'release'
  add_project_arguments(
    '-march=native', '-mtune=native',
    '-fomit-frame-pointer', '-ffunction-sections', '-fdata-sections',
    language: ['c', 'cpp'],
  )
  add_project_link_arguments(
    '-Wl,--gc-sections', '-Wl,--as-needed',
    language: ['c', 'cpp'],
  )
endif

# ── Dependencies ──────────────────────────────────────────────────────────────
sdbus_cpp_dep       = dependency('sdbus-c++')
wayland_client_dep  = dependency('wayland-client')
wayland_protos_dep  = dependency('wayland-protocols')
egl_dep             = dependency('egl')
glesv2_dep          = dependency('glesv2')
wayland_egl_dep     = dependency('wayland-egl')
freetype2_dep       = dependency('freetype2')
fontconfig_dep      = dependency('fontconfig')
cairo_dep           = dependency('cairo')
cairo_ft_dep        = dependency('cairo-ft')
pango_dep           = dependency('pango')
pangocairo_dep      = dependency('pangocairo')
xkbcommon_dep       = dependency('xkbcommon')
# PipeWire/SPA headers use GCC extensions that trigger -Wpedantic/-Wconversion;
# mark as system so the compiler suppresses those warnings.
pipewire_dep        = dependency('libpipewire-0.3', include_type: 'system')
curl_dep            = dependency('libcurl')
pam_dep             = cc.find_library('pam')

# ── Vendored: tinyexpr (C, needs suppressed warnings) ─────────────────────────
_tinyexpr_lib = static_library('tinyexpr',
  'third_party/tinyexpr/tinyexpr.c',
  c_args: ['-Wno-pedantic', '-Wno-conversion'],
  override_options: ['warning_level=0'],
)
tinyexpr_dep = declare_dependency(
  link_with: _tinyexpr_lib,
  include_directories: include_directories('third_party/tinyexpr', is_system: true),
)

# ── Vendored: Material Color Utilities (Google) ───────────────────────────────
# Upstream uses #include "cpp/..." prefixes, so the include root is the
# material_color_utilities/ dir itself. Built as a quiet static library.
_mcu_sources = files(
  'third_party/material_color_utilities/cpp/blend/blend.cc',
  'third_party/material_color_utilities/cpp/cam/cam.cc',
  'third_party/material_color_utilities/cpp/cam/hct.cc',
  'third_party/material_color_utilities/cpp/cam/hct_solver.cc',
  'third_party/material_color_utilities/cpp/cam/viewing_conditions.cc',
  'third_party/material_color_utilities/cpp/contrast/contrast.cc',
  'third_party/material_color_utilities/cpp/dislike/dislike.cc',
  'third_party/material_color_utilities/cpp/dynamiccolor/dynamic_color.cc',
  'third_party/material_color_utilities/cpp/dynamiccolor/dynamic_scheme.cc',
  'third_party/material_color_utilities/cpp/dynamiccolor/material_dynamic_colors.cc',
  'third_party/material_color_utilities/cpp/palettes/tones.cc',
  'third_party/material_color_utilities/cpp/quantize/celebi.cc',
  'third_party/material_color_utilities/cpp/quantize/lab.cc',
  'third_party/material_color_utilities/cpp/quantize/wsmeans.cc',
  'third_party/material_color_utilities/cpp/quantize/wu.cc',
  'third_party/material_color_utilities/cpp/scheme/scheme_content.cc',
  'third_party/material_color_utilities/cpp/scheme/scheme_expressive.cc',
  'third_party/material_color_utilities/cpp/scheme/scheme_fidelity.cc',
  'third_party/material_color_utilities/cpp/scheme/scheme_fruit_salad.cc',
  'third_party/material_color_utilities/cpp/scheme/scheme_monochrome.cc',
  'third_party/material_color_utilities/cpp/scheme/scheme_neutral.cc',
  'third_party/material_color_utilities/cpp/scheme/scheme_rainbow.cc',
  'third_party/material_color_utilities/cpp/scheme/scheme_tonal_spot.cc',
  'third_party/material_color_utilities/cpp/scheme/scheme_vibrant.cc',
  'third_party/material_color_utilities/cpp/score/score.cc',
  'third_party/material_color_utilities/cpp/temperature/temperature_cache.cc',
  'third_party/material_color_utilities/cpp/utils/utils.cc',
)
_mcu_lib = static_library('material_color_utilities',
  _mcu_sources,
  include_directories: include_directories('third_party/material_color_utilities', is_system: true),
  cpp_args: ['-Wno-pedantic', '-Wno-conversion', '-Wno-shadow', '-Wno-unused-parameter'],
  override_options: ['warning_level=0'],
)
mcu_dep = declare_dependency(
  link_with: _mcu_lib,
  include_directories: include_directories('third_party/material_color_utilities', is_system: true),
)

# ── Vendored: stb_image_resize2 (header-only) ─────────────────────────────────
stb_dep = declare_dependency(
  include_directories: include_directories('third_party/stb', is_system: true),
)

# ── System: libwebp (VP8 lossy WebP; wuffs only handles VP8L lossless) ────────
libwebp_dep = dependency('libwebp', required: true)

# ── Wayland protocol generation ───────────────────────────────────────────────
wayland_scanner    = find_program('wayland-scanner')
wayland_protos_dir = wayland_protos_dep.get_variable('pkgdatadir')

# Generates a (header, source) pair from a protocol XML path/target.
# Returns [h_target, c_target] — add c_target to sources.
# The c_target has an order-only dep on h_target so the header exists when
# the generated .c is compiled (it does #include "foo-client-protocol.h").
_protocol_sources = []

# Helper macro via foreach — each entry: [name, xml_input]
# xml_input can be a string (path) or a custom_target.

foreach _p : [
  # ── wlr-layer-shell needs namespace→name_space substitution first ──────────
  # Handled separately below.

  # ── system wayland-protocols ──────────────────────────────────────────────
  ['xdg-output-unstable-v1',
    wayland_protos_dir / 'unstable/xdg-output/xdg-output-unstable-v1.xml'],
  ['xdg-shell',
    wayland_protos_dir / 'stable/xdg-shell/xdg-shell.xml'],
  ['ext-workspace-v1',
    wayland_protos_dir / 'staging/ext-workspace/ext-workspace-v1.xml'],
  ['ext-data-control-v1',
    wayland_protos_dir / 'staging/ext-data-control/ext-data-control-v1.xml'],
  ['xdg-activation-v1',
    wayland_protos_dir / 'staging/xdg-activation/xdg-activation-v1.xml'],
  ['ext-session-lock-v1',
    wayland_protos_dir / 'staging/ext-session-lock/ext-session-lock-v1.xml'],
  ['ext-idle-notify-v1',
    wayland_protos_dir / 'staging/ext-idle-notify/ext-idle-notify-v1.xml'],
  ['idle-inhibit-unstable-v1',
    wayland_protos_dir / 'unstable/idle-inhibit/idle-inhibit-unstable-v1.xml'],

  # ── project-local custom protocols ────────────────────────────────────────
  ['dwl-ipc-unstable-v2',
    'protocols/dwl-ipc-unstable-v2.xml'],
  ['cursor-shape-v1',
    'protocols/cursor-shape-v1.xml'],
  ['wlr-foreign-toplevel-management-unstable-v1',
    'protocols/wlr-foreign-toplevel-management-unstable-v1.xml'],
  ['wlr-data-control-unstable-v1',
    'protocols/wlr-data-control-unstable-v1.xml'],
]
  _name = _p[0]
  _xml  = _p[1]

  _h = custom_target(_name + '-client-header',
    input:   _xml,
    output:  _name + '-client-protocol.h',
    command: [wayland_scanner, 'client-header', '@INPUT@', '@OUTPUT@'],
  )
  _c = custom_target(_name + '-client-source',
    input:   _xml,
    output:  _name + '-client-protocol.c',
    command: [wayland_scanner, 'private-code', '@INPUT@', '@OUTPUT@'],
    depends: _h,  # ensure .h exists before this .c is compiled (it #includes it)
  )
  _protocol_sources += _c
endforeach

# wlr-layer-shell: 'namespace' is a C++ keyword; rename it in the generated
# header only (private-code is compiled as C so it's fine as-is).
_wlr_ls_xml = 'protocols/wlr-layer-shell-unstable-v1.xml'
_wlr_ls_h = custom_target('wlr-layer-shell-unstable-v1-client-header',
  input:   _wlr_ls_xml,
  output:  'wlr-layer-shell-unstable-v1-client-protocol.h',
  command: [
    'sh', '-c',
    '"$1" client-header "$2" "$3" && sed -i s/namespace/name_space/g "$3"',
    '_', wayland_scanner.full_path(), '@INPUT@', '@OUTPUT@',
  ],
)
_wlr_ls_c = custom_target('wlr-layer-shell-unstable-v1-client-source',
  input:   _wlr_ls_xml,
  output:  'wlr-layer-shell-unstable-v1-client-protocol.c',
  command: [wayland_scanner, 'private-code', '@INPUT@', '@OUTPUT@'],
  depends: _wlr_ls_h,
)
_protocol_sources += _wlr_ls_c

# ── Main sources ──────────────────────────────────────────────────────────────
_noctalia_sources = files(
  'src/app/application.cpp',
  'src/app/main_loop.cpp',
  'src/auth/pam_authenticator.cpp',
  'src/config/config_service.cpp',
  'src/config/state_service.cpp',
  'src/core/deferred_call.cpp',
  'src/core/log.cpp',
  'src/core/process.cpp',
  'src/core/timer_manager.cpp',
  'src/dbus/mpris/mpris_service.cpp',
  'src/dbus/notification/notification_poll_source.cpp',
  'src/dbus/notification/notification_service.cpp',
  'src/dbus/power/power_profiles_service.cpp',
  'src/dbus/session_bus.cpp',
  'src/dbus/system_bus.cpp',
  'src/dbus/tray/tray_service.cpp',
  'src/dbus/upower/upower_service.cpp',
  'src/debug/debug_service.cpp',
  'src/i18n/i18n.cpp',
  'src/i18n/i18n_service.cpp',
  'src/idle/idle_inhibitor.cpp',
  'src/idle/idle_manager.cpp',
  'src/ipc/ipc_client.cpp',
  'src/ipc/ipc_service.cpp',
  'src/launcher/app_provider.cpp',
  'src/launcher/emoji_provider.cpp',
  'src/launcher/math_provider.cpp',
  'src/launcher/usage_tracker.cpp',
  'src/main.cpp',
  'src/net/http_client.cpp',
  'src/notification/notification_manager.cpp',
  'src/pipewire/pipewire_service.cpp',
  'src/pipewire/pipewire_spectrum.cpp',
  'src/render/animation/animation.cpp',
  'src/render/animation/animation_manager.cpp',
  'src/render/core/shader_program.cpp',
  'src/render/core/texture_manager.cpp',
  'src/render/core/image_decoder.cpp',
  'src/render/image_loaders.cpp',
  'src/render/programs/color_glyph_program.cpp',
  'src/render/programs/image_program.cpp',
  'src/render/programs/linear_gradient_program.cpp',
  'src/render/programs/rounded_rect_program.cpp',
  'src/render/programs/spinner_program.cpp',
  'src/render/programs/blur_program.cpp',
  'src/render/programs/wallpaper_program.cpp',
  'src/render/render_context.cpp',
  'src/render/render_target.cpp',
  'src/render/scene/input_area.cpp',
  'src/render/scene/input_dispatcher.cpp',
  'src/render/scene/node.cpp',
  'src/render/text/cairo_text_renderer.cpp',
  'src/render/text/cairo_glyph_renderer.cpp',
  'src/render/wallpaper_renderer.cpp',
  'src/shell/bar/bar.cpp',
  'src/shell/clipboard/clipboard_panel.cpp',
  'src/shell/control_center/calendar_tab.cpp',
  'src/shell/control_center/audio_tab.cpp',
  'src/shell/control_center/control_center_panel.cpp',
  'src/shell/control_center/media_tab.cpp',
  'src/shell/control_center/network_tab.cpp',
  'src/shell/control_center/notifications_tab.cpp',
  'src/shell/control_center/overview_tab.cpp',
  'src/shell/control_center/tab.cpp',
  'src/shell/control_center/weather_tab.cpp',
  'src/shell/launcher/launcher_panel.cpp',
  'src/shell/lockscreen/lock_screen.cpp',
  'src/shell/lockscreen/lock_surface.cpp',
  'src/shell/notification/notification_toast.cpp',
  'src/shell/osd/audio_osd.cpp',
  'src/shell/osd/osd_overlay.cpp',
  'src/shell/panel/panel_manager.cpp',
  'src/shell/session/session_panel.cpp',
  'src/shell/test/test_panel.cpp',
  'src/shell/tray/tray_menu.cpp',
  'src/shell/overview/overview.cpp',
  'src/shell/overview/overview_surface.cpp',
  'src/shell/wallpaper/wallpaper.cpp',
  'src/shell/wallpaper/wallpaper_surface.cpp',
  'src/shell/wallpaper/panel/thumbnail_service.cpp',
  'src/shell/wallpaper/panel/wallpaper_page_grid.cpp',
  'src/shell/wallpaper/panel/wallpaper_panel.cpp',
  'src/shell/wallpaper/panel/wallpaper_scanner.cpp',
  'src/shell/wallpaper/panel/wallpaper_tile.cpp',
  'src/shell/widget/widget.cpp',
  'src/shell/widget/widget_factory.cpp',
  'src/shell/widgets/active_window_widget.cpp',
  'src/shell/widgets/battery_widget.cpp',
  'src/shell/widgets/clock_widget.cpp',
  'src/shell/widgets/idle_inhibitor_widget.cpp',
  'src/shell/widgets/launcher_widget.cpp',
  'src/shell/widgets/media_mini_widget.cpp',
  'src/shell/widgets/notification_widget.cpp',
  'src/shell/widgets/power_profiles_widget.cpp',
  'src/shell/widgets/session_widget.cpp',
  'src/shell/widgets/spacer_widget.cpp',
  'src/shell/widgets/sysmon_widget.cpp',
  'src/shell/widgets/test_widget.cpp',
  'src/shell/widgets/tray_widget.cpp',
  'src/shell/widgets/volume_widget.cpp',
  'src/shell/widgets/weather_widget.cpp',
  'src/shell/widgets/workspaces_widget.cpp',
  'src/system/desktop_entry.cpp',
  'src/system/distro_info.cpp',
  'src/system/icon_resolver.cpp',
  'src/system/night_light_manager.cpp',
  'src/system/system_monitor_service.cpp',
  'src/system/weather_service.cpp',
  'src/time/time_service.cpp',
  'src/ui/controls/audio_spectrum.cpp',
  'src/ui/controls/box.cpp',
  'src/ui/controls/button.cpp',
  'src/ui/controls/checkbox.cpp',
  'src/ui/controls/chip.cpp',
  'src/ui/controls/context_menu.cpp',
  'src/ui/controls/flex.cpp',
  'src/ui/controls/glyph.cpp',
  'src/ui/controls/glyph_registry.cpp',
  'src/ui/controls/grid_view.cpp',
  'src/ui/controls/grid_tile.cpp',
  'src/ui/controls/image.cpp',
  'src/ui/controls/input.cpp',
  'src/ui/controls/label.cpp',
  'src/ui/controls/progress_bar.cpp',
  'src/ui/controls/radio_button.cpp',
  'src/ui/controls/scroll_view.cpp',
  'src/ui/controls/select.cpp',
  'src/ui/controls/slider.cpp',
  'src/ui/controls/spinner.cpp',
  'src/ui/controls/toggle.cpp',
  'src/util/fuzzy_match.cpp',
  'src/wayland/clipboard_service.cpp',
  'src/compositors/ext_workspace_backend.cpp',
  'src/compositors/mango/mango_workspace_backend.cpp',
  'src/compositors/niri/niri_output_backend.cpp',
  'src/compositors/sway/sway_workspace_backend.cpp',
  'src/wayland/layer_surface.cpp',
  'src/wayland/popup_surface.cpp',
  'src/wayland/surface.cpp',
  'src/wayland/wayland_connection.cpp',
  'src/wayland/wayland_seat.cpp',
  'src/wayland/wayland_toplevels.cpp',
  'src/wayland/wayland_workspaces.cpp',
  'src/theme/scheme.cpp',
  'src/theme/color.cpp',
  'src/theme/contrast.cpp',
  'src/theme/image_loader.cpp',
  'src/theme/palette_generator.cpp',
  'src/theme/m3_schemes.cpp',
  'src/theme/custom_schemes.cpp',
  'src/theme/json_output.cpp',
  'src/theme/cli.cpp',
  'src/ipc/cli.cpp',
)

if sanitize
  _noctalia_sources += files('src/pipewire/pipewire_lsan.cpp')
endif

# ── Include directories ────────────────────────────────────────────────────────
_noctalia_inc = [
  include_directories('src'),
  include_directories('third_party/nanosvg'),
  include_directories('third_party/tomlplusplus'),
  include_directories('third_party/wuffs', is_system: true),
  # nlohmann is header-only and uses GCC extensions in some paths; treat as system.
  include_directories('third_party/nlohmann', is_system: true),
  # '.' adds both the source root and the corresponding build-dir root, so
  # generated protocol headers (written to the build root) are found by #include.
  include_directories('.'),
]

# ── Executable ────────────────────────────────────────────────────────────────
executable('noctalia',
  sources: _noctalia_sources + _protocol_sources,
  dependencies: [
    sdbus_cpp_dep,
    wayland_client_dep,
    egl_dep,
    glesv2_dep,
    wayland_egl_dep,
    freetype2_dep,
    fontconfig_dep,
    cairo_dep,
    cairo_ft_dep,
    pango_dep,
    pangocairo_dep,
    xkbcommon_dep,
    pipewire_dep,
    curl_dep,
    pam_dep,
    tinyexpr_dep,
    mcu_dep,
    stb_dep,
    libwebp_dep,
  ],
  include_directories: _noctalia_inc,
  cpp_args: [
    '-Wall', '-Wextra', '-Wpedantic', '-Wconversion', '-Wshadow',
    '-DNOCTALIA_ASSETS_DIR="' + meson.project_source_root() / 'assets' + '"',
    '-DNOCTALIA_I18N_DIR="' + meson.project_source_root() / 'assets' / 'translations' + '"',
    '-DNOCTALIA_VERSION="' + meson.project_version() + '"',
  ],
  install: false,
)
