#pragma once

#include "core/timer_manager.h"
#include "render/core/color.h"
#include "render/core/thumbnail_service.h"
#include "shell/panel/panel.h"
#include "shell/wallpaper/panel/wallpaper_scanner.h"

#include <cstddef>
#include <filesystem>
#include <memory>
#include <optional>
#include <string>
#include <unordered_set>
#include <vector>

class Button;
class ConfigService;
class Flex;
class Input;
class InputArea;
class Label;
class Segmented;
class Select;
class Toggle;
class VirtualGridView;
class WallpaperGridAdapter;
class WaylandConnection;

class WallpaperPanel : public Panel {
public:
  enum class SortMode : std::uint8_t {
    NameAsc,
    NameDesc,
    DateAsc,
    DateDesc,
  };

  WallpaperPanel(WaylandConnection* wayland, ConfigService* config, ThumbnailService* thumbnails);
  ~WallpaperPanel() override;

  void create() override;
  void onOpen(std::string_view context) override;
  void onClose() override;
  [[nodiscard]] bool handleGlobalKey(std::uint32_t sym, std::uint32_t modifiers, bool pressed, bool preedit) override;

  [[nodiscard]] float preferredWidth() const override { return scaled(980.0f); }
  [[nodiscard]] float preferredHeight() const override { return scaled(700.0f); }
  [[nodiscard]] PanelPlacement panelPlacement() const noexcept override;
  [[nodiscard]] LayerShellLayer layer() const override { return LayerShellLayer::Overlay; }
  [[nodiscard]] LayerShellKeyboard keyboardMode() const override { return LayerShellKeyboard::Exclusive; }
  [[nodiscard]] InputArea* initialFocusArea() const override;

private:
  void doLayout(Renderer& renderer, float width, float height) override;
  void doUpdate(Renderer& renderer) override;
  void onPanelCardOpacityChanged(float opacity) override;
  // "ALL" is represented by an empty connector string.
  struct MonitorChoice {
    std::string connector; // empty = ALL
    std::string label;
  };

  void populateMonitorChoices();
  void refreshVisibleEntries();
  void refreshScan();
  void applyFilter();
  void syncBrowseChrome();
  void rebuildBreadcrumb();
  void navigateInto(const std::filesystem::path& dir);
  void navigateUp();
  void applyWallpaperFromEntry(const WallpaperEntry& entry);
  void applyWallpaperPath(const std::string& path, const WallpaperFavorite* applyTheme);
  [[nodiscard]] const WallpaperFavorite* favoriteThemeToApply(std::string_view path) const;
  [[nodiscard]] WallpaperFavorite themeFromControls() const;
  void applyLiveThemePreview(const std::string& path);
  void toggleFavoriteForPath(const std::string& path);
  void syncThemeControls();
  void rebuildFavoritePaletteDetailSelect(const WallpaperFavorite* favorite);
  [[nodiscard]] std::string selectedWallpaperPath() const;
  void appendFilteredFavoriteEntries(
      std::vector<WallpaperEntry>& out, std::unordered_set<std::string>& favoritePaths,
      const std::filesystem::path& activeDir, const std::filesystem::path& rootDir
  ) const;
  void sortVisibleEntries();
  void syncSortButtonGlyph();
  void cycleSortMode();
  void setSortMode(SortMode mode);
  [[nodiscard]] static SortMode sortModeFromState(std::string_view value);
  [[nodiscard]] static std::string_view sortModeStateValue(SortMode mode);
  [[nodiscard]] static std::string_view sortModeGlyph(SortMode mode);
  [[nodiscard]] static const char* sortModeTooltipKey(SortMode mode);
  void applyColorWallpaper();
  void rebindGrid(bool resetScroll = false);
  void resetSelection();
  void selectVisibleIndex(std::size_t index);
  void activateSelectedEntry();
  [[nodiscard]] bool handleKeyEvent(std::uint32_t sym, std::uint32_t modifiers);
  [[nodiscard]] std::filesystem::path activeDirectoryForSelection() const;
  [[nodiscard]] std::filesystem::path rootDirectoryForSelection() const;
  [[nodiscard]] std::string currentWallpaperPathForSelection() const;
  [[nodiscard]] std::vector<std::string> allMonitorConnectors() const;
  [[nodiscard]] std::optional<Color> selectedFillColor() const;
  [[nodiscard]] static std::string displayNameForWallpaperPath(std::string_view path);

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  ThumbnailService* m_thumbnails = nullptr;

  WallpaperScanner m_scanner;

  // UI nodes (owned by the root flex tree).
  Flex* m_rootLayout = nullptr;
  Flex* m_header = nullptr;
  Flex* m_toolbar = nullptr;
  Flex* m_favoritesOptionsColumn = nullptr;
  Label* m_title = nullptr;
  Button* m_backButton = nullptr;
  Label* m_breadcrumb = nullptr;
  Segmented* m_favoriteThemeSegmented = nullptr;
  Label* m_favoriteThemeLabel = nullptr;
  Segmented* m_favoritePaletteSourceSegmented = nullptr;
  Select* m_favoritePaletteDetailSelect = nullptr;
  Label* m_favoritePaletteLabel = nullptr;
  Select* m_monitorSelect = nullptr;
  Input* m_filterInput = nullptr;
  Toggle* m_flattenToggle = nullptr;
  Label* m_flattenLabel = nullptr;
  Button* m_sortButton = nullptr;
  Button* m_refreshButton = nullptr;
  Button* m_colorButton = nullptr;
  Button* m_closeButton = nullptr;
  VirtualGridView* m_grid = nullptr;
  std::unique_ptr<WallpaperGridAdapter> m_adapter;

  std::vector<MonitorChoice> m_monitorChoices;
  std::size_t m_selectedMonitorIndex = 0;

  // Navigation state for the current selected monitor.
  std::vector<std::filesystem::path> m_navStack;

  // Filtered view of the scanner's entries for the currently active
  // directory. The grid reads a page-sized slice of this vector via a
  // raw pointer; any mutation of the vector must be followed by applyPage().
  std::vector<WallpaperEntry> m_visibleEntries;

  std::string m_filterQuery;
  std::string m_pendingFilterQuery;
  Timer m_filterDebounceTimer;

  bool m_flatten = false;
  SortMode m_sortMode = SortMode::NameAsc;
  std::size_t m_pinnedFavoriteCount = 0;
  bool m_syncingFavoriteControls = false;
  std::vector<std::string> m_favoritePaletteDetailValues;
  std::size_t m_selectedVisibleIndex = 0;
  float m_lastWidth = 0.0f;
  float m_lastHeight = 0.0f;
  bool m_dirty = false;
  bool m_thumbnailRefreshPending = false;
  ThumbnailService::Subscription m_thumbnailPendingSub;
};
