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
#include "time/time_service.h"
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
constexpr float kRowHeight = 46.0f;
constexpr float kPreviewImageHeight = 280.0f;
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


std::string previewTitle(const ClipboardEntry& entry) {
  if (entry.isImage()) {
    return "Image Clipboard Entry";
  }
  return "Text Clipboard Entry";
}

} // namespace

ClipboardPanel::ClipboardPanel(ClipboardService* clipboard) : m_clipboard(clipboard) {}

void ClipboardPanel::create(Renderer& renderer) {
  const float scale = contentScale();
  auto root = std::make_unique<Flex>();
  root->setDirection(FlexDirection::Horizontal);
  root->setAlign(FlexAlign::Stretch);
  root->setGap(Style::spaceSm * scale);
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
  sidebar->setAlign(FlexAlign::Stretch);
  sidebar->setPadding(Style::spaceSm * scale);
  sidebar->setGap(Style::spaceSm * scale);
  m_sidebar = sidebar.get();

  auto sidebarHeader = std::make_unique<Flex>();
  sidebarHeader->setDirection(FlexDirection::Horizontal);
  sidebarHeader->setAlign(FlexAlign::Center);
  sidebarHeader->setJustify(FlexJustify::SpaceBetween);
  sidebarHeader->setGap(Style::spaceSm * scale);
  m_sidebarHeaderRow = sidebarHeader.get();

  auto title = std::make_unique<Label>();
  title->setText("Clipboard");
  title->setFontSize(Style::fontSizeTitle * scale);
  title->setBold(true);
  title->setColor(palette.primary);
  m_sidebarTitle = title.get();
  sidebarHeader->addChild(std::move(title));

  auto clearHistoryButton = std::make_unique<Button>();
  clearHistoryButton->setGlyph("trash");
  clearHistoryButton->setVariant(ButtonVariant::Destructive);
  clearHistoryButton->setGlyphSize(Style::fontSizeTitle * scale);
  clearHistoryButton->setMinWidth(Style::controlHeight * scale);
  clearHistoryButton->setMinHeight(Style::controlHeight * scale);
  clearHistoryButton->setPadding(Style::spaceSm * scale, Style::spaceSm * scale);
  clearHistoryButton->setRadius(Style::radiusMd * scale);
  clearHistoryButton->setOnClick([this]() {
    if (m_clipboard != nullptr) {
      m_clipboard->clearHistory();
    }
  });
  m_clearHistoryButton = clearHistoryButton.get();
  sidebarHeader->addChild(std::move(clearHistoryButton));
  sidebar->addChild(std::move(sidebarHeader));

  auto listScroll = std::make_unique<ScrollView>();
  listScroll->setScrollbarVisible(true);
  listScroll->setViewportPaddingH(0.0f);
  listScroll->setViewportPaddingV(0.0f);
  listScroll->setFlexGrow(1.0f);
  m_listScrollView = listScroll.get();
  m_list = listScroll->content();
  m_list->setDirection(FlexDirection::Vertical);
  m_list->setAlign(FlexAlign::Start);
  m_list->setGap(Style::spaceXs * scale);
  m_list->setPadding(Style::spaceXs * scale, 0.0f, 0.0f, 0.0f);
  sidebar->addChild(std::move(listScroll));

  root->addChild(std::move(sidebar));

  auto preview = std::make_unique<Flex>();
  preview->setDirection(FlexDirection::Vertical);
  preview->setAlign(FlexAlign::Stretch);
  preview->setGap(Style::spaceSm * scale);
  preview->setPadding(Style::spaceSm * scale);
  preview->setFlexGrow(1.0f);
  m_previewCard = preview.get();

  auto previewHeader = std::make_unique<Flex>();
  previewHeader->setDirection(FlexDirection::Horizontal);
  previewHeader->setAlign(FlexAlign::Center);
  previewHeader->setJustify(FlexJustify::SpaceBetween);
  previewHeader->setGap(Style::spaceSm * scale);
  m_previewHeaderRow = previewHeader.get();

  auto previewTitleLabel = std::make_unique<Label>();
  previewTitleLabel->setText("Clipboard entry");
  previewTitleLabel->setFontSize(Style::fontSizeTitle * scale);
  previewTitleLabel->setBold(true);
  previewTitleLabel->setColor(palette.primary);
  m_previewTitle = previewTitleLabel.get();
  previewTitleLabel->setFlexGrow(1.0f);
  previewHeader->addChild(std::move(previewTitleLabel));

  auto copyButton = std::make_unique<Button>();
  copyButton->setText("Copy Selected");
  copyButton->setGlyph("copy");
  copyButton->setVariant(ButtonVariant::Secondary);
  copyButton->setOnClick([this]() { activateSelected(); });
  m_copyButton = copyButton.get();
  previewHeader->addChild(std::move(copyButton));
  preview->addChild(std::move(previewHeader));

  auto previewMetaLabel = std::make_unique<Label>();
  previewMetaLabel->setCaptionStyle();
  previewMetaLabel->setFontSize(Style::fontSizeCaption * scale);
  previewMetaLabel->setColor(palette.onSurfaceVariant);
  m_previewMeta = previewMetaLabel.get();
  preview->addChild(std::move(previewMetaLabel));

  auto previewScroll = std::make_unique<ScrollView>();
  previewScroll->setScrollbarVisible(true);
  previewScroll->setBackgroundStyle(palette.surfaceVariant, palette.outline, Style::borderWidth);
  previewScroll->setFlexGrow(1.0f);
  m_previewScrollView = previewScroll.get();
  m_previewContent = previewScroll->content();
  m_previewContent->setDirection(FlexDirection::Vertical);
  m_previewContent->setAlign(FlexAlign::Start);
  m_previewContent->setGap(Style::spaceSm * scale);
  preview->addChild(std::move(previewScroll));

  root->addChild(std::move(preview));

  m_root = std::move(root);
  if (m_animations != nullptr) {
    m_root->setAnimationManager(m_animations);
  }

  rebuildList(renderer, scaled(kSidebarWidth) - Style::spaceSm * scale * 2.0f);
  rebuildPreview(renderer, preferredWidth() - scaled(kSidebarWidth) - Style::spaceSm * scale - Style::spaceSm * scale * 2.0f,
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
  m_sidebar->setSize(sidebarWidth, 0.0f);

  m_focusArea->setPosition(0.0f, 0.0f);
  m_focusArea->setSize(1.0f, 1.0f);

  // Flex layout handles all sizing: sidebar title is measured automatically,
  // listScroll fills remaining sidebar height (flexGrow), preview fills
  // remaining root width (flexGrow), previewScroll fills remaining preview
  // height (flexGrow). Stretch alignment propagates cross-axis sizes.
  m_rootLayout->setSize(width, height);
  m_rootLayout->layout(renderer);

  // Rebuild content if viewport dimensions changed.
  if (m_lastListWidth != m_listScrollView->contentViewportWidth() ||
      (m_clipboard != nullptr && m_lastChangeSerial != m_clipboard->changeSerial())) {
    rebuildList(renderer, m_listScrollView->contentViewportWidth());
  }

  const float previewScrollH = m_previewScrollView->height();
  if (m_lastPreviewWidth != m_previewScrollView->contentViewportWidth() ||
      m_lastPreviewHeight != previewScrollH) {
    rebuildPreview(renderer, m_previewScrollView->contentViewportWidth(), previewScrollH);
    m_rootLayout->layout(renderer);
  }
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
  m_hoverIndex = static_cast<std::size_t>(-1);
  m_mouseActive = false;
  m_lastListWidth = -1.0f;
  m_lastPreviewWidth = -1.0f;
  m_lastPreviewHeight = -1.0f;
}

void ClipboardPanel::onClose() {
  m_rootLayout = nullptr;
  m_focusArea = nullptr;
  m_sidebar = nullptr;
  m_sidebarHeaderRow = nullptr;
  m_sidebarTitle = nullptr;
  m_clearHistoryButton = nullptr;
  m_listScrollView = nullptr;
  m_list = nullptr;
  m_previewCard = nullptr;
  m_previewHeaderRow = nullptr;
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
    m_list->addChild(std::move(empty));
    m_lastChangeSerial = m_clipboard != nullptr ? m_clipboard->changeSerial() : 0;
    m_lastListWidth = width;
    return;
  }

  const float textWidth = std::max(0.0f, width - kListGlyphSize - Style::spaceMd - Style::spaceSm * 2.0f);
  for (std::size_t i = 0; i < history.size(); ++i) {
    const auto& entry = history[i];
    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Horizontal);
    row->setAlign(FlexAlign::Center);
    row->setGap(Style::spaceMd);
    row->setPadding(Style::spaceXs, Style::spaceSm,
                    Style::spaceXs, Style::spaceSm);
    row->setMinWidth(width);
    row->setMinHeight(kRowHeight);
    row->setRadius(Style::radiusMd);
    if (i == m_selectedIndex) {
      row->setBackground(palette.surfaceVariant);
    }

    auto* rowPtr = row.get();
    auto area = std::make_unique<InputArea>();
    area->setPropagateEvents(true);
    area->setOnClick([this, idx = i](const InputArea::PointerData& /*data*/) {
      if (m_selectedIndex == idx) {
        activateSelected();
        return;
      }
      selectIndex(idx);
    });
    area->setOnMotion([this, idx = i, rowPtr](const InputArea::PointerData& /*data*/) {
      if (!m_mouseActive) {
        m_mouseActive = true;
        if (idx != m_selectedIndex && m_hoverIndex != idx) {
          m_hoverIndex = idx;
          rowPtr->setBackground(
              rgba(palette.surfaceVariant.r, palette.surfaceVariant.g, palette.surfaceVariant.b, 0.45f));
          PanelManager::instance().refresh();
        }
      }
    });
    area->setOnEnter([this, idx = i, rowPtr](const InputArea::PointerData& /*data*/) {
      if (!m_mouseActive || idx == m_selectedIndex) {
        return;
      }
      m_hoverIndex = idx;
      rowPtr->setBackground(
          rgba(palette.surfaceVariant.r, palette.surfaceVariant.g, palette.surfaceVariant.b, 0.45f));
      PanelManager::instance().refresh();
    });
    area->setOnLeave([this, idx = i, rowPtr]() {
      if (m_hoverIndex != idx || idx == m_selectedIndex) {
        return;
      }
      m_hoverIndex = static_cast<std::size_t>(-1);
      rowPtr->setBackground(rgba(0, 0, 0, 0));
      PanelManager::instance().refresh();
    });

    auto glyph = std::make_unique<Glyph>();
    glyph->setGlyph(entry.isImage() ? "photo" : "file-text");
    glyph->setGlyphSize(kListGlyphSize);
    glyph->setColor(entry.isImage() ? palette.secondary : palette.primary);
    row->addChild(std::move(glyph));

    auto textColumn = std::make_unique<Flex>();
    textColumn->setDirection(FlexDirection::Vertical);
    textColumn->setAlign(FlexAlign::Start);
    textColumn->setGap(Style::spaceXs);

    const std::string rawTitle = entryTitle(entry);
    const std::string cleanTitle = entry.isImage() ? rawTitle : collapseWhitespace(rawTitle);
    auto title = std::make_unique<Label>();
    title->setText(truncateToWidth(renderer, cleanTitle, Style::fontSizeBody, textWidth, true));
    title->setFontSize(Style::fontSizeBody);
    title->setBold(true);
    title->setColor(palette.onSurface);
    title->setMaxWidth(textWidth);
    textColumn->addChild(std::move(title));

    auto timeLabel = std::make_unique<Label>();
    timeLabel->setText(formatTimeAgo(entry.capturedAt) + "  •  " + formatBytes(entry.byteSize));
    timeLabel->setCaptionStyle();
    timeLabel->setColor(palette.onSurfaceVariant);
    timeLabel->setMaxWidth(textWidth);
    textColumn->addChild(std::move(timeLabel));

    row->addChild(std::move(textColumn));

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

    auto empty = std::make_unique<Label>();
    empty->setText("Clipboard history is empty.");
    empty->setColor(palette.onSurfaceVariant);
    empty->setMaxWidth(width);
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
  m_previewMeta->setText(formatTimeAgo(loadedEntry.capturedAt) + "  •  " + formatBytes(loadedEntry.byteSize));
  m_previewMeta->setMaxWidth(width);

  if (loadedEntry.isImage()) {
    auto image = std::make_unique<Image>();
    image->setSize(width, std::min(kPreviewImageHeight, std::max(180.0f, height - Style::spaceMd)));
    image->setFit(ImageFit::Contain);
    image->setSourceBytes(renderer, loadedEntry.data.data(), loadedEntry.data.size());
    m_previewImage = image.get();
    m_previewContent->addChild(std::move(image));

    auto hint = std::make_unique<Label>();
    hint->setText("Press Enter or use the button above to copy this entry and promote it to the top.");
    hint->setCaptionStyle();
    hint->setColor(palette.onSurfaceVariant);
    hint->setMaxWidth(width);
    m_previewContent->addChild(std::move(hint));
  } else {
    constexpr std::size_t kMaxPreviewChars = 8000;
    constexpr std::size_t kMaxPreviewLines = 200;

    std::string text(loadedEntry.data.begin(), loadedEntry.data.end());
    bool truncated = text.size() > kMaxPreviewChars;
    if (truncated) {
      text.resize(kMaxPreviewChars);
    }

    // Split on newlines first to preserve line structure, then word-wrap each segment.
    std::vector<std::string> outputLines;
    std::size_t pos = 0;
    while (pos <= text.size() && outputLines.size() < kMaxPreviewLines) {
      const std::size_t nlPos = text.find('\n', pos);
      const std::string_view segment = (nlPos == std::string::npos)
                                           ? std::string_view(text).substr(pos)
                                           : std::string_view(text).substr(pos, nlPos - pos);
      if (segment.empty()) {
        outputLines.emplace_back(" ");
      } else {
        // Preserve leading whitespace (tabs → 4 spaces).
        std::string indent;
        std::size_t contentStart = 0;
        for (; contentStart < segment.size(); ++contentStart) {
          if (segment[contentStart] == '\t') {
            indent += "    ";
          } else if (segment[contentStart] == ' ') {
            indent += ' ';
          } else {
            break;
          }
        }
        const float indentWidth =
            indent.empty() ? 0.0f : renderer.measureText(indent, Style::fontSizeBody, false).width;
        const std::string_view content = segment.substr(contentStart);
        if (content.empty()) {
          outputLines.push_back(indent.empty() ? std::string(" ") : indent);
        } else {
          auto wrapped = wrapLines(renderer, content, Style::fontSizeBody,
                                   std::max(0.0f, width - indentWidth), kMaxPreviewLines - outputLines.size());
          bool first = true;
          for (auto& l : wrapped) {
            outputLines.push_back(first ? indent + l : std::move(l));
            first = false;
          }
        }
      }
      if (nlPos == std::string::npos) {
        break;
      }
      pos = nlPos + 1;
    }
    truncated = truncated || outputLines.size() >= kMaxPreviewLines;

    if (outputLines.empty()) {
      auto empty = std::make_unique<Label>();
      empty->setText("(empty text payload)");
      empty->setColor(palette.onSurfaceVariant);
      m_previewContent->addChild(std::move(empty));
    } else {
      for (const auto& line : outputLines) {
        auto label = std::make_unique<Label>();
        label->setText(line);
        label->setFontSize(Style::fontSizeBody);
        label->setColor(palette.onSurface);
        label->setMaxWidth(width);
        m_previewContent->addChild(std::move(label));
      }
      if (truncated) {
        auto hint = std::make_unique<Label>();
        hint->setText("… truncated");
        hint->setCaptionStyle();
        hint->setColor(palette.onSurfaceVariant);
        m_previewContent->addChild(std::move(hint));
      }
    }
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
