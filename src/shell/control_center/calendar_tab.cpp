#include "core/ui_phase.h"
#include "shell/control_center/calendar_tab.h"

#include "render/core/renderer.h"
#include "shell/control_center/tab.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/grid_tile.h"
#include "ui/controls/grid_view.h"
#include "ui/controls/label.h"

#include <algorithm>
#include <array>
#include <cmath>
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
constexpr float kCalendarLayoutEpsilon = 0.5f;

std::string todayLabel() {
  std::time_t now = std::time(nullptr);
  std::tm local = *std::localtime(&now);
  char buf[64];
  if (std::strftime(buf, sizeof(buf), "Today · %A, %d %B %Y", &local) == 0) {
    return "Today";
  }
  return buf;
}

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

struct CalendarBuildState {
  int currentYear = 0;
  int currentMonth = 0;
  int today = 0;
  int displayYear = 0;
  int displayMonth = 0;
  int displayWeekday = 0;
  bool isCurrentMonth = false;
};

CalendarBuildState currentCalendarState(int monthOffset) {
  std::time_t now = std::time(nullptr);
  std::tm local = *std::localtime(&now);

  CalendarBuildState state;
  state.currentYear = local.tm_year + 1900;
  state.currentMonth = local.tm_mon;
  state.today = local.tm_mday;

  std::tm display = local;
  display.tm_mday = 1;
  display.tm_mon += monthOffset;
  std::mktime(&display);
  state.displayYear = display.tm_year + 1900;
  state.displayMonth = display.tm_mon;
  state.displayWeekday = display.tm_wday;
  state.isCurrentMonth = state.displayYear == state.currentYear && state.displayMonth == state.currentMonth;
  return state;
}

} // namespace

std::unique_ptr<Flex> CalendarTab::create() {
  const float scale = contentScale();

  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Horizontal);
  tab->setAlign(FlexAlign::Stretch);
  tab->setGap(Style::spaceMd * scale);
  m_rootLayout = tab.get();

  auto calendarCard = std::make_unique<Flex>();
  control_center::applyOutlinedCard(*calendarCard, scale);
  calendarCard->setGap(Style::spaceMd * scale);
  calendarCard->setFlexGrow(3.0f);
  m_card = calendarCard.get();

  auto header = std::make_unique<Flex>();
  header->setDirection(FlexDirection::Horizontal);
  header->setAlign(FlexAlign::Center);
  header->setJustify(FlexJustify::SpaceBetween);
  header->setGap(Style::spaceSm * scale);
  header->setMinHeight(kCalendarHeaderHeight * scale);
  m_header = header.get();

  auto previousSlot = std::make_unique<Flex>();
  previousSlot->setDirection(FlexDirection::Horizontal);
  previousSlot->setAlign(FlexAlign::Center);
  previousSlot->setJustify(FlexJustify::Center);
  m_previousSlot = previousSlot.get();

  auto previous = std::make_unique<Button>();
  previous->setGlyph("chevron-left");
  previous->setVariant(ButtonVariant::Ghost);
  previous->setMinWidth(kCalendarNavButtonSize * scale);
  previous->setMinHeight(kCalendarNavButtonSize * scale);
  previous->setOnClick([this]() {
    --m_monthOffset;
    PanelManager::instance().refresh();
  });
  m_previousButton = previous.get();
  previousSlot->addChild(std::move(previous));
  header->addChild(std::move(previousSlot));

  auto monthWrap = std::make_unique<Flex>();
  monthWrap->setDirection(FlexDirection::Vertical);
  monthWrap->setAlign(FlexAlign::Center);
  monthWrap->setJustify(FlexJustify::Center);
  monthWrap->setFlexGrow(1.0f);
  m_monthWrap = monthWrap.get();

  auto month = std::make_unique<Label>();
  month->setBold(true);
  month->setFontSize((Style::fontSizeTitle + Style::spaceXs) * scale);
  month->setMaxLines(1);
  month->setColor(roleColor(ColorRole::OnSurface));
  m_monthLabel = month.get();
  monthWrap->addChild(std::move(month));

  auto monthSub = std::make_unique<Label>();
  monthSub->setText("Today");
  monthSub->setCaptionStyle();
  monthSub->setFontSize(Style::fontSizeCaption * scale);
  monthSub->setColor(roleColor(ColorRole::OnSurfaceVariant));
  monthSub->setMaxLines(1);
  m_monthSubLabel = monthSub.get();
  monthWrap->addChild(std::move(monthSub));
  header->addChild(std::move(monthWrap));

  auto nextSlot = std::make_unique<Flex>();
  nextSlot->setDirection(FlexDirection::Horizontal);
  nextSlot->setAlign(FlexAlign::Center);
  nextSlot->setJustify(FlexJustify::Center);
  m_nextSlot = nextSlot.get();

  auto next = std::make_unique<Button>();
  next->setGlyph("chevron-right");
  next->setVariant(ButtonVariant::Ghost);
  next->setMinWidth(kCalendarNavButtonSize * scale);
  next->setMinHeight(kCalendarNavButtonSize * scale);
  next->setOnClick([this]() {
    ++m_monthOffset;
    PanelManager::instance().refresh();
  });
  m_nextButton = next.get();
  nextSlot->addChild(std::move(next));
  header->addChild(std::move(nextSlot));

  calendarCard->addChild(std::move(header));

  auto grid = std::make_unique<Flex>();
  grid->setDirection(FlexDirection::Vertical);
  grid->setAlign(FlexAlign::Stretch);
  grid->setGap(kCalendarGridGap * scale);
  grid->setFlexGrow(1.0f);
  m_grid = grid.get();
  calendarCard->addChild(std::move(grid));
  tab->addChild(std::move(calendarCard));

  auto tasksCard = std::make_unique<Flex>();
  control_center::applyOutlinedCard(*tasksCard, scale);
  tasksCard->setFlexGrow(2.0f);

  auto tasksTitle = std::make_unique<Label>();
  tasksTitle->setText("Tasks");
  tasksTitle->setBold(true);
  tasksTitle->setFontSize(Style::fontSizeTitle * scale);
  tasksTitle->setColor(roleColor(ColorRole::OnSurface));
  tasksCard->addChild(std::move(tasksTitle));

  auto tasksBody = std::make_unique<Label>();
  tasksBody->setText("No tasks yet.");
  tasksBody->setFontSize(Style::fontSizeBody * scale);
  tasksBody->setColor(roleColor(ColorRole::OnSurfaceVariant));
  tasksBody->setMaxLines(3);
  tasksCard->addChild(std::move(tasksBody));

  tab->addChild(std::move(tasksCard));

  return tab;
}

void CalendarTab::doLayout(Renderer& renderer, float contentWidth, float bodyHeight) {
  if (m_rootLayout == nullptr || m_card == nullptr) {
    return;
  }

  m_rootLayout->setSize(contentWidth, bodyHeight);
  m_rootLayout->layout(renderer);

  const float innerWidth = std::max(0.0f, m_card->width() - (m_card->paddingLeft() + m_card->paddingRight()));
  const float innerHeight = std::max(0.0f, m_card->height() - (m_card->paddingTop() + m_card->paddingBottom()));
  const CalendarBuildState state = currentCalendarState(m_monthOffset);

  const bool sizeChanged = std::abs(innerWidth - m_lastInnerWidth) >= kCalendarLayoutEpsilon ||
                           std::abs(innerHeight - m_lastInnerHeight) >= kCalendarLayoutEpsilon;
  const bool displayChanged = state.displayYear != m_lastDisplayYear || state.displayMonth != m_lastDisplayMonth;
  const bool todayChanged = state.currentYear != m_lastCurrentYear || state.currentMonth != m_lastCurrentMonth ||
                            state.today != m_lastToday;
  if (!sizeChanged && !displayChanged && !todayChanged) {
    return;
  }

  m_lastInnerWidth = innerWidth;
  m_lastInnerHeight = innerHeight;
  m_lastDisplayYear = state.displayYear;
  m_lastDisplayMonth = state.displayMonth;
  m_lastCurrentYear = state.currentYear;
  m_lastCurrentMonth = state.currentMonth;
  m_lastToday = state.today;

  rebuild();
  m_rootLayout->layout(renderer);
}

void CalendarTab::onClose() {
  m_rootLayout = nullptr;
  m_card = nullptr;
  m_header = nullptr;
  m_previousSlot = nullptr;
  m_nextSlot = nullptr;
  m_monthWrap = nullptr;
  m_monthLabel = nullptr;
  m_monthSubLabel = nullptr;
  m_previousButton = nullptr;
  m_nextButton = nullptr;
  m_grid = nullptr;
  m_lastInnerWidth = -1.0f;
  m_lastInnerHeight = -1.0f;
  m_lastDisplayYear = std::numeric_limits<int>::min();
  m_lastDisplayMonth = -1;
  m_lastCurrentYear = std::numeric_limits<int>::min();
  m_lastCurrentMonth = -1;
  m_lastToday = -1;
}

void CalendarTab::rebuild() {
  uiAssertNotRendering("CalendarTab::rebuild");
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
  if (m_previousSlot != nullptr) {
    m_previousSlot->setSize(kCalendarNavButtonSize * scale, kCalendarHeaderHeight * scale);
  }
  if (m_nextSlot != nullptr) {
    m_nextSlot->setSize(kCalendarNavButtonSize * scale, kCalendarHeaderHeight * scale);
  }
  if (m_previousButton != nullptr) {
    m_previousButton->setSize(kCalendarNavButtonSize * scale, kCalendarNavButtonSize * scale);
  }
  if (m_nextButton != nullptr) {
    m_nextButton->setSize(kCalendarNavButtonSize * scale, kCalendarNavButtonSize * scale);
  }
  if (m_monthWrap != nullptr) {
    m_monthWrap->setSize(monthWidth, kCalendarHeaderHeight * scale);
  }

  const CalendarBuildState state = currentCalendarState(m_monthOffset);
  const int year = state.displayYear;
  const int month = state.displayMonth;

  m_monthLabel->setText(monthName(month) + " " + std::to_string(year));
  m_monthLabel->setMaxWidth(monthWidth);
  if (m_monthSubLabel != nullptr) {
    m_monthSubLabel->setText(todayLabel());
    m_monthSubLabel->setMaxWidth(monthWidth);
  }

  static constexpr std::array<const char*, 7> kWeekdays = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
  auto weekdayRow = std::make_unique<GridView>();
  weekdayRow->setColumns(kWeekdays.size());
  weekdayRow->setColumnGap(kCalendarGridGap * scale);
  weekdayRow->setSize(innerWidth, weekdayHeight);
  weekdayRow->setMinCellHeight(weekdayHeight);
  for (std::size_t i = 0; i < kWeekdays.size(); ++i) {
    auto dayCell = std::make_unique<GridTile>();
    dayCell->setDirection(FlexDirection::Vertical);
    dayCell->setAlign(FlexAlign::Center);
    dayCell->setJustify(FlexJustify::Center);

    auto dayLabel = std::make_unique<Label>();
    dayLabel->setText(kWeekdays[i]);
    dayLabel->setFontSize((Style::fontSizeCaption + 1.0f) * scale);
    dayLabel->setBold(true);
    dayLabel->setColor(roleColor(i >= 5 ? ColorRole::Secondary : ColorRole::OnSurfaceVariant));
    dayCell->addChild(std::move(dayLabel));

    weekdayRow->addChild(std::move(dayCell));
  }
  m_grid->addChild(std::move(weekdayRow));

  const int firstWeekdayMonBased = (state.displayWeekday == 0) ? 6 : (state.displayWeekday - 1);
  const int previousMonth = month == 0 ? 11 : month - 1;
  const int previousMonthYear = month == 0 ? year - 1 : year;
  const int previousMonthDays = daysInMonth(previousMonthYear, previousMonth);
  const int monthDays = daysInMonth(year, month);

  auto dayGrid = std::make_unique<GridView>();
  dayGrid->setColumns(7);
  dayGrid->setColumnGap(kCalendarGridGap * scale);
  dayGrid->setSize(innerWidth, 0.0f);
  dayGrid->setMinCellHeight(dayCellHeight);

  int day = 1;
  int trailingDay = 1;
  for (int index = 0; index < 42; ++index) {
    auto cell = std::make_unique<Button>();
    cell->setVariant(ButtonVariant::Ghost);
    cell->setContentAlign(ButtonContentAlign::Center);
    cell->setMinHeight(dayCellHeight);
    cell->setRadius(Style::radiusLg * scale);
    cell->setFontSize(dayCellHeight > (Style::controlHeightLg + Style::spaceXs) * scale ? Style::fontSizeTitle * scale
                                                                                           : Style::fontSizeBody * scale);
    cell->setText("");

    if (index < firstWeekdayMonBased) {
      const int leadingDay = previousMonthDays - firstWeekdayMonBased + index + 1;
      cell->setText(std::to_string(leadingDay));
      cell->label()->setColor(roleColor(ColorRole::OnSurfaceVariant, 0.75f));
    } else if (day > monthDays) {
      cell->setText(std::to_string(trailingDay));
      cell->label()->setColor(roleColor(ColorRole::OnSurfaceVariant, 0.75f));
      ++trailingDay;
    } else {
      cell->setText(std::to_string(day));
      if (state.isCurrentMonth && day == state.today) {
        cell->setVariant(ButtonVariant::Accent);
      } else {
        cell->label()->setColor(roleColor(ColorRole::OnSurface));
      }
      ++day;
    }

    dayGrid->addChild(std::move(cell));
  }

  m_grid->addChild(std::move(dayGrid));
}
