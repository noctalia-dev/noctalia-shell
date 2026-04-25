#pragma once

#include "render/animation/animation_manager.h"
#include "render/scene/input_dispatcher.h"
#include "render/scene/node.h"
#include "ui/controls/scroll_view.h"
#include "wayland/toplevel_surface.h"

#include <memory>
#include <string>

class Box;
class ConfigService;
class Flex;
class RenderContext;
class WaylandConnection;
struct KeyboardEvent;
struct PointerEvent;
struct wl_surface;

// Standalone xdg-toplevel settings UI (same binary as the shell; shares RenderContext / GLES).
class SettingsWindow {
public:
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

private:
  void destroyWindow();
  void prepareFrame(bool needsUpdate, bool needsLayout);
  void buildScene(std::uint32_t width, std::uint32_t height);
  [[nodiscard]] float uiScale() const;

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  RenderContext* m_renderContext = nullptr;

  std::unique_ptr<ToplevelSurface> m_surface;
  std::unique_ptr<Node> m_sceneRoot;
  Flex* m_mainContainer = nullptr;  // Outer Flex inside m_sceneRoot, sized to the window
  Box* m_panelBackground = nullptr; // Window-sized background panel inside m_sceneRoot
  InputDispatcher m_inputDispatcher;
  AnimationManager m_animations;
  bool m_pointerInside = false;

  std::uint32_t m_lastSceneWidth = 0;
  std::uint32_t m_lastSceneHeight = 0;
  ScrollViewState m_contentScrollState;
  bool m_rebuildRequested = false;
  bool m_focusSearchOnRebuild = false;
  std::string m_searchQuery;
  std::string m_openWidgetPickerPath;
  std::string m_editingWidgetName;
  std::string m_pendingDeleteWidgetName;
  std::string m_pendingDeleteWidgetSettingPath;
  std::string m_renamingWidgetName;
  std::string m_creatingWidgetType;
  std::string m_selectedBarName;
  std::string m_selectedMonitorOverride;
  std::string m_selectedSection;
  std::string m_statusMessage;
  std::string m_pendingResetPageScope;
  bool m_showAdvanced = false;
  bool m_showOverriddenOnly = false;
  bool m_statusIsError = false;
};
