#include "shell/clipboard/clipboard_panel.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "core/process.h"
#include "core/ui_phase.h"
#include "i18n/i18n.h"
#include "render/core/async_texture_cache.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/control_center/tab.h"
#include "shell/panel/panel_manager.h"
#include "time/time_format.h"
#include "ui/controls/box.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/image.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/virtual_grid_view.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "util/string_utils.h"
#include "wayland/clipboard_service.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <ctime>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

  constexpr float kSidebarWidth = 272.0f;
  constexpr float kRowHeight = 46.0f;
  constexpr float kPreviewImageHeight = 280.0f;
  constexpr float kListGlyphSize = 24.0f;
  constexpr float kListThumbSize = 40.0f;
  constexpr std::size_t kListOverscanRows = 3;
  constexpr auto kPreviewPayloadDebounceInterval = std::chrono::milliseconds(75);
  constexpr auto kFilterDebounceInterval = std::chrono::milliseconds(120);
  constexpr Logger kLog("clipboard");

  void replaceAll(std::string& text, std::string_view needle, std::string_view replacement) {
    if (needle.empty()) {
      return;
    }

    std::size_t pos = 0;
    while ((pos = text.find(needle, pos)) != std::string::npos) {
      text.replace(pos, needle.size(), replacement);
      pos += replacement.size();
    }
  }

  std::string buildImageActionCommand(std::string command, std::string_view imagePath) {
    const bool hasPathPlaceholder = command.find("{path}") != std::string::npos;
    const bool hasStdinPlaceholder = command.find("{stdin}") != std::string::npos;
    const std::string quotedPath = StringUtils::shellQuote(imagePath);

    if (hasPathPlaceholder) {
      replaceAll(command, "{path}", quotedPath);
    }
    if (hasStdinPlaceholder) {
      replaceAll(command, "{stdin}", "-");
    }

    if (!hasPathPlaceholder || hasStdinPlaceholder) {
      return "cat -- " + quotedPath + " | " + command;
    }
    return command;
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
      return i18n::tr("clipboard.entry.image");
    }
    return entry.dataMimeType.empty() ? i18n::tr("clipboard.entry.title") : entry.dataMimeType;
  }

  std::string previewTitle(const ClipboardEntry& entry) {
    if (entry.isImage()) {
      return i18n::tr("clipboard.preview.image-title");
    }
    return i18n::tr("clipboard.preview.text-title");
  }

  class ClipboardListRow final : public InputArea {
  public:
    ClipboardListRow(float scale, ThumbnailService* thumbnails) : m_scale(scale), m_thumbnails(thumbnails) {
      setVisible(false);

      auto background = std::make_unique<Box>();
      background->setRadius(Style::scaledRadiusMd(scale));
      m_background = static_cast<Box*>(addChild(std::move(background)));

      auto row = std::make_unique<Flex>();
      row->setDirection(FlexDirection::Horizontal);
      row->setAlign(FlexAlign::Center);
      row->setGap(Style::spaceMd * scale);
      row->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
      m_row = static_cast<Flex*>(addChild(std::move(row)));

      auto lead = std::make_unique<Flex>();
      lead->setDirection(FlexDirection::Horizontal);
      lead->setAlign(FlexAlign::Center);
      lead->setJustify(FlexJustify::Center);
      m_lead = static_cast<Flex*>(m_row->addChild(std::move(lead)));

      auto image = std::make_unique<Image>();
      image->setFit(ImageFit::Cover);
      image->setRadius(Style::scaledRadiusSm(scale));
      image->setVisible(false);
      m_image = static_cast<Image*>(m_lead->addChild(std::move(image)));

      auto glyph = std::make_unique<Glyph>();
      glyph->setGlyphSize(kListGlyphSize * scale);
      m_glyph = static_cast<Glyph*>(m_lead->addChild(std::move(glyph)));

      auto textColumn = std::make_unique<Flex>();
      textColumn->setDirection(FlexDirection::Vertical);
      textColumn->setAlign(FlexAlign::Start);
      textColumn->setGap(Style::spaceXs * scale);
      textColumn->setFlexGrow(1.0f);
      m_textColumn = static_cast<Flex*>(m_row->addChild(std::move(textColumn)));

      auto title = std::make_unique<Label>();
      title->setFontSize(Style::fontSizeBody * scale);
      title->setBold(true);
      title->setMaxLines(1);
      title->setHitTestVisible(false);
      m_title = static_cast<Label*>(m_textColumn->addChild(std::move(title)));

      auto meta = std::make_unique<Label>();
      meta->setCaptionStyle();
      meta->setFontSize(Style::fontSizeCaption * scale);
      meta->setMaxLines(1);
      meta->setHitTestVisible(false);
      m_meta = static_cast<Label*>(m_textColumn->addChild(std::move(meta)));
    }

    ~ClipboardListRow() override { releaseThumbnail(); }

    void setThumbnailService(ThumbnailService* thumbnails) {
      if (m_thumbnails == thumbnails) {
        return;
      }
      releaseThumbnail();
      m_thumbnails = thumbnails;
    }

    void bind(Renderer& renderer, const ClipboardEntry& entry, std::size_t historyIndex, float width, bool selected,
              bool hovered) {
      m_historyIndex = historyIndex;
      m_selected = selected;
      m_hovered = hovered;
      m_isImage = entry.isImage();
      setVisible(true);
      setEnabled(true);
      setSize(width, kRowHeight * m_scale);

      const std::string nextThumbPath = m_isImage ? entry.payloadPath : std::string();
      if (m_thumbnailPath != nextThumbPath) {
        if (m_image != nullptr) {
          m_image->clear(renderer);
          m_image->setVisible(false);
        }
        releaseThumbnail();
        m_thumbnailPath = nextThumbPath;
        if (!m_thumbnailPath.empty() && m_thumbnails != nullptr) {
          (void)m_thumbnails->acquire(m_thumbnailPath);
        }
      }

      const std::string rawTitle = entryTitle(entry);
      m_title->setText(m_isImage ? rawTitle : collapseWhitespace(rawTitle));
      m_meta->setText(formatTimeAgo(entry.capturedAt) + "  •  " + formatBytes(entry.byteSize));

      if (m_glyph != nullptr) {
        m_glyph->setGlyph(m_isImage ? "photo" : "file-text");
      }
      refreshThumbnail(renderer);
      applyVisualState();
      layout(renderer);
    }

    void refreshThumbnail(Renderer& renderer) {
      if (m_image == nullptr || m_glyph == nullptr) {
        return;
      }
      if (!m_isImage || m_thumbnailPath.empty() || m_thumbnails == nullptr) {
        m_image->clear(renderer);
        m_image->setVisible(false);
        m_glyph->setVisible(true);
        return;
      }

      const TextureHandle handle = m_thumbnails->peek(m_thumbnailPath);
      if (handle.id == 0) {
        m_image->clear(renderer);
        m_image->setVisible(false);
        m_glyph->setVisible(true);
        return;
      }

      m_image->setExternalTexture(renderer, handle);
      m_image->setVisible(true);
      m_glyph->setVisible(false);
    }

  private:
    void doLayout(Renderer& renderer) override {
      const float thumbPx = kListThumbSize * m_scale;
      const float rowW = width();
      const float rowH = height();
      if (m_background != nullptr) {
        m_background->setPosition(0.0f, 0.0f);
        m_background->setSize(rowW, rowH);
      }
      if (m_row != nullptr) {
        m_row->setPosition(0.0f, 0.0f);
        m_row->setSize(rowW, rowH);
      }
      if (m_lead != nullptr) {
        m_lead->setSize(thumbPx, thumbPx);
        m_lead->setMinWidth(thumbPx);
        m_lead->setMinHeight(thumbPx);
      }
      if (m_image != nullptr) {
        m_image->setSize(thumbPx, thumbPx);
      }
      if (m_title != nullptr && m_meta != nullptr) {
        const float textWidth =
            std::max(0.0f, rowW - thumbPx - Style::spaceMd * m_scale - Style::spaceSm * m_scale * 2.0f);
        m_title->setMaxWidth(textWidth);
        m_meta->setMaxWidth(textWidth);
      }

      InputArea::doLayout(renderer);
    }

    void releaseThumbnail() {
      if (!m_thumbnailPath.empty() && m_thumbnails != nullptr) {
        m_thumbnails->release(m_thumbnailPath);
      }
      m_thumbnailPath.clear();
    }

    void applyVisualState() {
      if (m_background == nullptr || m_glyph == nullptr || m_title == nullptr || m_meta == nullptr) {
        return;
      }

      const Color bg = m_selected  ? colorForRole(ColorRole::SurfaceVariant)
                       : m_hovered ? colorForRole(ColorRole::SurfaceVariant, 0.45f)
                                   : clearColor();
      m_background->setFill(bg);
      m_glyph->setColor(colorSpecFromRole(m_isImage ? ColorRole::Secondary : ColorRole::Primary));
      m_title->setColor(colorSpecFromRole(ColorRole::OnSurface));
      m_meta->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    }

    float m_scale = 1.0f;
    ThumbnailService* m_thumbnails = nullptr;
    Box* m_background = nullptr;
    Flex* m_row = nullptr;
    Flex* m_lead = nullptr;
    Image* m_image = nullptr;
    Glyph* m_glyph = nullptr;
    Flex* m_textColumn = nullptr;
    Label* m_title = nullptr;
    Label* m_meta = nullptr;
    std::size_t m_historyIndex = static_cast<std::size_t>(-1);
    bool m_selected = false;
    bool m_hovered = false;
    bool m_isImage = false;
    std::string m_thumbnailPath;
  };

} // namespace

class ClipboardListAdapter final : public VirtualGridAdapter {
public:
  ClipboardListAdapter(float scale, ClipboardService* clipboard, ThumbnailService* thumbnails)
      : m_scale(scale), m_clipboard(clipboard), m_thumbnails(thumbnails) {}

  void setRenderer(Renderer* renderer) { m_renderer = renderer; }
  void setFilteredIndices(const std::vector<std::size_t>* indices) { m_filteredIndices = indices; }
  void setThumbnailService(ThumbnailService* thumbnails) {
    m_thumbnails = thumbnails;
    for (ClipboardListRow* row : m_pool) {
      if (row != nullptr) {
        row->setThumbnailService(thumbnails);
      }
    }
  }
  void setOnActivate(std::function<void(std::size_t)> callback) { m_onActivate = std::move(callback); }

  void refreshVisibleThumbnails(Renderer& renderer) {
    for (ClipboardListRow* row : m_pool) {
      if (row != nullptr && row->visible()) {
        row->refreshThumbnail(renderer);
      }
    }
  }

  [[nodiscard]] std::size_t itemCount() const override {
    return m_filteredIndices == nullptr ? 0 : m_filteredIndices->size();
  }

  [[nodiscard]] std::unique_ptr<Node> createTile() override {
    auto row = std::make_unique<ClipboardListRow>(m_scale, m_thumbnails);
    m_pool.push_back(row.get());
    return row;
  }

  void bindTile(Node& tile, std::size_t index, bool selected, bool hovered) override {
    if (m_renderer == nullptr || m_clipboard == nullptr || m_filteredIndices == nullptr ||
        index >= m_filteredIndices->size()) {
      return;
    }
    const std::size_t historyIndex = (*m_filteredIndices)[index];
    const auto& history = m_clipboard->history();
    if (historyIndex >= history.size()) {
      return;
    }
    auto* row = static_cast<ClipboardListRow*>(&tile);
    row->bind(*m_renderer, history[historyIndex], historyIndex, row->width(), selected, hovered && !selected);
  }

  void onActivate(std::size_t index) override {
    if (m_onActivate) {
      m_onActivate(index);
    }
  }

private:
  float m_scale = 1.0f;
  ClipboardService* m_clipboard = nullptr;
  ThumbnailService* m_thumbnails = nullptr;
  Renderer* m_renderer = nullptr;
  const std::vector<std::size_t>* m_filteredIndices = nullptr;
  std::vector<ClipboardListRow*> m_pool;
  std::function<void(std::size_t)> m_onActivate;
};

ClipboardPanel::ClipboardPanel(ClipboardService* clipboard, ConfigService* config, ThumbnailService* thumbnails,
                               AsyncTextureCache* asyncTextures)
    : m_clipboard(clipboard), m_config(config), m_thumbnails(thumbnails), m_asyncTextures(asyncTextures) {}

ClipboardPanel::~ClipboardPanel() = default;

bool ClipboardPanel::prefersAttachedToBar() const noexcept {
  return m_config != nullptr && m_config->config().shell.panel.attachClipboard;
}

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
  title->setColor(colorSpecFromRole(ColorRole::Primary));
  m_sidebarTitle = title.get();
  sidebarHeader->addChild(std::move(title));

  auto clearHistoryButton = std::make_unique<Button>();
  clearHistoryButton->setGlyph("trash");
  clearHistoryButton->setVariant(ButtonVariant::Destructive);
  clearHistoryButton->setGlyphSize(Style::fontSizeBody * scale);
  clearHistoryButton->setMinWidth(Style::controlHeightSm * scale);
  clearHistoryButton->setMinHeight(Style::controlHeightSm * scale);
  clearHistoryButton->setPadding(Style::spaceXs * scale);
  clearHistoryButton->setRadius(Style::scaledRadiusMd(scale));
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
  filterInput->setClearButtonEnabled(true);
  filterInput->setOnChange([this](const std::string& text) { onFilterChanged(text); });
  filterInput->setOnSubmit([this](const std::string& /*text*/) { activateSelected(); });
  filterInput->setOnKeyEvent(
      [this](std::uint32_t sym, std::uint32_t modifiers) { return handleKeyEvent(sym, modifiers); });
  m_filterInput = filterInput.get();
  sidebar->addChild(std::move(filterInput));

  m_listAdapter = std::make_unique<ClipboardListAdapter>(scale, m_clipboard, m_thumbnails);
  m_listAdapter->setFilteredIndices(&m_filteredIndices);
  m_listAdapter->setOnActivate([this](std::size_t index) {
    if (m_selectedIndex == index) {
      activateSelected();
      return;
    }
    selectIndex(index);
  });

  auto listGrid = std::make_unique<VirtualGridView>();
  listGrid->setColumns(1);
  listGrid->setSquareCells(false);
  listGrid->setCellHeight(kRowHeight * scale);
  listGrid->setRowGap(Style::spaceXs * scale);
  listGrid->setColumnGap(0.0f);
  listGrid->setOverscanRows(kListOverscanRows);
  listGrid->setFlexGrow(1.0f);
  listGrid->scrollView().setScrollbarVisible(true);
  listGrid->setAdapter(m_listAdapter.get());
  m_listGrid = static_cast<VirtualGridView*>(sidebar->addChild(std::move(listGrid)));

  auto listEmpty = std::make_unique<Label>();
  listEmpty->setCaptionStyle();
  listEmpty->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  listEmpty->setVisible(false);
  listEmpty->setParticipatesInLayout(false);
  m_listEmptyLabel = static_cast<Label*>(sidebar->addChild(std::move(listEmpty)));

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
  previewTitleLabel->setText(i18n::tr("clipboard.entry.title"));
  previewTitleLabel->setFontSize(Style::fontSizeTitle * scale);
  previewTitleLabel->setBold(true);
  previewTitleLabel->setColor(colorSpecFromRole(ColorRole::Primary));
  m_previewTitle = previewTitleLabel.get();
  previewTitleLabel->setFlexGrow(1.0f);
  previewHeader->addChild(std::move(previewTitleLabel));

  auto previewActions = std::make_unique<Flex>();
  previewActions->setDirection(FlexDirection::Horizontal);
  previewActions->setAlign(FlexAlign::Center);
  previewActions->setGap(Style::spaceXs * scale);

  auto imageActionButton = std::make_unique<Button>();
  imageActionButton->setGlyph("photo-edit");
  imageActionButton->setVariant(ButtonVariant::Secondary);
  imageActionButton->setGlyphSize(Style::fontSizeBody * scale);
  imageActionButton->setMinWidth(Style::controlHeightSm * scale);
  imageActionButton->setMinHeight(Style::controlHeightSm * scale);
  imageActionButton->setPadding(Style::spaceXs * scale);
  imageActionButton->setRadius(Style::scaledRadiusMd(scale));
  imageActionButton->setVisible(false);
  imageActionButton->setParticipatesInLayout(false);
  imageActionButton->setOnClick([this]() { runImageAction(); });
  m_imageActionButton = imageActionButton.get();
  previewActions->addChild(std::move(imageActionButton));

  auto copyButton = std::make_unique<Button>();
  copyButton->setGlyph("copy");
  copyButton->setVariant(ButtonVariant::Secondary);
  copyButton->setGlyphSize(Style::fontSizeBody * scale);
  copyButton->setMinWidth(Style::controlHeightSm * scale);
  copyButton->setMinHeight(Style::controlHeightSm * scale);
  copyButton->setPadding(Style::spaceXs * scale);
  copyButton->setRadius(Style::scaledRadiusMd(scale));
  copyButton->setOnClick([this]() { activateSelected(); });
  m_copyButton = copyButton.get();
  previewActions->addChild(std::move(copyButton));

  auto deleteEntryButton = std::make_unique<Button>();
  deleteEntryButton->setGlyph("trash");
  deleteEntryButton->setVariant(ButtonVariant::Destructive);
  deleteEntryButton->setGlyphSize(Style::fontSizeBody * scale);
  deleteEntryButton->setMinWidth(Style::controlHeightSm * scale);
  deleteEntryButton->setMinHeight(Style::controlHeightSm * scale);
  deleteEntryButton->setPadding(Style::spaceXs * scale);
  deleteEntryButton->setRadius(Style::scaledRadiusMd(scale));
  deleteEntryButton->setOnClick([this]() { deleteSelectedEntry(); });
  m_deleteEntryButton = deleteEntryButton.get();
  previewActions->addChild(std::move(deleteEntryButton));

  previewHeader->addChild(std::move(previewActions));
  preview->addChild(std::move(previewHeader));

  auto previewMetaLabel = std::make_unique<Label>();
  previewMetaLabel->setCaptionStyle();
  previewMetaLabel->setFontSize(Style::fontSizeCaption * scale);
  previewMetaLabel->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  m_previewMeta = previewMetaLabel.get();
  preview->addChild(std::move(previewMetaLabel));

  auto previewScroll = std::make_unique<ScrollView>();
  previewScroll->setScrollbarVisible(true);
  previewScroll->setCardStyle(scale, panelCardOpacity());
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

  if (m_thumbnails != nullptr) {
    m_thumbnailPendingSub = m_thumbnails->subscribePendingUpload([this]() {
      m_thumbnailRefreshPending = true;
      PanelManager::instance().requestUpdateOnly();
    });
  }

  schedulePreviewPayloadRefresh(false);
}

void ClipboardPanel::doLayout(Renderer& renderer, float width, float height) {
  if (m_rootLayout == nullptr || m_sidebar == nullptr || m_previewCard == nullptr || m_listGrid == nullptr ||
      m_previewScrollView == nullptr) {
    return;
  }

  m_lastWidth = width;
  m_lastHeight = height;

  const float sidebarWidth = std::min(kSidebarWidth, std::max(220.0f, width * 0.34f));
  m_sidebar->setSize(sidebarWidth, 0.0f);

  m_focusArea->setPosition(0.0f, 0.0f);
  m_focusArea->setSize(1.0f, 1.0f);

  if (m_listAdapter != nullptr) {
    m_listAdapter->setRenderer(&renderer);
  }

  // Flex layout handles all sizing: sidebar title is measured automatically,
  // listGrid fills remaining sidebar height (flexGrow), preview fills
  // remaining root width (flexGrow), previewScroll fills remaining preview
  // height (flexGrow). Stretch alignment propagates cross-axis sizes.
  m_rootLayout->setSize(width, height);
  m_rootLayout->layout(renderer);

  bool relayoutNeeded = false;
  const float previewScrollH = m_previewScrollView->height();
  if (m_lastPreviewWidth != m_previewScrollView->contentViewportWidth() || m_lastPreviewHeight != previewScrollH) {
    rebuildPreview(renderer, m_previewScrollView->contentViewportWidth(), previewScrollH);
    relayoutNeeded = true;
  }

  if (relayoutNeeded) {
    m_rootLayout->layout(renderer);
  }

  if (m_thumbnails != nullptr) {
    const bool changed = m_thumbnails->uploadPending(renderer.textureManager());
    if (changed) {
      m_thumbnailRefreshPending = false;
      if (m_listAdapter != nullptr) {
        m_listAdapter->setRenderer(&renderer);
        m_listAdapter->refreshVisibleThumbnails(renderer);
      }
    }
  }

  if (m_pendingScrollToSelected) {
    scrollToSelected();
    m_pendingScrollToSelected = false;
  }
}

void ClipboardPanel::doUpdate(Renderer& renderer) {
  if (m_thumbnailRefreshPending && m_thumbnails != nullptr) {
    const bool changed = m_thumbnails->uploadPending(renderer.textureManager());
    m_thumbnailRefreshPending = false;
    if (changed && m_listAdapter != nullptr) {
      m_listAdapter->setRenderer(&renderer);
      m_listAdapter->refreshVisibleThumbnails(renderer);
    }
  }

  updatePreviewActions();

  if (m_clipboard == nullptr || m_lastWidth <= 0.0f) {
    return;
  }

  if (m_lastChangeSerial != m_clipboard->changeSerial()) {
    applyFilter();
    if (m_filteredIndices.empty()) {
      m_selectedIndex = 0;
    } else if (m_selectedIndex >= m_filteredIndices.size()) {
      m_selectedIndex = m_filteredIndices.size() - 1;
    }

    m_lastChangeSerial = m_clipboard->changeSerial();
    updateListState();
    if (m_listGrid != nullptr) {
      m_listGrid->notifyDataChanged();
      m_listGrid->setSelectedIndex(m_filteredIndices.empty() ? std::nullopt
                                                             : std::optional<std::size_t>(m_selectedIndex));
    }

    schedulePreviewPayloadRefresh(false);
    const float previewWidth =
        m_previewScrollView != nullptr ? m_previewScrollView->contentViewportWidth() : m_lastWidth;
    const float previewHeight = m_previewScrollView != nullptr ? m_previewScrollView->height() : m_lastHeight;
    rebuildPreview(renderer, previewWidth, previewHeight);
  }
}

void ClipboardPanel::onOpen(std::string_view /*context*/) {
  m_selectedIndex = 0;
  m_previewPayloadIndex = static_cast<std::size_t>(-1);
  m_pendingPreviewPayloadIndex = static_cast<std::size_t>(-1);
  m_previewPayloadDebounceTimer.stop();
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
  updateListState();
  if (m_listGrid != nullptr) {
    m_listGrid->notifyDataChanged();
    m_listGrid->setSelectedIndex(m_filteredIndices.empty() ? std::nullopt
                                                           : std::optional<std::size_t>(m_selectedIndex));
    m_listGrid->scrollView().setScrollOffset(0.0f);
  }
  m_lastChangeSerial = m_clipboard != nullptr ? m_clipboard->changeSerial() : 0;
  schedulePreviewPayloadRefresh(false);
}

void ClipboardPanel::onClose() {
  m_thumbnailPendingSub.disconnect();
  if (m_listGrid != nullptr) {
    m_listGrid->setAdapter(nullptr);
  }
  m_listAdapter.reset();
  m_rootLayout = nullptr;
  m_focusArea = nullptr;
  m_sidebar = nullptr;
  m_sidebarHeaderRow = nullptr;
  m_sidebarTitle = nullptr;
  m_clearHistoryButton = nullptr;
  m_filterInput = nullptr;
  m_listGrid = nullptr;
  m_listEmptyLabel = nullptr;
  m_filteredIndices.clear();
  m_previewCard = nullptr;
  m_previewHeaderRow = nullptr;
  m_previewTitle = nullptr;
  m_previewMeta = nullptr;
  m_imageActionButton = nullptr;
  m_copyButton = nullptr;
  m_deleteEntryButton = nullptr;
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
  m_thumbnailRefreshPending = false;

  if (m_clipboard != nullptr) {
    m_clipboard->evictAllPayloads();
  }
  if (m_asyncTextures != nullptr) {
    DeferredCall::callLater([asyncTextures = m_asyncTextures]() { asyncTextures->trimUnused(0); });
  }
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

void ClipboardPanel::updateListState() {
  const auto& history = m_clipboard != nullptr ? m_clipboard->history() : std::deque<ClipboardEntry>{};
  const bool empty = history.empty() || m_filteredIndices.empty();

  if (m_listEmptyLabel != nullptr) {
    m_listEmptyLabel->setText(history.empty()         ? i18n::tr("clipboard.empty.history-title")
                              : m_filterQuery.empty() ? i18n::tr("clipboard.empty.history-title")
                                                      : i18n::tr("clipboard.empty.no-matches-title"));
    m_listEmptyLabel->setVisible(empty);
    m_listEmptyLabel->setParticipatesInLayout(empty);
  }
  if (m_listGrid != nullptr) {
    m_listGrid->setVisible(!empty);
    m_listGrid->setParticipatesInLayout(!empty);
  }
}

void ClipboardPanel::updatePreviewActions() {
  if (m_imageActionButton == nullptr) {
    return;
  }

  bool showImageAction = false;
  if (m_clipboard != nullptr && m_config != nullptr &&
      !StringUtils::trim(m_config->config().shell.clipboardImageActionCommand).empty()) {
    const std::size_t historyIndex = selectedHistoryIndex();
    const auto& history = m_clipboard->history();
    showImageAction = historyIndex != static_cast<std::size_t>(-1) && historyIndex < history.size() &&
                      history[historyIndex].isImage();
  }

  m_imageActionButton->setVisible(showImageAction);
  m_imageActionButton->setParticipatesInLayout(showImageAction);
  m_imageActionButton->setEnabled(showImageAction);
}

void ClipboardPanel::rebuildPreview(Renderer& renderer, float width, float height) {
  uiAssertNotRendering("ClipboardPanel::rebuildPreview");
  if (m_previewContent == nullptr || m_previewTitle == nullptr || m_previewMeta == nullptr) {
    return;
  }

  updatePreviewActions();

  while (!m_previewContent->children().empty()) {
    m_previewContent->removeChild(m_previewContent->children().front().get());
  }
  m_previewImage = nullptr;

  const auto& history = m_clipboard != nullptr ? m_clipboard->history() : std::deque<ClipboardEntry>{};
  const std::size_t historyIndex = selectedHistoryIndex();
  if (history.empty() || historyIndex == static_cast<std::size_t>(-1)) {
    m_previewTitle->setText(i18n::tr("clipboard.entry.title"));
    m_previewMeta->setText(history.empty() ? i18n::tr("clipboard.empty.history-message")
                                           : i18n::tr("clipboard.empty.no-matches-title"));

    auto empty = std::make_unique<Label>();
    empty->setText(history.empty() ? i18n::tr("clipboard.empty.history-message")
                                   : i18n::tr("clipboard.empty.no-matches-message"));
    empty->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
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
    pending->setText(i18n::tr("clipboard.preview.loading"));
    pending->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    pending->setMaxWidth(width);
    m_previewContent->addChild(std::move(pending));
    m_lastPreviewWidth = width;
    m_lastPreviewHeight = height;
    return;
  }

  if (m_clipboard != nullptr && m_previewPayloadIndex != static_cast<std::size_t>(-1) &&
      m_previewPayloadIndex != historyIndex) {
    m_clipboard->evictEntryPayload(m_previewPayloadIndex);
  }

  if (entry.isImage()) {
    auto image = std::make_unique<Image>();
    const float imageHeight = std::min(kPreviewImageHeight, std::max(180.0f, height - Style::spaceMd));
    image->setSize(width, imageHeight);
    image->setFit(ImageFit::Contain);
    const int previewTargetSize = static_cast<int>(std::ceil(std::max(width, imageHeight)));
    image->setAsyncReadyCallback([]() { PanelManager::instance().refresh(); });
    if (m_asyncTextures != nullptr && !entry.payloadPath.empty()) {
      (void)image->setSourceFileAsync(renderer, *m_asyncTextures, entry.payloadPath, previewTargetSize);
    }
    m_previewImage = image.get();
    m_previewContent->addChild(std::move(image));
  } else {
    if (m_clipboard != nullptr) {
      (void)m_clipboard->ensureEntryLoaded(historyIndex);
    }
    const auto& loadedEntry = m_clipboard != nullptr ? m_clipboard->history()[historyIndex] : entry;
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
      empty->setText(i18n::tr("clipboard.preview.empty-text-payload"));
      empty->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
      m_previewContent->addChild(std::move(empty));
    } else {
      auto label = std::make_unique<Label>();
      label->setText(expanded);
      label->setFontSize(Style::fontSizeBody);
      label->setColor(colorSpecFromRole(ColorRole::OnSurface));
      label->setMaxWidth(width);
      label->setMaxLines(kMaxPreviewLines);
      m_previewContent->addChild(std::move(label));
      if (truncated) {
        auto hint = std::make_unique<Label>();
        hint->setText(i18n::tr("clipboard.preview.truncated"));
        hint->setCaptionStyle();
        hint->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
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
    updateListState();
    if (m_listGrid != nullptr) {
      m_listGrid->notifyDataChanged();
      m_listGrid->setSelectedIndex(m_filteredIndices.empty() ? std::nullopt
                                                             : std::optional<std::size_t>(m_selectedIndex));
    }
    schedulePreviewPayloadRefresh(true);
    m_pendingScrollToSelected = true;
    PanelManager::instance().refresh();
  };

  m_filterDebounceTimer.start(kFilterDebounceInterval, commit);
}

void ClipboardPanel::selectIndex(std::size_t index) {
  if (m_clipboard == nullptr || index >= m_filteredIndices.size()) {
    return;
  }
  if (m_selectedIndex == index) {
    return;
  }
  m_selectedIndex = index;
  if (m_listGrid != nullptr) {
    m_listGrid->setSelectedIndex(index);
  }
  schedulePreviewPayloadRefresh(true);
  m_pendingScrollToSelected = true;
  PanelManager::instance().refresh();
}

void ClipboardPanel::deleteSelectedEntry() {
  if (m_clipboard == nullptr) {
    return;
  }
  const std::size_t historyIndex = selectedHistoryIndex();
  if (historyIndex == static_cast<std::size_t>(-1)) {
    return;
  }
  const std::size_t filterPos = m_selectedIndex;
  if (!m_clipboard->removeHistoryEntry(historyIndex)) {
    return;
  }
  applyFilter();
  if (m_filteredIndices.empty()) {
    m_selectedIndex = 0;
  } else {
    m_selectedIndex = std::min(filterPos, m_filteredIndices.size() - 1);
  }
  updateListState();
  if (m_listGrid != nullptr) {
    m_listGrid->notifyDataChanged();
    m_listGrid->setSelectedIndex(m_filteredIndices.empty() ? std::nullopt
                                                           : std::optional<std::size_t>(m_selectedIndex));
  }
  schedulePreviewPayloadRefresh(false);
  m_pendingScrollToSelected = true;
  PanelManager::instance().refresh();
}

void ClipboardPanel::runImageAction() {
  if (m_clipboard == nullptr || m_config == nullptr) {
    return;
  }

  const std::string configuredCommand = StringUtils::trim(m_config->config().shell.clipboardImageActionCommand);
  if (configuredCommand.empty()) {
    return;
  }

  const std::size_t historyIndex = selectedHistoryIndex();
  if (historyIndex == static_cast<std::size_t>(-1)) {
    return;
  }

  const auto& history = m_clipboard->history();
  if (historyIndex >= history.size() || !history[historyIndex].isImage()) {
    return;
  }

  const std::optional<std::string> exportedPath = m_clipboard->exportEntryForExternalTool(historyIndex);
  if (!exportedPath.has_value()) {
    kLog.warn("clipboard image action failed: selected image could not be exported");
    return;
  }

  const std::string command = buildImageActionCommand(configuredCommand, *exportedPath);
  if (!process::runAsync(command)) {
    kLog.warn("clipboard image action failed to launch: {}", configuredCommand);
  }
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
    updateListState();
    if (m_listGrid != nullptr) {
      m_listGrid->notifyDataChanged();
      m_listGrid->setSelectedIndex(m_filteredIndices.empty() ? std::nullopt
                                                             : std::optional<std::size_t>(m_selectedIndex));
    }
    schedulePreviewPayloadRefresh(false);
    PanelManager::instance().refresh();
  }
}

bool ClipboardPanel::handleKeyEvent(std::uint32_t sym, std::uint32_t modifiers) {
  if (m_clipboard == nullptr || m_filteredIndices.empty()) {
    return false;
  }

  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Up, sym, modifiers)) {
    if (m_selectedIndex > 0) {
      selectIndex(m_selectedIndex - 1);
    }
    return true;
  }

  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Down, sym, modifiers)) {
    if (m_selectedIndex + 1 < m_filteredIndices.size()) {
      selectIndex(m_selectedIndex + 1);
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
  if (m_listGrid == nullptr || m_selectedIndex >= m_filteredIndices.size()) {
    return;
  }
  m_listGrid->scrollToIndex(m_selectedIndex);
}
