#include "theme/theme_service.h"

#include "config/config_service.h"
#include "core/log.h"
#include "theme/builtin_palettes.h"
#include "theme/fixed_palette.h"
#include "theme/image_loader.h"
#include "theme/palette_generator.h"
#include "theme/scheme.h"

#include <chrono>
#include <string>

namespace noctalia::theme {

  namespace {

    constexpr auto kLog = Logger("theme");

    constexpr float kTransitionDurationMs = 400.0f;
    constexpr std::chrono::milliseconds kTransitionTick{8};

    struct ResolvedTheme {
      GeneratedPalette generated;
      Palette palette;
      std::string mode;
    };

    std::string resolvedModeName(const ThemeConfig& cfg) { return cfg.mode == ThemeMode::Light ? "light" : "dark"; }

    ResolvedTheme resolveBuiltin(const ThemeConfig& cfg) {
      const auto* palette = findBuiltinPalette(cfg.builtinPalette);
      if (palette == nullptr) {
        kLog.warn("unknown builtin palette '{}', falling back to Noctalia", cfg.builtinPalette);
        palette = findBuiltinPalette("Noctalia");
      }
      const std::string mode = resolvedModeName(cfg);
      const GeneratedPalette generated = expandBuiltinPalette(*palette);
      return {
          .generated = generated,
          .palette = mapGeneratedPaletteMode(mode == "light" ? generated.light : generated.dark),
          .mode = mode,
      };
    }

    std::optional<ResolvedTheme> resolveWallpaper(const ThemeConfig& cfg, const std::string& wallpaperPath) {
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
      const std::string mode = resolvedModeName(cfg);
      return ResolvedTheme{
          .generated = generated,
          .palette = mapGeneratedPaletteMode(mode == "light" ? generated.light : generated.dark),
          .mode = mode,
      };
    }

    std::optional<ResolvedTheme> resolveForConfig(const ThemeConfig& cfg, const ConfigService& config) {
      std::optional<ResolvedTheme> resolved;
      if (cfg.source == ThemeSource::Wallpaper) {
        resolved = resolveWallpaper(cfg, config.getDefaultWallpaperPath());
      }
      if (!resolved.has_value()) {
        resolved = resolveBuiltin(cfg);
      }
      return resolved;
    }

  } // namespace

  ThemeService::ThemeService(ConfigService& config) : m_config(config) {}

  void ThemeService::apply() { resolveAndSet(/*animate=*/false); }

  void ThemeService::onConfigReload() { resolveAndSet(/*animate=*/true); }

  void ThemeService::onWallpaperChange() {
    if (m_config.config().theme.source == ThemeSource::Wallpaper) {
      resolveAndSet(/*animate=*/true);
    }
  }

  void ThemeService::toggleLightDark() {
    const auto next = m_isLightMode ? ThemeMode::Dark : ThemeMode::Light;
    // Persist via ConfigService → StateService. The resulting overrides-change
    // callback rebuilds the Config and fires the reload callbacks, which call
    // ThemeService::onConfigReload() to transition to the new palette.
    m_config.setThemeMode(next);
  }

  bool ThemeService::isLightMode() const noexcept { return m_isLightMode; }

  void ThemeService::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

  void ThemeService::setResolvedCallback(ResolvedCallback callback) { m_resolvedCallback = std::move(callback); }

  void ThemeService::resolveAndSet(bool animate) {
    const auto& cfg = m_config.config().theme;
    auto resolved = resolveForConfig(cfg, m_config);

    if (m_resolvedCallback) {
      m_resolvedCallback(resolved->generated, resolved->mode);
    }

    m_isLightMode = resolved->mode == "light";

    if (animate) {
      startTransition(resolved->palette);
    } else {
      if (m_transitionAnimId == 0 && palette == resolved->palette) {
        return;
      }
      if (m_transitionAnimId != 0) {
        m_animations.cancel(m_transitionAnimId);
        m_transitionAnimId = 0;
      }
      m_transitionTimer.stop();
      setPalette(resolved->palette);
      if (m_changeCallback) {
        m_changeCallback();
      }
    }
  }

  void ThemeService::startTransition(const Palette& target) {
    if (m_transitionAnimId == 0 && palette == target) {
      return;
    }
    if (m_transitionAnimId != 0 && m_targetPalette == target) {
      return;
    }
    // Capture the currently-displayed palette (possibly mid-fade) so a new
    // transition starts from wherever the previous one had reached.
    if (m_transitionAnimId != 0) {
      m_animations.cancel(m_transitionAnimId);
      m_transitionAnimId = 0;
    }
    m_fromPalette = palette;
    m_targetPalette = target;
    m_transitionAnimId = m_animations.animate(
        0.0f, 1.0f, kTransitionDurationMs, Easing::EaseOutCubic,
        [this](float t) {
          setPalette(lerpPalette(m_fromPalette, m_targetPalette, t));
          if (m_changeCallback) {
            m_changeCallback();
          }
        },
        [this]() {
          m_transitionAnimId = 0;
          m_transitionTimer.stop();
          setPalette(m_targetPalette);
          if (m_changeCallback) {
            m_changeCallback();
          }
        });
    if (m_transitionAnimId == 0) {
      m_transitionTimer.stop();
      return;
    }
    m_transitionTimer.startRepeating(kTransitionTick, [this] { tickTransition(); });
  }

  void ThemeService::tickTransition() {
    if (!m_animations.hasActive()) {
      m_transitionTimer.stop();
      return;
    }
    m_animations.tick(static_cast<float>(kTransitionTick.count()));
  }

} // namespace noctalia::theme
