#include "shell/desktop/desktop_widget_factory.h"

#include "core/log.h"
#include "pipewire/pipewire_spectrum.h"
#include "shell/desktop/widgets/desktop_audio_visualizer_widget.h"
#include "shell/desktop/widgets/desktop_clock_widget.h"
#include "shell/desktop/widgets/desktop_sticker_widget.h"

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

} // namespace

DesktopWidgetFactory::DesktopWidgetFactory(TimeService* timeService, PipeWireSpectrum* pipewireSpectrum)
    : m_timeService(timeService), m_pipewireSpectrum(pipewireSpectrum) {}

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
        std::make_unique<DesktopClockWidget>(*m_timeService, getStringSetting(settings, "format", "{:%H:%M}"));
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
        getIntSetting(settings, "bands", 32), getBoolSetting(settings, "mirrored", false),
        getThemeColorSetting(settings, "low_color", roleColor(ColorRole::Primary)),
        getThemeColorSetting(settings, "high_color", roleColor(ColorRole::Primary)));
    widget->setContentScale(contentScale);
    return widget;
  }

  if (type == "sticker") {
    auto widget = std::make_unique<DesktopStickerWidget>(getStringSetting(settings, "image_path"));
    widget->setContentScale(contentScale);
    return widget;
  }

  kLog.warn("desktop widget factory: unknown widget type \"{}\"", type);
  return nullptr;
}
