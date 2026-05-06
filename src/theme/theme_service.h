#pragma once

#include "config/config_types.h"
#include "core/timer_manager.h"
#include "render/animation/animation_manager.h"
#include "theme/palette.h"
#include "ui/palette.h"

#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <string_view>

class ConfigService;
class HttpClient;
class IpcService;

namespace noctalia::theme {

  class ThemeService {
  public:
    using ChangeCallback = std::function<void()>;
    using ResolvedCallback = std::function<void(const GeneratedPalette&, std::string_view)>;

    ThemeService(ConfigService& config, HttpClient& httpClient);

    // Snaps the palette to the resolved theme (no fade). Used at startup.
    void apply();

    // Resolves the target theme and cross-fades to it.
    void onConfigReload();
    void onWallpaperChange();
    void onAutoSchemeChanged();
    void toggleLightDark();
    void cycleMode();
    [[nodiscard]] ThemeMode configuredMode() const noexcept;
    [[nodiscard]] bool isLightMode() const noexcept;

    void setChangeCallback(ChangeCallback callback);
    void setResolvedCallback(ResolvedCallback callback);

    void registerIpc(IpcService& ipc);

  private:
    void resolveAndSet(bool animate);
    void queueResolvedCallback(const GeneratedPalette& generated, std::string_view mode);
    void flushResolvedCallback(bool defer);
    void startTransition(const Palette& target);
    void finishTransition(bool deferResolvedCallback);
    void tickTransition();
    void startCommunityDownload(const std::string& name);

    ConfigService& m_config;
    HttpClient& m_httpClient;
    std::string m_inflightCommunityName;
    ChangeCallback m_changeCallback;
    ResolvedCallback m_resolvedCallback;
    // External template/hooks callbacks are delayed until the shell palette is
    // applied, and deferred callbacks must be able to drop stale resolves.
    std::optional<GeneratedPalette> m_pendingResolvedPalette;
    std::string m_pendingResolvedMode;
    std::uint64_t m_resolvedCallbackGeneration = 0;

    AnimationManager m_animations;
    Timer m_transitionTimer;
    Palette m_fromPalette{};
    Palette m_targetPalette{};
    AnimationManager::Id m_transitionAnimId = 0;
    bool m_transitionResolvedCallbackFlushed = false;
    bool m_isLightMode = false;
  };

} // namespace noctalia::theme
