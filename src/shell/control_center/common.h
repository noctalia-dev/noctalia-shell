#pragma once

#include "notification/notification_manager.h"
#include "render/core/color.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <string>

class Flex;
class Label;

namespace control_center {

inline constexpr float kPreferredPanelWidth = 932.0f;
inline constexpr float kPreferredPanelHeight =
    Style::controlHeightLg * 15 + Style::spaceLg + Style::spaceSm;
inline constexpr float kSidebarWidthRatio = 162.0f / 932.0f;
inline constexpr float kSidebarWidth = kPreferredPanelWidth * kSidebarWidthRatio;
inline constexpr float kSidebarButtonWidth = kSidebarWidth - Style::spaceMd * 2;
inline constexpr float kContentMinWidth = Style::controlHeightLg * 14;
inline constexpr float kMediaSliderWidth = Style::controlHeightLg * 9;
inline constexpr float kValueLabelWidth = Style::controlHeightLg + Style::spaceLg;
inline constexpr float kHeaderReserveHeight = Style::controlHeightSm;
inline constexpr float kNotificationListRightPadding = Style::spaceXs;
inline constexpr float kMediaNowCardMinHeight =
    Style::controlHeightLg * 11 + Style::spaceSm * 2;
inline constexpr float kMediaAudioCardMinHeight =
    Style::controlHeightLg * 3 + Style::spaceMd * 2;
inline constexpr float kMediaPlayerSelectHeight = Style::controlHeight;
inline constexpr float kMediaControlsHeight = Style::controlHeightLg + Style::spaceXs;
inline constexpr float kMediaPlayPauseHeight = Style::controlHeightLg + Style::spaceSm;
inline constexpr float kMediaArtworkMinHeight = Style::controlHeightLg * 4;
inline constexpr float kCalendarCellSizeMin = Style::controlHeightSm + Style::spaceXs;
inline constexpr float kCalendarCellSizeMax = Style::controlHeightLg + Style::spaceLg;
inline constexpr float kCalendarCellSize = kCalendarCellSizeMax;
inline constexpr float kCalendarWeekdayWidth = kCalendarCellSize;
inline constexpr float kCalendarGridGap = Style::spaceSm;
inline constexpr float kCalendarCardPadding = Style::spaceMd;
inline constexpr float kCalendarNavButtonSize = Style::controlHeight;
inline constexpr float kCalendarWeekdayRowHeight = Style::controlHeight;
inline constexpr float kCalendarHeaderHeight = Style::controlHeightLg + Style::spaceSm;
inline constexpr float kCalendarCardMinWidth =
    kCalendarCellSize * 7.0f + kCalendarGridGap * 6.0f + kCalendarCardPadding * 2.0f;
inline constexpr float kCalendarCardMinHeight =
    kCalendarHeaderHeight + kCalendarWeekdayRowHeight + kCalendarCellSize * 6.0f + kCalendarGridGap * 7.0f +
    kCalendarCardPadding * 2.0f;

constexpr Color alphaSurfaceVariant(float alpha) {
  return rgba(palette.surfaceVariant.r, palette.surfaceVariant.g, palette.surfaceVariant.b, alpha);
}

void applyCard(Flex& card);
Label* addTitle(Flex& parent, const std::string& text);
void addBody(Flex& parent, const std::string& text);
std::string statusText(const NotificationHistoryEntry& entry);
Color statusColor(const NotificationHistoryEntry& entry);
std::string monthName(int month);

} // namespace control_center
