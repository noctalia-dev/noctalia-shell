#include "shell/desktop/desktop_widget_factory.h"

#include "core/log.h"
#include "pipewire/pipewire_spectrum.h"
#include "shell/desktop/widgets/desktop_audio_visualizer_widget.h"
#include "shell/desktop/widgets/desktop_clock_widget.h"
#include "shell/desktop/widgets/desktop_media_player_widget.h"
#include "shell/desktop/widgets/desktop_sticker_widget.h"
#include "shell/desktop/widgets/desktop_weather_widget.h"

namespace {

  constexpr Logger kLog("desktop");
  constexpr float kDefaultDesktopAudioVisualizerAspectRatio = 240.0f / 96.0f;

  std::string getStringSetting(const std::unordered_map<std::string, WidgetSettingValue>& settings,
                               const std::string& key, const std::string& fallback = {}) {
    const auto it = settings.find(key);
    if (it == settings.end()) {
      return fallback;
    }
    if (const auto* value = std::get_if<std::string>(&it->second)) {
      return *value;
    }
    return fallback;
  }

  float getFloatSetting(const std::unordered_map<std::string, WidgetSettingValue>& settings, const std::string& key,
                        float fallback) {
    const auto it = settings.find(key);
    if (it == settings.end()) {
      return fallback;
    }
    if (const auto* value = std::get_if<double>(&it->second)) {
      return static_cast<float>(*value);
    }
    if (const auto* value = std::get_if<std::int64_t>(&it->second)) {
      return static_cast<float>(*value);
    }
    return fallback;
  }

  int getIntSetting(const std::unordered_map<std::string, WidgetSettingValue>& settings, const std::string& key,
                    int fallback) {
    const auto it = settings.find(key);
    if (it == settings.end()) {
      return fallback;
    }
    if (const auto* value = std::get_if<std::int64_t>(&it->second)) {
      return static_cast<int>(*value);
    }
    if (const auto* value = std::get_if<double>(&it->second)) {
      return static_cast<int>(*value);
    }
    return fallback;
  }

  bool getBoolSetting(const std::unordered_map<std::string, WidgetSettingValue>& settings, const std::string& key,
                      bool fallback) {
    const auto it = settings.find(key);
    if (it == settings.end()) {
      return fallback;
    }
    if (const auto* value = std::get_if<bool>(&it->second)) {
      return *value;
    }
    return fallback;
  }

  ThemeColor getThemeColorSetting(const std::unordered_map<std::string, WidgetSettingValue>& settings,
                                  const std::string& key, const ThemeColor& fallback) {
    const auto it = settings.find(key);
    if (it == settings.end()) {
      return fallback;
    }
    if (const auto* value = std::get_if<std::string>(&it->second)) {
      return themeColorFromConfigString(*value);
    }
    return fallback;
  }

  constexpr float kDefaultBgRadius = 12.0f;
  constexpr float kDefaultBgPadding = 10.0f;

  void applyCommonSettings(DesktopWidget& widget, const std::unordered_map<std::string, WidgetSettingValue>& settings) {
    if (getBoolSetting(settings, "background", false)) {
      const ThemeColor bgColor =
          getThemeColorSetting(settings, "background_color", roleColor(ColorRole::Surface, 0.8f));
      const float radius = getFloatSetting(settings, "background_radius", kDefaultBgRadius);
      const float padding = getFloatSetting(settings, "background_padding", kDefaultBgPadding);
      widget.setBackgroundStyle(bgColor, radius, padding);
    }
  }

} // namespace

DesktopWidgetFactory::DesktopWidgetFactory(TimeService* timeService, PipeWireSpectrum* pipewireSpectrum,
                                           const WeatherService* weather, MprisService* mpris, HttpClient* httpClient)
    : m_timeService(timeService), m_pipewireSpectrum(pipewireSpectrum), m_weather(weather), m_mpris(mpris),
      m_httpClient(httpClient) {}

std::unique_ptr<DesktopWidget>
DesktopWidgetFactory::create(const std::string& type,
                             const std::unordered_map<std::string, WidgetSettingValue>& settings,
                             float contentScale) const {
  if (type == "clock") {
    if (m_timeService == nullptr) {
      kLog.warn("desktop widget factory: clock requires TimeService");
      return nullptr;
    }
    auto widget =
        std::make_unique<DesktopClockWidget>(*m_timeService, getStringSetting(settings, "format", "{:%H:%M}"),
                                             getThemeColorSetting(settings, "color", roleColor(ColorRole::OnSurface)),
                                             getBoolSetting(settings, "shadow", true));
    applyCommonSettings(*widget, settings);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "audio_visualizer") {
    if (m_pipewireSpectrum == nullptr) {
      kLog.warn("desktop widget factory: audio_visualizer requires PipeWireSpectrum");
      return nullptr;
    }
    auto widget = std::make_unique<DesktopAudioVisualizerWidget>(
        m_pipewireSpectrum, getFloatSetting(settings, "aspect_ratio", kDefaultDesktopAudioVisualizerAspectRatio),
        getIntSetting(settings, "bands", 32), getBoolSetting(settings, "mirrored", true),
        getThemeColorSetting(settings, "low_color", roleColor(ColorRole::Primary)),
        getThemeColorSetting(settings, "high_color", roleColor(ColorRole::Primary)),
        std::clamp(getFloatSetting(settings, "min_value", 0.0f), 0.0f, 1.0f));
    applyCommonSettings(*widget, settings);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "sticker") {
    auto widget = std::make_unique<DesktopStickerWidget>(getStringSetting(settings, "image_path"));
    applyCommonSettings(*widget, settings);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "weather") {
    if (m_weather == nullptr) {
      kLog.warn("desktop widget factory: weather requires WeatherService");
      return nullptr;
    }
    auto widget = std::make_unique<DesktopWeatherWidget>(
        m_weather, getThemeColorSetting(settings, "color", roleColor(ColorRole::OnSurface)),
        getBoolSetting(settings, "shadow", true));
    applyCommonSettings(*widget, settings);
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "media_player") {
    if (m_mpris == nullptr) {
      kLog.warn("desktop widget factory: media_player requires MprisService");
      return nullptr;
    }
    const bool vertical = getStringSetting(settings, "layout", "horizontal") == "vertical";
    auto widget = std::make_unique<DesktopMediaPlayerWidget>(
        m_mpris, m_httpClient, vertical, getThemeColorSetting(settings, "color", roleColor(ColorRole::OnSurface)),
        getBoolSetting(settings, "shadow", true));
    applyCommonSettings(*widget, settings);
    widget->setContentScale(contentScale);
    return widget;
  }

  kLog.warn("desktop widget factory: unknown widget type \"{}\"", type);
  return nullptr;
}
