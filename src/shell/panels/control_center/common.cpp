#include "shell/panels/control_center/common.h"

#include "ui/controls/flex.h"
#include "ui/controls/label.h"

#include <array>
#include <cstddef>
#include <memory>

namespace control_center {

void applyCard(Flex& card) {
  card.setDirection(FlexDirection::Vertical);
  card.setAlign(FlexAlign::Start);
  card.setGap(static_cast<float>(Style::spaceXs));
  card.setPadding(static_cast<float>(Style::spaceSm), static_cast<float>(Style::spaceMd),
                  static_cast<float>(Style::spaceSm), static_cast<float>(Style::spaceMd));
  card.setRadius(static_cast<float>(Style::radiusLg));
  card.setBackground(alphaSurfaceVariant(0.75f));
  card.setBorderWidth(0.0f);
  card.setSoftness(1.0f);
}

Label* addTitle(Flex& parent, const std::string& text) {
  auto label = std::make_unique<Label>();
  label->setText(text);
  label->setBold(true);
  label->setFontSize(Style::fontSizeTitle);
  label->setColor(palette.onSurface);
  auto* ptr = label.get();
  parent.addChild(std::move(label));
  return ptr;
}

void addBody(Flex& parent, const std::string& text) {
  auto label = std::make_unique<Label>();
  label->setText(text);
  label->setColor(palette.onSurfaceVariant);
  parent.addChild(std::move(label));
}

std::string statusText(const NotificationHistoryEntry& entry) {
  if (entry.active) {
    return "Active";
  }
  if (!entry.closeReason.has_value()) {
    return "Closed";
  }

  switch (*entry.closeReason) {
  case CloseReason::Expired:
    return "Expired";
  case CloseReason::Dismissed:
    return "Dismissed";
  case CloseReason::ClosedByCall:
    return "Closed";
  }

  return "Closed";
}

Color statusColor(const NotificationHistoryEntry& entry) {
  if (entry.active) {
    return palette.primary;
  }
  if (entry.closeReason == CloseReason::Dismissed) {
    return palette.secondary;
  }
  return palette.onSurfaceVariant;
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

} // namespace control_center
