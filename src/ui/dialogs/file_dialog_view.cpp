#include "ui/dialogs/file_dialog_view.h"

#include "core/deferred_call.h"
#include "core/ui_phase.h"
#include "i18n/i18n.h"
#include "render/core/renderer.h"
#include "render/core/thumbnail_service.h"
#include "render/scene/input_area.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/separator.h"
#include "ui/controls/spacer.h"
#include "ui/dialogs/file_entry_row.h"
#include "ui/dialogs/file_entry_tile.h"
#include "ui/style.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdlib>
#include <memory>
#include <unordered_set>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

  constexpr std::uint32_t kModShift = 1u << 0;
  constexpr std::uint32_t kModCtrl = 1u << 1;
  constexpr std::size_t kListRowOverscan = 3;
  constexpr std::size_t kGridRowOverscan = 1;

  std::string lower(std::string_view text) {
    std::string out;
    out.reserve(text.size());
    for (char ch : text) {
      out.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(ch))));
    }
    return out;
  }

  std::size_t rowPoolCount(float viewportHeight, float itemHeight, std::size_t overscanRows) {
    const float safeHeight = std::max(itemHeight, 1.0f);
    return std::max<std::size_t>(1,
                                 static_cast<std::size_t>(std::ceil(viewportHeight / safeHeight)) + overscanRows * 2);
  }

  void configureDialogActionButton(Button& button, float scale) {
    button.setMinHeight(Style::controlHeight * scale);
    button.setMinWidth(92.0f * scale);
    button.setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
    button.setRadius(Style::radiusMd * scale);
  }

} // namespace

FileDialogView::FileDialogView(ThumbnailService* thumbnails) : m_thumbnails(thumbnails) {}

FileDialogView::~FileDialogView() = default;

void FileDialogView::create() {
  const float scale = contentScale();
  m_listRowHeight = std::ceil(32.0f * scale);
  m_gridCellWidth = 140.0f * scale;
  m_gridCellHeight = 140.0f * scale;

  const auto configureIconButton = [scale](Button* button) {
    if (button == nullptr) {
      return;
    }
    button->setVariant(ButtonVariant::Default);
    button->setGlyphSize(Style::fontSizeBody * scale);
    button->setMinWidth(Style::controlHeightSm * scale);
    button->setMinHeight(Style::controlHeightSm * scale);
    button->setPadding(Style::spaceXs * scale);
    button->setRadius(Style::radiusMd * scale);
  };

  auto root = std::make_unique<Flex>();
  root->setDirection(FlexDirection::Vertical);
  root->setAlign(FlexAlign::Stretch);
  root->setGap(Style::spaceSm * scale);
  root->setPadding(Style::spaceMd * scale);
  m_rootLayout = root.get();

  auto listFocus = std::make_unique<InputArea>();
  listFocus->setFocusable(true);
  listFocus->setVisible(false);
  listFocus->setParticipatesInLayout(false);
  m_listFocusArea = static_cast<InputArea*>(root->addChild(std::move(listFocus)));

  auto header = std::make_unique<Flex>();
  header->setDirection(FlexDirection::Horizontal);
  header->setAlign(FlexAlign::Center);
  header->setGap(Style::spaceSm * scale);

  auto title = std::make_unique<Label>();
  title->setFontSize(Style::fontSizeTitle * scale);
  title->setBold(true);
  title->setColor(roleColor(ColorRole::Primary));
  m_titleLabel = static_cast<Label*>(header->addChild(std::move(title)));

  header->addChild(std::make_unique<Spacer>());

  auto closeButton = std::make_unique<Button>();
  closeButton->setGlyph("close");
  configureIconButton(closeButton.get());
  closeButton->setOnClick([this]() { DeferredCall::callLater([this]() { cancelDialog(); }); });
  header->addChild(std::move(closeButton));
  root->addChild(std::move(header));

  auto breadcrumb = std::make_unique<Flex>();
  breadcrumb->setDirection(FlexDirection::Horizontal);
  breadcrumb->setAlign(FlexAlign::Center);
  breadcrumb->setGap(Style::spaceXs * scale);
  breadcrumb->setClipChildren(true);
  breadcrumb->setFillWidth(true);
  m_breadcrumbRow = breadcrumb.get();
  root->addChild(std::move(breadcrumb));

  auto toolbar = std::make_unique<Flex>();
  toolbar->setDirection(FlexDirection::Horizontal);
  toolbar->setAlign(FlexAlign::Center);
  toolbar->setGap(Style::spaceSm * scale);

  auto backButton = std::make_unique<Button>();
  backButton->setGlyph("arrow-back");
  configureIconButton(backButton.get());
  backButton->setOnClick([this]() { DeferredCall::callLater([this]() { navigateUp(); }); });
  m_backButton = static_cast<Button*>(toolbar->addChild(std::move(backButton)));

  auto searchInput = std::make_unique<Input>();
  searchInput->setPlaceholder(i18n::tr("ui.dialogs.file.filter-placeholder"));
  searchInput->setFontSize(Style::fontSizeBody * scale);
  searchInput->setControlHeight(Style::controlHeight * scale);
  searchInput->setHorizontalPadding(Style::spaceMd * scale);
  searchInput->setSize(320.0f * scale, 0.0f);
  searchInput->setFlexGrow(1.0f);
  searchInput->setOnChange([this](const std::string& text) {
    m_filterQuery = text;
    applyFilter(true);
  });
  searchInput->setOnSubmit([this](const std::string&) { activateSelection(); });
  m_searchInput = static_cast<Input*>(toolbar->addChild(std::move(searchInput)));

  toolbar->addChild(std::make_unique<Spacer>());

  auto sortLabel = std::make_unique<Label>();
  sortLabel->setFontSize(Style::fontSizeCaption * scale);
  m_sortLabel = static_cast<Label*>(toolbar->addChild(std::move(sortLabel)));

  auto hiddenToggle = std::make_unique<Button>();
  hiddenToggle->setGlyph("eye");
  hiddenToggle->setVariant(ButtonVariant::Tab);
  configureIconButton(hiddenToggle.get());
  hiddenToggle->setOnClick([this]() { DeferredCall::callLater([this]() { setShowHiddenFiles(!m_showHiddenFiles); }); });
  m_hiddenToggle = static_cast<Button*>(toolbar->addChild(std::move(hiddenToggle)));

  auto listToggle = std::make_unique<Button>();
  listToggle->setGlyph("list");
  listToggle->setVariant(ButtonVariant::Tab);
  configureIconButton(listToggle.get());
  listToggle->setOnClick([this]() { DeferredCall::callLater([this]() { setViewMode(ViewMode::List); }); });
  m_listToggle = static_cast<Button*>(toolbar->addChild(std::move(listToggle)));

  auto gridToggle = std::make_unique<Button>();
  gridToggle->setGlyph("layout-grid");
  gridToggle->setVariant(ButtonVariant::Tab);
  configureIconButton(gridToggle.get());
  gridToggle->setOnClick([this]() { DeferredCall::callLater([this]() { setViewMode(ViewMode::Grid); }); });
  m_gridToggle = static_cast<Button*>(toolbar->addChild(std::move(gridToggle)));

  root->addChild(std::move(toolbar));

  auto listContainer = std::make_unique<Flex>();
  listContainer->setDirection(FlexDirection::Vertical);
  listContainer->setAlign(FlexAlign::Stretch);
  listContainer->setGap(Style::spaceSm * scale);
  listContainer->setFlexGrow(1.0f);
  m_listContainer = listContainer.get();

  auto listHeader = std::make_unique<Flex>();
  listHeader->setDirection(FlexDirection::Horizontal);
  listHeader->setAlign(FlexAlign::Center);
  listHeader->setGap(Style::spaceSm * scale);

  const auto configureHeaderButton = [scale](Button* button) {
    button->setVariant(ButtonVariant::Ghost);
    button->setMinHeight(Style::controlHeightSm * scale);
    button->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
  };

  auto nameSort = std::make_unique<Button>();
  nameSort->setText(i18n::tr("ui.dialogs.file.sort.name"));
  configureHeaderButton(nameSort.get());
  nameSort->setContentAlign(ButtonContentAlign::Start);
  nameSort->setFlexGrow(1.0f);
  nameSort->setOnClick([this]() { DeferredCall::callLater([this]() { setSort(FileDialogSortField::Name); }); });
  m_nameSortButton = static_cast<Button*>(listHeader->addChild(std::move(nameSort)));

  auto sizeSort = std::make_unique<Button>();
  sizeSort->setText(i18n::tr("ui.dialogs.file.sort.size"));
  configureHeaderButton(sizeSort.get());
  sizeSort->setMinWidth(96.0f * scale);
  sizeSort->setContentAlign(ButtonContentAlign::End);
  sizeSort->setOnClick([this]() { DeferredCall::callLater([this]() { setSort(FileDialogSortField::Size); }); });
  m_sizeSortButton = static_cast<Button*>(listHeader->addChild(std::move(sizeSort)));

  auto dateSort = std::make_unique<Button>();
  dateSort->setText(i18n::tr("ui.dialogs.file.sort.date"));
  configureHeaderButton(dateSort.get());
  dateSort->setMinWidth(152.0f * scale);
  dateSort->setContentAlign(ButtonContentAlign::End);
  dateSort->setOnClick([this]() { DeferredCall::callLater([this]() { setSort(FileDialogSortField::Modified); }); });
  m_dateSortButton = static_cast<Button*>(listHeader->addChild(std::move(dateSort)));

  listContainer->addChild(std::move(listHeader));
  listContainer->addChild(std::make_unique<Separator>());

  auto listScroll = std::make_unique<ScrollView>();
  listScroll->setFlexGrow(1.0f);
  listScroll->setScrollbarVisible(true);
  listScroll->setCardStyle(scale);
  listScroll->setOnScrollChanged([this](float offset) {
    if (m_visibleEntries.empty() || m_listRowHeight <= 0.0f) {
      return;
    }
    const auto topIndex = static_cast<std::size_t>(std::floor(offset / m_listRowHeight));
    const auto startIndex = topIndex > kListRowOverscan ? topIndex - kListRowOverscan : 0;
    if (startIndex != m_rowPoolStartIndex) {
      m_dirty = true;
      requestLayout();
    }
  });
  m_listScrollView = listScroll.get();
  auto* listContent = listScroll->content();
  listContent->setDirection(FlexDirection::Vertical);
  listContent->setAlign(FlexAlign::Start);
  auto listRoot = std::make_unique<Node>();
  m_listRoot = listRoot.get();
  listContent->addChild(std::move(listRoot));
  auto listEmpty = std::make_unique<Label>();
  listEmpty->setCaptionStyle();
  listEmpty->setVisible(false);
  m_listEmptyLabel = static_cast<Label*>(m_listRoot->addChild(std::move(listEmpty)));
  listContainer->addChild(std::move(listScroll));
  root->addChild(std::move(listContainer));

  auto gridScroll = std::make_unique<ScrollView>();
  gridScroll->setFlexGrow(1.0f);
  gridScroll->setScrollbarVisible(true);
  gridScroll->setCardStyle(scale);
  gridScroll->setViewportPaddingH(0.0f);
  gridScroll->setVisible(false);
  gridScroll->setOnScrollChanged([this](float offset) {
    if (m_visibleEntries.empty()) {
      return;
    }
    const float pitch = m_gridCellHeight + Style::spaceSm * contentScale();
    const auto topRow = static_cast<std::size_t>(std::floor(offset / std::max(pitch, 1.0f)));
    const auto startRow = topRow > kGridRowOverscan ? topRow - kGridRowOverscan : 0;
    const std::size_t startIndex = startRow * std::max<std::size_t>(1, m_gridColumns);
    if (startIndex != m_tilePoolStartIndex) {
      m_dirty = true;
      requestLayout();
    }
  });
  m_gridScrollView = gridScroll.get();
  auto* gridContent = gridScroll->content();
  gridContent->setDirection(FlexDirection::Vertical);
  gridContent->setAlign(FlexAlign::Start);
  auto gridRoot = std::make_unique<Node>();
  m_gridRoot = gridRoot.get();
  gridContent->addChild(std::move(gridRoot));
  auto gridEmpty = std::make_unique<Label>();
  gridEmpty->setCaptionStyle();
  gridEmpty->setVisible(false);
  m_gridEmptyLabel = static_cast<Label*>(m_gridRoot->addChild(std::move(gridEmpty)));
  root->addChild(std::move(gridScroll));

  auto footer = std::make_unique<Flex>();
  footer->setDirection(FlexDirection::Horizontal);
  footer->setAlign(FlexAlign::Center);
  footer->setGap(Style::spaceSm * scale);

  auto filenameInput = std::make_unique<Input>();
  filenameInput->setPlaceholder(i18n::tr("ui.dialogs.file.filename-placeholder"));
  filenameInput->setFontSize(Style::fontSizeBody * scale);
  filenameInput->setControlHeight(Style::controlHeight * scale);
  filenameInput->setHorizontalPadding(Style::spaceMd * scale);
  filenameInput->setFlexGrow(1.0f);
  filenameInput->setOnChange([this](const std::string&) { updateControls(); });
  filenameInput->setOnSubmit([this](const std::string&) { submitDialog(); });
  m_filenameInput = static_cast<Input*>(footer->addChild(std::move(filenameInput)));

  footer->addChild(std::make_unique<Spacer>());

  auto cancelButton = std::make_unique<Button>();
  cancelButton->setText(i18n::tr("common.actions.cancel"));
  cancelButton->setVariant(ButtonVariant::Secondary);
  configureDialogActionButton(*cancelButton, scale);
  cancelButton->setOnClick([this]() { DeferredCall::callLater([this]() { cancelDialog(); }); });
  m_cancelButton = static_cast<Button*>(footer->addChild(std::move(cancelButton)));

  auto okButton = std::make_unique<Button>();
  okButton->setVariant(ButtonVariant::Accent);
  configureDialogActionButton(*okButton, scale);
  okButton->setOnClick([this]() { DeferredCall::callLater([this]() { submitDialog(); }); });
  m_okButton = static_cast<Button*>(footer->addChild(std::move(okButton)));

  root->addChild(std::move(footer));
  setRoot(std::move(root));

  if (m_animations != nullptr && this->root() != nullptr) {
    this->root()->setAnimationManager(m_animations);
  }

  if (m_thumbnails != nullptr) {
    m_thumbnails->setReadyCallback([this]() {
      m_thumbnailRefreshPending = true;
      requestUpdateOnly();
    });
  }
}

void FileDialogView::onOpen(std::string_view /*context*/) {
  m_options = FileDialog::currentOptions();
  m_currentDirectory = resolveStartDirectory(m_options.startDirectory);
  m_filterQuery.clear();
  m_viewMode = m_options.defaultViewMode == FileDialogViewMode::Grid ? ViewMode::Grid : ViewMode::List;
  m_sortField = FileDialogSortField::Name;
  m_sortOrder = FileDialogSortOrder::Ascending;
  m_showHiddenFiles = m_options.showHiddenFiles;
  m_selectedIndex = static_cast<std::size_t>(-1);
  m_hoverIndex = static_cast<std::size_t>(-1);
  m_rowPoolStartIndex = static_cast<std::size_t>(-1);
  m_tilePoolStartIndex = static_cast<std::size_t>(-1);
  m_lastListWidth = -1.0f;
  m_lastGridWidth = -1.0f;
  m_mouseActive = false;
  m_dirty = true;
  m_thumbnailRefreshPending = false;

  if (m_titleLabel != nullptr) {
    m_titleLabel->setText(m_options.title);
  }
  if (m_searchInput != nullptr) {
    m_searchInput->setValue("");
  }
  if (m_filenameInput != nullptr) {
    m_filenameInput->setValue(m_options.defaultFilename);
    const bool showFilename = m_options.mode != FileDialogMode::SelectFolder;
    m_filenameInput->setVisible(showFilename);
    m_filenameInput->inputArea()->setEnabled(m_options.mode == FileDialogMode::Save);
    m_filenameInput->inputArea()->setFocusable(m_options.mode == FileDialogMode::Save);
  }

  setViewMode(m_viewMode);
  refreshDirectory();
}

void FileDialogView::onClose() {
  if (m_thumbnails != nullptr) {
    m_thumbnails->releaseAll();
  }

  m_entries.clear();
  m_visibleEntries.clear();
  m_rowPool.clear();
  m_tilePool.clear();
  m_currentDirectory.clear();
  m_filterQuery.clear();
  m_selectedIndex = static_cast<std::size_t>(-1);
  m_hoverIndex = static_cast<std::size_t>(-1);
  m_rowPoolStartIndex = static_cast<std::size_t>(-1);
  m_tilePoolStartIndex = static_cast<std::size_t>(-1);
  m_rootLayout = nullptr;
  m_titleLabel = nullptr;
  m_breadcrumbRow = nullptr;
  m_homeButton = nullptr;
  m_backButton = nullptr;
  m_searchInput = nullptr;
  m_sortLabel = nullptr;
  m_hiddenToggle = nullptr;
  m_listToggle = nullptr;
  m_gridToggle = nullptr;
  m_listContainer = nullptr;
  m_nameSortButton = nullptr;
  m_sizeSortButton = nullptr;
  m_dateSortButton = nullptr;
  m_listScrollView = nullptr;
  m_listRoot = nullptr;
  m_listEmptyLabel = nullptr;
  m_gridScrollView = nullptr;
  m_gridRoot = nullptr;
  m_gridEmptyLabel = nullptr;
  m_filenameInput = nullptr;
  m_cancelButton = nullptr;
  m_okButton = nullptr;
  m_listFocusArea = nullptr;
  clearReleasedRoot();
}

InputArea* FileDialogView::initialFocusArea() const {
  if (m_options.mode == FileDialogMode::Save && m_filenameInput != nullptr) {
    return m_filenameInput->inputArea();
  }
  return m_searchInput != nullptr ? m_searchInput->inputArea() : m_listFocusArea;
}

void FileDialogView::doLayout(Renderer& renderer, float width, float height) {
  if (m_rootLayout == nullptr) {
    return;
  }

  m_lastWidth = width;
  m_rootLayout->setSize(width, height);
  m_rootLayout->layout(renderer);

  bool relayoutNeeded = false;
  if (m_dirty || (m_listScrollView != nullptr && m_lastListWidth != m_listScrollView->contentViewportWidth()) ||
      (m_gridScrollView != nullptr && m_lastGridWidth != m_gridScrollView->contentViewportWidth())) {
    rebuildVisibleEntries(renderer);
    m_dirty = false;
    relayoutNeeded = true;
  }

  if (relayoutNeeded) {
    m_rootLayout->layout(renderer);

    const bool listWidthChanged =
        m_listScrollView != nullptr && std::abs(m_lastListWidth - m_listScrollView->contentViewportWidth()) >= 0.5f;
    const bool gridWidthChanged =
        m_gridScrollView != nullptr && std::abs(m_lastGridWidth - m_gridScrollView->contentViewportWidth()) >= 0.5f;
    if (listWidthChanged || gridWidthChanged) {
      rebuildVisibleEntries(renderer);
      m_rootLayout->layout(renderer);
    }
  }
}

void FileDialogView::doUpdate(Renderer& renderer) {
  if (!m_thumbnailRefreshPending || m_thumbnails == nullptr) {
    return;
  }

  m_thumbnails->uploadPending(renderer.textureManager());
  m_thumbnailRefreshPending = false;
  refreshVisibleTileThumbnails(renderer);
}

bool FileDialogView::handleGlobalKey(std::uint32_t sym, std::uint32_t modifiers, bool pressed, bool preedit) {
  if (!pressed || preedit) {
    return false;
  }

  if ((modifiers & kModCtrl) != 0 && (sym == XKB_KEY_l || sym == XKB_KEY_L)) {
    focusSearch();
    return true;
  }

  if (sym == XKB_KEY_Tab) {
    cycleFocus((modifiers & kModShift) != 0);
    return true;
  }

  if (sym == XKB_KEY_Escape) {
    cancelDialog();
    return true;
  }

  if (sym == XKB_KEY_BackSpace && !isTextInputFocused()) {
    navigateUp();
    return true;
  }

  if (m_visibleEntries.empty()) {
    if (sym == XKB_KEY_Return || sym == XKB_KEY_KP_Enter) {
      if (m_options.mode == FileDialogMode::SelectFolder) {
        submitDialog();
        return true;
      }
    }
    return false;
  }

  if (sym == XKB_KEY_Return || sym == XKB_KEY_KP_Enter) {
    if (!isTextInputFocused() || hostFocusedArea() == m_listFocusArea) {
      activateSelection();
      return true;
    }
    return false;
  }

  InputArea* focused = hostFocusedArea();
  const bool filenameFocused = m_filenameInput != nullptr && focused == m_filenameInput->inputArea();
  if (filenameFocused) {
    return false;
  }

  auto moveSelection = [this](int delta) {
    if (m_visibleEntries.empty()) {
      return;
    }
    if (m_selectedIndex == static_cast<std::size_t>(-1)) {
      selectIndex(firstSelectableIndex());
      return;
    }

    int next = static_cast<int>(m_selectedIndex) + delta;
    while (next >= 0 && next < static_cast<int>(m_visibleEntries.size())) {
      if (isSelectableIndex(static_cast<std::size_t>(next))) {
        selectIndex(static_cast<std::size_t>(next));
        return;
      }
      next += delta > 0 ? 1 : -1;
    }
  };

  if (sym == XKB_KEY_Up) {
    moveSelection(m_viewMode == ViewMode::Grid ? -static_cast<int>(m_gridColumns) : -1);
    return true;
  }
  if (sym == XKB_KEY_Down) {
    moveSelection(m_viewMode == ViewMode::Grid ? static_cast<int>(m_gridColumns) : 1);
    return true;
  }
  if (m_viewMode == ViewMode::Grid && sym == XKB_KEY_Left) {
    moveSelection(-1);
    return true;
  }
  if (m_viewMode == ViewMode::Grid && sym == XKB_KEY_Right) {
    moveSelection(1);
    return true;
  }

  return false;
}

void FileDialogView::refreshDirectory() {
  if (m_thumbnails != nullptr) {
    m_thumbnails->releaseAll();
  }
  m_entries = m_scanner.scan(m_currentDirectory, m_options.extensions, m_showHiddenFiles, m_sortField, m_sortOrder);
  rebuildBreadcrumb();
  applyFilter(true);
}

void FileDialogView::applyFilter(bool resetScroll) {
  const std::filesystem::path preserved = selectedPath();
  const std::string query = lower(m_filterQuery);

  m_visibleEntries.clear();
  for (const auto& entry : m_entries) {
    if (!query.empty() && lower(entry.name).find(query) == std::string::npos) {
      continue;
    }
    m_visibleEntries.push_back(entry);
  }

  m_selectedIndex = static_cast<std::size_t>(-1);
  if (!preserved.empty()) {
    for (std::size_t i = 0; i < m_visibleEntries.size(); ++i) {
      if (m_visibleEntries[i].absPath == preserved && isSelectableIndex(i)) {
        m_selectedIndex = i;
        break;
      }
    }
  }
  if (m_selectedIndex == static_cast<std::size_t>(-1)) {
    m_selectedIndex = firstSelectableIndex();
  }

  m_hoverIndex = static_cast<std::size_t>(-1);
  m_mouseActive = false;
  m_rowPoolStartIndex = static_cast<std::size_t>(-1);
  m_tilePoolStartIndex = static_cast<std::size_t>(-1);
  if (resetScroll) {
    if (m_listScrollView != nullptr) {
      m_listScrollView->setScrollOffset(0.0f);
    }
    if (m_gridScrollView != nullptr) {
      m_gridScrollView->setScrollOffset(0.0f);
    }
  }
  updateFilenameFieldFromSelection();
  updateControls();
  m_dirty = true;
  if (root() != nullptr) {
    root()->markLayoutDirty();
  }
  requestLayout();
}

void FileDialogView::rebuildBreadcrumb() {
  if (m_breadcrumbRow == nullptr) {
    return;
  }

  while (!m_breadcrumbRow->children().empty()) {
    m_breadcrumbRow->removeChild(m_breadcrumbRow->children().back().get());
  }

  const float scale = contentScale();

  auto home = std::make_unique<Button>();
  home->setGlyph("home");
  home->setVariant(ButtonVariant::Ghost);
  home->setPadding(Style::spaceXs * scale);
  home->setMinHeight(Style::controlHeightSm * scale);
  home->setOnClick([this]() { DeferredCall::callLater([this]() { navigateHome(); }); });
  m_homeButton = static_cast<Button*>(m_breadcrumbRow->addChild(std::move(home)));

  std::filesystem::path partial("/");
  for (const auto& component : m_currentDirectory.relative_path()) {
    auto sep = std::make_unique<Label>();
    sep->setText("/");
    sep->setFontSize(Style::fontSizeCaption * scale);
    m_breadcrumbRow->addChild(std::move(sep));

    partial /= component;
    auto segment = std::make_unique<Button>();
    segment->setText(component.string());
    segment->setVariant(ButtonVariant::Ghost);
    segment->setPadding(Style::spaceXs * scale);
    const auto target = partial;
    segment->setOnClick([this, target]() { DeferredCall::callLater([this, target]() { navigateInto(target); }); });
    m_breadcrumbRow->addChild(std::move(segment));
  }
}

void FileDialogView::rebuildVisibleEntries(Renderer& renderer) {
  if (m_listScrollView != nullptr && m_listContainer != nullptr && m_listContainer->visible()) {
    rebuildList(renderer, m_listScrollView->contentViewportWidth());
  }
  if (m_gridScrollView != nullptr && m_gridScrollView->visible()) {
    rebuildGrid(renderer, m_gridScrollView->contentViewportWidth());
  }
  updateVisibleStates();
}

void FileDialogView::rebuildList(Renderer& renderer, float width) {
  if (m_listRoot == nullptr || m_listEmptyLabel == nullptr || m_listScrollView == nullptr) {
    return;
  }

  const float viewportHeight = std::max(0.0f, m_listScrollView->height() - Style::spaceSm * contentScale() * 2.0f);
  ensureRowPool(viewportHeight);

  if (m_visibleEntries.empty()) {
    m_listEmptyLabel->setVisible(true);
    m_listEmptyLabel->setText(i18n::tr("ui.dialogs.file.empty-filtered"));
    m_listEmptyLabel->measure(renderer);
    m_listEmptyLabel->setPosition(0.0f, 0.0f);
    m_listRoot->setSize(width, m_listEmptyLabel->height());
    for (auto* rowArea : m_rowPool) {
      static_cast<FileEntryRow*>(rowArea)->clear();
    }
    m_lastListWidth = width;
    return;
  }

  m_listEmptyLabel->setVisible(false);
  m_listRoot->setSize(width, m_listRowHeight * static_cast<float>(m_visibleEntries.size()));

  const auto topIndex =
      std::min(static_cast<std::size_t>(std::floor(m_listScrollView->scrollOffset() / m_listRowHeight)),
               m_visibleEntries.size() - 1);
  const auto startIndex = topIndex > kListRowOverscan ? topIndex - kListRowOverscan : 0;
  m_rowPoolStartIndex = startIndex;

  for (std::size_t slot = 0; slot < m_rowPool.size(); ++slot) {
    auto* row = static_cast<FileEntryRow*>(m_rowPool[slot]);
    const std::size_t visibleIndex = startIndex + slot;
    if (visibleIndex < m_visibleEntries.size()) {
      row->setPosition(0.0f, static_cast<float>(visibleIndex) * m_listRowHeight);
      row->bind(renderer, m_visibleEntries[visibleIndex], visibleIndex, width, visibleIndex == m_selectedIndex,
                m_mouseActive && visibleIndex == m_hoverIndex && visibleIndex != m_selectedIndex,
                !isSelectableIndex(visibleIndex));
    } else {
      row->clear();
    }
  }

  m_lastListWidth = width;
}

void FileDialogView::rebuildGrid(Renderer& renderer, float width) {
  if (m_gridRoot == nullptr || m_gridEmptyLabel == nullptr || m_gridScrollView == nullptr) {
    return;
  }

  const float gap = Style::spaceSm * contentScale();
  const std::size_t columns =
      std::max<std::size_t>(1, static_cast<std::size_t>(std::floor((width + gap) / (m_gridCellWidth + gap))));
  m_gridColumns = columns;
  const float pitch = m_gridCellHeight + gap;
  const float viewportHeight = std::max(0.0f, m_gridScrollView->height() - Style::spaceSm * contentScale() * 2.0f);
  ensureTilePool(viewportHeight, columns);

  if (m_visibleEntries.empty()) {
    m_gridEmptyLabel->setVisible(true);
    m_gridEmptyLabel->setText(i18n::tr("ui.dialogs.file.empty-filtered"));
    m_gridEmptyLabel->measure(renderer);
    m_gridEmptyLabel->setPosition(0.0f, 0.0f);
    m_gridRoot->setSize(width, m_gridEmptyLabel->height());
    std::unordered_set<std::string> releasedPaths;
    for (auto* tileArea : m_tilePool) {
      if (std::string released = static_cast<FileEntryTile*>(tileArea)->clear(renderer); !released.empty()) {
        releasedPaths.insert(std::move(released));
      }
    }
    if (m_thumbnails != nullptr) {
      for (const auto& path : releasedPaths) {
        m_thumbnails->release(path);
      }
    }
    m_lastGridWidth = width;
    return;
  }

  m_gridEmptyLabel->setVisible(false);
  const std::size_t rows = (m_visibleEntries.size() + columns - 1) / columns;
  m_gridRoot->setSize(width, rows > 0 ? static_cast<float>(rows) * pitch - gap : 0.0f);

  const auto topRow = static_cast<std::size_t>(std::floor(m_gridScrollView->scrollOffset() / std::max(pitch, 1.0f)));
  const auto startRow = topRow > kGridRowOverscan ? topRow - kGridRowOverscan : 0;
  const auto startIndex = startRow * columns;
  m_tilePoolStartIndex = startIndex;

  std::unordered_set<std::string> releasedPaths;
  std::unordered_set<std::string> retainedPaths;
  retainedPaths.reserve(m_tilePool.size());

  for (std::size_t slot = 0; slot < m_tilePool.size(); ++slot) {
    auto* tile = static_cast<FileEntryTile*>(m_tilePool[slot]);
    const std::size_t visibleIndex = startIndex + slot;
    if (visibleIndex < m_visibleEntries.size()) {
      const std::size_t col = visibleIndex % columns;
      const std::size_t row = visibleIndex / columns;
      tile->setPosition(static_cast<float>(col) * (m_gridCellWidth + gap), static_cast<float>(row) * pitch);
      if (std::string released =
              tile->bind(renderer, m_visibleEntries[visibleIndex], visibleIndex, m_gridCellWidth, m_gridCellHeight,
                         visibleIndex == m_selectedIndex,
                         m_mouseActive && visibleIndex == m_hoverIndex && visibleIndex != m_selectedIndex,
                         !isSelectableIndex(visibleIndex));
          !released.empty()) {
        releasedPaths.insert(std::move(released));
      }
      if (!tile->thumbnailPath().empty()) {
        retainedPaths.insert(tile->thumbnailPath());
      }
    } else {
      if (std::string released = tile->clear(renderer); !released.empty()) {
        releasedPaths.insert(std::move(released));
      }
    }
  }

  if (m_thumbnails != nullptr) {
    for (const auto& path : releasedPaths) {
      if (!retainedPaths.contains(path)) {
        m_thumbnails->release(path);
      }
    }
  }

  m_lastGridWidth = width;
}

void FileDialogView::ensureRowPool(float viewportHeight) {
  if (m_listRoot == nullptr) {
    return;
  }

  const std::size_t desired = rowPoolCount(viewportHeight, m_listRowHeight, kListRowOverscan);
  if (m_rowPool.size() == desired) {
    return;
  }

  for (auto* rowArea : m_rowPool) {
    m_listRoot->removeChild(rowArea);
  }
  m_rowPool.clear();

  const float scale = contentScale();
  for (std::size_t i = 0; i < desired; ++i) {
    auto row = std::make_unique<FileEntryRow>(scale);
    row->setCallbacks(
        [this](std::size_t index) { DeferredCall::callLater([this, index]() { handleEntryClick(index); }); },
        [this](std::size_t index) {
          if (!m_mouseActive) {
            m_mouseActive = true;
          }
          if (index != m_selectedIndex && m_hoverIndex != index) {
            m_hoverIndex = index;
            updateVisibleStates();
            requestRedraw();
          }
        },
        [this](std::size_t index) {
          if (!m_mouseActive || index == m_selectedIndex || m_hoverIndex == index) {
            return;
          }
          m_hoverIndex = index;
          updateVisibleStates();
          requestRedraw();
        },
        [this](std::size_t index) {
          if (m_hoverIndex != index || index == m_selectedIndex) {
            return;
          }
          m_hoverIndex = static_cast<std::size_t>(-1);
          updateVisibleStates();
          requestRedraw();
        });
    m_rowPool.push_back(static_cast<InputArea*>(m_listRoot->addChild(std::move(row))));
  }
}

void FileDialogView::ensureTilePool(float viewportHeight, std::size_t columns) {
  if (m_gridRoot == nullptr) {
    return;
  }

  const float pitch = m_gridCellHeight + Style::spaceSm * contentScale();
  const std::size_t visibleRows = rowPoolCount(viewportHeight, pitch, kGridRowOverscan);
  const std::size_t desired = std::max<std::size_t>(1, visibleRows * columns);
  if (m_tilePool.size() == desired) {
    return;
  }

  for (auto* tileArea : m_tilePool) {
    m_gridRoot->removeChild(tileArea);
  }
  m_tilePool.clear();

  const float scale = contentScale();
  for (std::size_t i = 0; i < desired; ++i) {
    auto tile = std::make_unique<FileEntryTile>(scale, m_thumbnails);
    tile->setCallbacks(
        [this](std::size_t index) { DeferredCall::callLater([this, index]() { handleEntryClick(index); }); },
        [this](std::size_t index) {
          if (!m_mouseActive) {
            m_mouseActive = true;
          }
          if (index != m_selectedIndex && m_hoverIndex != index) {
            m_hoverIndex = index;
            updateVisibleStates();
            requestRedraw();
          }
        },
        [this](std::size_t index) {
          if (!m_mouseActive || index == m_selectedIndex || m_hoverIndex == index) {
            return;
          }
          m_hoverIndex = index;
          updateVisibleStates();
          requestRedraw();
        },
        [this](std::size_t index) {
          if (m_hoverIndex != index || index == m_selectedIndex) {
            return;
          }
          m_hoverIndex = static_cast<std::size_t>(-1);
          updateVisibleStates();
          requestRedraw();
        });
    m_tilePool.push_back(static_cast<InputArea*>(m_gridRoot->addChild(std::move(tile))));
  }
}

void FileDialogView::refreshVisibleTileThumbnails(Renderer& renderer) {
  if (m_viewMode != ViewMode::Grid) {
    return;
  }
  for (auto* tileArea : m_tilePool) {
    auto* tile = static_cast<FileEntryTile*>(tileArea);
    if (tile->boundIndex() != static_cast<std::size_t>(-1)) {
      tile->refreshThumbnail(renderer);
    }
  }
  requestRedraw();
}

void FileDialogView::updateVisibleStates() {
  for (auto* rowArea : m_rowPool) {
    auto* row = static_cast<FileEntryRow*>(rowArea);
    const std::size_t index = row->boundIndex();
    if (index == static_cast<std::size_t>(-1)) {
      continue;
    }
    row->setVisualState(index == m_selectedIndex, m_mouseActive && index == m_hoverIndex && index != m_selectedIndex,
                        !isSelectableIndex(index));
  }
  for (auto* tileArea : m_tilePool) {
    auto* tile = static_cast<FileEntryTile*>(tileArea);
    const std::size_t index = tile->boundIndex();
    if (index == static_cast<std::size_t>(-1)) {
      continue;
    }
    tile->setVisualState(index == m_selectedIndex, m_mouseActive && index == m_hoverIndex && index != m_selectedIndex,
                         !isSelectableIndex(index));
  }
}

void FileDialogView::updateControls() {
  std::string okText = i18n::tr("ui.dialogs.file.actions.open");
  switch (m_options.mode) {
  case FileDialogMode::Open:
    okText = i18n::tr("ui.dialogs.file.actions.open");
    break;
  case FileDialogMode::Save:
    okText = i18n::tr("ui.dialogs.file.actions.save");
    break;
  case FileDialogMode::SelectFolder:
    okText = i18n::tr("ui.dialogs.file.actions.select-folder");
    break;
  }

  if (m_okButton != nullptr) {
    m_okButton->setText(okText);
    bool enabled = false;
    if (m_options.mode == FileDialogMode::Open) {
      enabled = m_selectedIndex < m_visibleEntries.size() && !m_visibleEntries[m_selectedIndex].isDir;
    } else if (m_options.mode == FileDialogMode::Save) {
      enabled = m_filenameInput != nullptr && !m_filenameInput->value().empty();
    } else {
      enabled = true;
    }
    m_okButton->setEnabled(enabled);
  }

  if (m_backButton != nullptr) {
    m_backButton->setEnabled(m_currentDirectory.has_parent_path() &&
                             m_currentDirectory != m_currentDirectory.root_path());
  }
  if (m_hiddenToggle != nullptr) {
    m_hiddenToggle->setSelected(m_showHiddenFiles);
  }
  if (m_listToggle != nullptr) {
    m_listToggle->setSelected(m_viewMode == ViewMode::List);
  }
  if (m_gridToggle != nullptr) {
    m_gridToggle->setSelected(m_viewMode == ViewMode::Grid);
  }

  if (m_sortLabel != nullptr) {
    std::string field = i18n::tr("ui.dialogs.file.sort.name");
    switch (m_sortField) {
    case FileDialogSortField::Name:
      field = i18n::tr("ui.dialogs.file.sort.name");
      break;
    case FileDialogSortField::Size:
      field = i18n::tr("ui.dialogs.file.sort.size");
      break;
    case FileDialogSortField::Modified:
      field = i18n::tr("ui.dialogs.file.sort.date");
      break;
    }
    m_sortLabel->setText(i18n::tr("ui.dialogs.file.sort.summary", "field", field, "direction",
                                  m_sortOrder == FileDialogSortOrder::Ascending
                                      ? i18n::tr("ui.dialogs.file.sort.ascending")
                                      : i18n::tr("ui.dialogs.file.sort.descending")));
  }

  if (m_listContainer != nullptr) {
    m_listContainer->setVisible(m_viewMode == ViewMode::List);
  }
  if (m_gridScrollView != nullptr) {
    m_gridScrollView->setVisible(m_viewMode == ViewMode::Grid);
  }
}

void FileDialogView::setShowHiddenFiles(bool show) {
  if (m_showHiddenFiles == show) {
    return;
  }

  m_showHiddenFiles = show;
  refreshDirectory();
}

void FileDialogView::updateFilenameFieldFromSelection() {
  if (m_filenameInput == nullptr || m_options.mode == FileDialogMode::SelectFolder) {
    return;
  }

  if (m_options.mode == FileDialogMode::Open) {
    if (m_selectedIndex < m_visibleEntries.size()) {
      m_filenameInput->setValue(m_visibleEntries[m_selectedIndex].name);
    } else {
      m_filenameInput->setValue("");
    }
    return;
  }

  if (m_selectedIndex < m_visibleEntries.size() && !m_visibleEntries[m_selectedIndex].isDir) {
    m_filenameInput->setValue(m_visibleEntries[m_selectedIndex].name);
  }
}

void FileDialogView::setViewMode(ViewMode mode) {
  if (m_viewMode == mode) {
    updateControls();
    return;
  }
  m_viewMode = mode;
  updateControls();
  ensureSelectionVisible();
  m_dirty = true;
  requestLayout();
}

void FileDialogView::setSort(FileDialogSortField field) {
  if (m_sortField == field) {
    m_sortOrder = m_sortOrder == FileDialogSortOrder::Ascending ? FileDialogSortOrder::Descending
                                                                : FileDialogSortOrder::Ascending;
  } else {
    m_sortField = field;
    m_sortOrder = FileDialogSortOrder::Ascending;
  }
  refreshDirectory();
}

void FileDialogView::navigateInto(const std::filesystem::path& path) {
  std::error_code ec;
  if (path.empty() || !std::filesystem::exists(path, ec) || ec || !std::filesystem::is_directory(path, ec) || ec) {
    return;
  }
  m_currentDirectory = path;
  refreshDirectory();
}

void FileDialogView::navigateUp() {
  if (!m_currentDirectory.has_parent_path()) {
    return;
  }
  const std::filesystem::path parent = m_currentDirectory.parent_path();
  if (parent.empty() || parent == m_currentDirectory) {
    return;
  }
  navigateInto(parent);
}

void FileDialogView::navigateHome() { navigateInto(homeDirectory()); }

void FileDialogView::selectIndex(std::size_t index) {
  if (index >= m_visibleEntries.size() || !isSelectableIndex(index)) {
    return;
  }
  m_selectedIndex = index;
  m_hoverIndex = static_cast<std::size_t>(-1);
  updateFilenameFieldFromSelection();
  updateControls();
  updateVisibleStates();
  focusList();
  ensureSelectionVisible();
  requestRedraw();
}

void FileDialogView::handleEntryClick(std::size_t index) {
  if (index >= m_visibleEntries.size()) {
    return;
  }

  const FileEntry& entry = m_visibleEntries[index];
  if (entry.isDir) {
    if (m_options.mode == FileDialogMode::SelectFolder) {
      if (m_selectedIndex == index) {
        navigateInto(entry.absPath);
      } else {
        selectIndex(index);
      }
    } else {
      navigateInto(entry.absPath);
    }
    return;
  }

  if (!isSelectableIndex(index)) {
    return;
  }

  if (m_selectedIndex == index) {
    if (m_options.mode == FileDialogMode::Save) {
      updateFilenameFieldFromSelection();
    }
    submitDialog();
    return;
  }

  selectIndex(index);
}

void FileDialogView::activateSelection() {
  if (m_selectedIndex >= m_visibleEntries.size()) {
    if (m_options.mode == FileDialogMode::SelectFolder) {
      submitDialog();
    }
    return;
  }

  const FileEntry& entry = m_visibleEntries[m_selectedIndex];
  if (entry.isDir) {
    if (m_options.mode == FileDialogMode::SelectFolder) {
      submitDialog();
    } else {
      navigateInto(entry.absPath);
    }
    return;
  }

  if (m_options.mode == FileDialogMode::SelectFolder) {
    return;
  }
  submitDialog();
}

void FileDialogView::submitDialog() {
  if (m_options.mode == FileDialogMode::Open) {
    if (m_selectedIndex >= m_visibleEntries.size() || m_visibleEntries[m_selectedIndex].isDir) {
      return;
    }
    acceptDialog(m_visibleEntries[m_selectedIndex].absPath);
    return;
  }

  if (m_options.mode == FileDialogMode::Save) {
    if (m_filenameInput == nullptr || m_filenameInput->value().empty()) {
      return;
    }
    acceptDialog(m_currentDirectory / m_filenameInput->value());
    return;
  }

  if (m_selectedIndex < m_visibleEntries.size() && m_visibleEntries[m_selectedIndex].isDir) {
    acceptDialog(m_visibleEntries[m_selectedIndex].absPath);
  } else {
    acceptDialog(m_currentDirectory);
  }
}

void FileDialogView::focusSearch() {
  if (m_searchInput != nullptr) {
    focusHostArea(m_searchInput->inputArea());
  }
}

void FileDialogView::focusList() {
  if (m_listFocusArea != nullptr) {
    focusHostArea(m_listFocusArea);
  }
}

void FileDialogView::focusFilename() {
  if (m_options.mode == FileDialogMode::Save && m_filenameInput != nullptr) {
    focusHostArea(m_filenameInput->inputArea());
  }
}

void FileDialogView::cycleFocus(bool reverse) {
  std::vector<InputArea*> order;
  if (m_searchInput != nullptr) {
    order.push_back(m_searchInput->inputArea());
  }
  if (m_listFocusArea != nullptr) {
    order.push_back(m_listFocusArea);
  }
  if (m_options.mode == FileDialogMode::Save && m_filenameInput != nullptr) {
    order.push_back(m_filenameInput->inputArea());
  }
  if (order.empty()) {
    return;
  }

  InputArea* current = hostFocusedArea();
  auto it = std::find(order.begin(), order.end(), current);
  std::size_t index = it == order.end() ? 0 : static_cast<std::size_t>(std::distance(order.begin(), it));
  if (reverse) {
    index = index == 0 ? order.size() - 1 : index - 1;
  } else {
    index = (index + 1) % order.size();
  }
  focusHostArea(order[index]);
}

void FileDialogView::ensureSelectionVisible() {
  if (m_selectedIndex >= m_visibleEntries.size()) {
    return;
  }

  if (m_viewMode == ViewMode::List && m_listScrollView != nullptr && m_listRowHeight > 0.0f) {
    const float top = static_cast<float>(m_selectedIndex) * m_listRowHeight;
    const float bottom = top + m_listRowHeight;
    const float viewport = m_listScrollView->height() - Style::spaceSm * contentScale() * 2.0f;
    const float offset = m_listScrollView->scrollOffset();
    if (top < offset) {
      m_listScrollView->setScrollOffset(top);
    } else if (bottom > offset + viewport) {
      m_listScrollView->setScrollOffset(bottom - viewport);
    }
    m_dirty = true;
    requestLayout();
    return;
  }

  if (m_viewMode == ViewMode::Grid && m_gridScrollView != nullptr && m_gridColumns > 0) {
    const float gap = Style::spaceSm * contentScale();
    const float pitch = m_gridCellHeight + gap;
    const std::size_t row = m_selectedIndex / m_gridColumns;
    const float top = static_cast<float>(row) * pitch;
    const float bottom = top + m_gridCellHeight;
    const float viewport = m_gridScrollView->height() - Style::spaceSm * contentScale() * 2.0f;
    const float offset = m_gridScrollView->scrollOffset();
    if (top < offset) {
      m_gridScrollView->setScrollOffset(top);
    } else if (bottom > offset + viewport) {
      m_gridScrollView->setScrollOffset(bottom - viewport);
    }
    m_dirty = true;
    requestLayout();
  }
}

std::size_t FileDialogView::firstSelectableIndex() const {
  for (std::size_t i = 0; i < m_visibleEntries.size(); ++i) {
    if (isSelectableIndex(i)) {
      return i;
    }
  }
  return static_cast<std::size_t>(-1);
}

bool FileDialogView::isSelectableIndex(std::size_t index) const {
  if (index >= m_visibleEntries.size()) {
    return false;
  }
  if (m_options.mode == FileDialogMode::SelectFolder) {
    return m_visibleEntries[index].isDir;
  }
  return true;
}

bool FileDialogView::isTextInputFocused() const {
  InputArea* focused = hostFocusedArea();
  if (m_searchInput != nullptr && focused == m_searchInput->inputArea()) {
    return true;
  }
  if (m_filenameInput != nullptr && focused == m_filenameInput->inputArea()) {
    return true;
  }
  return false;
}

std::filesystem::path FileDialogView::selectedPath() const {
  if (m_selectedIndex < m_visibleEntries.size()) {
    return m_visibleEntries[m_selectedIndex].absPath;
  }
  return {};
}

std::filesystem::path FileDialogView::homeDirectory() const {
  if (const char* home = std::getenv("HOME"); home != nullptr && home[0] != '\0') {
    return std::filesystem::path(home);
  }
  return std::filesystem::current_path();
}

std::filesystem::path FileDialogView::resolveStartDirectory(const std::filesystem::path& preferred) const {
  std::error_code ec;
  if (!preferred.empty() && std::filesystem::exists(preferred, ec) && !ec &&
      std::filesystem::is_directory(preferred, ec) && !ec) {
    return preferred;
  }

  const std::filesystem::path home = homeDirectory();
  if (std::filesystem::exists(home, ec) && !ec && std::filesystem::is_directory(home, ec) && !ec) {
    return home;
  }
  return std::filesystem::current_path();
}

void FileDialogView::requestUpdateOnly() {
  if (m_host != nullptr) {
    m_host->requestUpdateOnly();
  }
}

void FileDialogView::requestLayout() {
  if (m_host != nullptr) {
    m_host->requestLayout();
  }
}

void FileDialogView::requestRedraw() {
  if (m_host != nullptr) {
    m_host->requestRedraw();
  }
}

void FileDialogView::focusHostArea(InputArea* area) {
  if (m_host != nullptr) {
    m_host->focusArea(area);
  }
}

InputArea* FileDialogView::hostFocusedArea() const { return m_host != nullptr ? m_host->focusedArea() : nullptr; }

void FileDialogView::acceptDialog(std::optional<std::filesystem::path> result) {
  if (m_host != nullptr) {
    m_host->accept(std::move(result));
  }
}

void FileDialogView::cancelDialog() {
  if (m_host != nullptr) {
    m_host->cancel();
  }
}
