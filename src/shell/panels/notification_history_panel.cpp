#include "shell/panels/notification_history_panel.h"

#include "notification/notification_manager.h"
#include "render/core/renderer.h"
#include "render/scene/node.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <memory>
#include <string>
#include <vector>

namespace {

void applyNotificationCardStyle(Flex& card) {
  card.setRadius(Style::radiusMd);
  card.setBackground(palette.surfaceVariant);
  card.setBorderWidth(0.0f);
  card.setSoftness(1.0f);
}

std::string collapseWhitespace(std::string_view text) {
  std::string out;
  out.reserve(text.size());

  bool lastWasSpace = true;
  for (char ch : text) {
    const bool isWhitespace = (ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r');
    if (isWhitespace) {
      if (!lastWasSpace) {
        out.push_back(' ');
      }
      lastWasSpace = true;
      continue;
    }
    out.push_back(ch);
    lastWasSpace = false;
  }

  if (!out.empty() && out.back() == ' ') {
    out.pop_back();
  }
  return out;
}

std::string truncateToWidth(Renderer& renderer, std::string text, float fontSize, float maxWidth, bool bold = false) {
  static constexpr std::string_view kEllipsis = "\xe2\x80\xa6";
  if (renderer.measureText(text, fontSize, bold).width <= maxWidth) {
    return text;
  }

  while (!text.empty()) {
    text.pop_back();
    std::string candidate = text + std::string(kEllipsis);
    if (renderer.measureText(candidate, fontSize, bold).width <= maxWidth) {
      return candidate;
    }
  }

  return std::string(kEllipsis);
}

std::vector<std::string> wrapLines(Renderer& renderer, std::string_view text, float fontSize, float maxWidth,
                                   std::size_t maxLines, bool bold = false) {
  const std::string normalized = collapseWhitespace(text);
  if (normalized.empty()) {
    return {};
  }

  std::vector<std::string> words;
  std::size_t start = 0;
  while (start < normalized.size()) {
    const std::size_t end = normalized.find(' ', start);
    if (end == std::string::npos) {
      words.push_back(normalized.substr(start));
      break;
    }
    words.push_back(normalized.substr(start, end - start));
    start = end + 1;
  }

  std::vector<std::string> lines;
  lines.reserve(maxLines);

  std::size_t wordIndex = 0;
  while (wordIndex < words.size() && lines.size() < maxLines) {
    std::string line = words[wordIndex];
    if (renderer.measureText(line, fontSize, bold).width > maxWidth) {
      lines.push_back(truncateToWidth(renderer, line, fontSize, maxWidth, bold));
      ++wordIndex;
      continue;
    }

    std::size_t nextIndex = wordIndex + 1;
    while (nextIndex < words.size()) {
      const std::string candidate = line + " " + words[nextIndex];
      if (renderer.measureText(candidate, fontSize, bold).width > maxWidth) {
        break;
      }
      line = candidate;
      ++nextIndex;
    }

    if (lines.size() + 1 == maxLines && nextIndex < words.size()) {
      std::string remainder = line;
      for (std::size_t i = nextIndex; i < words.size(); ++i) {
        remainder += " ";
        remainder += words[i];
      }
      line = truncateToWidth(renderer, remainder, fontSize, maxWidth, bold);
      nextIndex = words.size();
    }

    lines.push_back(std::move(line));
    wordIndex = nextIndex;
  }

  return lines;
}

void addWrappedLabelLines(Flex& parent, Renderer& renderer, std::string_view text, float fontSize, float maxWidth,
                          std::size_t maxLines, bool bold, const Color& color) {
  const auto lines = wrapLines(renderer, text, fontSize, maxWidth, maxLines, bold);
  for (const auto& line : lines) {
    auto label = std::make_unique<Label>();
    label->setText(line);
    label->setFontSize(fontSize);
    label->setBold(bold);
    label->setColor(color);
    label->setMaxWidth(maxWidth);
    label->measure(renderer);
    parent.addChild(std::move(label));
  }
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

  if (entry.closeReason == CloseReason::Expired) {
    return palette.onSurfaceVariant;
  }

  if (entry.closeReason == CloseReason::Dismissed) {
    return palette.secondary;
  }

  return palette.onSurfaceVariant;
}

} // namespace

NotificationHistoryPanel::NotificationHistoryPanel(NotificationManager* manager) : m_manager(manager) {}

void NotificationHistoryPanel::create(Renderer& renderer) {
  auto container = std::make_unique<Flex>();
  container->setDirection(FlexDirection::Vertical);
  container->setAlign(FlexAlign::Start);
  container->setGap(Style::spaceMd);

  auto header = std::make_unique<Flex>();
  header->setDirection(FlexDirection::Vertical);
  header->setAlign(FlexAlign::Start);
  header->setGap(Style::spaceXs);
  header->setBackground(palette.surface);
  header->setPadding(0.0f, 0.0f, static_cast<float>(Style::spaceXs), 0.0f);
  header->setZIndex(2);
  m_header = header.get();

  auto headerRow = std::make_unique<Flex>();
  headerRow->setDirection(FlexDirection::Horizontal);
  headerRow->setAlign(FlexAlign::Center);
  headerRow->setGap(Style::spaceSm);
  m_headerRow = headerRow.get();

  auto title = std::make_unique<Label>();
  title->setText("Notifications");
  title->setFontSize(Style::fontSizeTitle);
  title->setBold(true);
  title->setColor(palette.primary);
  m_titleLabel = title.get();
  headerRow->addChild(std::move(title));

  auto clearAllButton = std::make_unique<Button>();
  clearAllButton->setText("Clear all");
  clearAllButton->setVariant(ButtonVariant::Ghost);
  clearAllButton->setOnClick([this]() { clearAll(); });
  m_clearAllButton = clearAllButton.get();
  headerRow->addChild(std::move(clearAllButton));

  header->addChild(std::move(headerRow));

  auto subtitle = std::make_unique<Label>();
  subtitle->setText("Recent activity from newest to oldest");
  subtitle->setCaptionStyle();
  subtitle->setColor(palette.onSurfaceVariant);
  m_subtitleLabel = subtitle.get();
  header->addChild(std::move(subtitle));

  container->addChild(std::move(header));

  auto scrollView = std::make_unique<ScrollView>();
  scrollView->setScrollbarVisible(true);
  scrollView->setScrollStep(56.0f);
  scrollView->setZIndex(1);
  m_scrollView = scrollView.get();
  m_list = scrollView->content();
  m_list->setDirection(FlexDirection::Vertical);
  m_list->setAlign(FlexAlign::Start);
  m_list->setGap(Style::spaceSm);
  container->addChild(std::move(scrollView));

  m_container = container.get();
  m_root = std::move(container);

  if (m_animations != nullptr) {
    m_root->setAnimationManager(m_animations);
  }

  rebuildList(renderer, preferredWidth());
}

void NotificationHistoryPanel::layout(Renderer& renderer, float width, float height) {
  if (m_container == nullptr || m_header == nullptr || m_scrollView == nullptr) {
    return;
  }

  m_lastWidth = width;
  m_lastHeight = height;

  if (m_titleLabel != nullptr) {
    m_titleLabel->setMaxWidth(width);
    m_titleLabel->measure(renderer);
  }
  if (m_clearAllButton != nullptr) {
    m_clearAllButton->layout(renderer);
    m_clearAllButton->updateInputArea();
  }
  if (m_headerRow != nullptr && m_titleLabel != nullptr && m_clearAllButton != nullptr) {
    const float titleWidth = std::max(0.0f, width - m_clearAllButton->width() - Style::spaceSm);
    m_titleLabel->setMaxWidth(titleWidth);
    m_titleLabel->measure(renderer);
    m_headerRow->setMinWidth(width);
    m_headerRow->layout(renderer);
  }
  if (m_subtitleLabel != nullptr) {
    m_subtitleLabel->setMaxWidth(width);
    m_subtitleLabel->measure(renderer);
  }

  m_header->setMinWidth(width);
  m_header->layout(renderer);

  const float scrollHeight = std::max(0.0f, height - m_header->height() - Style::spaceMd);
  m_scrollView->setSize(width, scrollHeight);
  m_scrollView->layout(renderer);
  rebuildList(renderer, m_scrollView->contentViewportWidth());
  m_scrollView->layout(renderer);

  m_container->setMinWidth(width);
  m_container->setSize(width, height);
  m_container->layout(renderer);
}

void NotificationHistoryPanel::update(Renderer& renderer) {
  const std::uint64_t changeSerial = m_manager != nullptr ? m_manager->changeSerial() : 0;
  if ((changeSerial == m_lastChangeSerial && m_lastListWidth >= 0.0f) || m_lastWidth <= 0.0f) {
    return;
  }

  const float listWidth = m_scrollView != nullptr ? m_scrollView->contentViewportWidth() : m_lastWidth;
  rebuildList(renderer, listWidth);
}

void NotificationHistoryPanel::rebuildList(Renderer& renderer, float width) {
  if (m_list == nullptr) {
    return;
  }

  if (width == m_lastListWidth && m_manager != nullptr && m_lastChangeSerial == m_manager->changeSerial()) {
    return;
  }

  const float cardWidth = std::max(0.0f, width);
  while (!m_list->children().empty()) {
    m_list->removeChild(m_list->children().front().get());
  }

  if (m_manager == nullptr || m_manager->history().empty()) {
    auto emptyCard = std::make_unique<Flex>();
    emptyCard->setDirection(FlexDirection::Vertical);
    emptyCard->setAlign(FlexAlign::Start);
    emptyCard->setGap(Style::spaceXs);
    emptyCard->setPadding(Style::spaceMd);
    applyNotificationCardStyle(*emptyCard);
    emptyCard->setMinWidth(cardWidth);

    auto title = std::make_unique<Label>();
    title->setText("No notifications yet");
    title->setBold(true);
    title->setMaxWidth(cardWidth - Style::spaceMd * 2.0f);
    title->measure(renderer);
    emptyCard->addChild(std::move(title));

    auto body = std::make_unique<Label>();
    body->setText("Incoming notifications will appear here.");
    body->setCaptionStyle();
    body->setColor(palette.onSurfaceVariant);
    body->setMaxWidth(cardWidth - Style::spaceMd * 2.0f);
    body->measure(renderer);
    emptyCard->addChild(std::move(body));

    m_list->addChild(std::move(emptyCard));
    m_lastChangeSerial = m_manager != nullptr ? m_manager->changeSerial() : 0;
    m_lastListWidth = width;
    return;
  }

  for (auto it = m_manager->history().rbegin(); it != m_manager->history().rend(); ++it) {
    const auto& entry = *it;
    auto card = std::make_unique<Flex>();
    card->setDirection(FlexDirection::Vertical);
    card->setAlign(FlexAlign::Start);
    card->setGap(Style::spaceXs);
    card->setPadding(Style::spaceMd);
    applyNotificationCardStyle(*card);
    card->setMinWidth(cardWidth);

    auto metaRow = std::make_unique<Flex>();
    metaRow->setDirection(FlexDirection::Horizontal);
    metaRow->setAlign(FlexAlign::Center);
    metaRow->setGap(Style::spaceSm);

    const float innerWidth = cardWidth - Style::spaceMd * 2.0f;

    auto dismissButton = std::make_unique<Button>();
    dismissButton->setText("");
    dismissButton->setIcon("trash");
    dismissButton->setIconSize(Style::fontSizeCaption);
    dismissButton->setVariant(ButtonVariant::Ghost);
    dismissButton->setMinHeight(static_cast<float>(Style::controlHeightSm));
    dismissButton->setPadding(static_cast<float>(Style::spaceXs));
    dismissButton->setGap(0.0f);
    dismissButton->setOnClick(
        [this, id = entry.notification.id, wasActive = entry.active]() { dismissEntry(id, wasActive); });
    dismissButton->layout(renderer);
    dismissButton->updateInputArea();
    Button* dismissButtonPtr = dismissButton.get();

    auto spacer = std::make_unique<Node>();
    auto meta = std::make_unique<Label>();
    meta->setText(entry.notification.appName + " • " + statusText(entry));
    meta->setCaptionStyle();
    meta->setColor(statusColor(entry));
    meta->setMaxWidth(std::max(0.0f, innerWidth - dismissButtonPtr->width() - Style::spaceSm));
    meta->measure(renderer);
    spacer->setSize(std::max(0.0f, innerWidth - meta->width() - dismissButtonPtr->width() - Style::spaceSm * 2.0f),
                    1.0f);
    metaRow->addChild(std::move(meta));
    metaRow->addChild(std::move(spacer));
    metaRow->addChild(std::move(dismissButton));
    metaRow->setMinWidth(innerWidth);
    metaRow->layout(renderer);
    card->addChild(std::move(metaRow));

    addWrappedLabelLines(*card, renderer,
                         entry.notification.summary.empty() ? "Untitled notification" : entry.notification.summary,
                         Style::fontSizeTitle, innerWidth, 2, true, palette.onSurface);

    if (!entry.notification.body.empty()) {
      addWrappedLabelLines(*card, renderer, entry.notification.body, Style::fontSizeBody, innerWidth, 2, false,
                           palette.onSurfaceVariant);
    }

    m_list->addChild(std::move(card));
  }

  m_lastChangeSerial = m_manager->changeSerial();
  m_lastListWidth = width;
}

void NotificationHistoryPanel::dismissEntry(uint32_t id, bool wasActive) {
  if (m_manager == nullptr) {
    return;
  }

  if (wasActive) {
    m_manager->close(id, CloseReason::Dismissed);
  }
  m_manager->removeHistoryEntry(id);
  PanelManager::instance().refresh();
}

void NotificationHistoryPanel::clearAll() {
  if (m_manager == nullptr) {
    return;
  }

  std::vector<uint32_t> activeIds;
  activeIds.reserve(m_manager->history().size());
  for (const auto& entry : m_manager->history()) {
    if (entry.active) {
      activeIds.push_back(entry.notification.id);
    }
  }

  for (const uint32_t id : activeIds) {
    m_manager->close(id, CloseReason::Dismissed);
  }
  m_manager->clearHistory();
  PanelManager::instance().refresh();
}
