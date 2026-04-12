#pragma once

#include "core/timer_manager.h"
#include "render/animation/animation_manager.h"
#include "theme/palette.h"
#include "ui/palette.h"

#include <functional>
#include <string_view>

class ConfigService;
class StateService;

namespace noctalia::theme {

  class ThemeService {
  public:
    using ChangeCallback = std::function<void()>;
    using ResolvedCallback = std::function<void(const GeneratedPalette&, std::string_view)>;

    ThemeService(const ConfigService& config, const StateService& state);

    // Snaps the palette to the resolved theme (no fade). Used at startup.
    void apply();

    // Resolves the target theme and cross-fades to it.
    void onConfigReload();
    void onWallpaperChange();

    void setChangeCallback(ChangeCallback callback);
    void setResolvedCallback(ResolvedCallback callback);

  private:
    void resolveAndSet(bool animate);
    void startTransition(const Palette& target);
    void tickTransition();

    const ConfigService& m_config;
    const StateService& m_state;
    ChangeCallback m_changeCallback;
    ResolvedCallback m_resolvedCallback;

    AnimationManager m_animations;
    Timer m_transitionTimer;
    Palette m_fromPalette{};
    Palette m_targetPalette{};
    AnimationManager::Id m_transitionAnimId = 0;
  };

} // namespace noctalia::theme
