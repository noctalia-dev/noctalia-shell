import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Dock
import qs.Modules.MainScreen

SmartPanel {
  id: root
  panelBackgroundColor: Qt.alpha(Color.mSurface, Settings.data.dock.backgroundOpacity)

  readonly property string dockPosition: Settings.data.dock.position
  readonly property bool isVertical: dockPosition === "left" || dockPosition === "right"
  readonly property bool hasBar: modelData && modelData.name ? (Settings.data.bar.monitors.includes(modelData.name) || (Settings.data.bar.monitors.length === 0)) : false
  readonly property bool barAtSameEdge: hasBar && Settings.getBarPositionForScreen(modelData?.name) === dockPosition
  readonly property bool isFramed: Settings.data.bar.barType === "framed" && hasBar
  property bool isDockHovered: false
  property bool panelHovered: false
  readonly property int iconSize: Math.round(12 + 24 * (Settings.data.dock.size ?? 1))
  readonly property int maxWidth: screen ? screen.width * 0.8 : 1000
  readonly property int maxHeight: screen ? screen.height * 0.8 : 1000
  readonly property bool autoHide: false
  readonly property int hideDelay: 1000
  readonly property int showDelay: 100

  // Shared state with dock content
  property bool dockHovered: false
  property bool anyAppHovered: false
  property bool menuHovered: false
  property bool hidden: false
  property bool peekHovered: false

  // Track the currently open context menu
  property var currentContextMenu: null

  // Combined model of running apps and pinned apps
  property var dockApps: []
  property var groupCycleIndices: ({})
  // manual window ordering per grouped appId.
  property var groupWindowOrders: ({})
  // Track the group that is being actively hovered
  property string activeHoverGroupAppId: ""

  // Track the session order of apps (transient reordering)
  property var sessionAppOrder: []

  // Drag and Drop state for visual feedback
  property int dragSourceIndex: -1
  property int dragTargetIndex: -1

  // Revision counter to force icon re-evaluation
  property int iconRevision: 0

  property alias hideTimer: hideTimer
  property alias showTimer: showTimer

  onMenuHoveredChanged: {
    if (!menuHovered && !panelHovered) {
      hoverCloseTimer.restart();
    }
  }

  onClosed: {
    hoverCloseTimer.stop();
    isDockHovered = false;
  }

  panelAnchorTop: dockPosition === "top"
  panelAnchorBottom: dockPosition === "bottom"
  panelAnchorLeft: dockPosition === "left"
  panelAnchorRight: dockPosition === "right"
  panelAnchorHorizontalCenter: !isVertical
  panelAnchorVerticalCenter: isVertical

  forceAttachToBar: hasBar
  exclusiveKeyboard: false

  // when dragging ended but the cursor is outside the dock area, restart the timer
  onDragSourceIndexChanged: {
    if (dragSourceIndex === -1) {
      if (autoHide && !dockHovered && !anyAppHovered && !peekHovered && !menuHovered) {
        hideTimer.restart();
      }
    }
  }

  // Function to close any open context menu
  function closeAllContextMenus() {
    if (currentContextMenu && currentContextMenu.visible) {
      currentContextMenu.hide();
    }
  }

  function getAppKey(appData) {
    if (!appData)
      return null;

    if (Settings.data.dock.groupApps) {
      return appData.appId;
    }

    // Use stable appId for pinned apps to maintain their slot regardless of running state
    if (appData.type === "pinned" || appData.type === "pinned-running") {
      return appData.appId;
    }

    // prefer toplevel object identity for unpinned running apps to distinguish instances
    if (appData.toplevel)
      return appData.toplevel;

    // fallback to appId
    return appData.appId;
  }

  function sortDockApps(apps) {
    if (!sessionAppOrder || sessionAppOrder.length === 0) {
      return apps;
    }

    const sorted = [];
    const remaining = [...apps];

    // Pick apps that are in the session order
    for (let i = 0; i < sessionAppOrder.length; i++) {
      const key = sessionAppOrder[i];

      // Pick ALL matching apps (e.g. all instances of a pinned app)
      while (true) {
        const idx = remaining.findIndex(app => getAppKey(app) === key);
        if (idx !== -1) {
          sorted.push(remaining[idx]);
          remaining.splice(idx, 1);
        } else {
          break;
        }
      }
    }

    // Append any new/remaining apps
    remaining.forEach(app => sorted.push(app));

    return sorted;
  }

  function reorderApps(fromIndex, toIndex) {
    if (fromIndex === toIndex || fromIndex < 0 || toIndex < 0 || fromIndex >= dockApps.length || toIndex >= dockApps.length)
      return;

    const list = [...dockApps];
    const item = list.splice(fromIndex, 1)[0];
    list.splice(toIndex, 0, item);

    dockApps = list;
    sessionAppOrder = dockApps.map(getAppKey);
    savePinnedOrder();
  }

  function savePinnedOrder() {
    const currentPinned = Settings.data.dock.pinnedApps || [];
    const newPinned = [];
    const seen = new Set();

    // Extract pinned apps in their current visual order
    dockApps.forEach(app => {
                       if (app.appId && !seen.has(app.appId)) {
                         const isPinned = currentPinned.some(p => normalizeAppId(p) === normalizeAppId(app.appId));

                         if (isPinned) {
                           newPinned.push(app.appId);
                           seen.add(app.appId);
                         }
                       }
                     });

    // Check if any pinned apps were missed (unlikely if dockApps is correct)
    currentPinned.forEach(p => {
                            if (!seen.has(p)) {
                              newPinned.push(p);
                              seen.add(p);
                            }
                          });

    if (JSON.stringify(currentPinned) !== JSON.stringify(newPinned)) {
      Settings.data.dock.pinnedApps = newPinned;
    }
  }

  // Helper function to normalize app IDs for case-insensitive matching
  function normalizeAppId(appId) {
    if (!appId || typeof appId !== 'string')
      return "";
    let id = appId.toLowerCase().trim();
    if (id.endsWith(".desktop"))
      id = id.substring(0, id.length - 8);
    return id;
  }

  // Helper function to check if an app ID matches a pinned app (case-insensitive)
  function isAppIdPinned(appId, pinnedApps) {
    if (!appId || !pinnedApps || pinnedApps.length === 0)
      return false;
    const normalizedId = normalizeAppId(appId);
    return pinnedApps.some(pinnedId => normalizeAppId(pinnedId) === normalizedId);
  }

  // Helper function to get app name from desktop entry
  function getAppNameFromDesktopEntry(appId) {
    if (!appId)
      return appId;

    try {
      if (typeof DesktopEntries !== 'undefined' && DesktopEntries.heuristicLookup) {
        const entry = DesktopEntries.heuristicLookup(appId);
        if (entry && entry.name) {
          return entry.name;
        }
      }

      if (typeof DesktopEntries !== 'undefined' && DesktopEntries.byId) {
        const entry = DesktopEntries.byId(appId);
        if (entry && entry.name) {
          return entry.name;
        }
      }
    } catch (e)
      // Fall through to return original appId
    {}

    // Return original appId if we can't find a desktop entry
    return appId;
  }

  function getToplevelsForEntry(appData) {
    if (!appData)
      return [];

    if (appData.toplevels && appData.toplevels.length > 0) {
      return appData.toplevels.filter(toplevel => toplevel && (!Settings.data.dock.onlySameOutput || !toplevel.screens || toplevel.screens.includes(screen)));
    }

    if (!appData.toplevel)
      return [];

    if (Settings.data.dock.onlySameOutput && appData.toplevel.screens && !appData.toplevel.screens.includes(screen))
      return [];

    return [appData.toplevel];
  }

  function getPrimaryToplevelForEntry(appData) {
    const toplevels = getToplevelsForEntry(appData);
    if (toplevels.length === 0)
      return null;

    if (ToplevelManager && ToplevelManager.activeToplevel && toplevels.includes(ToplevelManager.activeToplevel))
      return ToplevelManager.activeToplevel;

    return toplevels[0];
  }

  // Build grouped render model without mutating the raw toplevel list.
  function buildGroupedDockApps(apps) {
    if (!Settings.data.dock.groupApps) {
      return apps.map(app => {
                        const entry = Object.assign({}, app);
                        entry.toplevels = getToplevelsForEntry(app);
                        return entry;
                      });
    }

    const grouped = [];
    const groupedById = new Map();

    apps.forEach(app => {
                   const appId = app.appId;
                   const toplevels = getToplevelsForEntry(app);
                   const existing = groupedById.get(appId);

                   if (existing) {
                     toplevels.forEach(toplevel => {
                                         if (!existing.toplevels.includes(toplevel)) {
                                           existing.toplevels.push(toplevel);
                                         }
                                       });
                     if (app.type === "pinned" || app.type === "pinned-running") {
                       existing.isPinned = true;
                     }
                   } else {
                     const entry = {
                       "type": app.type,
                       "appId": appId,
                       "title": app.title,
                       "toplevels": toplevels.slice(),
                       "isPinned": app.type === "pinned" || app.type === "pinned-running"
                     };
                     grouped.push(entry);
                     groupedById.set(appId, entry);
                   }
                 });

    grouped.forEach(entry => {
                      entry.toplevel = getPrimaryToplevelForEntry(entry);
                      if (entry.toplevels.length > 0 && entry.isPinned) {
                        entry.type = "pinned-running";
                      } else if (entry.toplevels.length > 0) {
                        entry.type = "running";
                      } else {
                        entry.type = "pinned";
                      }
                      if (entry.toplevel && entry.toplevel.title && entry.toplevel.title.trim() !== "") {
                        entry.title = entry.toplevel.title;
                      }
                    });

    return grouped;
  }

  // Function to update the combined dock apps model
  function updateDockApps() {
    const runningApps = ToplevelManager ? (ToplevelManager.toplevels.values || []) : [];
    const pinnedApps = Settings.data.dock.pinnedApps || [];
    const combined = [];
    const processedToplevels = new Set();
    const processedPinnedAppIds = new Set();

    // push an app onto combined with the given appType
    function pushApp(appType, toplevel, appId, title) {
      // Use canonical ID for pinned apps to ensure key stability
      const canonicalId = isAppIdPinned(appId, pinnedApps) ? (pinnedApps.find(p => normalizeAppId(p) === normalizeAppId(appId)) || appId) : appId;

      // For running apps, track by toplevel object to allow multiple instances
      if (toplevel) {
        if (processedToplevels.has(toplevel)) {
          return;
        }
        if (Settings.data.dock.onlySameOutput && toplevel.screens && !toplevel.screens.includes(screen)) {
          return;
        }
        combined.push({
                        "type": appType,
                        "toplevel": toplevel,
                        "toplevels": toplevel ? [toplevel] : [],
                        "appId": canonicalId,
                        "title": title
                      });
        processedToplevels.add(toplevel);
      } else {
        // For pinned apps that aren't running, track by appId to avoid duplicates
        if (processedPinnedAppIds.has(canonicalId)) {
          return;
        }
        combined.push({
                        "type": appType,
                        "toplevel": toplevel,
                        "toplevels": [],
                        "appId": canonicalId,
                        "title": title
                      });
        processedPinnedAppIds.add(canonicalId);
      }
    }

    function pushRunning(first) {
      runningApps.forEach(toplevel => {
                            if (toplevel) {
                              // Use robust matching to check if pinned
                              const isPinned = isAppIdPinned(toplevel.appId, pinnedApps);
                              if (!first && isPinned && processedToplevels.has(toplevel)) {
                                return; // Already added by pushPinned()
                              }
                              pushApp((first && isPinned) ? "pinned-running" : "running", toplevel, toplevel.appId, toplevel.title);
                            }
                          });
    }

    function pushPinned() {
      pinnedApps.forEach(pinnedAppId => {
                           // Find all running instances of this pinned app using robust matching
                           const matchingToplevels = runningApps.filter(app => app && normalizeAppId(app.appId) === normalizeAppId(pinnedAppId));

                           if (matchingToplevels.length > 0) {
                             // Add all running instances as pinned-running
                             matchingToplevels.forEach(toplevel => {
                                                         pushApp("pinned-running", toplevel, pinnedAppId, toplevel.title);
                                                       });
                           } else {
                             // App is pinned but not running - add once
                             pushApp("pinned", null, pinnedAppId, getAppNameFromDesktopEntry(pinnedAppId) || pinnedAppId);
                           }
                         });
    }

    // if pinnedStatic then push all pinned and then all remaining running apps
    if (Settings.data.dock.pinnedStatic) {
      pushPinned();
      pushRunning(false);

      // else add all running apps and then remaining pinned apps
    } else {
      pushRunning(true);
      pushPinned();
    }

    const sortedApps = sortDockApps(combined);
    dockApps = buildGroupedDockApps(sortedApps);
    const cycleState = root.groupCycleIndices || {};
    const nextCycleState = {};
    dockApps.forEach(app => {
                       if (app && app.appId && cycleState[app.appId] !== undefined) {
                         nextCycleState[app.appId] = cycleState[app.appId];
                       }
                     });
    root.groupCycleIndices = nextCycleState;

    // Sync session order if needed
    if (!sessionAppOrder || sessionAppOrder.length === 0) {
      sessionAppOrder = dockApps.map(getAppKey);
    } else {
      const currentKeys = new Set(dockApps.map(getAppKey));
      const existingKeys = new Set();
      const newOrder = [];

      // Keep existing keys that are still present
      sessionAppOrder.forEach(key => {
                                if (currentKeys.has(key)) {
                                  newOrder.push(key);
                                  existingKeys.add(key);
                                }
                              });

      // Add new keys at the end
      dockApps.forEach(app => {
                         const key = getAppKey(app);
                         if (!existingKeys.has(key)) {
                           newOrder.push(key);
                           existingKeys.add(key);
                         }
                       });

      if (JSON.stringify(newOrder) !== JSON.stringify(sessionAppOrder)) {
        sessionAppOrder = newOrder;
      }
    }
  }

  // Update dock apps when toplevels change
  Connections {
    target: ToplevelManager ? ToplevelManager.toplevels : null
    function onValuesChanged() {
      updateDockApps();
    }
  }

  // Update dock apps when pinned apps change
  Connections {
    target: Settings.data.dock
    function onPinnedAppsChanged() {
      updateDockApps();
    }
    function onOnlySameOutputChanged() {
      updateDockApps();
    }
    function onGroupAppsChanged() {
      updateDockApps();
    }
  }

  // Initial update when component is ready
  Component.onCompleted: {
    if (ToplevelManager) {
      updateDockApps();
    }
  }

  // Refresh icons when DesktopEntries becomes available
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      root.iconRevision++;
    }
  }

  Timer {
    id: hideTimer
    interval: hideDelay
    onTriggered: {}
  }

  Timer {
    id: showTimer
    interval: showDelay
    onTriggered: {}
  }

  Timer {
    id: hoverCloseTimer
    interval: hideDelay
    onTriggered: {
      if (root.menuHovered || (root.currentContextMenu && root.currentContextMenu.visible)) {
        restart();
        return;
      }
      root.isDockHovered = false;
      root.close();
    }
  }

  panelContent: Item {
    id: panelContent

    property bool allowAttach: true
    property real frameThickness: isFramed && !barAtSameEdge && !Settings.data.dock.sitOnFrame ? Settings.data.bar.frameThickness : 0
    property real contentPreferredWidth: Math.round(dockContainerWrapper.width) - (isVertical ? frameThickness : 0)
    property real contentPreferredHeight: Math.round(dockContainerWrapper.height) - (!isVertical ? frameThickness : 0)

    // Detect hover over panel content (including DockContent)
    HoverHandler {
      id: dockHoverHandler
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onHoveredChanged: {
        root.panelHovered = hovered;
        if (hovered) {
          root.isDockHovered = true;
          hoverCloseTimer.stop();
        } else {
          if (root.menuHovered || (root.currentContextMenu && root.currentContextMenu.visible)) {
            hoverCloseTimer.stop();
          } else {
            hoverCloseTimer.restart();
          }
        }
      }
    }

    Item {
      id: dockContainerWrapper
      readonly property real frameThickness: isFramed ? Settings.data.bar.frameThickness : 0
      width: dockContent.dockContainer.width
      height: dockContent.dockContainer.height
      anchors.top: root.dockPosition === "bottom" ? parent.top : undefined
      anchors.bottom: root.dockPosition === "top" ? parent.bottom : undefined
      anchors.left: root.dockPosition === "right" ? parent.left : undefined
      anchors.right: root.dockPosition === "left" ? parent.right : undefined

      DockContent {
        id: dockContent
        anchors.fill: parent
        dockRoot: root
        extraTop: 0
        extraBottom: 0
        extraLeft: 0
        extraRight: 0
      }
    }
  }
}
