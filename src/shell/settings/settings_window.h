#pragma once

#include "render/animation/animation_manager.h"
#include "render/scene/input_dispatcher.h"
#include "render/scene/node.h"
#include "shell/settings/settings_registry.h"
#include "ui/controls/context_menu_popup.h"
#include "ui/controls/scroll_view.h"
#include "wayland/toplevel_surface.h"

#include <functional>
#include <memory>
#include <string>
#include <utility>
#include <vector>

class Box;
class Button;
class ConfigService;
class Flex;
class RenderContext;
class WaylandConnection;
struct KeyboardEvent;
struct PointerEvent;
struct wl_output;
struct wl_surface;

// Standalone xdg-toplevel settings UI (same binary as the shell; shares RenderContext).
class SettingsWindow {
public:
  ~SettingsWindow();

  void initialize(WaylandConnection& wayland, ConfigService* config, RenderContext* renderContext);

  void open();
  void close();
  [[nodiscard]] bool isOpen() const noexcept { return m_surface != nullptr && m_surface->isRunning(); }
  [[nodiscard]] wl_surface* wlSurface() const noexcept {
    return m_surface != nullptr ? m_surface->wlSurface() : nullptr;
  }

  [[nodiscard]] bool onPointerEvent(const PointerEvent& event);
  void onKeyboardEvent(const KeyboardEvent& event);
  void onThemeChanged();
  void onFontChanged();
  void onExternalOptionsChanged();
  void setOpenDesktopWidgetEditor(std::function<void()> callback) { m_openDesktopWidgetEditor = std::move(callback); }

private:
  void destroyWindow();
  void prepareFrame(bool needsUpdate, bool needsLayout);
  void buildScene(std::uint32_t width, std::uint32_t height);
  void rebuildSettingsContent();
  void requestSceneRebuild();
  void requestContentRebuild();
  void clearStatusMessage();
  void clearTransientSettingsState();
  void openActionsMenu();
  void saveSupportReport();
  void saveFlattenedConfig();
  void setSettingOverride(std::vector<std::string> path, ConfigOverrideValue value);
  void setSettingOverrides(std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>> overrides);
  void clearSettingOverride(std::vector<std::string> path);
  void clearSettingOverrides(std::vector<std::vector<std::string>> paths);
  void renameWidgetInstance(std::string oldName, std::string newName,
                            std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>> referenceOverrides);
  void createBar(std::string name);
  void renameBar(std::string oldName, std::string newName);
  void deleteBar(std::string name);
  void moveBar(std::string name, int direction);
  void createMonitorOverride(std::string barName, std::string match);
  void renameMonitorOverride(std::string barName, std::string oldMatch, std::string newMatch);
  void deleteMonitorOverride(std::string barName, std::string match);
  [[nodiscard]] float uiScale() const;

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  RenderContext* m_renderContext = nullptr;

  std::unique_ptr<ToplevelSurface> m_surface;
  std::unique_ptr<Node> m_sceneRoot;
  Flex* m_mainContainer = nullptr;  // Outer Flex inside m_sceneRoot, sized to the window
  Box* m_panelBackground = nullptr; // Window-sized background panel inside m_sceneRoot
  Button* m_actionsMenuButton = nullptr;
  Flex* m_contentContainer = nullptr;
  std::unique_ptr<ContextMenuPopup> m_actionsMenuPopup;
  InputDispatcher m_inputDispatcher;
  AnimationManager m_animations;
  bool m_pointerInside = false;
  wl_output* m_output = nullptr;

  std::uint32_t m_lastSceneWidth = 0;
  std::uint32_t m_lastSceneHeight = 0;
  ScrollViewState m_sidebarScrollState;
  ScrollViewState m_contentScrollState;
  std::vector<settings::SettingEntry> m_settingsRegistry;
  bool m_rebuildRequested = false;
  bool m_contentRebuildRequested = false;
  bool m_focusSearchOnRebuild = false;
  std::string m_searchQuery;
  std::string m_openWidgetPickerPath;
  std::string m_editingWidgetName;
  std::string m_pendingDeleteWidgetName;
  std::string m_pendingDeleteWidgetSettingPath;
  std::string m_renamingWidgetName;
  std::string m_creatingWidgetType;
  std::string m_creatingBarName;
  std::string m_renamingBarName;
  std::string m_pendingDeleteBarName;
  std::string m_creatingMonitorOverrideBarName;
  std::string m_creatingMonitorOverrideMatch;
  std::string m_renamingMonitorOverrideBarName;
  std::string m_renamingMonitorOverrideMatch;
  std::string m_pendingDeleteMonitorOverrideBarName;
  std::string m_pendingDeleteMonitorOverrideMatch;
  std::string m_selectedBarName;
  std::string m_selectedMonitorOverride;
  std::string m_selectedSection;
  std::string m_statusMessage;
  std::string m_pendingResetPageScope;
  bool m_showAdvanced = false;
  bool m_showOverriddenOnly = false;
  bool m_statusIsError = false;
  std::function<void()> m_openDesktopWidgetEditor;
};
