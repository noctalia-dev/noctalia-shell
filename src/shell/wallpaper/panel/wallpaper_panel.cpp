#include "shell/wallpaper/panel/wallpaper_panel.h"

#include "config/config_service.h"
#include "config/state_service.h"
#include "core/log.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/panel/panel_manager.h"
#include "shell/wallpaper/panel/thumbnail_service.h"
#include "shell/wallpaper/panel/wallpaper_page_grid.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/select.h"
#include "ui/controls/toggle.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <memory>
#include <utility>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

constexpr Logger kLog("wp-panel");
constexpr auto kFilterDebounceInterval = std::chrono::milliseconds(120);

std::string toLower(std::string_view text) {
  std::string out;
  out.reserve(text.size());
  for (char ch : text) {
    out.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(ch))));
  }
  return out;
}

} // namespace

WallpaperPanel::WallpaperPanel(WaylandConnection* wayland, ConfigService* config, StateService* state,
                               ThumbnailService* thumbnails)
    : m_wayland(wayland), m_config(config), m_state(state), m_thumbnails(thumbnails) {}

void WallpaperPanel::create() {
  const float scale = contentScale();

  auto root = std::make_unique<Flex>();
  root->setDirection(FlexDirection::Vertical);
  root->setAlign(FlexAlign::Stretch);
  root->setGap(Style::spaceSm * scale);
  root->setPadding(Style::spaceMd * scale);
  m_rootLayout = root.get();

  // ── Toolbar ────────────────────────────────────────────────────────────
  auto toolbar = std::make_unique<Flex>();
  toolbar->setDirection(FlexDirection::Horizontal);
  toolbar->setAlign(FlexAlign::Center);
  toolbar->setGap(Style::spaceSm * scale);
  m_toolbar = toolbar.get();

  auto back = std::make_unique<Button>();
  back->setGlyph("arrow-left");
  back->setVariant(ButtonVariant::Secondary);
  back->setGlyphSize(Style::fontSizeTitle * scale);
  back->setOnClick([this]() { navigateUp(); });
  m_backButton = static_cast<Button*>(toolbar->addChild(std::move(back)));

  auto breadcrumb = std::make_unique<Label>();
  breadcrumb->setFontSize(Style::fontSizeBody * scale);
  breadcrumb->setColor(roleColor(ColorRole::OnSurfaceVariant));
  breadcrumb->setMaxLines(1);
  breadcrumb->setFlexGrow(1.0f);
  m_breadcrumb = static_cast<Label*>(toolbar->addChild(std::move(breadcrumb)));

  auto monitorSelect = std::make_unique<Select>();
  monitorSelect->setFontSize(Style::fontSizeBody * scale);
  monitorSelect->setControlHeight(Style::controlHeight * scale);
  monitorSelect->setOnSelectionChanged([this](std::size_t idx, std::string_view) {
    m_selectedMonitorIndex = idx;
    m_navStack.clear();
    refreshScan();
    applyFilter();
    resetPage();
    resetSelection();
    applyPage();
    rebuildBreadcrumb();
    m_dirty = true;
    PanelManager::instance().refresh();
  });
  m_monitorSelect = static_cast<Select*>(toolbar->addChild(std::move(monitorSelect)));

  auto filter = std::make_unique<Input>();
  filter->setPlaceholder("Filter…");
  filter->setFontSize(Style::fontSizeBody * scale);
  filter->setControlHeight(Style::controlHeight * scale);
  filter->setHorizontalPadding(Style::spaceMd * scale);
  filter->setOnChange([this](const std::string& text) {
    if (text == m_pendingFilterQuery) {
      return;
    }
    m_pendingFilterQuery = text;
    m_filterDebounceTimer.start(kFilterDebounceInterval, [this]() {
      if (m_pendingFilterQuery == m_filterQuery) {
        return;
      }
      m_filterQuery = m_pendingFilterQuery;
      applyFilter();
      resetPage();
      resetSelection();
      applyPage();
      m_dirty = true;
      PanelManager::instance().refresh();
    });
  });
  filter->setOnKeyEvent([this](std::uint32_t sym, std::uint32_t modifiers) { return handleKeyEvent(sym, modifiers); });
  m_filterInput = static_cast<Input*>(toolbar->addChild(std::move(filter)));

  auto flattenLabel = std::make_unique<Label>();
  flattenLabel->setText("Flatten");
  flattenLabel->setFontSize(Style::fontSizeBody * scale);
  flattenLabel->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_flattenLabel = static_cast<Label*>(toolbar->addChild(std::move(flattenLabel)));

  auto flatten = std::make_unique<Toggle>();
  flatten->setChecked(false);
  flatten->setOnChange([this](bool checked) {
    m_flatten = checked;
    refreshScan();
    applyFilter();
    resetPage();
    resetSelection();
    applyPage();
    m_dirty = true;
    PanelManager::instance().refresh();
  });
  m_flattenToggle = static_cast<Toggle*>(toolbar->addChild(std::move(flatten)));

  auto refresh = std::make_unique<Button>();
  refresh->setGlyph("refresh");
  refresh->setVariant(ButtonVariant::Secondary);
  refresh->setGlyphSize(Style::fontSizeTitle * scale);
  refresh->setOnClick([this]() {
    m_scanner.invalidate();
    refreshScan();
    applyFilter();
    resetPage();
    resetSelection();
    applyPage();
    m_dirty = true;
    PanelManager::instance().refresh();
  });
  m_refreshButton = static_cast<Button*>(toolbar->addChild(std::move(refresh)));

  root->addChild(std::move(toolbar));

  // ── Body: paged grid ───────────────────────────────────────────────────
  auto grid = std::make_unique<WallpaperPageGrid>(scale);
  grid->setFlexGrow(1.0f);
  m_grid = grid.get();
  m_grid->setThumbnailService(m_thumbnails);
  m_grid->setOnTileClick([this](const WallpaperEntry& entry) {
    if (entry.isDir) {
      navigateInto(entry.absPath);
    } else {
      applyWallpaperFromEntry(entry);
    }
  });
  m_grid->setOnTileMotion([this](std::size_t index) {
    const std::size_t visibleIndex = m_currentPage * WallpaperPageGrid::kPageSize + index;
    if (visibleIndex >= m_visibleEntries.size()) {
      return;
    }
    if (!m_mouseActive) {
      m_mouseActive = true;
    }
    if (visibleIndex == m_selectedVisibleIndex || visibleIndex == m_hoverVisibleIndex) {
      return;
    }
    m_hoverVisibleIndex = visibleIndex;
    syncGridSelection();
    m_dirty = true;
    PanelManager::instance().refresh();
  });
  m_grid->setOnTileEnter([this](std::size_t index) {
    if (!m_mouseActive) {
      return;
    }
    const std::size_t visibleIndex = m_currentPage * WallpaperPageGrid::kPageSize + index;
    if (visibleIndex >= m_visibleEntries.size() || visibleIndex == m_selectedVisibleIndex ||
        visibleIndex == m_hoverVisibleIndex) {
      return;
    }
    m_hoverVisibleIndex = visibleIndex;
    syncGridSelection();
    m_dirty = true;
    PanelManager::instance().refresh();
  });
  m_grid->setOnTileLeave([this](std::size_t index) {
    const std::size_t visibleIndex = m_currentPage * WallpaperPageGrid::kPageSize + index;
    if (m_hoverVisibleIndex != visibleIndex) {
      return;
    }
    m_hoverVisibleIndex = static_cast<std::size_t>(-1);
    syncGridSelection();
    m_dirty = true;
    PanelManager::instance().refresh();
  });
  root->addChild(std::move(grid));

  // ── Pagination bar ─────────────────────────────────────────────────────
  auto pagination = std::make_unique<Flex>();
  pagination->setDirection(FlexDirection::Horizontal);
  pagination->setAlign(FlexAlign::Center);
  pagination->setJustify(FlexJustify::Center);
  pagination->setFillParentMainAxis(true);
  pagination->setGap(Style::spaceMd * scale);
  m_pagination = pagination.get();

  auto prev = std::make_unique<Button>();
  prev->setGlyph("chevron-left");
  prev->setVariant(ButtonVariant::Secondary);
  prev->setGlyphSize(Style::fontSizeTitle * scale);
  prev->setOnClick([this]() {
    if (m_currentPage == 0) {
      return;
    }
    m_currentPage--;
    const std::size_t firstIndex = m_currentPage * WallpaperPageGrid::kPageSize;
    if (firstIndex < m_visibleEntries.size()) {
      m_selectedVisibleIndex = firstIndex;
    }
    m_hoverVisibleIndex = static_cast<std::size_t>(-1);
    m_mouseActive = false;
    applyPage();
    m_dirty = true;
    PanelManager::instance().refresh();
  });
  m_prevButton = static_cast<Button*>(pagination->addChild(std::move(prev)));

  auto pageLabel = std::make_unique<Label>();
  pageLabel->setFontSize(Style::fontSizeBody * scale);
  pageLabel->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_pageLabel = static_cast<Label*>(pagination->addChild(std::move(pageLabel)));

  auto next = std::make_unique<Button>();
  next->setGlyph("chevron-right");
  next->setVariant(ButtonVariant::Secondary);
  next->setGlyphSize(Style::fontSizeTitle * scale);
  next->setOnClick([this]() {
    const std::size_t total = pageCount();
    if (m_currentPage + 1 >= total) {
      return;
    }
    m_currentPage++;
    const std::size_t firstIndex = m_currentPage * WallpaperPageGrid::kPageSize;
    if (firstIndex < m_visibleEntries.size()) {
      m_selectedVisibleIndex = firstIndex;
    }
    m_hoverVisibleIndex = static_cast<std::size_t>(-1);
    m_mouseActive = false;
    applyPage();
    m_dirty = true;
    PanelManager::instance().refresh();
  });
  m_nextButton = static_cast<Button*>(pagination->addChild(std::move(next)));

  root->addChild(std::move(pagination));

  setRoot(std::move(root));
  if (m_animations != nullptr) {
    this->root()->setAnimationManager(m_animations);
  }

  if (m_thumbnails != nullptr) {
    m_thumbnails->setReadyCallback([this]() {
      if (m_rootLayout == nullptr) {
        return;
      }
      m_dirty = true;
      PanelManager::instance().refresh();
    });
  }
}

void WallpaperPanel::layout(Renderer& renderer, float width, float height) {
  if (m_rootLayout == nullptr) {
    return;
  }
  m_lastWidth = width;
  m_lastHeight = height;

  if (m_thumbnails != nullptr) {
    m_thumbnails->uploadPending();
  }

  if (m_grid != nullptr) {
    m_grid->setRenderer(&renderer);
  }

  m_rootLayout->setSize(width, height);
  m_rootLayout->layout(renderer);
  m_dirty = false;
}

void WallpaperPanel::update(Renderer& renderer) {
  if (!m_dirty || m_rootLayout == nullptr) {
    return;
  }
  if (m_thumbnails != nullptr) {
    m_thumbnails->uploadPending();
  }
  m_rootLayout->layout(renderer);
  m_dirty = false;
}

void WallpaperPanel::onOpen(std::string_view /*context*/) {
  m_filterQuery.clear();
  m_pendingFilterQuery.clear();
  m_filterDebounceTimer.stop();
  if (m_filterInput != nullptr) {
    m_filterInput->setValue("");
  }
  m_navStack.clear();
  populateMonitorChoices();
  refreshScan();
  applyFilter();
  resetPage();
  resetSelection();
  applyPage();
  rebuildBreadcrumb();
  m_dirty = true;
}

void WallpaperPanel::onClose() {
  m_filterDebounceTimer.stop();
  m_pendingFilterQuery.clear();
  m_filterQuery.clear();

  if (m_thumbnails != nullptr) {
    m_thumbnails->setReadyCallback(nullptr);
    m_thumbnails->releaseAll();
  }

  m_visibleEntries.clear();

  m_rootLayout = nullptr;
  m_toolbar = nullptr;
  m_backButton = nullptr;
  m_breadcrumb = nullptr;
  m_monitorSelect = nullptr;
  m_filterInput = nullptr;
  m_flattenToggle = nullptr;
  m_flattenLabel = nullptr;
  m_refreshButton = nullptr;
  m_grid = nullptr;
  m_pagination = nullptr;
  m_prevButton = nullptr;
  m_nextButton = nullptr;
  m_pageLabel = nullptr;

  clearReleasedRoot();
  m_lastWidth = 0.0f;
  m_lastHeight = 0.0f;
}

InputArea* WallpaperPanel::initialFocusArea() const {
  return m_filterInput != nullptr ? m_filterInput->inputArea() : nullptr;
}

void WallpaperPanel::populateMonitorChoices() {
  m_monitorChoices.clear();
  m_monitorChoices.push_back({"", "ALL"});
  if (m_wayland != nullptr) {
    for (const auto& out : m_wayland->outputs()) {
      if (out.connectorName.empty()) {
        continue;
      }
      m_monitorChoices.push_back({out.connectorName, out.connectorName});
    }
  }

  if (m_selectedMonitorIndex >= m_monitorChoices.size()) {
    m_selectedMonitorIndex = 0;
  }

  if (m_monitorSelect != nullptr) {
    std::vector<std::string> labels;
    labels.reserve(m_monitorChoices.size());
    for (const auto& c : m_monitorChoices) {
      labels.push_back(c.label);
    }
    m_monitorSelect->setOptions(std::move(labels));
    m_monitorSelect->setSelectedIndex(m_selectedMonitorIndex);
  }
}

std::filesystem::path WallpaperPanel::rootDirectoryForSelection() const {
  if (m_config == nullptr || m_selectedMonitorIndex >= m_monitorChoices.size()) {
    return {};
  }
  const auto& wp = m_config->config().wallpaper;
  const auto& choice = m_monitorChoices[m_selectedMonitorIndex];
  if (choice.connector.empty()) {
    return wp.directory;
  }
  for (const auto& ovr : wp.monitorOverrides) {
    if (ovr.match == choice.connector && ovr.directory.has_value() && !ovr.directory->empty()) {
      return *ovr.directory;
    }
  }
  return wp.directory;
}

std::filesystem::path WallpaperPanel::activeDirectoryForSelection() const {
  if (!m_navStack.empty()) {
    return m_navStack.back();
  }
  return rootDirectoryForSelection();
}

void WallpaperPanel::refreshScan() {
  const auto dir = activeDirectoryForSelection();
  if (!dir.empty()) {
    m_scanner.scan(dir, m_flatten);
  }
  applyFilter();
}

void WallpaperPanel::applyFilter() {
  m_visibleEntries.clear();
  const auto dir = activeDirectoryForSelection();
  if (dir.empty()) {
    resetSelection();
    return;
  }
  const auto& result = m_scanner.scan(dir, m_flatten);

  if (m_filterQuery.empty()) {
    m_visibleEntries = result.entries;
    if (m_selectedVisibleIndex >= m_visibleEntries.size()) {
      resetSelection();
    }
    return;
  }

  const std::string needle = toLower(m_filterQuery);
  m_visibleEntries.reserve(result.entries.size());
  for (const auto& e : result.entries) {
    if (toLower(e.name).find(needle) != std::string::npos) {
      m_visibleEntries.push_back(e);
    }
  }
  if (m_selectedVisibleIndex >= m_visibleEntries.size()) {
    resetSelection();
  }
}

void WallpaperPanel::resetPage() { m_currentPage = 0; }

std::size_t WallpaperPanel::pageCount() const noexcept {
  if (m_visibleEntries.empty()) {
    return 1;
  }
  return (m_visibleEntries.size() + WallpaperPageGrid::kPageSize - 1) / WallpaperPageGrid::kPageSize;
}

void WallpaperPanel::applyPage() {
  if (m_grid == nullptr) {
    return;
  }

  const std::size_t total = m_visibleEntries.size();
  const std::size_t pageSize = WallpaperPageGrid::kPageSize;
  const std::size_t pages = pageCount();
  if (m_currentPage >= pages) {
    m_currentPage = pages == 0 ? 0 : pages - 1;
  }
  const std::size_t start = m_currentPage * pageSize;
  const std::size_t count = (start >= total) ? 0 : std::min(pageSize, total - start);

  m_grid->setPage(count == 0 ? nullptr : m_visibleEntries.data() + start, count);
  syncGridSelection();

  if (m_pageLabel != nullptr) {
    if (total == 0) {
      m_pageLabel->setText("0 / 0");
    } else {
      m_pageLabel->setText(std::to_string(m_currentPage + 1) + " / " + std::to_string(pages));
    }
  }
  if (m_prevButton != nullptr) {
    m_prevButton->setEnabled(m_currentPage > 0);
  }
  if (m_nextButton != nullptr) {
    m_nextButton->setEnabled(total > 0 && m_currentPage + 1 < pages);
  }
}

void WallpaperPanel::resetSelection() {
  m_selectedVisibleIndex = 0;
  m_hoverVisibleIndex = static_cast<std::size_t>(-1);
  m_mouseActive = false;
}

void WallpaperPanel::syncGridSelection() {
  if (m_grid == nullptr) {
    return;
  }

  const std::size_t pageStart = m_currentPage * WallpaperPageGrid::kPageSize;
  const std::size_t pageEnd = pageStart + WallpaperPageGrid::kPageSize;
  const std::size_t selectedIndex =
      (m_selectedVisibleIndex < m_visibleEntries.size() && m_selectedVisibleIndex >= pageStart &&
       m_selectedVisibleIndex < pageEnd)
          ? (m_selectedVisibleIndex - pageStart)
          : WallpaperPageGrid::kPageSize;
  const std::size_t hoverIndex =
      (m_hoverVisibleIndex < m_visibleEntries.size() && m_hoverVisibleIndex >= pageStart && m_hoverVisibleIndex < pageEnd)
          ? (m_hoverVisibleIndex - pageStart)
          : WallpaperPageGrid::kPageSize;

  m_grid->setHighlightedIndex(selectedIndex, hoverIndex, m_mouseActive);
}

void WallpaperPanel::selectVisibleIndex(std::size_t index) {
  if (m_visibleEntries.empty() || index >= m_visibleEntries.size()) {
    return;
  }

  m_selectedVisibleIndex = index;
  m_hoverVisibleIndex = static_cast<std::size_t>(-1);
  m_mouseActive = false;

  const std::size_t nextPage = index / WallpaperPageGrid::kPageSize;
  if (nextPage != m_currentPage) {
    m_currentPage = nextPage;
    applyPage();
  } else {
    syncGridSelection();
  }

  m_dirty = true;
  PanelManager::instance().refresh();
}

void WallpaperPanel::activateSelectedEntry() {
  if (m_selectedVisibleIndex >= m_visibleEntries.size()) {
    return;
  }

  const auto& entry = m_visibleEntries[m_selectedVisibleIndex];
  if (entry.isDir) {
    navigateInto(entry.absPath);
  } else {
    applyWallpaperFromEntry(entry);
  }
}

bool WallpaperPanel::handleKeyEvent(std::uint32_t sym, std::uint32_t /*modifiers*/) {
  if (m_visibleEntries.empty()) {
    return false;
  }

  if (sym == XKB_KEY_Left) {
    if (m_selectedVisibleIndex > 0) {
      selectVisibleIndex(m_selectedVisibleIndex - 1);
    }
    return true;
  }

  if (sym == XKB_KEY_Right) {
    if (m_selectedVisibleIndex + 1 < m_visibleEntries.size()) {
      selectVisibleIndex(m_selectedVisibleIndex + 1);
    }
    return true;
  }

  if (sym == XKB_KEY_Up) {
    if (m_selectedVisibleIndex >= WallpaperPageGrid::kColumns) {
      selectVisibleIndex(m_selectedVisibleIndex - WallpaperPageGrid::kColumns);
    }
    return true;
  }

  if (sym == XKB_KEY_Down) {
    const std::size_t nextIndex = m_selectedVisibleIndex + WallpaperPageGrid::kColumns;
    if (nextIndex < m_visibleEntries.size()) {
      selectVisibleIndex(nextIndex);
    }
    return true;
  }

  if (sym == XKB_KEY_Return || sym == XKB_KEY_KP_Enter) {
    activateSelectedEntry();
    return true;
  }

  return false;
}

void WallpaperPanel::rebuildBreadcrumb() {
  if (m_breadcrumb == nullptr) {
    return;
  }
  const auto root = rootDirectoryForSelection();
  const auto current = activeDirectoryForSelection();
  if (current.empty()) {
    m_breadcrumb->setText("No directory configured");
    if (m_backButton != nullptr) {
      m_backButton->setEnabled(false);
    }
    return;
  }
  std::string text;
  if (current == root) {
    text = root.filename().empty() ? root.string() : root.filename().string();
  } else {
    std::error_code ec;
    auto rel = std::filesystem::relative(current, root, ec);
    text = ec ? current.string() : (root.filename().string() + "/" + rel.string());
  }
  m_breadcrumb->setText(text);
  if (m_backButton != nullptr) {
    m_backButton->setEnabled(!m_navStack.empty());
  }
}

void WallpaperPanel::navigateInto(const std::filesystem::path& dir) {
  m_navStack.push_back(dir);
  refreshScan();
  applyFilter();
  resetPage();
  resetSelection();
  applyPage();
  rebuildBreadcrumb();
  m_dirty = true;
  PanelManager::instance().refresh();
}

void WallpaperPanel::navigateUp() {
  if (m_navStack.empty()) {
    return;
  }
  m_navStack.pop_back();
  refreshScan();
  applyFilter();
  resetPage();
  resetSelection();
  applyPage();
  rebuildBreadcrumb();
  m_dirty = true;
  PanelManager::instance().refresh();
}

void WallpaperPanel::applyWallpaperFromEntry(const WallpaperEntry& entry) {
  if (m_state == nullptr || m_selectedMonitorIndex >= m_monitorChoices.size()) {
    return;
  }
  const auto& choice = m_monitorChoices[m_selectedMonitorIndex];
  const std::string path = entry.absPath.string();

  if (choice.connector.empty()) {
    StateService::WallpaperBatch batch(*m_state);
    if (m_wayland != nullptr) {
      for (const auto& out : m_wayland->outputs()) {
        if (!out.connectorName.empty()) {
          m_state->setWallpaperPath(out.connectorName, path);
        }
      }
    }
    m_state->setWallpaperPath(std::nullopt, path);
  } else {
    m_state->setWallpaperPath(choice.connector, path);
  }
  kLog.info("applied wallpaper {} to {}", path, choice.connector.empty() ? "ALL" : choice.connector);
}
