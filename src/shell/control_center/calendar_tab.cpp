#include "shell/control_center/control_center_panel.h"

#include "render/core/renderer.h"
#include "shell/panel/panel_manager.h"
#include "shell/control_center/common.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"

#include <algorithm>
#include <array>
#include <ctime>
#include <memory>
#include <string>

using namespace control_center;

void ControlCenterPanel::buildCalendarTab() {
  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Vertical);
  tab->setAlign(FlexAlign::Center);
  tab->setGap(Style::spaceLg);
  tab->setPadding(Style::spaceSm);
  m_tabContainers[tabIndex(TabId::Calendar)] = tab.get();

  auto card = std::make_unique<Flex>();
  card->setDirection(FlexDirection::Vertical);
  card->setAlign(FlexAlign::Start);
  card->setGap(kCalendarGridGap);
  card->setPadding(kCalendarCardPadding);
  card->setMinWidth(kCalendarCardMinWidth);
  card->setMinHeight(kCalendarCardMinHeight);
  m_calendarCard = card.get();

  auto header = std::make_unique<Flex>();
  header->setDirection(FlexDirection::Horizontal);
  header->setAlign(FlexAlign::Center);
  header->setGap(Style::spaceSm);
  header->setMinWidth(kCalendarCardMinWidth - kCalendarCardPadding * 2.0f);
  header->setMinHeight(kCalendarHeaderHeight);

  auto previous = std::make_unique<Button>();
  previous->setGlyph("chevron-left");
  previous->setVariant(ButtonVariant::Ghost);
  previous->setMinimalChrome(true);
  previous->setMinWidth(kCalendarNavButtonSize);
  previous->setMinHeight(kCalendarNavButtonSize);
  previous->setOnClick([this]() {
    --m_calendarMonthOffset;
    PanelManager::instance().refresh();
  });
  header->addChild(std::move(previous));

  auto monthWrap = std::make_unique<Flex>();
  monthWrap->setDirection(FlexDirection::Vertical);
  monthWrap->setAlign(FlexAlign::Center);
  monthWrap->setMinWidth(kCalendarCardMinWidth - kCalendarCardPadding * 2.0f - kCalendarNavButtonSize * 2.0f -
                         Style::spaceSm * 2);

  auto month = std::make_unique<Label>();
  month->setBold(true);
  month->setFontSize(Style::fontSizeTitle + Style::spaceXs);
  month->setColor(palette.primary);
  m_calendarMonthLabel = month.get();
  monthWrap->addChild(std::move(month));
  header->addChild(std::move(monthWrap));

  auto next = std::make_unique<Button>();
  next->setGlyph("chevron-right");
  next->setVariant(ButtonVariant::Ghost);
  next->setMinimalChrome(true);
  next->setMinWidth(kCalendarNavButtonSize);
  next->setMinHeight(kCalendarNavButtonSize);
  next->setOnClick([this]() {
    ++m_calendarMonthOffset;
    PanelManager::instance().refresh();
  });
  header->addChild(std::move(next));

  card->addChild(std::move(header));

  auto grid = std::make_unique<Flex>();
  grid->setDirection(FlexDirection::Vertical);
  grid->setAlign(FlexAlign::Start);
  grid->setGap(kCalendarGridGap);
  m_calendarGrid = grid.get();
  card->addChild(std::move(grid));

  tab->addChild(std::move(card));

  m_tabBodies->addChild(std::move(tab));
}

void ControlCenterPanel::rebuildCalendar(Renderer& renderer) {
  if (m_calendarGrid == nullptr || m_calendarMonthLabel == nullptr || m_calendarCard == nullptr) {
    return;
  }

  auto* calendarTab = m_tabContainers[tabIndex(TabId::Calendar)];
  auto& cardChildren = m_calendarCard->children();
  auto* header = !cardChildren.empty() ? dynamic_cast<Flex*>(cardChildren.front().get()) : nullptr;
  Flex* monthWrap = nullptr;
  if (header != nullptr) {
    auto& headerChildren = header->children();
    if (headerChildren.size() >= 2) {
      monthWrap = dynamic_cast<Flex*>(headerChildren[1].get());
    }
  }

  const float availableWidth =
      calendarTab != nullptr ? std::max(0.0f, calendarTab->width() - Style::spaceSm * 2)
                             : kCalendarCardMinWidth;
  const float availableHeight =
      calendarTab != nullptr ? std::max(0.0f, calendarTab->height() - Style::spaceSm * 2)
                             : kCalendarCardMinHeight;
  const float gridWidthAvailable =
      std::max(0.0f, availableWidth - kCalendarCardPadding * 2.0f - kCalendarGridGap * 6.0f);
  const float gridHeightAvailable = std::max(
      0.0f, availableHeight - kCalendarCardPadding * 2.0f - kCalendarHeaderHeight - kCalendarWeekdayRowHeight -
                kCalendarGridGap * 7.0f);
  const float widthDrivenCellSize = gridWidthAvailable / 7.0f;
  const float heightDrivenCellSize = gridHeightAvailable / 6.0f;
  const float cellSize =
      std::clamp(std::min(widthDrivenCellSize, heightDrivenCellSize), kCalendarCellSizeMin, kCalendarCellSizeMax);
  const float weekdayWidth = cellSize;
  const float cardWidth = cellSize * 7.0f + kCalendarGridGap * 6.0f + kCalendarCardPadding * 2.0f;
  const float cardHeight = kCalendarHeaderHeight + kCalendarWeekdayRowHeight + cellSize * 6.0f +
                           kCalendarGridGap * 7.0f + kCalendarCardPadding * 2.0f;
  const float headerWidth = std::max(0.0f, cardWidth - kCalendarCardPadding * 2.0f);
  const float monthWrapWidth =
      std::max(0.0f, headerWidth - kCalendarNavButtonSize * 2.0f - Style::spaceSm * 2);

  m_calendarCard->setMinWidth(cardWidth);
  m_calendarCard->setMinHeight(cardHeight);
  if (header != nullptr) {
    header->setMinWidth(headerWidth);
    header->setMinHeight(kCalendarHeaderHeight);
  }
  if (monthWrap != nullptr) {
    monthWrap->setMinWidth(monthWrapWidth);
  }

  while (!m_calendarGrid->children().empty()) {
    m_calendarGrid->removeChild(m_calendarGrid->children().front().get());
  }

  std::time_t now = std::time(nullptr);
  std::tm local = *std::localtime(&now);
  const int currentYear = local.tm_year + 1900;
  const int currentMonth = local.tm_mon;
  const int today = local.tm_mday;

  std::tm display = local;
  display.tm_mday = 1;
  display.tm_mon += m_calendarMonthOffset;
  std::mktime(&display);
  const int year = display.tm_year + 1900;
  const int month = display.tm_mon;
  const bool isCurrentMonth = year == currentYear && month == currentMonth;

  m_calendarMonthLabel->setText(monthName(month) + " " + std::to_string(year));
  m_calendarMonthLabel->measure(renderer);

  static constexpr std::array<const char*, 7> kWeekdays = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
  auto weekdayRow = std::make_unique<Flex>();
  weekdayRow->setDirection(FlexDirection::Horizontal);
  weekdayRow->setAlign(FlexAlign::Center);
  weekdayRow->setGap(kCalendarGridGap);
  for (std::size_t i = 0; i < kWeekdays.size(); ++i) {
    auto dayLabel = std::make_unique<Button>();
    dayLabel->setText(kWeekdays[i]);
    dayLabel->setVariant(ButtonVariant::Tab);
    dayLabel->setMinimalChrome(true);
    dayLabel->setFontSize(Style::fontSizeCaption + 1.0f);
    dayLabel->setMinWidth(weekdayWidth);
    dayLabel->setMinHeight(kCalendarWeekdayRowHeight);
    dayLabel->label()->setColor(i >= 5 ? palette.primary : palette.onSurfaceVariant);
    weekdayRow->addChild(std::move(dayLabel));
  }
  m_calendarGrid->addChild(std::move(weekdayRow));

  const int firstWeekdayMonBased = (display.tm_wday == 0) ? 6 : (display.tm_wday - 1);
  const int previousMonth = month == 0 ? 11 : month - 1;
  const int previousMonthYear = month == 0 ? year - 1 : year;
  const int previousMonthDays = [](int yearValue, int monthValue) {
    static constexpr std::array<int, 12> kDays = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    int result = kDays[static_cast<std::size_t>(monthValue)];
    if (monthValue == 1) {
      const bool leap = ((yearValue % 4 == 0 && yearValue % 100 != 0) || (yearValue % 400 == 0));
      result = leap ? 29 : 28;
    }
    return result;
  }(previousMonthYear, previousMonth);

  const int monthDays = [](int yearValue, int monthValue) {
    static constexpr std::array<int, 12> kDays = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    int result = kDays[static_cast<std::size_t>(monthValue)];
    if (monthValue == 1) {
      const bool leap = ((yearValue % 4 == 0 && yearValue % 100 != 0) || (yearValue % 400 == 0));
      result = leap ? 29 : 28;
    }
    return result;
  }(year, month);

  int day = 1;
  int trailingDay = 1;
  for (int week = 0; week < 6; ++week) {
    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Horizontal);
    row->setAlign(FlexAlign::Center);
    row->setGap(kCalendarGridGap);

    for (int wd = 0; wd < 7; ++wd) {
      auto cell = std::make_unique<Button>();
      cell->setVariant(ButtonVariant::Default);
      cell->setMinimalChrome(false);
      cell->setMinWidth(cellSize);
      cell->setMinHeight(cellSize);
      cell->setRadius(Style::radiusLg);
      cell->setFontSize(cellSize > Style::controlHeightLg + Style::spaceXs ? Style::fontSizeTitle
                                                                                                : Style::fontSizeBody);
      cell->setText("");

      const int index = week * 7 + wd;
      if (index < firstWeekdayMonBased) {
        const int leadingDay = previousMonthDays - firstWeekdayMonBased + index + 1;
        cell->setText(std::to_string(leadingDay));
        cell->label()->setColor(palette.onSurfaceVariant);
      } else if (day > monthDays) {
        cell->setText(std::to_string(trailingDay));
        cell->label()->setColor(palette.onSurfaceVariant);
        ++trailingDay;
      } else {
        cell->setText(std::to_string(day));
        if (isCurrentMonth && day == today) {
          cell->setVariant(ButtonVariant::Accent);
        } else {
          cell->label()->setColor(palette.onSurface);
        }
        ++day;
      }

      row->addChild(std::move(cell));
    }
    m_calendarGrid->addChild(std::move(row));
    if (day > monthDays) {
      break;
    }
  }
}
