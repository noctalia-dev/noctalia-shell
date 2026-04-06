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
    static_cast<float>(Style::controlHeightLg * 15 + Style::spaceLg + Style::spaceSm);
inline constexpr float kSidebarWidthRatio = 162.0f / 932.0f;
inline constexpr float kSidebarWidth = kPreferredPanelWidth * kSidebarWidthRatio;
inline constexpr float kSidebarButtonWidth = kSidebarWidth - static_cast<float>(Style::spaceMd * 2);
inline constexpr float kContentMinWidth = static_cast<float>(Style::controlHeightLg * 14);
inline constexpr float kMediaSliderWidth = static_cast<float>(Style::controlHeightLg * 9);
inline constexpr float kValueLabelWidth = static_cast<float>(Style::controlHeightLg + Style::spaceLg);
inline constexpr float kHeaderReserveHeight = static_cast<float>(Style::controlHeightSm);
inline constexpr float kNotificationListRightPadding = static_cast<float>(Style::spaceXs);
inline constexpr float kMediaNowCardMinHeight =
    static_cast<float>(Style::controlHeightLg * 11 + Style::spaceSm * 2);
inline constexpr float kMediaAudioCardMinHeight =
    static_cast<float>(Style::controlHeightLg * 3 + Style::spaceMd * 2);
inline constexpr float kMediaPlayerSelectHeight = static_cast<float>(Style::controlHeight);
inline constexpr float kMediaControlsHeight = static_cast<float>(Style::controlHeightLg + Style::spaceXs);
inline constexpr float kMediaPlayPauseHeight = static_cast<float>(Style::controlHeightLg + Style::spaceSm);
inline constexpr float kMediaArtworkMinHeight = static_cast<float>(Style::controlHeightLg * 4);
inline constexpr float kCalendarCellSizeMin = static_cast<float>(Style::controlHeightSm + Style::spaceXs);
inline constexpr float kCalendarCellSizeMax = static_cast<float>(Style::controlHeightLg + Style::spaceLg);
inline constexpr float kCalendarCellSize = kCalendarCellSizeMax;
inline constexpr float kCalendarWeekdayWidth = kCalendarCellSize;
inline constexpr float kCalendarGridGap = static_cast<float>(Style::spaceSm);
inline constexpr float kCalendarCardPadding = static_cast<float>(Style::spaceMd);
inline constexpr float kCalendarNavButtonSize = static_cast<float>(Style::controlHeight);
inline constexpr float kCalendarWeekdayRowHeight = static_cast<float>(Style::controlHeight);
inline constexpr float kCalendarHeaderHeight = static_cast<float>(Style::controlHeightLg + Style::spaceSm);
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
