#include "shell/panels/clipboard_panel.h"

#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/control_center/tab.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/clipboard_service.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <ctime>
#include <memory>
#include <string>
#include <string_view>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

constexpr float kSidebarWidth = 272.0f;
constexpr float kRowHeight = 58.0f;
constexpr float kPreviewImageHeight = 260.0f;
constexpr float kListGlyphSize = 24.0f;

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
                                   std::size_t maxLines = static_cast<std::size_t>(-1), bool bold = false) {
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

std::string formatTimestamp(const ClipboardEntry& entry) {
  const std::time_t rawTime = std::chrono::system_clock::to_time_t(entry.capturedAt);
  std::tm localTime{};
  localtime_r(&rawTime, &localTime);

  std::time_t nowRaw = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
  std::tm nowLocal{};
  localtime_r(&nowRaw, &nowLocal);

  char buffer[64];
  const bool sameDay = localTime.tm_year == nowLocal.tm_year && localTime.tm_yday == nowLocal.tm_yday;
  std::strftime(buffer, sizeof(buffer), sameDay ? "%H:%M" : "%b %e %H:%M", &localTime);
  return buffer;
}

std::string formatBytes(std::size_t bytes) {
  const char* units[] = {"B", "KB", "MB", "GB"};
  double value = static_cast<double>(bytes);
  std::size_t unitIndex = 0;
  while (value >= 1024.0 && unitIndex + 1 < std::size(units)) {
    value /= 1024.0;
    ++unitIndex;
  }

  char buffer[32];
  if (unitIndex == 0) {
    std::snprintf(buffer, sizeof(buffer), "%zu %s", bytes, units[unitIndex]);
  } else {
    std::snprintf(buffer, sizeof(buffer), "%.1f %s", value, units[unitIndex]);
  }
  return buffer;
}

std::string entryTitle(const ClipboardEntry& entry) {
  if (!entry.textPreview.empty()) {
    return entry.textPreview;
  }
  if (entry.isImage()) {
    return "Image";
  }
  return entry.dataMimeType.empty() ? "Clipboard entry" : entry.dataMimeType;
}

std::string entrySubtitle(const ClipboardEntry& entry) {
  if (entry.isImage()) {
    return formatBytes(entry.byteSize);
  }
  if (!entry.dataMimeType.empty()) {
    return entry.dataMimeType;
  }
  return formatBytes(entry.byteSize);
}

std::string previewTitle(const ClipboardEntry& entry) {
  if (entry.isImage()) {
    return "Image Clipboard Entry";
  }
  return "Text Clipboard Entry";
}

} // namespace

ClipboardPanel::ClipboardPanel(ClipboardService* clipboard) : m_clipboard(clipboard) {}

void ClipboardPanel::create(Renderer& renderer) {
  auto root = std::make_unique<Flex>();
  root->setDirection(FlexDirection::Horizontal);
  root->setAlign(FlexAlign::Start);
  root->setGap(Style::spaceLg);
  m_rootLayout = root.get();

  auto focusArea = std::make_unique<InputArea>();
  focusArea->setFocusable(true);
  focusArea->setVisible(false);
  focusArea->setOnKeyDown([this](const InputArea::KeyData& key) {
    if (key.pressed) {
      handleKeyEvent(key.sym, key.modifiers);
    }
  });
  m_focusArea = static_cast<InputArea*>(root->addChild(std::move(focusArea)));

  auto sidebar = std::make_unique<Flex>();
  sidebar->setDirection(FlexDirection::Vertical);
  sidebar->setAlign(FlexAlign::Start);
  sidebar->setGap(Style::spaceSm);
  sidebar->setPadding(Style::spaceMd);
  sidebar->setRadius(Style::radiusXl);
  sidebar->setBackground(control_center::alphaSurfaceVariant(0.9f));
  sidebar->setBorderWidth(0.0f);
  sidebar->setSoftness(1.0f);
  m_sidebar = sidebar.get();

  auto title = std::make_unique<Label>();
  title->setText("Clipboard");
  title->setFontSize(Style::fontSizeTitle);
  title->setBold(true);
  title->setColor(palette.primary);
  m_sidebarTitle = title.get();
  sidebar->addChild(std::move(title));

  auto subtitle = std::make_unique<Label>();
  subtitle->setText("Newest first");
  subtitle->setCaptionStyle();
  subtitle->setColor(palette.onSurfaceVariant);
  m_sidebarSubtitle = subtitle.get();
  sidebar->addChild(std::move(subtitle));

  auto listScroll = std::make_unique<ScrollView>();
  listScroll->setScrollbarVisible(true);
  m_listScrollView = listScroll.get();
  m_list = listScroll->content();
  m_list->setDirection(FlexDirection::Vertical);
  m_list->setAlign(FlexAlign::Start);
  m_list->setGap(Style::spaceXs);
  sidebar->addChild(std::move(listScroll));

  root->addChild(std::move(sidebar));

  auto preview = std::make_unique<Flex>();
  preview->setDirection(FlexDirection::Vertical);
  preview->setAlign(FlexAlign::Start);
  preview->setGap(Style::spaceMd);
  preview->setPadding(Style::spaceLg);
  preview->setRadius(Style::radiusXl);
  preview->setBackground(control_center::alphaSurfaceVariant(0.9f));
  preview->setBorderWidth(0.0f);
  preview->setSoftness(1.0f);
  m_previewCard = preview.get();

  auto previewTitleLabel = std::make_unique<Label>();
  previewTitleLabel->setText("Clipboard entry");
  previewTitleLabel->setFontSize(Style::fontSizeTitle);
  previewTitleLabel->setBold(true);
  previewTitleLabel->setColor(palette.primary);
  m_previewTitle = previewTitleLabel.get();
  preview->addChild(std::move(previewTitleLabel));

  auto previewMetaLabel = std::make_unique<Label>();
  previewMetaLabel->setCaptionStyle();
  previewMetaLabel->setColor(palette.onSurfaceVariant);
  m_previewMeta = previewMetaLabel.get();
  preview->addChild(std::move(previewMetaLabel));

  auto copyButton = std::make_unique<Button>();
  copyButton->setText("Copy Selected");
  copyButton->setGlyph("copy");
  copyButton->setVariant(ButtonVariant::Secondary);
  copyButton->setOnClick([this]() { activateSelected(); });
  m_copyButton = copyButton.get();
  preview->addChild(std::move(copyButton));

  auto previewScroll = std::make_unique<ScrollView>();
  previewScroll->setScrollbarVisible(true);
  m_previewScrollView = previewScroll.get();
  m_previewContent = previewScroll->content();
  m_previewContent->setDirection(FlexDirection::Vertical);
  m_previewContent->setAlign(FlexAlign::Start);
  m_previewContent->setGap(Style::spaceSm);
  preview->addChild(std::move(previewScroll));

  root->addChild(std::move(preview));

  m_root = std::move(root);
  if (m_animations != nullptr) {
    m_root->setAnimationManager(m_animations);
  }

  rebuildList(renderer, kSidebarWidth - Style::spaceMd * 2.0f);
  rebuildPreview(renderer, preferredWidth() - kSidebarWidth - Style::spaceLg - Style::spaceLg * 2.0f,
                 preferredHeight());
}

void ClipboardPanel::layout(Renderer& renderer, float width, float height) {
  if (m_rootLayout == nullptr || m_sidebar == nullptr || m_previewCard == nullptr || m_listScrollView == nullptr ||
      m_previewScrollView == nullptr) {
    return;
  }

  m_lastWidth = width;
  m_lastHeight = height;

  const float sidebarWidth = std::min(kSidebarWidth, std::max(220.0f, width * 0.34f));
  const float previewWidth = std::max(0.0f, width - sidebarWidth - Style::spaceLg);
  const float sidebarInnerWidth = std::max(0.0f, sidebarWidth - Style::spaceMd * 2.0f);
  const float previewInnerWidth = std::max(0.0f, previewWidth - Style::spaceLg * 2.0f);

  m_focusArea->setPosition(0.0f, 0.0f);
  m_focusArea->setSize(1.0f, 1.0f);

  if (m_sidebarTitle != nullptr) {
    m_sidebarTitle->setMaxWidth(sidebarInnerWidth);
    m_sidebarTitle->measure(renderer);
  }
  if (m_sidebarSubtitle != nullptr) {
    m_sidebarSubtitle->setMaxWidth(sidebarInnerWidth);
    m_sidebarSubtitle->measure(renderer);
  }

  const float sidebarHeaderHeight = (m_sidebarTitle != nullptr ? m_sidebarTitle->height() : 0.0f) +
                                    (m_sidebarSubtitle != nullptr ? m_sidebarSubtitle->height() : 0.0f) +
                                    Style::spaceSm;
  const float listHeight = std::max(0.0f, height - Style::spaceMd * 2.0f - sidebarHeaderHeight);
  m_listScrollView->setSize(sidebarInnerWidth, listHeight);
  m_listScrollView->layout(renderer);

  if (m_lastListWidth != m_listScrollView->contentViewportWidth() ||
      (m_clipboard != nullptr && m_lastChangeSerial != m_clipboard->changeSerial())) {
    rebuildList(renderer, m_listScrollView->contentViewportWidth());
    m_listScrollView->layout(renderer);
  }

  if (m_previewTitle != nullptr) {
    m_previewTitle->setMaxWidth(previewInnerWidth);
    m_previewTitle->measure(renderer);
  }
  if (m_previewMeta != nullptr) {
    m_previewMeta->setMaxWidth(previewInnerWidth);
    m_previewMeta->measure(renderer);
  }
  if (m_copyButton != nullptr) {
    m_copyButton->layout(renderer);
    m_copyButton->updateInputArea();
  }

  const float previewHeaderHeight = (m_previewTitle != nullptr ? m_previewTitle->height() : 0.0f) +
                                    (m_previewMeta != nullptr ? m_previewMeta->height() : 0.0f) +
                                    (m_copyButton != nullptr ? m_copyButton->height() : 0.0f) + Style::spaceMd * 2.0f;
  const float previewScrollHeight = std::max(0.0f, height - Style::spaceLg * 2.0f - previewHeaderHeight);
  m_previewScrollView->setSize(previewInnerWidth, previewScrollHeight);
  rebuildPreview(renderer, m_previewScrollView->contentViewportWidth(), previewScrollHeight);
  m_previewScrollView->layout(renderer);

  m_sidebar->setMinWidth(sidebarWidth);
  m_sidebar->setSize(sidebarWidth, height);
  m_sidebar->layout(renderer);

  m_previewCard->setMinWidth(previewWidth);
  m_previewCard->setSize(previewWidth, height);
  m_previewCard->layout(renderer);

  m_rootLayout->setSize(width, height);
  m_rootLayout->layout(renderer);
}

void ClipboardPanel::update(Renderer& renderer) {
  if (m_clipboard == nullptr || m_lastWidth <= 0.0f) {
    return;
  }

  if (m_lastChangeSerial == m_clipboard->changeSerial()) {
    return;
  }

  const std::size_t itemCount = m_clipboard->history().size();
  if (itemCount == 0) {
    m_selectedIndex = 0;
  } else if (m_selectedIndex >= itemCount) {
    m_selectedIndex = itemCount - 1;
  }

  const float listWidth = m_listScrollView != nullptr ? m_listScrollView->contentViewportWidth() : kSidebarWidth;
  const float previewWidth = m_previewScrollView != nullptr ? m_previewScrollView->contentViewportWidth() : m_lastWidth;
  const float previewHeight = m_previewScrollView != nullptr ? m_previewScrollView->height() : m_lastHeight;
  rebuildList(renderer, listWidth);
  rebuildPreview(renderer, previewWidth, previewHeight);
}

void ClipboardPanel::onOpen(std::string_view /*context*/) {
  m_selectedIndex = 0;
  m_lastListWidth = -1.0f;
  m_lastPreviewWidth = -1.0f;
  m_lastPreviewHeight = -1.0f;
}

void ClipboardPanel::onClose() {
  m_rootLayout = nullptr;
  m_focusArea = nullptr;
  m_sidebar = nullptr;
  m_sidebarTitle = nullptr;
  m_sidebarSubtitle = nullptr;
  m_listScrollView = nullptr;
  m_list = nullptr;
  m_previewCard = nullptr;
  m_previewTitle = nullptr;
  m_previewMeta = nullptr;
  m_copyButton = nullptr;
  m_previewScrollView = nullptr;
  m_previewContent = nullptr;
  m_previewImage = nullptr;
  m_rootPtr = nullptr;
  m_lastWidth = 0.0f;
  m_lastHeight = 0.0f;
}

InputArea* ClipboardPanel::initialFocusArea() const { return m_focusArea; }

void ClipboardPanel::rebuildList(Renderer& renderer, float width) {
  if (m_list == nullptr) {
    return;
  }

  const auto& history = m_clipboard != nullptr ? m_clipboard->history() : std::deque<ClipboardEntry>{};
  while (!m_list->children().empty()) {
    m_list->removeChild(m_list->children().front().get());
  }

  if (history.empty()) {
    auto empty = std::make_unique<Label>();
    empty->setText("Clipboard history is empty");
    empty->setCaptionStyle();
    empty->setColor(palette.onSurfaceVariant);
    empty->setMaxWidth(width);
    empty->measure(renderer);
    m_list->addChild(std::move(empty));
    m_lastChangeSerial = m_clipboard != nullptr ? m_clipboard->changeSerial() : 0;
    m_lastListWidth = width;
    return;
  }

  const float textWidth = std::max(0.0f, width - kListGlyphSize - Style::spaceSm * 4.0f - 48.0f);
  for (std::size_t i = 0; i < history.size(); ++i) {
    const auto& entry = history[i];
    auto area = std::make_unique<InputArea>();
    area->setPropagateEvents(true);
    area->setOnClick([this, idx = i](const InputArea::PointerData& /*data*/) {
      if (m_selectedIndex == idx) {
        activateSelected();
        return;
      }
      selectIndex(idx);
    });

    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Horizontal);
    row->setAlign(FlexAlign::Center);
    row->setGap(Style::spaceSm);
    row->setPadding(Style::spaceSm);
    row->setMinWidth(width);
    row->setMinHeight(kRowHeight);
    row->setRadius(Style::radiusLg);
    row->setBackground(i == m_selectedIndex ? palette.surface : control_center::alphaSurfaceVariant(0.55f));
    row->setBorderWidth(0.0f);
    row->setSoftness(1.0f);

    auto glyph = std::make_unique<Glyph>();
    glyph->setGlyph(entry.isImage() ? "photo" : "file-text");
    glyph->setGlyphSize(kListGlyphSize);
    glyph->setColor(entry.isImage() ? palette.secondary : palette.primary);
    glyph->measure(renderer);
    row->addChild(std::move(glyph));

    auto textColumn = std::make_unique<Flex>();
    textColumn->setDirection(FlexDirection::Vertical);
    textColumn->setAlign(FlexAlign::Start);
    textColumn->setGap(Style::spaceXs);

    auto title = std::make_unique<Label>();
    title->setText(truncateToWidth(renderer, entryTitle(entry), Style::fontSizeBody, textWidth, true));
    title->setFontSize(Style::fontSizeBody);
    title->setBold(true);
    title->setColor(palette.onSurface);
    title->setMaxWidth(textWidth);
    title->measure(renderer);
    textColumn->addChild(std::move(title));

    auto subtitle = std::make_unique<Label>();
    subtitle->setText(entrySubtitle(entry));
    subtitle->setCaptionStyle();
    subtitle->setColor(palette.onSurfaceVariant);
    subtitle->setMaxWidth(textWidth);
    subtitle->measure(renderer);
    textColumn->addChild(std::move(subtitle));

    row->addChild(std::move(textColumn));

    auto time = std::make_unique<Label>();
    time->setText(formatTimestamp(entry));
    time->setCaptionStyle();
    time->setColor(palette.onSurfaceVariant);
    time->measure(renderer);
    row->addChild(std::move(time));

    row->layout(renderer);
    area->setSize(row->width(), row->height());
    area->addChild(std::move(row));
    m_list->addChild(std::move(area));
  }

  m_lastChangeSerial = m_clipboard != nullptr ? m_clipboard->changeSerial() : 0;
  m_lastListWidth = width;
}

void ClipboardPanel::rebuildPreview(Renderer& renderer, float width, float height) {
  if (m_previewContent == nullptr || m_previewTitle == nullptr || m_previewMeta == nullptr) {
    return;
  }

  while (!m_previewContent->children().empty()) {
    m_previewContent->removeChild(m_previewContent->children().front().get());
  }
  m_previewImage = nullptr;

  const auto& history = m_clipboard != nullptr ? m_clipboard->history() : std::deque<ClipboardEntry>{};
  if (history.empty() || m_selectedIndex >= history.size()) {
    m_previewTitle->setText("Clipboard entry");
    m_previewMeta->setText("Select an item from the left");
    m_previewMeta->measure(renderer);

    auto empty = std::make_unique<Label>();
    empty->setText("Clipboard history is empty.");
    empty->setColor(palette.onSurfaceVariant);
    empty->setMaxWidth(width);
    empty->measure(renderer);
    m_previewContent->addChild(std::move(empty));
    m_lastPreviewWidth = width;
    m_lastPreviewHeight = height;
    return;
  }

  const auto& entry = history[m_selectedIndex];
  if (m_clipboard != nullptr) {
    (void)m_clipboard->ensureEntryLoaded(m_selectedIndex);
  }
  const auto& loadedEntry = m_clipboard != nullptr ? m_clipboard->history()[m_selectedIndex] : entry;
  m_previewTitle->setText(previewTitle(loadedEntry));
  m_previewTitle->setMaxWidth(width);
  m_previewTitle->measure(renderer);
  m_previewMeta->setText(formatTimestamp(loadedEntry) + "  •  " + loadedEntry.dataMimeType + "  •  " +
                         formatBytes(loadedEntry.byteSize));
  m_previewMeta->setMaxWidth(width);
  m_previewMeta->measure(renderer);

  if (loadedEntry.isImage()) {
    auto image = std::make_unique<Image>();
    image->setSize(width, std::min(kPreviewImageHeight, std::max(180.0f, height - Style::spaceMd)));
    image->setCornerRadius(Style::radiusLg);
    image->setBackground(control_center::alphaSurfaceVariant(0.7f));
    image->setPadding(Style::spaceSm);
    image->setFit(ImageFit::Contain);
    image->setSourceBytes(renderer, loadedEntry.data.data(), loadedEntry.data.size());
    m_previewImage = image.get();
    m_previewContent->addChild(std::move(image));

    auto hint = std::make_unique<Label>();
    hint->setText("Press Enter or use the button above to copy this entry and promote it to the top.");
    hint->setCaptionStyle();
    hint->setColor(palette.onSurfaceVariant);
    hint->setMaxWidth(width);
    hint->measure(renderer);
    m_previewContent->addChild(std::move(hint));
  } else {
    auto card = std::make_unique<Flex>();
    card->setDirection(FlexDirection::Vertical);
    card->setAlign(FlexAlign::Start);
    card->setGap(Style::spaceXs);
    card->setPadding(Style::spaceMd);
    card->setRadius(Style::radiusLg);
    card->setBackground(control_center::alphaSurfaceVariant(0.7f));
    card->setBorderWidth(0.0f);
    card->setSoftness(1.0f);
    card->setMinWidth(width);

    std::string text(loadedEntry.data.begin(), loadedEntry.data.end());
    const auto lines = wrapLines(renderer, text, Style::fontSizeBody, std::max(0.0f, width - Style::spaceMd * 2.0f));
    if (lines.empty()) {
      auto empty = std::make_unique<Label>();
      empty->setText("(empty text payload)");
      empty->setColor(palette.onSurfaceVariant);
      empty->measure(renderer);
      card->addChild(std::move(empty));
    } else {
      for (const auto& line : lines) {
        auto label = std::make_unique<Label>();
        label->setText(line);
        label->setFontSize(Style::fontSizeBody);
        label->setColor(palette.onSurface);
        label->setMaxWidth(width - Style::spaceMd * 2.0f);
        label->measure(renderer);
        card->addChild(std::move(label));
      }
    }
    m_previewContent->addChild(std::move(card));
  }

  m_previewContent->layout(renderer);
  m_lastPreviewWidth = width;
  m_lastPreviewHeight = height;
}

void ClipboardPanel::selectIndex(std::size_t index) {
  if (m_clipboard == nullptr || index >= m_clipboard->history().size()) {
    return;
  }
  if (m_selectedIndex == index) {
    return;
  }
  m_selectedIndex = index;
  m_lastListWidth = -1.0f;
  m_lastPreviewWidth = -1.0f;
  PanelManager::instance().refresh();
  scrollToSelected();
}

void ClipboardPanel::activateSelected() {
  if (m_clipboard == nullptr || m_selectedIndex >= m_clipboard->history().size()) {
    return;
  }
  if (!m_clipboard->ensureEntryLoaded(m_selectedIndex)) {
    return;
  }
  const ClipboardEntry entry = m_clipboard->history()[m_selectedIndex];
  const bool promoted = m_clipboard->promoteEntry(m_selectedIndex);
  const bool copied = m_clipboard->copyEntry(entry);
  if (copied || promoted) {
    m_selectedIndex = 0;
    m_lastListWidth = -1.0f;
    m_lastPreviewWidth = -1.0f;
    PanelManager::instance().refresh();
  }
}

bool ClipboardPanel::handleKeyEvent(std::uint32_t sym, std::uint32_t /*modifiers*/) {
  if (m_clipboard == nullptr || m_clipboard->history().empty()) {
    return false;
  }

  if (sym == XKB_KEY_Up) {
    if (m_selectedIndex > 0) {
      --m_selectedIndex;
      m_lastListWidth = -1.0f;
      m_lastPreviewWidth = -1.0f;
      PanelManager::instance().refresh();
      scrollToSelected();
    }
    return true;
  }

  if (sym == XKB_KEY_Down) {
    if (m_selectedIndex + 1 < m_clipboard->history().size()) {
      ++m_selectedIndex;
      m_lastListWidth = -1.0f;
      m_lastPreviewWidth = -1.0f;
      PanelManager::instance().refresh();
      scrollToSelected();
    }
    return true;
  }

  if (sym == XKB_KEY_Return) {
    activateSelected();
    return true;
  }

  return false;
}

void ClipboardPanel::scrollToSelected() {
  if (m_listScrollView == nullptr || m_list == nullptr) {
    return;
  }

  const auto& children = m_list->children();
  if (m_selectedIndex >= children.size()) {
    return;
  }

  const auto* item = children[m_selectedIndex].get();
  const float itemTop = item->y();
  const float itemBottom = itemTop + item->height();
  constexpr float kScrollPadding = Style::spaceSm;
  const float viewportH = m_listScrollView->height() - kScrollPadding * 2.0f;
  const float scrollOffset = m_listScrollView->scrollOffset();

  if (itemTop < scrollOffset) {
    m_listScrollView->setScrollOffset(itemTop);
  } else if (itemBottom > scrollOffset + viewportH) {
    m_listScrollView->setScrollOffset(itemBottom - viewportH);
  }
}
