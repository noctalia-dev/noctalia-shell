#pragma once

#include <functional>

class ConfigService;
class StateService;

namespace noctalia::theme {

  class ThemeService {
  public:
    using ChangeCallback = std::function<void()>;

    ThemeService(const ConfigService& config, const StateService& state);

    void apply();

    void onConfigReload();
    void onWallpaperChange();

    void setChangeCallback(ChangeCallback callback);

  private:
    void resolveAndSet();

    const ConfigService& m_config;
    const StateService& m_state;
    ChangeCallback m_changeCallback;
  };

} // namespace noctalia::theme
