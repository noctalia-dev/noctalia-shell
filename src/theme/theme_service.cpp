#include "theme/theme_service.h"

#include "config/config_service.h"
#include "config/state_service.h"
#include "core/log.h"
#include "render/core/color.h"
#include "theme/builtin_schemes.h"
#include "theme/image_loader.h"
#include "theme/palette_generator.h"
#include "theme/scheme.h"
#include "ui/palette.h"

#include <cstdint>
#include <string>
#include <unordered_map>

namespace noctalia::theme {

  namespace {

    constexpr auto kLog = Logger("theme");

    Color tokenToColor(const std::unordered_map<std::string, uint32_t>& tokens, std::string_view key) {
      auto it = tokens.find(std::string(key));
      if (it == tokens.end()) {
        return hex("#ff00ff");
      }
      return rgbHex(it->second & 0x00FFFFFFU);
    }

    Palette mapWallpaperTokens(const std::unordered_map<std::string, uint32_t>& t) {
      // Mapping mirrors noctalia-shell/Assets/Templates/noctalia.json.
      return Palette{
          .primary = tokenToColor(t, "primary"),
          .onPrimary = tokenToColor(t, "on_primary"),
          .secondary = tokenToColor(t, "secondary"),
          .onSecondary = tokenToColor(t, "on_secondary"),
          .tertiary = tokenToColor(t, "tertiary"),
          .onTertiary = tokenToColor(t, "on_tertiary"),
          .error = tokenToColor(t, "error"),
          .onError = tokenToColor(t, "on_error"),
          .surface = tokenToColor(t, "surface"),
          .onSurface = tokenToColor(t, "on_surface"),
          .surfaceVariant = tokenToColor(t, "surface_container"),
          .onSurfaceVariant = tokenToColor(t, "on_surface_variant"),
          .outline = tokenToColor(t, "outline_variant"),
          .shadow = tokenToColor(t, "shadow"),
          .hover = tokenToColor(t, "tertiary"),
          .onHover = tokenToColor(t, "on_tertiary"),
      };
    }

    Palette resolveBuiltin(const ThemeConfig& cfg) {
      const auto* scheme = findBuiltinScheme(cfg.builtinName);
      if (scheme == nullptr) {
        kLog.warn("unknown builtin scheme '{}', falling back to Noctalia", cfg.builtinName);
        scheme = findBuiltinScheme("Noctalia");
      }
      const bool useLight = cfg.mode == ThemeMode::Light;
      return useLight ? scheme->light : scheme->dark;
    }

    std::optional<Palette> resolveWallpaper(const ThemeConfig& cfg, const std::string& wallpaperPath) {
      if (wallpaperPath.empty()) {
        kLog.warn("wallpaper theme requested but no wallpaper path set");
        return std::nullopt;
      }
      auto scheme = schemeFromString(cfg.wallpaperScheme);
      if (!scheme.has_value()) {
        kLog.warn("unknown wallpaper scheme '{}', falling back to m3-content", cfg.wallpaperScheme);
        scheme = Scheme::Content;
      }
      std::string err;
      auto image = loadAndResize(wallpaperPath, *scheme, &err);
      if (!image.has_value()) {
        kLog.warn("failed to load wallpaper '{}': {}", wallpaperPath, err);
        return std::nullopt;
      }
      auto generated = generate(image->rgb, *scheme, &err);
      if (generated.dark.empty()) {
        kLog.warn("failed to generate palette from wallpaper: {}", err);
        return std::nullopt;
      }
      const bool useLight = cfg.mode == ThemeMode::Light;
      return mapWallpaperTokens(useLight ? generated.light : generated.dark);
    }

  } // namespace

  ThemeService::ThemeService(const ConfigService& config, const StateService& state)
      : m_config(config), m_state(state) {}

  void ThemeService::apply() { resolveAndSet(); }

  void ThemeService::onConfigReload() { resolveAndSet(); }

  void ThemeService::onWallpaperChange() {
    if (m_config.config().theme.source == ThemeSource::Wallpaper) {
      resolveAndSet();
    }
  }

  void ThemeService::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

  void ThemeService::resolveAndSet() {
    const auto& cfg = m_config.config().theme;
    std::optional<Palette> resolved;

    if (cfg.source == ThemeSource::Wallpaper) {
      resolved = resolveWallpaper(cfg, m_state.getDefaultWallpaperPath());
    }
    if (!resolved.has_value()) {
      resolved = resolveBuiltin(cfg);
    }

    setPalette(*resolved);
    if (m_changeCallback) {
      m_changeCallback();
    }
  }

} // namespace noctalia::theme
