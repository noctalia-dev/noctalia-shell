#pragma once

#include "core/timer_manager.h"
#include "render/animation/animation_manager.h"
#include "theme/palette.h"
#include "ui/palette.h"

#include <functional>
#include <string_view>

class ConfigService;

namespace noctalia::theme {

  class ThemeService {
  public:
    using ChangeCallback = std::function<void()>;
    using ResolvedCallback = std::function<void(const GeneratedPalette&, std::string_view)>;

    explicit ThemeService(ConfigService& config);

    // Snaps the palette to the resolved theme (no fade). Used at startup.
    void apply();

    // Resolves the target theme and cross-fades to it.
    void onConfigReload();
    void onWallpaperChange();
    void toggleLightDark();
    [[nodiscard]] bool isLightMode() const noexcept;

    void setChangeCallback(ChangeCallback callback);
    void setResolvedCallback(ResolvedCallback callback);

  private:
    void resolveAndSet(bool animate);
    void startTransition(const Palette& target);
    void tickTransition();

    ConfigService& m_config;
    ChangeCallback m_changeCallback;
    ResolvedCallback m_resolvedCallback;

    AnimationManager m_animations;
    Timer m_transitionTimer;
    Palette m_fromPalette{};
    Palette m_targetPalette{};
    AnimationManager::Id m_transitionAnimId = 0;
    bool m_isLightMode = false;
  };

} // namespace noctalia::theme
