#include "shell/wallpaper/panel/wallpaper_panel.h"

#include "config/config_service.h"
#include "core/log.h"
#include "core/ui_phase.h"
#include "i18n/i18n.h"
#include "render/core/renderer.h"
#include "render/core/thumbnail_service.h"
#include "render/scene/input_area.h"
#include "shell/panel/panel_manager.h"
#include "shell/wallpaper/panel/wallpaper_tile.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/input.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/select.h"
#include "ui/controls/spacer.h"
#include "ui/controls/toggle.h"
#include "ui/controls/virtual_grid_view.h"
#include "ui/dialogs/color_picker_dialog.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "util/string_utils.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <chrono>
#include <memory>
#include <string_view>
#include <utility>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

  constexpr Logger kLog("wp-panel");
  constexpr auto kFilterDebounceInterval = std::chrono::milliseconds(120);
  constexpr float kMinTileWidth = 180.0f;
  constexpr float kTileAspect = 0.78f; // height / width — leaves room for label under widescreen thumb

  bool parseColorWallpaperPath(std::string_view path, Color& out) {
    constexpr std::string_view kPrefix = "color:";
    if (!path.starts_with(kPrefix)) {
      return false;
    }
    return tryParseHexColor(path.substr(kPrefix.size()), out);
  }

  std::string colorWallpaperPath(const Color& color) { return "color:" + formatRgbHex(color); }

} // namespace

class WallpaperGridAdapter : public VirtualGridAdapter {
public:
  using ActivateCallback = std::function<void(const WallpaperEntry&)>;

  explicit WallpaperGridAdapter(float scale) : m_scale(scale) {}

  void setEntries(const std::vector<WallpaperEntry>* entries) { m_entries = entries; }
  void setRenderer(Renderer* renderer) { m_renderer = renderer; }
  void setThumbnailService(ThumbnailService* service) {
    m_thumbnails = service;
    for (WallpaperTile* tile : m_pool) {
      if (tile != nullptr) {
        tile->setThumbnailService(service);
      }
    }
  }
  void setOnActivate(ActivateCallback callback) { m_onActivate = std::move(callback); }

  void refreshVisibleThumbnails(Renderer& renderer) {
    for (WallpaperTile* tile : m_pool) {
      if (tile != nullptr && tile->visible()) {
        tile->refreshThumbnail(renderer);
      }
    }
  }

  [[nodiscard]] std::size_t itemCount() const override { return m_entries == nullptr ? 0u : m_entries->size(); }

  [[nodiscard]] std::unique_ptr<Node> createTile() override {
    auto tile = std::make_unique<WallpaperTile>(0.0f, 0.0f, m_scale);
    tile->setThumbnailService(m_thumbnails);
    m_pool.push_back(tile.get());
    return tile;
  }

  void bindTile(Node& tile, std::size_t index, bool selected, bool hovered) override {
    auto* wt = static_cast<WallpaperTile*>(&tile);
    wt->setCellSize(wt->width(), wt->height());
    if (m_renderer != nullptr && m_entries != nullptr && index < m_entries->size()) {
      wt->setEntry((*m_entries)[index], *m_renderer);
    }
    wt->setSelected(selected);
    wt->setHoveredVisual(hovered && !selected);
  }

  // VirtualGridView's overlay InputArea catches the click, so per-tile click
  // callbacks never fire — dispatch from here instead.
  void onActivate(std::size_t index) override {
    if (!m_onActivate || m_entries == nullptr || index >= m_entries->size()) {
      return;
    }
    m_onActivate((*m_entries)[index]);
  }

private:
  float m_scale;
  const std::vector<WallpaperEntry>* m_entries = nullptr;
  Renderer* m_renderer = nullptr;
  ThumbnailService* m_thumbnails = nullptr;

  std::vector<WallpaperTile*> m_pool;
  ActivateCallback m_onActivate;
};

WallpaperPanel::WallpaperPanel(WaylandConnection* wayland, ConfigService* config, ThumbnailService* thumbnails)
    : m_wayland(wayland), m_config(config), m_thumbnails(thumbnails) {}

WallpaperPanel::~WallpaperPanel() = default;

void WallpaperPanel::create() {
  const float scale = contentScale();
  const auto configureIconButton = [scale](Button* button) {
    if (button == nullptr) {
      return;
    }
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
  root->setFill(colorSpecFromRole(ColorRole::Surface));
  root->setRadius(Style::radiusXl * scale);
  m_rootLayout = root.get();

  auto header = std::make_unique<Flex>();
  header->setDirection(FlexDirection::Horizontal);
  header->setAlign(FlexAlign::Center);
  header->setGap(Style::spaceSm * scale);
  header->setFillWidth(true);
  m_header = header.get();

  auto headerLeft = std::make_unique<Flex>();
  headerLeft->setDirection(FlexDirection::Horizontal);
  headerLeft->setAlign(FlexAlign::Center);
  headerLeft->setJustify(FlexJustify::Start);
  headerLeft->setFlexGrow(1.0f);
  headerLeft->setFillWidth(true);

  auto title = std::make_unique<Label>();
  title->setText(i18n::tr("wallpaper.panel.title"));
  title->setFontSize(Style::fontSizeTitle * scale);
  title->setBold(true);
  title->setColor(colorSpecFromRole(ColorRole::Primary));
  m_title = title.get();
  headerLeft->addChild(std::move(title));
  header->addChild(std::move(headerLeft));

  auto breadcrumb = std::make_unique<Label>();
  breadcrumb->setFontSize(Style::fontSizeBody * scale);
  breadcrumb->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  breadcrumb->setMaxLines(1);
  m_breadcrumb = breadcrumb.get();
  header->addChild(std::move(breadcrumb));

  auto headerRight = std::make_unique<Flex>();
  headerRight->setDirection(FlexDirection::Horizontal);
  headerRight->setAlign(FlexAlign::Center);
  headerRight->setJustify(FlexJustify::End);
  headerRight->setFlexGrow(1.0f);
  headerRight->setFillWidth(true);

  auto closeButton = std::make_unique<Button>();
  closeButton->setGlyph("close");
  closeButton->setVariant(ButtonVariant::Default);
  configureIconButton(closeButton.get());
  closeButton->setOnClick([]() { PanelManager::instance().close(); });
  m_closeButton = closeButton.get();
  headerRight->addChild(std::move(closeButton));
  header->addChild(std::move(headerRight));

  root->addChild(std::move(header));

  // ── Toolbar ────────────────────────────────────────────────────────────
  auto toolbar = std::make_unique<Flex>();
  toolbar->setDirection(FlexDirection::Horizontal);
  toolbar->setAlign(FlexAlign::Center);
  toolbar->setGap(Style::spaceSm * scale);
  toolbar->setFillWidth(true);
  m_toolbar = toolbar.get();

  auto filter = std::make_unique<Input>();
  filter->setPlaceholder(i18n::tr("wallpaper.panel.filter-placeholder"));
  filter->setFontSize(Style::fontSizeBody * scale);
  filter->setControlHeight(Style::controlHeight * scale);
  filter->setHorizontalPadding(Style::spaceMd * scale);
  filter->setSize(360.0f * scale, 0.0f);
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
      resetSelection();
      rebindGrid();
      m_dirty = true;
      PanelManager::instance().refresh();
    });
  });
  filter->setOnKeyEvent([this](std::uint32_t sym, std::uint32_t modifiers) { return handleKeyEvent(sym, modifiers); });
  m_filterInput = static_cast<Input*>(toolbar->addChild(std::move(filter)));

  auto back = std::make_unique<Button>();
  back->setGlyph("arrow-big-up");
  back->setVariant(ButtonVariant::Secondary);
  configureIconButton(back.get());
  back->setOnClick([this]() { navigateUp(); });
  m_backButton = static_cast<Button*>(toolbar->addChild(std::move(back)));

  auto spacer = std::make_unique<Spacer>();
  toolbar->addChild(std::move(spacer));

  auto flattenLabel = std::make_unique<Label>();
  flattenLabel->setText(i18n::tr("wallpaper.panel.flatten"));
  flattenLabel->setFontSize(Style::fontSizeBody * scale);
  flattenLabel->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  m_flattenLabel = static_cast<Label*>(toolbar->addChild(std::move(flattenLabel)));

  auto flatten = std::make_unique<Toggle>();
  flatten->setChecked(false);
  flatten->setOnChange([this](bool checked) {
    m_flatten = checked;
    refreshScan();
    applyFilter();
    resetSelection();
    rebindGrid();
    m_dirty = true;
    PanelManager::instance().refresh();
  });
  m_flattenToggle = static_cast<Toggle*>(toolbar->addChild(std::move(flatten)));

  auto monitorSelect = std::make_unique<Select>();
  monitorSelect->setFontSize(Style::fontSizeBody * scale);
  monitorSelect->setControlHeight(Style::controlHeight * scale);
  monitorSelect->setOnSelectionChanged([this](std::size_t idx, std::string_view) {
    m_selectedMonitorIndex = idx;
    m_navStack.clear();
    refreshScan();
    applyFilter();
    resetSelection();
    rebindGrid();
    rebuildBreadcrumb();
    m_dirty = true;
    PanelManager::instance().refresh();
  });
  m_monitorSelect = static_cast<Select*>(toolbar->addChild(std::move(monitorSelect)));

  auto color = std::make_unique<Button>();
  color->setGlyph("color-picker");
  color->setVariant(ButtonVariant::Secondary);
  configureIconButton(color.get());
  color->setOnClick([this]() { applyColorWallpaper(); });
  m_colorButton = static_cast<Button*>(toolbar->addChild(std::move(color)));

  auto refresh = std::make_unique<Button>();
  refresh->setGlyph("refresh");
  refresh->setVariant(ButtonVariant::Secondary);
  configureIconButton(refresh.get());
  refresh->setOnClick([this]() {
    m_scanner.invalidate();
    refreshScan();
    applyFilter();
    resetSelection();
    rebindGrid();
    m_dirty = true;
    PanelManager::instance().refresh();
  });
  m_refreshButton = static_cast<Button*>(toolbar->addChild(std::move(refresh)));

  root->addChild(std::move(toolbar));

  // ── Body: virtualized scrolling grid ──────────────────────────────────
  m_adapter = std::make_unique<WallpaperGridAdapter>(scale);
  m_adapter->setThumbnailService(m_thumbnails);
  m_adapter->setEntries(&m_visibleEntries);
  m_adapter->setOnActivate([this](const WallpaperEntry& entry) {
    if (entry.isDir) {
      navigateInto(entry.absPath);
    } else {
      applyWallpaperFromEntry(entry);
    }
  });

  auto grid = std::make_unique<VirtualGridView>();
  grid->setMinCellWidth(kMinTileWidth * scale);
  grid->setSquareCells(false);
  grid->setColumnGap(Style::spaceMd * scale);
  grid->setRowGap(Style::spaceMd * scale);
  grid->setOverscanRows(2);
  grid->setFlexGrow(1.0f);
  grid->setFillWidth(true);
  grid->setAdapter(m_adapter.get());
  grid->setOnSelectionChanged([this](std::optional<std::size_t> idx) {
    if (idx.has_value() && *idx < m_visibleEntries.size()) {
      m_selectedVisibleIndex = *idx;
    }
  });
  m_grid = static_cast<VirtualGridView*>(root->addChild(std::move(grid)));

  setRoot(std::move(root));
  if (m_animations != nullptr) {
    this->root()->setAnimationManager(m_animations);
  }

  if (m_thumbnails != nullptr) {
    m_thumbnailPendingSub = m_thumbnails->subscribePendingUpload([this]() {
      if (m_rootLayout == nullptr) {
        return;
      }
      m_thumbnailRefreshPending = true;
      PanelManager::instance().requestUpdateOnly();
    });
  }
}

void WallpaperPanel::doLayout(Renderer& renderer, float width, float height) {
  if (m_rootLayout == nullptr) {
    return;
  }
  m_lastWidth = width;
  m_lastHeight = height;

  if (m_thumbnails != nullptr) {
    (void)m_thumbnails->uploadPending(renderer.textureManager());
    m_thumbnailRefreshPending = false;
  }

  if (m_adapter != nullptr) {
    m_adapter->setRenderer(&renderer);
  }

  // Drive cell height from current tile width via VirtualGridView's resolved
  // geometry: configure the cell height to follow the chosen tile aspect.
  if (m_grid != nullptr) {
    m_grid->setCellHeight(kMinTileWidth * contentScale() * kTileAspect);
  }

  m_rootLayout->setSize(width, height);
  m_rootLayout->layout(renderer);
  m_dirty = false;
}

void WallpaperPanel::doUpdate(Renderer& renderer) {
  if (m_rootLayout == nullptr) {
    return;
  }

  if (m_thumbnailRefreshPending && m_thumbnails != nullptr) {
    const bool changed = m_thumbnails->uploadPending(renderer.textureManager());
    m_thumbnailRefreshPending = false;
    if (changed && m_adapter != nullptr) {
      m_adapter->setRenderer(&renderer);
      m_adapter->refreshVisibleThumbnails(renderer);
    }
  }
}

void WallpaperPanel::onOpen(std::string_view /*context*/) {
  m_filterQuery.clear();
  m_pendingFilterQuery.clear();
  m_flatten = false;
  m_filterDebounceTimer.stop();
  if (m_filterInput != nullptr) {
    m_filterInput->setValue("");
  }
  if (m_flattenToggle != nullptr) {
    m_flattenToggle->setChecked(false);
  }
  m_navStack.clear();
  populateMonitorChoices();
  refreshScan();
  applyFilter();
  resetSelection();
  rebindGrid();
  rebuildBreadcrumb();
  m_dirty = true;
}

void WallpaperPanel::onClose() {
  m_filterDebounceTimer.stop();
  m_pendingFilterQuery.clear();
  m_filterQuery.clear();

  m_visibleEntries.clear();

  // Detach adapter from grid before either is destroyed; the pool tiles were
  // minted by the adapter.
  if (m_grid != nullptr) {
    m_grid->setAdapter(nullptr);
  }
  m_adapter.reset();
  m_thumbnailPendingSub.disconnect();

  m_rootLayout = nullptr;
  m_header = nullptr;
  m_toolbar = nullptr;
  m_title = nullptr;
  m_backButton = nullptr;
  m_breadcrumb = nullptr;
  m_monitorSelect = nullptr;
  m_filterInput = nullptr;
  m_flattenToggle = nullptr;
  m_flattenLabel = nullptr;
  m_refreshButton = nullptr;
  m_colorButton = nullptr;
  m_closeButton = nullptr;
  m_grid = nullptr;

  clearReleasedRoot();
  m_lastWidth = 0.0f;
  m_lastHeight = 0.0f;
  m_thumbnailRefreshPending = false;
}

bool WallpaperPanel::handleGlobalKey(std::uint32_t sym, std::uint32_t modifiers, bool pressed, bool preedit) {
  if (!pressed || preedit) {
    return false;
  }
  return handleKeyEvent(sym, modifiers);
}

InputArea* WallpaperPanel::initialFocusArea() const {
  return m_filterInput != nullptr ? m_filterInput->inputArea() : nullptr;
}

void WallpaperPanel::populateMonitorChoices() {
  m_monitorChoices.clear();
  m_monitorChoices.push_back({"", i18n::tr("wallpaper.panel.all-monitors")});
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

std::optional<Color> WallpaperPanel::selectedFillColor() const {
  if (m_config == nullptr || m_selectedMonitorIndex >= m_monitorChoices.size()) {
    return std::nullopt;
  }

  const auto& wp = m_config->config().wallpaper;
  const auto& choice = m_monitorChoices[m_selectedMonitorIndex];
  Color sourceColor;
  const std::string currentPath =
      choice.connector.empty() ? m_config->getDefaultWallpaperPath() : m_config->getWallpaperPath(choice.connector);
  if (parseColorWallpaperPath(currentPath, sourceColor)) {
    return sourceColor;
  }

  if (!choice.connector.empty()) {
    for (const auto& ovr : wp.monitorOverrides) {
      if (ovr.match == choice.connector && ovr.fillColor.has_value()) {
        return resolveColorSpec(*ovr.fillColor);
      }
    }
  }

  if (wp.fillColor.has_value()) {
    return resolveColorSpec(*wp.fillColor);
  }
  return std::nullopt;
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

  const std::string needle = StringUtils::toLower(m_filterQuery);
  m_visibleEntries.reserve(result.entries.size());
  for (const auto& e : result.entries) {
    if (StringUtils::toLower(e.name).find(needle) != std::string::npos) {
      m_visibleEntries.push_back(e);
    }
  }
  if (m_selectedVisibleIndex >= m_visibleEntries.size()) {
    resetSelection();
  }
}

void WallpaperPanel::rebindGrid(bool resetScroll) {
  if (m_grid == nullptr) {
    return;
  }
  m_grid->notifyDataChanged();
  if (resetScroll || m_visibleEntries.empty()) {
    m_grid->scrollView().setScrollOffset(0.0f);
  }
  if (m_visibleEntries.empty()) {
    m_grid->setSelectedIndex(std::nullopt);
  } else {
    m_grid->setSelectedIndex(m_selectedVisibleIndex);
  }
}

void WallpaperPanel::resetSelection() { m_selectedVisibleIndex = 0; }

bool WallpaperPanel::lightTheme() const {
  return m_config != nullptr && m_config->config().theme.mode == ThemeMode::Light;
}

void WallpaperPanel::selectVisibleIndex(std::size_t index) {
  if (m_visibleEntries.empty() || index >= m_visibleEntries.size()) {
    return;
  }

  m_selectedVisibleIndex = index;
  if (m_grid != nullptr) {
    m_grid->setSelectedIndex(index);
    m_grid->scrollToIndex(index);
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

bool WallpaperPanel::handleKeyEvent(std::uint32_t sym, std::uint32_t modifiers) {
  if (m_visibleEntries.empty()) {
    return false;
  }

  // Approximate column count from current grid layout. VirtualGridView does
  // not expose its column count directly, so we recompute from viewport width.
  std::size_t columns = 1;
  if (m_grid != nullptr) {
    const float viewportW = m_grid->scrollView().contentViewportWidth();
    const float cellW = kMinTileWidth * contentScale();
    const float gap = Style::spaceMd * contentScale();
    if (cellW > 0.0f) {
      columns = std::max<std::size_t>(1, static_cast<std::size_t>((viewportW + gap) / (cellW + gap)));
    }
  }

  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Left, sym, modifiers)) {
    if (m_selectedVisibleIndex > 0) {
      selectVisibleIndex(m_selectedVisibleIndex - 1);
    }
    return true;
  }

  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Right, sym, modifiers)) {
    if (m_selectedVisibleIndex + 1 < m_visibleEntries.size()) {
      selectVisibleIndex(m_selectedVisibleIndex + 1);
    }
    return true;
  }

  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Up, sym, modifiers)) {
    if (m_selectedVisibleIndex >= columns) {
      selectVisibleIndex(m_selectedVisibleIndex - columns);
    }
    return true;
  }

  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Down, sym, modifiers)) {
    const std::size_t nextIndex = m_selectedVisibleIndex + columns;
    if (nextIndex < m_visibleEntries.size()) {
      selectVisibleIndex(nextIndex);
    }
    return true;
  }

  if (m_config != nullptr && m_config->matchesKeybind(KeybindAction::Validate, sym, modifiers)) {
    activateSelectedEntry();
    return true;
  }

  return false;
}

void WallpaperPanel::rebuildBreadcrumb() {
  uiAssertNotRendering("WallpaperPanel::rebuildBreadcrumb");
  if (m_breadcrumb == nullptr) {
    return;
  }
  const auto root = rootDirectoryForSelection();
  const auto current = activeDirectoryForSelection();
  if (current.empty()) {
    m_breadcrumb->setText(i18n::tr("wallpaper.panel.no-directory-configured"));
    if (m_backButton != nullptr) {
      m_backButton->setEnabled(false);
      m_backButton->setVisible(false);
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
    const bool canNavigateUp = !m_navStack.empty();
    m_backButton->setEnabled(canNavigateUp);
    m_backButton->setVisible(canNavigateUp);
  }
}

void WallpaperPanel::navigateInto(const std::filesystem::path& dir) {
  m_navStack.push_back(dir);
  refreshScan();
  applyFilter();
  resetSelection();
  rebindGrid(true);
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
  resetSelection();
  rebindGrid(true);
  rebuildBreadcrumb();
  m_dirty = true;
  PanelManager::instance().refresh();
}

void WallpaperPanel::applyWallpaperFromEntry(const WallpaperEntry& entry) {
  if (m_config == nullptr || m_selectedMonitorIndex >= m_monitorChoices.size()) {
    return;
  }
  const auto& choice = m_monitorChoices[m_selectedMonitorIndex];
  const std::string path = entry.absPath.string();

  if (choice.connector.empty()) {
    ConfigService::WallpaperBatch batch(*m_config);
    if (m_wayland != nullptr) {
      for (const auto& out : m_wayland->outputs()) {
        if (!out.connectorName.empty()) {
          m_config->setWallpaperPath(out.connectorName, path);
        }
      }
    }
    m_config->setWallpaperPath(std::nullopt, path);
  } else {
    m_config->setWallpaperPath(choice.connector, path);
  }
  kLog.info("applied wallpaper {} to {}", path, choice.connector.empty() ? "ALL" : choice.connector);
}

void WallpaperPanel::applyColorWallpaper() {
  if (m_config == nullptr || m_selectedMonitorIndex >= m_monitorChoices.size()) {
    return;
  }

  ColorPickerDialogOptions options;
  options.title = i18n::tr("wallpaper.panel.color-title");
  if (auto color = selectedFillColor()) {
    options.initialColor = *color;
  } else if (auto last = ColorPickerDialog::lastResult()) {
    options.initialColor = *last;
  }

  const auto choice = m_monitorChoices[m_selectedMonitorIndex];
  (void)ColorPickerDialog::open(std::move(options), [this, choice](std::optional<Color> result) {
    if (!result.has_value() || m_config == nullptr) {
      return;
    }

    Color rgb = *result;
    rgb.a = 1.0f;
    const std::string path = colorWallpaperPath(rgb);

    if (choice.connector.empty()) {
      ConfigService::WallpaperBatch batch(*m_config);
      if (m_wayland != nullptr) {
        for (const auto& out : m_wayland->outputs()) {
          if (!out.connectorName.empty()) {
            m_config->setWallpaperPath(out.connectorName, path);
          }
        }
      }
      m_config->setWallpaperPath(std::nullopt, path);
      kLog.info("applied color wallpaper {} to ALL", path);
      return;
    }

    m_config->setWallpaperPath(choice.connector, path);
    kLog.info("applied color wallpaper {} to {}", path, choice.connector);
  });
}
