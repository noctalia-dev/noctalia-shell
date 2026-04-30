#pragma once

#include "core/timer_manager.h"
#include "render/core/color.h"
#include "shell/panel/panel.h"
#include "shell/wallpaper/panel/wallpaper_scanner.h"

#include <cstddef>
#include <filesystem>
#include <optional>
#include <string>
#include <vector>

class Button;
class ConfigService;
class Flex;
class Input;
class InputArea;
class Label;
class Select;
class ThumbnailService;
class Toggle;
class WallpaperPageGrid;
class WaylandConnection;

class WallpaperPanel : public Panel {
public:
  WallpaperPanel(WaylandConnection* wayland, ConfigService* config, ThumbnailService* thumbnails);

  void create() override;
  void onOpen(std::string_view context) override;
  void onClose() override;
  [[nodiscard]] bool handleGlobalKey(std::uint32_t sym, std::uint32_t modifiers, bool pressed, bool preedit) override;

  [[nodiscard]] float preferredWidth() const override { return scaled(980.0f); }
  [[nodiscard]] float preferredHeight() const override { return scaled(700.0f); }
  [[nodiscard]] bool centeredHorizontally() const override { return true; }
  [[nodiscard]] bool centeredVertically() const override { return true; }
  [[nodiscard]] bool prefersAttachedToBar() const noexcept override { return true; }
  [[nodiscard]] LayerShellLayer layer() const override { return LayerShellLayer::Overlay; }
  [[nodiscard]] LayerShellKeyboard keyboardMode() const override { return LayerShellKeyboard::Exclusive; }
  [[nodiscard]] InputArea* initialFocusArea() const override;

private:
  void doLayout(Renderer& renderer, float width, float height) override;
  void doUpdate(Renderer& renderer) override;
  // "ALL" is represented by an empty connector string.
  struct MonitorChoice {
    std::string connector; // empty = ALL
    std::string label;
  };

  void populateMonitorChoices();
  void refreshScan();
  void applyFilter();
  void rebuildBreadcrumb();
  void navigateInto(const std::filesystem::path& dir);
  void navigateUp();
  void applyWallpaperFromEntry(const WallpaperEntry& entry);
  void applyColorWallpaper();
  void applyPage();
  void resetPage();
  void resetSelection();
  void syncGridSelection();
  void selectVisibleIndex(std::size_t index);
  void activateSelectedEntry();
  [[nodiscard]] bool lightTheme() const;
  [[nodiscard]] bool handleKeyEvent(std::uint32_t sym, std::uint32_t modifiers);
  [[nodiscard]] std::size_t pageCount() const noexcept;
  [[nodiscard]] std::filesystem::path activeDirectoryForSelection() const;
  [[nodiscard]] std::filesystem::path rootDirectoryForSelection() const;
  [[nodiscard]] std::optional<Color> selectedFillColor() const;

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  ThumbnailService* m_thumbnails = nullptr;

  WallpaperScanner m_scanner;

  // UI nodes (owned by the root flex tree).
  Flex* m_rootLayout = nullptr;
  Flex* m_header = nullptr;
  Flex* m_toolbar = nullptr;
  Label* m_title = nullptr;
  Button* m_backButton = nullptr;
  Label* m_breadcrumb = nullptr;
  Select* m_monitorSelect = nullptr;
  Input* m_filterInput = nullptr;
  Toggle* m_flattenToggle = nullptr;
  Label* m_flattenLabel = nullptr;
  Button* m_refreshButton = nullptr;
  Button* m_colorButton = nullptr;
  Button* m_closeButton = nullptr;
  WallpaperPageGrid* m_grid = nullptr;
  Flex* m_pagination = nullptr;
  Button* m_prevButton = nullptr;
  Button* m_nextButton = nullptr;
  Label* m_pageLabel = nullptr;

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
  std::size_t m_currentPage = 0;
  std::size_t m_selectedVisibleIndex = 0;
  std::size_t m_hoverVisibleIndex = static_cast<std::size_t>(-1);
  bool m_mouseActive = false;
  float m_lastWidth = 0.0f;
  float m_lastHeight = 0.0f;
  bool m_dirty = false;
  bool m_thumbnailRefreshPending = false;
};
