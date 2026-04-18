#include "shell/clipboard/clipboard_panel.h"

#include "config/config_service.h"
#include "core/ui_phase.h"
#include "i18n/i18n.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/control_center/tab.h"
#include "shell/panel/panel_manager.h"
#include "time/time_service.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/image.h"
#include "ui/controls/input.h"
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
  constexpr float kRowHeight = 46.0f;
  constexpr float kPreviewImageHeight = 280.0f;
  constexpr float kListGlyphSize = 24.0f;
  constexpr auto kPreviewPayloadDebounceInterval = std::chrono::milliseconds(75);
  constexpr auto kFilterDebounceInterval = std::chrono::milliseconds(120);

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
      return i18n::tr("clipboard.entry-image");
    }
    return entry.dataMimeType.empty() ? i18n::tr("clipboard.entry-title") : entry.dataMimeType;
  }

  std::string previewTitle(const ClipboardEntry& entry) {
    if (entry.isImage()) {
      return i18n::tr("clipboard.preview-image-title");
    }
    return i18n::tr("clipboard.preview-text-title");
  }

} // namespace

ClipboardPanel::ClipboardPanel(ClipboardService* clipboard, ConfigService* config)
    : m_clipboard(clipboard), m_config(config) {}

void ClipboardPanel::setActivateCallback(std::function<void(const ClipboardEntry&)> callback) {
  m_activateCallback = std::move(callback);
}

void ClipboardPanel::create() {
  const float scale = contentScale();
  auto rootLayout = std::make_unique<Flex>();
  rootLayout->setDirection(FlexDirection::Horizontal);
  rootLayout->setAlign(FlexAlign::Stretch);
  rootLayout->setGap(Style::spaceSm * scale);
  m_rootLayout = rootLayout.get();

  auto focusArea = std::make_unique<InputArea>();
  focusArea->setFocusable(true);
  focusArea->setVisible(false);
  focusArea->setOnKeyDown([this](const InputArea::KeyData& key) {
    if (key.pressed) {
      handleKeyEvent(key.sym, key.modifiers);
    }
  });
  m_focusArea = static_cast<InputArea*>(rootLayout->addChild(std::move(focusArea)));

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
  title->setText(i18n::tr("clipboard.title"));
  title->setFontSize(Style::fontSizeTitle * scale);
  title->setBold(true);
  title->setColor(roleColor(ColorRole::Primary));
  m_sidebarTitle = title.get();
  sidebarHeader->addChild(std::move(title));

  auto clearHistoryButton = std::make_unique<Button>();
  clearHistoryButton->setGlyph("trash");
  clearHistoryButton->setVariant(ButtonVariant::Destructive);
  clearHistoryButton->setGlyphSize(Style::fontSizeBody * scale);
  clearHistoryButton->setMinWidth(Style::controlHeightSm * scale);
  clearHistoryButton->setMinHeight(Style::controlHeightSm * scale);
  clearHistoryButton->setPadding(Style::spaceXs * scale);
  clearHistoryButton->setRadius(Style::radiusMd * scale);
  clearHistoryButton->setOnClick([this]() {
    if (m_clipboard != nullptr) {
      m_clipboard->clearHistory();
    }
  });
  m_clearHistoryButton = clearHistoryButton.get();
  sidebarHeader->addChild(std::move(clearHistoryButton));
  sidebar->addChild(std::move(sidebarHeader));

  auto filterInput = std::make_unique<Input>();
  filterInput->setPlaceholder(i18n::tr("clipboard.filter-placeholder"));
  filterInput->setFontSize(Style::fontSizeBody * scale);
  filterInput->setControlHeight(Style::controlHeight * scale);
  filterInput->setHorizontalPadding(Style::spaceMd * scale);
  filterInput->setOnChange([this](const std::string& text) { onFilterChanged(text); });
  filterInput->setOnSubmit([this](const std::string& /*text*/) { activateSelected(); });
  filterInput->setOnKeyEvent(
      [this](std::uint32_t sym, std::uint32_t modifiers) { return handleKeyEvent(sym, modifiers); });
  m_filterInput = filterInput.get();
  sidebar->addChild(std::move(filterInput));

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

  rootLayout->addChild(std::move(sidebar));

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
  previewTitleLabel->setText(i18n::tr("clipboard.entry-title"));
  previewTitleLabel->setFontSize(Style::fontSizeTitle * scale);
  previewTitleLabel->setBold(true);
  previewTitleLabel->setColor(roleColor(ColorRole::Primary));
  m_previewTitle = previewTitleLabel.get();
  previewTitleLabel->setFlexGrow(1.0f);
  previewHeader->addChild(std::move(previewTitleLabel));

  auto copyButton = std::make_unique<Button>();
  copyButton->setGlyph("copy");
  copyButton->setVariant(ButtonVariant::Secondary);
  copyButton->setGlyphSize(Style::fontSizeBody * scale);
  copyButton->setMinWidth(Style::controlHeightSm * scale);
  copyButton->setMinHeight(Style::controlHeightSm * scale);
  copyButton->setPadding(Style::spaceXs * scale);
  copyButton->setRadius(Style::radiusMd * scale);
  copyButton->setOnClick([this]() { activateSelected(); });
  m_copyButton = copyButton.get();
  previewHeader->addChild(std::move(copyButton));
  preview->addChild(std::move(previewHeader));

  auto previewMetaLabel = std::make_unique<Label>();
  previewMetaLabel->setCaptionStyle();
  previewMetaLabel->setFontSize(Style::fontSizeCaption * scale);
  previewMetaLabel->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_previewMeta = previewMetaLabel.get();
  preview->addChild(std::move(previewMetaLabel));

  auto previewScroll = std::make_unique<ScrollView>();
  previewScroll->setScrollbarVisible(true);
  previewScroll->setBackgroundRoles(ColorRole::SurfaceVariant, ColorRole::Outline, Style::borderWidth);
  previewScroll->setFlexGrow(1.0f);
  m_previewScrollView = previewScroll.get();
  m_previewContent = previewScroll->content();
  m_previewContent->setDirection(FlexDirection::Vertical);
  m_previewContent->setAlign(FlexAlign::Start);
  m_previewContent->setGap(Style::spaceSm * scale);
  preview->addChild(std::move(previewScroll));

  rootLayout->addChild(std::move(preview));

  setRoot(std::move(rootLayout));
  if (m_animations != nullptr) {
    root()->setAnimationManager(m_animations);
  }

  schedulePreviewPayloadRefresh(false);
}

void ClipboardPanel::doLayout(Renderer& renderer, float width, float height) {
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
  bool relayoutNeeded = false;
  if (m_lastListWidth != m_listScrollView->contentViewportWidth() ||
      (m_clipboard != nullptr && m_lastChangeSerial != m_clipboard->changeSerial())) {
    rebuildList(renderer, m_listScrollView->contentViewportWidth());
    relayoutNeeded = true;
  }

  const float previewScrollH = m_previewScrollView->height();
  if (m_lastPreviewWidth != m_previewScrollView->contentViewportWidth() || m_lastPreviewHeight != previewScrollH) {
    rebuildPreview(renderer, m_previewScrollView->contentViewportWidth(), previewScrollH);
    relayoutNeeded = true;
  }

  if (relayoutNeeded) {
    m_rootLayout->layout(renderer);
  }

  if (m_pendingScrollToSelected) {
    scrollToSelected();
    m_pendingScrollToSelected = false;
  }
}

void ClipboardPanel::doUpdate(Renderer& renderer) {
  if (m_clipboard == nullptr || m_lastWidth <= 0.0f) {
    return;
  }

  if (m_lastChangeSerial == m_clipboard->changeSerial()) {
    return;
  }

  applyFilter();
  if (m_filteredIndices.empty()) {
    m_selectedIndex = 0;
  } else if (m_selectedIndex >= m_filteredIndices.size()) {
    m_selectedIndex = m_filteredIndices.size() - 1;
  }

  schedulePreviewPayloadRefresh(false);
  const float listWidth = m_listScrollView != nullptr ? m_listScrollView->contentViewportWidth() : kSidebarWidth;
  const float previewWidth = m_previewScrollView != nullptr ? m_previewScrollView->contentViewportWidth() : m_lastWidth;
  const float previewHeight = m_previewScrollView != nullptr ? m_previewScrollView->height() : m_lastHeight;
  rebuildList(renderer, listWidth);
  rebuildPreview(renderer, previewWidth, previewHeight);
}

void ClipboardPanel::onOpen(std::string_view /*context*/) {
  m_selectedIndex = 0;
  m_previewPayloadIndex = static_cast<std::size_t>(-1);
  m_pendingPreviewPayloadIndex = static_cast<std::size_t>(-1);
  m_previewPayloadDebounceTimer.stop();
  m_hoverIndex = static_cast<std::size_t>(-1);
  m_mouseActive = false;
  m_lastListWidth = -1.0f;
  m_lastPreviewWidth = -1.0f;
  m_lastPreviewHeight = -1.0f;
  m_pendingScrollToSelected = false;
  m_filterQuery.clear();
  m_pendingFilterQuery.clear();
  m_filterDebounceTimer.stop();
  if (m_filterInput != nullptr) {
    m_filterInput->setValue("");
  }
  applyFilter();
  schedulePreviewPayloadRefresh(false);
}

void ClipboardPanel::onClose() {
  m_rootLayout = nullptr;
  m_focusArea = nullptr;
  m_sidebar = nullptr;
  m_sidebarHeaderRow = nullptr;
  m_sidebarTitle = nullptr;
  m_clearHistoryButton = nullptr;
  m_filterInput = nullptr;
  m_listScrollView = nullptr;
  m_list = nullptr;
  m_rowFlexes.clear();
  m_filteredIndices.clear();
  m_previewCard = nullptr;
  m_previewHeaderRow = nullptr;
  m_previewTitle = nullptr;
  m_previewMeta = nullptr;
  m_copyButton = nullptr;
  m_previewScrollView = nullptr;
  m_previewContent = nullptr;
  m_previewImage = nullptr;
  m_previewPayloadDebounceTimer.stop();
  m_filterDebounceTimer.stop();
  m_pendingFilterQuery.clear();
  m_filterQuery.clear();
  clearReleasedRoot();
  m_lastWidth = 0.0f;
  m_lastHeight = 0.0f;
  m_pendingScrollToSelected = false;
}

InputArea* ClipboardPanel::initialFocusArea() const {
  return m_filterInput != nullptr ? m_filterInput->inputArea() : m_focusArea;
}

void ClipboardPanel::schedulePreviewPayloadRefresh(bool debounced) {
  const std::size_t historyIndex = selectedHistoryIndex();
  if (m_clipboard == nullptr || historyIndex == static_cast<std::size_t>(-1)) {
    m_previewPayloadDebounceTimer.stop();
    m_previewPayloadIndex = static_cast<std::size_t>(-1);
    m_pendingPreviewPayloadIndex = static_cast<std::size_t>(-1);
    m_lastPreviewWidth = -1.0f;
    m_lastPreviewHeight = -1.0f;
    return;
  }

  if (!debounced || historyIndex == m_previewPayloadIndex) {
    m_previewPayloadDebounceTimer.stop();
    m_previewPayloadIndex = historyIndex;
    m_pendingPreviewPayloadIndex = static_cast<std::size_t>(-1);
    m_lastPreviewWidth = -1.0f;
    m_lastPreviewHeight = -1.0f;
    return;
  }

  m_pendingPreviewPayloadIndex = historyIndex;
  m_lastPreviewWidth = -1.0f;
  m_lastPreviewHeight = -1.0f;
  m_previewPayloadDebounceTimer.start(kPreviewPayloadDebounceInterval, [this]() {
    if (m_pendingPreviewPayloadIndex == static_cast<std::size_t>(-1)) {
      return;
    }
    m_previewPayloadIndex = m_pendingPreviewPayloadIndex;
    m_pendingPreviewPayloadIndex = static_cast<std::size_t>(-1);
    m_lastPreviewWidth = -1.0f;
    m_lastPreviewHeight = -1.0f;
    PanelManager::instance().refresh();
  });
}

void ClipboardPanel::rebuildList(Renderer& renderer, float width) {
  uiAssertNotRendering("ClipboardPanel::rebuildList");
  if (m_list == nullptr) {
    return;
  }

  const auto& history = m_clipboard != nullptr ? m_clipboard->history() : std::deque<ClipboardEntry>{};
  while (!m_list->children().empty()) {
    m_list->removeChild(m_list->children().front().get());
  }
  m_rowFlexes.clear();

  if (history.empty() || m_filteredIndices.empty()) {
    auto empty = std::make_unique<Label>();
    empty->setText(history.empty()         ? i18n::tr("clipboard.history-empty")
                   : m_filterQuery.empty() ? i18n::tr("clipboard.history-empty")
                                           : i18n::tr("clipboard.no-matching-entries"));
    empty->setCaptionStyle();
    empty->setColor(roleColor(ColorRole::OnSurfaceVariant));
    empty->setMaxWidth(width);
    m_list->addChild(std::move(empty));
    m_lastChangeSerial = m_clipboard != nullptr ? m_clipboard->changeSerial() : 0;
    m_lastListWidth = width;
    return;
  }

  const float textWidth = std::max(0.0f, width - kListGlyphSize - Style::spaceMd - Style::spaceSm * 2.0f);
  for (std::size_t i = 0; i < m_filteredIndices.size(); ++i) {
    const std::size_t historyIdx = m_filteredIndices[i];
    const auto& entry = history[historyIdx];
    auto row = std::make_unique<Flex>();
    row->setDirection(FlexDirection::Horizontal);
    row->setAlign(FlexAlign::Center);
    row->setGap(Style::spaceMd);
    row->setPadding(Style::spaceXs, Style::spaceSm, Style::spaceXs, Style::spaceSm);
    row->setSize(width, 0.0f);
    row->setFillParentMainAxis(true);
    row->setMinHeight(kRowHeight);
    row->setRadius(Style::radiusMd);
    if (i == m_selectedIndex) {
      row->setBackground(roleColor(ColorRole::SurfaceVariant));
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
          rowPtr->setBackground(roleColor(ColorRole::SurfaceVariant, 0.45f));
          PanelManager::instance().refresh();
        }
      }
    });
    area->setOnEnter([this, idx = i, rowPtr](const InputArea::PointerData& /*data*/) {
      if (!m_mouseActive || idx == m_selectedIndex) {
        return;
      }
      m_hoverIndex = idx;
      rowPtr->setBackground(roleColor(ColorRole::SurfaceVariant, 0.45f));
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
    glyph->setColor(roleColor(entry.isImage() ? ColorRole::Secondary : ColorRole::Primary));
    row->addChild(std::move(glyph));

    auto textColumn = std::make_unique<Flex>();
    textColumn->setDirection(FlexDirection::Vertical);
    textColumn->setAlign(FlexAlign::Start);
    textColumn->setGap(Style::spaceXs);

    const std::string rawTitle = entryTitle(entry);
    const std::string cleanTitle = entry.isImage() ? rawTitle : collapseWhitespace(rawTitle);
    auto title = std::make_unique<Label>();
    title->setText(cleanTitle);
    title->setFontSize(Style::fontSizeBody);
    title->setBold(true);
    title->setColor(roleColor(ColorRole::OnSurface));
    title->setMaxWidth(textWidth);
    title->setMaxLines(1);
    textColumn->addChild(std::move(title));

    auto timeLabel = std::make_unique<Label>();
    timeLabel->setText(formatTimeAgo(entry.capturedAt) + "  •  " + formatBytes(entry.byteSize));
    timeLabel->setCaptionStyle();
    timeLabel->setColor(roleColor(ColorRole::OnSurfaceVariant));
    timeLabel->setMaxWidth(textWidth);
    textColumn->addChild(std::move(timeLabel));

    row->addChild(std::move(textColumn));

    row->layout(renderer);
    area->setSize(row->width(), row->height());
    m_rowFlexes.push_back(rowPtr);
    area->addChild(std::move(row));
    m_list->addChild(std::move(area));
  }

  m_lastChangeSerial = m_clipboard != nullptr ? m_clipboard->changeSerial() : 0;
  m_lastListWidth = width;
}

void ClipboardPanel::rebuildPreview(Renderer& renderer, float width, float height) {
  uiAssertNotRendering("ClipboardPanel::rebuildPreview");
  if (m_previewContent == nullptr || m_previewTitle == nullptr || m_previewMeta == nullptr) {
    return;
  }

  while (!m_previewContent->children().empty()) {
    m_previewContent->removeChild(m_previewContent->children().front().get());
  }
  m_previewImage = nullptr;

  const auto& history = m_clipboard != nullptr ? m_clipboard->history() : std::deque<ClipboardEntry>{};
  const std::size_t historyIndex = selectedHistoryIndex();
  if (history.empty() || historyIndex == static_cast<std::size_t>(-1)) {
    m_previewTitle->setText(i18n::tr("clipboard.entry-title"));
    m_previewMeta->setText(history.empty() ? i18n::tr("clipboard.history-empty-sentence")
                                           : i18n::tr("clipboard.no-matching-entries"));

    auto empty = std::make_unique<Label>();
    empty->setText(history.empty() ? i18n::tr("clipboard.history-empty-sentence")
                                   : i18n::tr("clipboard.no-matching-entries-sentence"));
    empty->setColor(roleColor(ColorRole::OnSurfaceVariant));
    empty->setMaxWidth(width);
    m_previewContent->addChild(std::move(empty));
    m_lastPreviewWidth = width;
    m_lastPreviewHeight = height;
    return;
  }

  const auto& entry = history[historyIndex];
  m_previewTitle->setText(previewTitle(entry));
  m_previewTitle->setMaxWidth(width);
  m_previewMeta->setText(formatTimeAgo(entry.capturedAt) + "  •  " + formatBytes(entry.byteSize));
  m_previewMeta->setMaxWidth(width);

  if (m_previewPayloadIndex != historyIndex) {
    auto pending = std::make_unique<Label>();
    pending->setText(i18n::tr("clipboard.loading-preview"));
    pending->setColor(roleColor(ColorRole::OnSurfaceVariant));
    pending->setMaxWidth(width);
    m_previewContent->addChild(std::move(pending));
    m_lastPreviewWidth = width;
    m_lastPreviewHeight = height;
    return;
  }

  if (m_clipboard != nullptr) {
    (void)m_clipboard->ensureEntryLoaded(historyIndex);
  }
  const auto& loadedEntry = m_clipboard != nullptr ? m_clipboard->history()[historyIndex] : entry;

  if (loadedEntry.isImage()) {
    auto image = std::make_unique<Image>();
    image->setSize(width, std::min(kPreviewImageHeight, std::max(180.0f, height - Style::spaceMd)));
    image->setFit(ImageFit::Contain);
    image->setSourceBytes(renderer, loadedEntry.data.data(), loadedEntry.data.size());
    m_previewImage = image.get();
    m_previewContent->addChild(std::move(image));

    auto hint = std::make_unique<Label>();
    hint->setText(i18n::tr("clipboard.image-copy-hint"));
    hint->setCaptionStyle();
    hint->setColor(roleColor(ColorRole::OnSurfaceVariant));
    hint->setMaxWidth(width);
    m_previewContent->addChild(std::move(hint));
  } else {
    constexpr std::size_t kMaxPreviewChars = 8000;
    constexpr int kMaxPreviewLines = 200;

    std::string text(loadedEntry.data.begin(), loadedEntry.data.end());
    const bool truncated = text.size() > kMaxPreviewChars;
    if (truncated) {
      text.resize(kMaxPreviewChars);
    }

    // Expand tabs to 4 spaces once up front; Pango's natural wrapping then
    // handles everything else — newlines become paragraph breaks, each
    // paragraph's leading whitespace stays on its first line, continuations
    // have no indent, and the whole layout ellipsizes at kMaxPreviewLines.
    std::string expanded;
    expanded.reserve(text.size());
    for (char ch : text) {
      if (ch == '\t') {
        expanded.append("    ");
      } else {
        expanded.push_back(ch);
      }
    }

    if (expanded.empty()) {
      auto empty = std::make_unique<Label>();
      empty->setText(i18n::tr("clipboard.empty-text-payload"));
      empty->setColor(roleColor(ColorRole::OnSurfaceVariant));
      m_previewContent->addChild(std::move(empty));
    } else {
      auto label = std::make_unique<Label>();
      label->setText(expanded);
      label->setFontSize(Style::fontSizeBody);
      label->setColor(roleColor(ColorRole::OnSurface));
      label->setMaxWidth(width);
      label->setMaxLines(kMaxPreviewLines);
      m_previewContent->addChild(std::move(label));
      if (truncated) {
        auto hint = std::make_unique<Label>();
        hint->setText(i18n::tr("clipboard.truncated"));
        hint->setCaptionStyle();
        hint->setColor(roleColor(ColorRole::OnSurfaceVariant));
        m_previewContent->addChild(std::move(hint));
      }
    }
  }

  m_previewContent->layout(renderer);
  m_lastPreviewWidth = width;
  m_lastPreviewHeight = height;
}

std::size_t ClipboardPanel::selectedHistoryIndex() const {
  if (m_selectedIndex >= m_filteredIndices.size()) {
    return static_cast<std::size_t>(-1);
  }
  return m_filteredIndices[m_selectedIndex];
}

void ClipboardPanel::applyFilter() {
  m_filteredIndices.clear();
  if (m_clipboard == nullptr) {
    return;
  }
  const auto& history = m_clipboard->history();

  // Case-insensitive substring match on the entry title.
  std::string needle;
  needle.reserve(m_filterQuery.size());
  for (char ch : m_filterQuery) {
    needle.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(ch))));
  }

  m_filteredIndices.reserve(history.size());
  for (std::size_t i = 0; i < history.size(); ++i) {
    if (needle.empty()) {
      m_filteredIndices.push_back(i);
      continue;
    }
    std::string haystack = entryTitle(history[i]);
    for (char& ch : haystack) {
      ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    }
    if (haystack.find(needle) != std::string::npos) {
      m_filteredIndices.push_back(i);
    }
  }
}

void ClipboardPanel::onFilterChanged(const std::string& text) {
  if (text == m_pendingFilterQuery && text == m_filterQuery) {
    return;
  }
  m_pendingFilterQuery = text;

  auto commit = [this]() {
    if (m_pendingFilterQuery == m_filterQuery) {
      return;
    }
    m_filterQuery = m_pendingFilterQuery;
    applyFilter();
    m_selectedIndex = 0;
    m_hoverIndex = static_cast<std::size_t>(-1);
    m_mouseActive = false;
    schedulePreviewPayloadRefresh(true);
    m_lastListWidth = -1.0f;
    m_pendingScrollToSelected = true;
    PanelManager::instance().refresh();
  };

  m_filterDebounceTimer.start(kFilterDebounceInterval, commit);
}

void ClipboardPanel::updateRowSelection(std::size_t previousIndex) {
  if (previousIndex < m_rowFlexes.size() && m_rowFlexes[previousIndex] != nullptr) {
    Flex* prev = m_rowFlexes[previousIndex];
    if (m_hoverIndex == previousIndex) {
      prev->setBackground(roleColor(ColorRole::SurfaceVariant, 0.45f));
    } else {
      prev->setBackground(rgba(0, 0, 0, 0));
    }
  }
  if (m_selectedIndex < m_rowFlexes.size() && m_rowFlexes[m_selectedIndex] != nullptr) {
    m_rowFlexes[m_selectedIndex]->setBackground(roleColor(ColorRole::SurfaceVariant));
  }
}

void ClipboardPanel::selectIndex(std::size_t index) {
  if (m_clipboard == nullptr || index >= m_clipboard->history().size()) {
    return;
  }
  if (m_selectedIndex == index) {
    return;
  }
  const std::size_t previous = m_selectedIndex;
  m_selectedIndex = index;
  updateRowSelection(previous);
  schedulePreviewPayloadRefresh(true);
  m_pendingScrollToSelected = true;
  PanelManager::instance().refresh();
}

void ClipboardPanel::activateSelected() {
  if (m_clipboard == nullptr) {
    return;
  }
  const std::size_t historyIndex = selectedHistoryIndex();
  if (historyIndex == static_cast<std::size_t>(-1)) {
    return;
  }
  if (!m_clipboard->ensureEntryLoaded(historyIndex)) {
    return;
  }
  const ClipboardEntry entry = m_clipboard->history()[historyIndex];
  const bool promoted = m_clipboard->promoteEntry(historyIndex);
  const bool copied = m_clipboard->copyEntry(entry);
  if (copied || promoted) {
    if (m_activateCallback) {
      m_activateCallback(entry);
      return;
    }
    m_selectedIndex = 0;
    applyFilter();
    schedulePreviewPayloadRefresh(false);
    m_lastListWidth = -1.0f;
    PanelManager::instance().refresh();
  }
}

bool ClipboardPanel::handleKeyEvent(std::uint32_t sym, std::uint32_t modifiers) {
  if (m_clipboard == nullptr || m_filteredIndices.empty()) {
    return false;
  }

  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Up, sym, modifiers)) {
    if (m_selectedIndex > 0) {
      const std::size_t previous = m_selectedIndex;
      --m_selectedIndex;
      updateRowSelection(previous);
      schedulePreviewPayloadRefresh(true);
      m_pendingScrollToSelected = true;
      PanelManager::instance().refresh();
    }
    return true;
  }

  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Down, sym, modifiers)) {
    if (m_selectedIndex + 1 < m_filteredIndices.size()) {
      const std::size_t previous = m_selectedIndex;
      ++m_selectedIndex;
      updateRowSelection(previous);
      schedulePreviewPayloadRefresh(true);
      m_pendingScrollToSelected = true;
      PanelManager::instance().refresh();
    }
    return true;
  }

  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Validate, sym, modifiers)) {
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
