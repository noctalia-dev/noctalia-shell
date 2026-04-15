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

  std::unique_ptr<Flex> create() override;
  void onClose() override;

private:
  void doLayout(Renderer& renderer, float contentWidth, float bodyHeight) override;
  void doUpdate(Renderer& renderer) override;
  void sync(Renderer& renderer);
  [[nodiscard]] static std::string weekdayLabel(const std::string& isoDate);

  static constexpr std::size_t kDayCount = 7;
  static constexpr std::size_t kDetailRowCount = 6;

  WeatherService* m_weather = nullptr;
  Flex* m_rootLayout = nullptr;
  Flex* m_leftColumn = nullptr;
  Flex* m_currentCard = nullptr;
  Flex* m_detailsCard = nullptr;
  Flex* m_currentText = nullptr;
  Flex* m_forecastColumn = nullptr;
  Label* m_statusLabel = nullptr;
  Glyph* m_currentGlyph = nullptr;
  Label* m_currentTempLabel = nullptr;
  Label* m_currentHiLoLabel = nullptr;
  Label* m_currentDescLabel = nullptr;
  Label* m_updatedLabel = nullptr;
  Label* m_windLabel = nullptr;
  Label* m_sunriseLabel = nullptr;
  Label* m_sunsetLabel = nullptr;
  Label* m_timezoneLabel = nullptr;
  Label* m_longitudeLabel = nullptr;
  Label* m_elevationLabel = nullptr;
  std::array<Flex*, kDetailRowCount> m_detailRows{};
  std::array<Flex*, kDayCount> m_dayCards{};
  std::array<Flex*, kDayCount> m_dayIconSlots{};
  std::array<Glyph*, kDayCount> m_dayGlyphs{};
  std::array<Label*, kDayCount> m_dayMetas{};
  std::array<Label*, kDayCount> m_dayDescs{};
  std::array<Label*, kDayCount> m_dayTemps{};
};
