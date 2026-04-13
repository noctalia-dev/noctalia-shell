#pragma once

#include "config/config_service.h"
#include "render/animation/animation_manager.h"
#include "render/scene/input_dispatcher.h"
#include "system/desktop_entry.h"
#include "system/icon_resolver.h"
#include "ui/controls/context_menu.h"
#include "ui/signal.h"
#include "wayland/popup_surface.h"

#include <cstdint>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

class Box;
class ConfigService;
class Flex;
class Glyph;
class Image;
class InputArea;
class Label;
class RectNode;
class RenderContext;
class WaylandConnection;
class LayerSurface;
class Node;
struct PointerEvent;
struct ToplevelInfo;
struct WaylandOutput;
struct wl_output;
struct wl_surface;
struct zwlr_foreign_toplevel_handle_v1;

class Dock {
public:
  Dock();

  bool initialize(WaylandConnection& wayland, ConfigService* config, RenderContext* renderContext);
  void reload();
  void show();
  void closeAllInstances();
  void onOutputChange();
  void refresh();
  void toggleVisibility();
  void requestRedraw();
  bool onPointerEvent(const PointerEvent& event);

private:
  struct DockItemView {
    DesktopEntry entry;
    std::string idLower;
    std::string startupWmClassLower;
    InputArea* area = nullptr;
    Box* background = nullptr;
    Box* badge = nullptr;
    Label* badgeLabel = nullptr;
    Image* iconImage = nullptr;
    Glyph* iconGlyph = nullptr;
    bool hovered = false;
    bool running = false;
    bool active = false;
    float visualScale = -1.0f;
    float visualOpacity = -1.0f;
    AnimationManager::Id scaleAnimId = 0;
    AnimationManager::Id opacityAnimId = 0;
    std::size_t instanceCount = 0;
  };

  struct DockInstance {
    std::uint32_t outputName = 0;
    wl_output* output = nullptr;
    std::int32_t scale = 1;
    std::unique_ptr<LayerSurface> surface;
    // sceneRoot must be destroyed before `animations` — ~Node() calls cancelForOwner().
    AnimationManager animations;
    std::unique_ptr<Node> sceneRoot;
    RectNode* shadow = nullptr;
    Box* panel = nullptr;
    Flex* row = nullptr;
    InputDispatcher inputDispatcher;
    std::vector<DockItemView> items;
    std::uint64_t modelSerial = 0;
    std::string activeAppIdLower;
    bool pointerInside = false;
    // Auto-hide: tracks visibility [0,1] driven by hover.
    float hideOpacity = 1.0f;
    Signal<>::ScopedConnection paletteConn;
  };

  // Returns true if the item list was modified (triggers a rebuild).
  bool refreshPinnedAppsIfNeeded();
  void syncInstances();
  void createInstance(const WaylandOutput& output);
  void destroyInstance(std::uint32_t outputName);
  void prepareFrame(DockInstance& instance, bool needsUpdate, bool needsLayout);
  void buildScene(DockInstance& instance);
  void rebuildItems(DockInstance& instance);
  void resizeSurface(DockInstance& instance);
  void updateVisuals(DockInstance& instance);
  void applyPanelPalette(DockInstance& instance);
  void launchEntry(const DesktopEntry& entry);
  void launchAction(const DesktopAction& action);
  void handleItemClick(DockInstance& instance, DockItemView& item);
  void openWindowPicker(DockInstance& instance, DockItemView& item,
                        std::vector<ToplevelInfo> windows);
  void closeWindowPicker();
  void openItemMenu(DockInstance& instance, DockItemView& item);
  void closeItemMenu();
  void startHideFadeOut(DockInstance& inst);

  [[nodiscard]] bool matchesActiveApp(const DockItemView& item, std::string_view activeAppIdLower) const;
  [[nodiscard]] bool matchesRunningApp(const DockItemView& item,
                                       const std::vector<std::string>& runningLower) const;

  // Geometry helpers
  [[nodiscard]] std::int32_t dockContentSize(std::size_t itemCount) const; // item row length (main axis)
  [[nodiscard]] std::int32_t dockThickness() const;     // cross-axis (includes icon, cell padding, dock padding)
  [[nodiscard]] bool isVertical() const;

  // Generic popup (window picker and item context menu).
  struct DockPopup {
    std::unique_ptr<PopupSurface> surface;
    std::unique_ptr<Node> sceneRoot;
    InputDispatcher inputDispatcher;
    wl_surface* wlSurface = nullptr;
    bool pointerInside = false;
    std::vector<zwlr_foreign_toplevel_handle_v1*> handles;
  };

  // Route a pointer event to an open popup; returns true if consumed.
  bool routePopupEvent(DockPopup* popup, const PointerEvent& event);

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  RenderContext* m_renderContext = nullptr;
  DockConfig m_lastDockConfig{};
  std::vector<std::string> m_lastPinnedConfig;
  std::vector<DesktopEntry> m_pinnedEntries;
  std::uint64_t m_modelSerial = 0;
  std::uint64_t m_entriesVersion = 0;
  IconResolver m_iconResolver;
  std::vector<std::unique_ptr<DockInstance>> m_instances;
  std::unordered_map<wl_surface*, DockInstance*> m_surfaceMap;
  DockInstance* m_hoveredInstance = nullptr;
  wl_output* m_lastFilterOutput = nullptr;
  DockInstance* m_popupOwnerInstance = nullptr; // instance that owns the current open popup
  std::unique_ptr<DockPopup> m_windowMenu;  // left-click multi-window picker
  std::unique_ptr<DockPopup> m_itemMenu;    // right-click context menu
};
