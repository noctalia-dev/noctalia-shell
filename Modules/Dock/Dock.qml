import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Services.Compositor
import qs.Services.System
import qs.Services.UI
import qs.Widgets

Loader {

  active: Settings.data.dock.enabled
  sourceComponent: Variants {
    model: Quickshell.screens

    delegate: Item {
      id: root

      required property ShellScreen modelData

      property bool barIsReady: modelData ? BarService.isBarReady(modelData.name) : false

      Connections {
        target: BarService
        function onBarReadyChanged(screenName) {
          if (screenName === modelData.name) {
            barIsReady = true;
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

      // Refresh icons and names when DesktopEntries becomes available (or updates)
      Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
          root.iconRevision++;
          updateDockApps();
        }
      }

      // Shared properties between peek and dock windows
      readonly property string displayMode: Settings.data.dock.displayMode
      readonly property bool autoHide: displayMode === "auto_hide"
      readonly property bool exclusive: displayMode === "exclusive"
      readonly property bool isStaticMode: Settings.data.dock.dockType === "static"
      readonly property int hideDelay: 500
      readonly property int showDelay: 100
      readonly property int hideAnimationDuration: Math.max(0, Math.round(Style.animationFast / (Settings.data.dock.animationSpeed || 1.0)))
      readonly property int showAnimationDuration: Math.max(0, Math.round(Style.animationFast / (Settings.data.dock.animationSpeed || 1.0)))
      readonly property int peekHeight: 1
      readonly property int indicatorThickness: 3
      readonly property int iconSize: Math.round(12 + 24 * (Settings.data.dock.size ?? 1))
      readonly property int floatingMargin: Settings.data.dock.floatingRatio * Style.marginL
      readonly property int maxWidth: modelData ? modelData.width * 0.8 : 1000
      readonly property int maxHeight: modelData ? modelData.height * 0.8 : 1000

      // Dock position properties
      readonly property string dockPosition: Settings.data.dock.position
      readonly property bool isVertical: dockPosition === "left" || dockPosition === "right"

      // Bar detection and positioning properties
      readonly property bool hasBar: modelData && modelData.name ? (Settings.data.bar.monitors.includes(modelData.name) || (Settings.data.bar.monitors.length === 0)) : false
      readonly property bool barAtSameEdge: hasBar && Settings.getBarPositionForScreen(modelData?.name) === dockPosition
      readonly property int barHeight: Style.getBarHeightForScreen(modelData?.name)
      readonly property int peekEdgeLength: {
        const edgeSize = isVertical ? Math.round(modelData?.height || maxHeight) : Math.round(modelData?.width || maxWidth);
        const minLength = Math.max(1, Math.round(edgeSize * 0.1));
        return Math.max(minLength, frameIndicatorLength);
      }
      readonly property int peekCenterOffsetX: {
        if (isVertical)
          return 0;
        const edgeSize = Math.round(modelData?.width || maxWidth);
        return Math.max(0, Math.round((edgeSize - peekEdgeLength) / 2));
      }
      readonly property int peekCenterOffsetY: {
        if (!isVertical)
          return 0;
        const edgeSize = Math.round(modelData?.height || maxHeight);
        return Math.max(0, Math.round((edgeSize - peekEdgeLength) / 2));
      }
      readonly property bool showFrameIndicator: {
        if (!isStaticMode || !Settings.data.dock.showFrameIndicator || Settings.data.bar.barType !== "framed" || !hasBar)
          return false;
        var panel = getStaticDockPanel();
        if (panel && panel.isPanelOpen !== undefined)
          return !panel.isPanelOpen;
        return hidden;
      }
      readonly property int dockItemCount: dockApps.length + (Settings.data.dock.showLauncherIcon ? 1 : 0)
      readonly property int frameIndicatorLength: {
        if (dockItemCount <= 0)
          return 0;
        const spacing = Style.marginS;
        const layoutLength = (iconSize * dockItemCount) + (spacing * Math.max(0, dockItemCount - 1));
        const padded = layoutLength + Style.marginXL;
        return Math.min(padded, isVertical ? maxHeight : maxWidth);
      }

      // Shared state between windows
      property bool dockHovered: false
      property bool anyAppHovered: false
      property bool menuHovered: false
      property bool hidden: autoHide
      property bool peekHovered: false

      // Separate property to control Loader - stays true during animations
      property bool dockLoaded: !autoHide // Start loaded if autoHide is off

      // Track the currently open context menu
      property var currentContextMenu: null

      // Combined model of running apps and pinned apps
      property var dockApps: []
      property var groupCycleIndices: ({})

      // Track the session order of apps (transient reordering)
      property var sessionAppOrder: []

      // Drag and Drop state for visual feedback
      property int dragSourceIndex: -1
      property int dragTargetIndex: -1

      // when dragging ended but the cursor is outside the dock area, restart the timer
      onDragSourceIndexChanged: {
        if (dragSourceIndex === -1) {
          if (autoHide && !dockHovered && !anyAppHovered && !peekHovered && !menuHovered) {
            hideTimer.restart();
          }
        }
      }

      // Revision counter to force icon re-evaluation
      property int iconRevision: 0

      // Function to close any open context menu
      function closeAllContextMenus() {
        if (currentContextMenu && currentContextMenu.visible) {
          currentContextMenu.hide();
        }
      }

      function getStaticDockPanel() {
        return PanelService.getPanel("staticDockPanel", modelData, false);
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
          return appData.toplevels.filter(toplevel => toplevel && (!Settings.data.dock.onlySameOutput || !toplevel.screens || toplevel.screens.includes(modelData)));
        }

        if (!appData.toplevel)
          return [];

        if (Settings.data.dock.onlySameOutput && appData.toplevel.screens && !appData.toplevel.screens.includes(modelData))
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

        //push an app onto combined with the given appType
        function pushApp(appType, toplevel, appId, title) {
          // Use canonical ID for pinned apps to ensure key stability
          const canonicalId = isAppIdPinned(appId, pinnedApps) ? (pinnedApps.find(p => normalizeAppId(p) === normalizeAppId(appId)) || appId) : appId;

          // For running apps, track by toplevel object to allow multiple instances
          if (toplevel) {
            if (processedToplevels.has(toplevel)) {
              return; // Already processed this toplevel instance
            }
            if (Settings.data.dock.onlySameOutput && toplevel.screens && !toplevel.screens.includes(modelData)) {
              return; // Filtered out by onlySameOutput setting
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
              return; // Already processed this pinned app
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

        //if pinnedStatic then push all pinned and then all remaining running apps
        if (Settings.data.dock.pinnedStatic) {
          pushPinned();
          pushRunning(false);

          //else add all running apps and then remaining pinned apps
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
        // Instead of resetting everything when length changes, we reconcile the keys
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

      // Timer to unload dock after hide animation completes
      Timer {
        id: unloadTimer
        interval: hideAnimationDuration + 50 // Add small buffer
        onTriggered: {
          if (hidden && autoHide) {
            dockLoaded = false;
          }
        }
      }

      property alias hideTimer: hideTimer
      property alias showTimer: showTimer
      property alias unloadTimer: unloadTimer

      // Timer for auto-hide delay
      Timer {
        id: hideTimer
        interval: hideDelay
        onTriggered: {
          // do not hide if dragging
          if (root.dragSourceIndex !== -1) {
            return;
          }

          // Force menuHovered to false if no menu is current or visible
          if (!root.currentContextMenu || !root.currentContextMenu.visible) {
            menuHovered = false;
          }
          if (autoHide && !dockHovered && !anyAppHovered && !peekHovered && !menuHovered) {
            if (isStaticMode) {
              const panel = getStaticDockPanel();
              if (panel && (panel.menuHovered || (panel.currentContextMenu && panel.currentContextMenu.visible))) {
                restart();
                return;
              }
              if (panel && panel.isDockHovered) {
                restart();
                return;
              }
              if (panel)
                panel.close();
            } else {
              closeAllContextMenus();
            }
            hidden = true;
            unloadTimer.restart(); // Start unload timer when hiding
          } else if (autoHide && !dockHovered && !peekHovered) {
            // Restart timer if menu is closing (handles race condition)
            restart();
          }
        }
      }

      // Timer for show delay
      Timer {
        id: showTimer
        interval: showDelay
        onTriggered: {
          if (autoHide) {
            if (isStaticMode) {
              if (dockItemCount <= 0)
                return;
              const panel = getStaticDockPanel();
              if (panel && !panel.isPanelOpen)
                panel.open();
            } else {
              dockLoaded = true; // Load dock immediately
            }
            hidden = false; // Then trigger show animation
            unloadTimer.stop(); // Cancel any pending unload
          }
        }
      }

      // Watch for autoHide setting changes
      onAutoHideChanged: {
        if (!autoHide) {
          hidden = false;
          dockLoaded = true;
          hideTimer.stop();
          showTimer.stop();
          unloadTimer.stop();
        } else {
          hidden = true;
          unloadTimer.restart(); // Schedule unload after animation
        }
      }

      // PEEK WINDOW
      Loader {
        active: (barIsReady || !hasBar) && modelData && (Settings.data.dock.monitors.length === 0 || Settings.data.dock.monitors.includes(modelData.name)) && (autoHide || isStaticMode)

        sourceComponent: PanelWindow {
          id: peekWindow

          screen: modelData
          // Dynamic anchors based on dock position
          anchors.top: dockPosition === "top" || isVertical
          anchors.bottom: dockPosition === "bottom"
          anchors.left: dockPosition === "left" || !isVertical
          anchors.right: dockPosition === "right"
          focusable: false
          color: "transparent"

          // When bar is at same edge, position peek window past the bar so it receives mouse events
          margins.top: isVertical ? peekCenterOffsetY : (dockPosition === "top" && barAtSameEdge && !showFrameIndicator ? (barHeight + (Settings.data.bar.floating ? Settings.data.bar.marginVertical : 0)) : 0)
          margins.bottom: dockPosition === "bottom" && barAtSameEdge && !showFrameIndicator ? (barHeight + (Settings.data.bar.floating ? Settings.data.bar.marginVertical : 0)) : 0
          margins.left: !isVertical ? peekCenterOffsetX : (dockPosition === "left" && barAtSameEdge && !showFrameIndicator ? (barHeight + (Settings.data.bar.floating ? Settings.data.bar.marginHorizontal : 0)) : 0)
          margins.right: dockPosition === "right" && barAtSameEdge && !showFrameIndicator ? (barHeight + (Settings.data.bar.floating ? Settings.data.bar.marginHorizontal : 0)) : 0

          WlrLayershell.namespace: "noctalia-dock-peek-" + (screen?.name || "unknown")
          WlrLayershell.exclusionMode: ExclusionMode.Ignore
          // Larger peek area when bar is at same edge, normal 1px otherwise
          implicitHeight: isVertical ? peekEdgeLength : ((showFrameIndicator || barAtSameEdge) ? indicatorThickness : peekHeight)
          implicitWidth: isVertical ? ((showFrameIndicator || barAtSameEdge) ? indicatorThickness : peekHeight) : peekEdgeLength

          Rectangle {
            anchors.centerIn: parent
            width: isVertical ? indicatorThickness : frameIndicatorLength
            height: isVertical ? frameIndicatorLength : indicatorThickness
            radius: indicatorThickness
            color: Qt.alpha(Color.mPrimary, 0.6)
            opacity: showFrameIndicator && frameIndicatorLength > 0 ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
              NumberAnimation {
                duration: Style.animationFast
                easing.type: Easing.InOutQuad
              }
            }
          }

          MouseArea {
            id: peekArea
            anchors.fill: parent
            hoverEnabled: true

            onEntered: {
              peekHovered = true;
              if (isStaticMode && !autoHide) {
                if (dockItemCount <= 0)
                  return;
                const panel = getStaticDockPanel();
                if (panel && !panel.isPanelOpen)
                  panel.open();
                return;
              }
              if (isStaticMode) {
                showTimer.start();
                return;
              }
              if (hidden) {
                showTimer.start();
              }
            }

            onExited: {
              peekHovered = false;
              showTimer.stop();
              if (!hidden && !dockHovered && !anyAppHovered && !menuHovered) {
                hideTimer.restart();
              }
            }
          }
        }
      }

      // Force dock reload when position changes to fix anchor/layout issues
      // Force dock reload when position/mode changes to fix anchor/layout issues
      property bool _reloading: false
      function handleReload() {
        if (!autoHide && dockLoaded && !_reloading) {
          _reloading = true;
          // Brief unload/reload cycle to reset layout
          Qt.callLater(() => {
                         dockLoaded = false;
                         Qt.callLater(() => {
                                        dockLoaded = true;
                                        _reloading = false;
                                      });
                       });
        }
      }

      onDockPositionChanged: handleReload()
      onExclusiveChanged: handleReload()

      Loader {
        id: dockWindowLoader
        active: Settings.data.dock.enabled && !isStaticMode && (barIsReady || !hasBar) && modelData && (Settings.data.dock.monitors.length === 0 || Settings.data.dock.monitors.includes(modelData.name)) && dockLoaded && ToplevelManager && (dockApps.length > 0)

        sourceComponent: PanelWindow {
          id: dockWindow

          screen: modelData

          focusable: false
          color: "transparent"

          WlrLayershell.namespace: "noctalia-dock-" + (screen?.name || "unknown")
          WlrLayershell.exclusionMode: exclusive ? ExclusionMode.Auto : ExclusionMode.Ignore

          implicitWidth: dockContainerWrapper.width
          implicitHeight: dockContainerWrapper.height

          // Position based on dock setting
          anchors.top: dockPosition === "top"
          anchors.bottom: dockPosition === "bottom"
          anchors.left: dockPosition === "left"
          anchors.right: dockPosition === "right"

          // Offset past bar when at same edge (skip bar offset if dock is exclusive - exclusion zones stack)
          margins.top: dockPosition === "top" ? (barAtSameEdge && !exclusive ? barHeight + (Settings.data.bar.floating ? Settings.data.bar.marginVertical : 0) + floatingMargin : floatingMargin) : 0
          margins.bottom: dockPosition === "bottom" ? (barAtSameEdge && !exclusive ? barHeight + (Settings.data.bar.floating ? Settings.data.bar.marginVertical : 0) + floatingMargin : floatingMargin) : 0
          margins.left: dockPosition === "left" ? (barAtSameEdge && !exclusive ? barHeight + (Settings.data.bar.floating ? Settings.data.bar.marginHorizontal : 0) + floatingMargin : floatingMargin) : 0
          margins.right: dockPosition === "right" ? (barAtSameEdge && !exclusive ? barHeight + (Settings.data.bar.floating ? Settings.data.bar.marginHorizontal : 0) + floatingMargin : floatingMargin) : 0

          // Container wrapper for animations
          Item {
            id: dockContainerWrapper

            // Helper properties for orthogonal bar detection
            readonly property string screenBarPosition: Settings.getBarPositionForScreen(modelData?.name)
            readonly property bool barOnLeft: hasBar && screenBarPosition === "left" && !Settings.data.bar.floating
            readonly property bool barOnRight: hasBar && screenBarPosition === "right" && !Settings.data.bar.floating
            readonly property bool barOnTop: hasBar && screenBarPosition === "top" && !Settings.data.bar.floating
            readonly property bool barOnBottom: hasBar && screenBarPosition === "bottom" && !Settings.data.bar.floating

            // Calculate padding needed to shift center to match exclusive mode
            readonly property int extraTop: (isVertical && !exclusive && barOnTop) ? barHeight : 0
            readonly property int extraBottom: (isVertical && !exclusive && barOnBottom) ? barHeight : 0
            readonly property int extraLeft: (!isVertical && !exclusive && barOnLeft) ? barHeight : 0
            readonly property int extraRight: (!isVertical && !exclusive && barOnRight) ? barHeight : 0

            width: dockContent.dockContainer.width + extraLeft + extraRight
            height: dockContent.dockContainer.height + extraTop + extraBottom

            anchors.horizontalCenter: isVertical ? undefined : parent.horizontalCenter
            anchors.verticalCenter: isVertical ? parent.verticalCenter : undefined

            anchors.top: dockPosition === "top" ? parent.top : undefined
            anchors.bottom: dockPosition === "bottom" ? parent.bottom : undefined
            anchors.left: dockPosition === "left" ? parent.left : undefined
            anchors.right: dockPosition === "right" ? parent.right : undefined

            opacity: hidden ? 0 : 1
            scale: hidden ? 0.85 : 1

            Behavior on opacity {
              NumberAnimation {
                duration: hidden ? hideAnimationDuration : showAnimationDuration
                easing.type: Easing.InOutQuad
              }
            }

            Behavior on scale {
              NumberAnimation {
                duration: hidden ? hideAnimationDuration : showAnimationDuration
                easing.type: hidden ? Easing.InQuad : Easing.OutBack
                easing.overshoot: hidden ? 0 : 1.05
              }
            }

            DockContent {
              id: dockContent
              anchors.fill: parent
              dockRoot: root
              extraTop: dockContainerWrapper.extraTop
              extraBottom: dockContainerWrapper.extraBottom
              extraLeft: dockContainerWrapper.extraLeft
              extraRight: dockContainerWrapper.extraRight
            }
          }
        }
      }
    }
  }
}
