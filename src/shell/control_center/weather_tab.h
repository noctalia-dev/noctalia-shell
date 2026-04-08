#pragma once

#include "shell/control_center/tab.h"

#include <array>

class Flex;
class Glyph;
class Label;
class WeatherService;

class WeatherTab : public Tab {
public:
  explicit WeatherTab(WeatherService* weather);

  std::unique_ptr<Flex> build(Renderer& renderer) override;
  void layout(Renderer& renderer, float contentWidth, float bodyHeight) override;
  void update(Renderer& renderer) override;
  void onClose() override;

private:
  void sync(Renderer& renderer);
  [[nodiscard]] static std::string weekdayLabel(const std::string& isoDate);

  static constexpr std::size_t kDayCount = 6;

  WeatherService* m_weather = nullptr;
  Flex* m_rootLayout = nullptr;
  Flex* m_currentText = nullptr;
  Flex* m_forecastRow = nullptr;
  Label* m_statusLabel = nullptr;
  Glyph* m_currentGlyph = nullptr;
  Label* m_locationLabel = nullptr;
  Label* m_currentTempLabel = nullptr;
  Label* m_currentDescLabel = nullptr;
  Label* m_updatedLabel = nullptr;
  std::array<Flex*, kDayCount> m_dayCards{};
  std::array<Glyph*, kDayCount> m_dayGlyphs{};
  std::array<Label*, kDayCount> m_dayNames{};
  std::array<Label*, kDayCount> m_dayDescs{};
  std::array<Label*, kDayCount> m_dayTemps{};
};
