#include "theme/theme_service.h"

#include "config/config_service.h"
#include "config/state_service.h"
#include "core/log.h"
#include "render/animation/animation.h"
#include "theme/builtin_palettes.h"
#include "theme/fixed_palette.h"
#include "theme/image_loader.h"
#include "theme/palette_generator.h"
#include "theme/scheme.h"

#include <algorithm>
#include <chrono>
#include <string>

namespace noctalia::theme {

  namespace {

    constexpr auto kLog = Logger("theme");

    constexpr float kTransitionDurationMs = 400.0f;
    constexpr std::chrono::milliseconds kTransitionTick{16};

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

    std::optional<ResolvedTheme> resolveForConfig(const ThemeConfig& cfg, const StateService& state) {
      std::optional<ResolvedTheme> resolved;
      if (cfg.source == ThemeSource::Wallpaper) {
        resolved = resolveWallpaper(cfg, state.getDefaultWallpaperPath());
      }
      if (!resolved.has_value()) {
        resolved = resolveBuiltin(cfg);
      }
      return resolved;
    }

  } // namespace

  ThemeService::ThemeService(const ConfigService& config, const StateService& state)
      : m_config(config), m_state(state) {}

  void ThemeService::apply() { resolveAndSet(/*animate=*/false); }

  void ThemeService::onConfigReload() { resolveAndSet(/*animate=*/true); }

  void ThemeService::onWallpaperChange() {
    if (m_config.config().theme.source == ThemeSource::Wallpaper) {
      resolveAndSet(/*animate=*/true);
    }
  }

  void ThemeService::toggleLightDark() {
    ThemeConfig cfg = m_config.config().theme;
    cfg.mode = m_isLightMode ? ThemeMode::Dark : ThemeMode::Light;

    auto resolved = resolveForConfig(cfg, m_state);
    if (!resolved.has_value()) {
      return;
    }

    m_isLightMode = resolved->mode == "light";

    if (m_resolvedCallback) {
      m_resolvedCallback(resolved->generated, resolved->mode);
    }

    startTransition(resolved->palette);
  }

  bool ThemeService::isLightMode() const noexcept { return m_isLightMode; }

  void ThemeService::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

  void ThemeService::setResolvedCallback(ResolvedCallback callback) { m_resolvedCallback = std::move(callback); }

  void ThemeService::resolveAndSet(bool animate) {
    const auto& cfg = m_config.config().theme;
    auto resolved = resolveForConfig(cfg, m_state);

    if (m_resolvedCallback) {
      m_resolvedCallback(resolved->generated, resolved->mode);
    }

    m_isLightMode = resolved->mode == "light";

    if (animate) {
      startTransition(resolved->palette);
    } else {
      m_transitionActive = false;
      m_transitionTimer.stop();
      setPalette(resolved->palette);
      if (m_changeCallback) {
        m_changeCallback();
      }
    }
  }

  void ThemeService::startTransition(const Palette& target) {
    // Capture the currently-displayed palette (possibly mid-fade) so a new
    // transition starts from wherever the previous one had reached.
    m_fromPalette = palette;
    m_targetPalette = target;
    m_transitionStart = std::chrono::steady_clock::now();
    m_transitionActive = true;
    m_transitionTimer.startRepeating(kTransitionTick, [this] { tickTransition(); });
  }

  void ThemeService::tickTransition() {
    if (!m_transitionActive) {
      m_transitionTimer.stop();
      return;
    }
    const auto now = std::chrono::steady_clock::now();
    const auto elapsedMs = std::chrono::duration<float, std::milli>(now - m_transitionStart).count();
    const float rawT = std::clamp(elapsedMs / kTransitionDurationMs, 0.0f, 1.0f);
    const float easedT = applyEasing(Easing::EaseOutCubic, rawT);

    setPalette(lerpPalette(m_fromPalette, m_targetPalette, easedT));
    if (m_changeCallback) {
      m_changeCallback();
    }

    if (rawT >= 1.0f) {
      setPalette(m_targetPalette);
      if (m_changeCallback) {
        m_changeCallback();
      }
      m_transitionActive = false;
      m_transitionTimer.stop();
    }
  }

} // namespace noctalia::theme
