#include "shell/control_center/calendar_tab.h"

#include "render/core/renderer.h"
#include "shell/control_center/tab.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <ctime>
#include <memory>
#include <string>

namespace {

constexpr float kCalendarGridGap = Style::spaceSm;
constexpr float kCalendarNavButtonSize = Style::controlHeight;
constexpr float kCalendarWeekdayRowHeight = Style::controlHeight;
constexpr float kCalendarHeaderHeight = Style::controlHeightLg;
constexpr float kCalendarCellSizeMin = Style::controlHeightSm + Style::spaceXs;
constexpr float kCalendarCellSizeMax = Style::controlHeightLg + Style::spaceLg;

std::string monthName(int month) {
  static constexpr std::array<const char*, 12> kMonths = {"January",   "February", "March",    "April",
                                                           "May",       "June",     "July",     "August",
                                                           "September", "October",  "November", "December"};
  if (month < 0 || month >= static_cast<int>(kMonths.size())) {
    return "Calendar";
  }
  return kMonths[static_cast<std::size_t>(month)];
}

int daysInMonth(int yearValue, int monthValue) {
  static constexpr std::array<int, 12> kDays = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
  int result = kDays[static_cast<std::size_t>(monthValue)];
  if (monthValue == 1) {
    const bool leap = ((yearValue % 4 == 0 && yearValue % 100 != 0) || (yearValue % 400 == 0));
    result = leap ? 29 : 28;
  }
  return result;
}

} // namespace

std::unique_ptr<Flex> CalendarTab::build(Renderer& /*renderer*/) {
  const float scale = contentScale();

  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Horizontal);
  tab->setAlign(FlexAlign::Stretch);
  tab->setGap(Style::spaceMd * scale);
  m_rootLayout = tab.get();

  auto calendarCard = std::make_unique<Flex>();
  control_center::applyCard(*calendarCard, scale);
  calendarCard->setAlign(FlexAlign::Stretch);
  calendarCard->setGap(kCalendarGridGap * scale);
  calendarCard->setFlexGrow(3.0f);
  m_card = calendarCard.get();

  auto header = std::make_unique<Flex>();
  header->setDirection(FlexDirection::Horizontal);
  header->setAlign(FlexAlign::Center);
  header->setGap(Style::spaceSm * scale);
  header->setMinHeight(kCalendarHeaderHeight * scale);
  m_header = header.get();

  auto previous = std::make_unique<Button>();
  previous->setGlyph("chevron-left");
  previous->setVariant(ButtonVariant::Ghost);
  previous->setMinWidth(kCalendarNavButtonSize * scale);
  previous->setMinHeight(kCalendarNavButtonSize * scale);
  previous->setOnClick([this]() {
    --m_monthOffset;
    PanelManager::instance().refresh();
  });
  header->addChild(std::move(previous));

  auto monthWrap = std::make_unique<Flex>();
  monthWrap->setDirection(FlexDirection::Vertical);
  monthWrap->setAlign(FlexAlign::Center);
  monthWrap->setJustify(FlexJustify::Center);
  monthWrap->setFlexGrow(1.0f);
  m_monthWrap = monthWrap.get();

  auto month = std::make_unique<Label>();
  month->setBold(true);
  month->setFontSize((Style::fontSizeTitle + Style::spaceXs) * scale);
  month->setColor(palette.primary);
  m_monthLabel = month.get();
  monthWrap->addChild(std::move(month));
  header->addChild(std::move(monthWrap));

  auto next = std::make_unique<Button>();
  next->setGlyph("chevron-right");
  next->setVariant(ButtonVariant::Ghost);
  next->setMinWidth(kCalendarNavButtonSize * scale);
  next->setMinHeight(kCalendarNavButtonSize * scale);
  next->setOnClick([this]() {
    ++m_monthOffset;
    PanelManager::instance().refresh();
  });
  header->addChild(std::move(next));

  calendarCard->addChild(std::move(header));

  auto grid = std::make_unique<Flex>();
  grid->setDirection(FlexDirection::Vertical);
  grid->setAlign(FlexAlign::Stretch);
  grid->setGap(kCalendarGridGap * scale);
  grid->setFlexGrow(1.0f);
  m_grid = grid.get();
  calendarCard->addChild(std::move(grid));

  auto eventsCard = std::make_unique<Flex>();
  control_center::applyCard(*eventsCard, scale);
  eventsCard->setAlign(FlexAlign::Center);
  eventsCard->setJustify(FlexJustify::Center);
  eventsCard->setFlexGrow(2.0f);

  auto eventsLabel = std::make_unique<Label>();
  eventsLabel->setText("events");
  eventsLabel->setBold(true);
  eventsLabel->setFontSize(Style::fontSizeTitle * scale);
  eventsLabel->setColor(palette.onSurfaceVariant);
  eventsCard->addChild(std::move(eventsLabel));

  tab->addChild(std::move(calendarCard));
  tab->addChild(std::move(eventsCard));

  rebuild();
  return tab;
}

void CalendarTab::layout(Renderer& renderer, float contentWidth, float bodyHeight) {
  if (m_rootLayout == nullptr) {
    return;
  }

  m_rootLayout->setSize(contentWidth, bodyHeight);
  m_rootLayout->layout(renderer);
  rebuild();
  m_rootLayout->layout(renderer);
}

void CalendarTab::onClose() {
  m_rootLayout = nullptr;
  m_card = nullptr;
  m_header = nullptr;
  m_monthWrap = nullptr;
  m_monthLabel = nullptr;
  m_grid = nullptr;
}

void CalendarTab::rebuild() {
  if (m_grid == nullptr || m_monthLabel == nullptr || m_card == nullptr) {
    return;
  }

  while (!m_grid->children().empty()) {
    m_grid->removeChild(m_grid->children().front().get());
  }

  const float scale = contentScale();
  const float innerWidth = std::max(0.0f, m_card->width() - (m_card->paddingLeft() + m_card->paddingRight()));
  const float innerHeight = std::max(0.0f, m_card->height() - (m_card->paddingTop() + m_card->paddingBottom()));
  const float navWidth = kCalendarNavButtonSize * scale * 2.0f + Style::spaceSm * scale * 2.0f;
  const float monthWidth = std::max(0.0f, innerWidth - navWidth);
  const float gridHeightAvailable =
      std::max(0.0f, innerHeight - kCalendarHeaderHeight * scale - kCalendarGridGap * scale);
  const float weekdayHeight = kCalendarWeekdayRowHeight * scale;
  const float dayCellHeight = std::clamp((gridHeightAvailable - weekdayHeight - kCalendarGridGap * scale * 6.0f) / 6.0f,
                                         kCalendarCellSizeMin * scale, kCalendarCellSizeMax * scale);

  if (m_header != nullptr) {
    m_header->setSize(innerWidth, kCalendarHeaderHeight * scale);
  }
  if (m_monthWrap != nullptr) {
    m_monthWrap->setSize(monthWidth, kCalendarHeaderHeight * scale);
  }

  std::time_t now = std::time(nullptr);
  std::tm local = *std::localtime(&now);
  const int currentYear = local.tm_year + 1900;
  const int currentMonth = local.tm_mon;
  const int today = local.tm_mday;

  std::tm display = local;
  display.tm_mday = 1;
  display.tm_mon += m_monthOffset;
  std::mktime(&display);
  const int year = display.tm_year + 1900;
  const int month = display.tm_mon;
  const bool isCurrentMonth = year == currentYear && month == currentMonth;

  m_monthLabel->setText(monthName(month) + " " + std::to_string(year));
  m_monthLabel->setMaxWidth(monthWidth);

  static constexpr std::array<const char*, 7> kWeekdays = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
  auto weekdayRow = std::make_unique<Flex>();
  weekdayRow->setDirection(FlexDirection::Horizontal);
  weekdayRow->setAlign(FlexAlign::Stretch);
  weekdayRow->setGap(kCalendarGridGap * scale);
  weekdayRow->setSize(innerWidth, weekdayHeight);
  for (std::size_t i = 0; i < kWeekdays.size(); ++i) {
    auto dayLabel = std::make_unique<Button>();
    dayLabel->setText(kWeekdays[i]);
    dayLabel->setVariant(ButtonVariant::Tab);
    dayLabel->setFontSize((Style::fontSizeCaption + 1.0f) * scale);
    dayLabel->setContentAlign(ButtonContentAlign::Center);
    dayLabel->setFlexGrow(1.0f);
    dayLabel->setMinHeight(weekdayHeight);
    dayLabel->label()->setColor(i >= 5 ? palette.primary : palette.onSurfaceVariant);
    weekdayRow->addChild(std::move(dayLabel));
  }
  m_grid->addChild(std::move(weekdayRow));

  const int firstWeekdayMonBased = (display.tm_wday == 0) ? 6 : (display.tm_wday - 1);
  const int previousMonth = month == 0 ? 11 : month - 1;
  const int previousMonthYear = month == 0 ? year - 1 : year;
  const int previousMonthDays = daysInMonth(previousMonthYear, previousMonth);
  const int monthDays = daysInMonth(year, month);

  int day = 1;
  int trailingDay = 1;
  for (int week = 0; week < 6; ++week) {
    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Horizontal);
    row->setAlign(FlexAlign::Stretch);
    row->setGap(kCalendarGridGap * scale);
    row->setSize(innerWidth, dayCellHeight);

    for (int wd = 0; wd < 7; ++wd) {
      auto cell = std::make_unique<Button>();
      cell->setVariant(ButtonVariant::Default);
      cell->setContentAlign(ButtonContentAlign::Center);
      cell->setFlexGrow(1.0f);
      cell->setMinHeight(dayCellHeight);
      cell->setRadius(Style::radiusLg * scale);
      cell->setFontSize(dayCellHeight > (Style::controlHeightLg + Style::spaceXs) * scale ? Style::fontSizeTitle * scale
                                                                                             : Style::fontSizeBody * scale);
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

    m_grid->addChild(std::move(row));
  }
}
