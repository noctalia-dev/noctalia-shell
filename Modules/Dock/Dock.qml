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
      readonly property int hideDelay: 500
      readonly property int showDelay: 100
      readonly property int hideAnimationDuration: Math.max(0, Math.round(Style.animationFast / (Settings.data.dock.animationSpeed || 1.0)))
      readonly property int showAnimationDuration: Math.max(0, Math.round(Style.animationFast / (Settings.data.dock.animationSpeed || 1.0)))
      readonly property int peekHeight: 1
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

      function getAppKey(appData) {
        if (!appData)
          return null;

        // Use stable appId for all apps to group multiple instances together
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

      // Function to update the combined dock apps model
      function updateDockApps() {
        const runningApps = ToplevelManager ? (ToplevelManager.toplevels.values || []) : [];
        const pinnedApps = Settings.data.dock.pinnedApps || [];
        const combined = [];
        const processedToplevels = new Set();
        const processedPinnedAppIds = new Set();
        const appInstanceCounts = {}; // Track how many instances each app has

        // Count instances for each app
        runningApps.forEach(toplevel => {
          if (toplevel && toplevel.appId) {
            const normalizedId = normalizeAppId(toplevel.appId);
            appInstanceCounts[normalizedId] = (appInstanceCounts[normalizedId] || 0) + 1;
          }
        });

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

            // Check if we should group multiple instances
            const normalizedId = normalizeAppId(appId);
            const instanceCount = appInstanceCounts[normalizedId] || 1;

            // Only add the first instance, but mark it as having multiple instances
            if (instanceCount > 1) {
              // Check if we've already added an instance of this app
              const alreadyAdded = combined.some(app =>
                app.appId && normalizeAppId(app.appId) === normalizedId
              );

              if (!alreadyAdded) {
                combined.push({
                                "type": appType,
                                "toplevel": toplevel,
                                "appId": canonicalId,
                                "title": title,
                                "instanceCount": instanceCount
                              });
                processedToplevels.add(toplevel);
              } else {
                // Skip additional instances
                processedToplevels.add(toplevel);
                return;
              }
            } else {
              combined.push({
                            "type": appType,
                            "toplevel": toplevel,
                            "appId": canonicalId,
                            "title": title,
                            "instanceCount": 1
                          });
              processedToplevels.add(toplevel);
            }
          } else {
            // For pinned apps that aren't running, track by appId to avoid duplicates
            if (processedPinnedAppIds.has(canonicalId)) {
              return; // Already processed this pinned app
            }
            combined.push({
                            "type": appType,
                            "toplevel": toplevel,
                            "appId": canonicalId,
                            "title": title,
                            "instanceCount": 1
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

        dockApps = sortDockApps(combined);

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
            closeAllContextMenus();
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
            dockLoaded = true; // Load dock immediately
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
        active: (barIsReady || !hasBar) && modelData && (Settings.data.dock.monitors.length === 0 || Settings.data.dock.monitors.includes(modelData.name)) && autoHide

        sourceComponent: PanelWindow {
          id: peekWindow

          screen: modelData
          // Dynamic anchors based on dock position
          anchors.top: dockPosition === "top" || isVertical
          anchors.bottom: dockPosition === "bottom" || isVertical
          anchors.left: dockPosition === "left" || !isVertical
          anchors.right: dockPosition === "right" || !isVertical
          focusable: false
          color: "transparent"

          // When bar is at same edge, position peek window past the bar so it receives mouse events
          margins.top: dockPosition === "top" && barAtSameEdge ? (barHeight + (Settings.data.bar.floating ? Settings.data.bar.marginVertical : 0)) : 0
          margins.bottom: dockPosition === "bottom" && barAtSameEdge ? (barHeight + (Settings.data.bar.floating ? Settings.data.bar.marginVertical : 0)) : 0
          margins.left: dockPosition === "left" && barAtSameEdge ? (barHeight + (Settings.data.bar.floating ? Settings.data.bar.marginHorizontal : 0)) : 0
          margins.right: dockPosition === "right" && barAtSameEdge ? (barHeight + (Settings.data.bar.floating ? Settings.data.bar.marginHorizontal : 0)) : 0

          WlrLayershell.namespace: "noctalia-dock-peek-" + (screen?.name || "unknown")
          WlrLayershell.exclusionMode: ExclusionMode.Ignore
          // Larger peek area when bar is at same edge, normal 1px otherwise
          implicitHeight: barAtSameEdge && !isVertical ? 3 : peekHeight
          implicitWidth: barAtSameEdge && isVertical ? 3 : peekHeight

          MouseArea {
            id: peekArea
            anchors.fill: parent
            hoverEnabled: true

            onEntered: {
              peekHovered = true;
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
        active: Settings.data.dock.enabled && (barIsReady || !hasBar) && modelData && (Settings.data.dock.monitors.length === 0 || Settings.data.dock.monitors.includes(modelData.name)) && dockLoaded && ToplevelManager && (dockApps.length > 0)

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

            width: dockContainer.width + extraLeft + extraRight
            height: dockContainer.height + extraTop + extraBottom

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

            Rectangle {
              id: dockContainer
              // For vertical dock, swap width and height logic
              width: isVertical ? Math.round(iconSize * 1.5) : Math.min(dockLayout.implicitWidth + Style.marginXL, root.maxWidth)
              height: isVertical ? Math.min(dockLayout.implicitHeight + Style.marginXL, root.maxHeight) : Math.round(iconSize * 1.5)
              color: Qt.alpha(Color.mSurface, Settings.data.dock.backgroundOpacity)

              // Anchor based on padding to achieve centering shift
              anchors.horizontalCenter: parent.extraLeft > 0 || parent.extraRight > 0 ? undefined : parent.horizontalCenter
              anchors.right: parent.extraLeft > 0 ? parent.right : undefined
              anchors.left: parent.extraRight > 0 ? parent.left : undefined

              anchors.verticalCenter: parent.extraTop > 0 || parent.extraBottom > 0 ? undefined : parent.verticalCenter
              anchors.bottom: parent.extraTop > 0 ? parent.bottom : undefined
              anchors.top: parent.extraBottom > 0 ? parent.top : undefined

              radius: Style.radiusL
              border.width: Style.borderS
              border.color: Qt.alpha(Color.mOutline, Settings.data.dock.backgroundOpacity)

              // Enable layer caching to reduce GPU usage from continuous animations
              layer.enabled: true

              MouseArea {
                id: dockMouseArea
                anchors.fill: parent
                hoverEnabled: true

                onEntered: {
                  dockHovered = true;
                  if (autoHide) {
                    showTimer.stop();
                    hideTimer.stop();
                    unloadTimer.stop(); // Cancel unload if hovering
                    hidden = false; // Make sure dock is visible
                  }
                }

                onExited: {
                  dockHovered = false;
                  if (autoHide && !anyAppHovered && !peekHovered && !menuHovered && root.dragSourceIndex === -1) {
                    hideTimer.restart();
                  }
                }

                onClicked: {
                  // Close any open context menu when clicking on the dock background
                  closeAllContextMenus();
                }
              }

              Flickable {
                id: dock
                // Use parent dimensions more directly to avoid clipping
                width: isVertical ? parent.width : Math.min(dockLayout.implicitWidth, parent.width - Style.marginXL)
                height: !isVertical ? parent.height : Math.min(dockLayout.implicitHeight, parent.height - Style.marginXL)
                contentWidth: dockLayout.implicitWidth
                contentHeight: dockLayout.implicitHeight
                anchors.centerIn: parent
                clip: true

                flickableDirection: isVertical ? Flickable.VerticalFlick : Flickable.HorizontalFlick

                // Keep interactive dependent on overflow
                interactive: isVertical ? contentHeight > height : contentWidth > width

                // Centering margins
                contentX: isVertical && contentWidth < width ? (contentWidth - width) / 2 : 0
                contentY: !isVertical && contentHeight < height ? (contentHeight - height) / 2 : 0

                WheelHandler {
                  acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                  onWheel: event => {
                             var delta = (event.angleDelta.y !== 0) ? event.angleDelta.y : event.angleDelta.x;
                             if (root.isVertical) {
                               dock.contentY = Math.max(-dock.topMargin, Math.min(dock.contentHeight - dock.height + dock.bottomMargin, dock.contentY - delta));
                             } else {
                               // For horizontal dock, we want to scroll contentX with BOTH x and y wheels
                               var hDelta = (event.angleDelta.x !== 0) ? event.angleDelta.x : event.angleDelta.y;
                               dock.contentX = Math.max(-dock.leftMargin, Math.min(dock.contentWidth - dock.width + dock.rightMargin, dock.contentX - hDelta));
                             }
                             event.accepted = true;
                           }
                }

                ScrollBar.horizontal: ScrollBar {
                  visible: !isVertical && dock.interactive
                  policy: ScrollBar.AsNeeded
                }
                ScrollBar.vertical: ScrollBar {
                  visible: isVertical && dock.interactive
                  policy: ScrollBar.AsNeeded
                }

                function getAppIcon(appData): string {
                  if (!appData || !appData.appId)
                    return "";
                  return ThemeIcons.iconForAppId(appData.appId?.toLowerCase());
                }

                // Use GridLayout for flexible horizontal/vertical arrangement
                GridLayout {
                  id: dockLayout
                  columns: isVertical ? 1 : -1
                  rows: isVertical ? -1 : 1
                  rowSpacing: Style.marginS
                  columnSpacing: Style.marginS

                  // Ensure the layout takes its full implicit size
                  width: implicitWidth
                  height: implicitHeight

                  Repeater {
                    model: dockApps

                    delegate: Item {
                      id: appButton
                      readonly property real indicatorMargin: Math.max(3, Math.round(iconSize * 0.18))
                      Layout.preferredWidth: isVertical ? iconSize + indicatorMargin * 2 : iconSize
                      Layout.preferredHeight: isVertical ? iconSize : iconSize + indicatorMargin * 2
                      Layout.alignment: Qt.AlignCenter

                      property bool isActive: modelData.toplevel && ToplevelManager.activeToplevel && ToplevelManager.activeToplevel === modelData.toplevel
                      property bool hovered: appMouseArea.containsMouse
                      property string appId: modelData ? modelData.appId : ""
                      property string appTitle: {
                        if (!modelData)
                          return "";
                        // For running apps, use the toplevel title directly (reactive)
                        if (modelData.toplevel) {
                          const toplevelTitle = modelData.toplevel.title || "";
                          // If title is "Loading..." or empty, use desktop entry name
                          if (!toplevelTitle || toplevelTitle === "Loading..." || toplevelTitle.trim() === "") {
                            return root.getAppNameFromDesktopEntry(modelData.appId) || modelData.appId;
                          }
                          return toplevelTitle;
                        }
                        // For pinned apps that aren't running, use the stored title
                        return modelData.title || modelData.appId || "";
                      }
                      property bool isRunning: modelData && (modelData.type === "running" || modelData.type === "pinned-running")

                      // Store index for drag-and-drop
                      property int modelIndex: index
                      objectName: "dockAppButton"

                      DropArea {
                        anchors.fill: parent
                        keys: ["dock-app"]
                        onEntered: function (drag) {
                          if (drag.source && drag.source.objectName === "dockAppButton") {
                            root.dragTargetIndex = appButton.modelIndex;
                          }
                        }
                        onExited: function () {
                          if (root.dragTargetIndex === appButton.modelIndex) {
                            root.dragTargetIndex = -1;
                          }
                        }
                        onDropped: function (drop) {
                          root.dragSourceIndex = -1;
                          root.dragTargetIndex = -1;
                          if (drop.source && drop.source.objectName === "dockAppButton" && drop.source !== appButton) {
                            root.reorderApps(drop.source.modelIndex, appButton.modelIndex);
                          }
                        }
                      }

                      // Listen for the toplevel being closed
                      Connections {
                        target: modelData?.toplevel
                        function onClosed() {
                          Qt.callLater(root.updateDockApps);
                        }
                      }

                      // Draggable container for the icon
                      Item {
                        id: iconContainer
                        width: iconSize
                        height: iconSize

                        // When dragging, remove anchors so MouseArea can position it
                        anchors.centerIn: dragging ? undefined : parent

                        property bool dragging: appMouseArea.drag.active
                        onDraggingChanged: {
                          if (dragging) {
                            root.dragSourceIndex = index;
                          } else {
                            // Reset if not handled by drop (e.g. dropped outside)
                            Qt.callLater(() => {
                                           if (!appMouseArea.drag.active && root.dragSourceIndex === index) {
                                             root.dragSourceIndex = -1;
                                             root.dragTargetIndex = -1;
                                           }
                                         });
                          }
                        }

                        Drag.active: dragging
                        Drag.source: appButton
                        Drag.hotSpot.x: width / 2
                        Drag.hotSpot.y: height / 2
                        Drag.keys: ["dock-app"]

                        z: (root.dragSourceIndex === index) ? 1000 : ((dragging ? 1000 : 0))
                        scale: dragging ? 1.1 : (appButton.hovered ? 1.15 : 1.0)
                        Behavior on scale {
                          NumberAnimation {
                            duration: Style.animationNormal
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.2
                          }
                        }

                        // Visual shifting logic
                        readonly property bool isDragged: root.dragSourceIndex === index
                        property real shiftOffset: 0

                        Binding on shiftOffset {
                          value: {
                            if (root.dragSourceIndex !== -1 && root.dragTargetIndex !== -1 && !iconContainer.isDragged) {
                              if (root.dragSourceIndex < root.dragTargetIndex) {
                                // Dragging Forward: Items between source and target shift Backward
                                if (index > root.dragSourceIndex && index <= root.dragTargetIndex) {
                                  return -1 * (root.isVertical ? iconSize + Style.marginS : iconSize + Style.marginS);
                                }
                              } else if (root.dragSourceIndex > root.dragTargetIndex) {
                                // Dragging Backward: Items between target and source shift Forward
                                if (index >= root.dragTargetIndex && index < root.dragSourceIndex) {
                                  return (root.isVertical ? iconSize + Style.marginS : iconSize + Style.marginS);
                                }
                              }
                            }
                            return 0;
                          }
                        }

                        transform: Translate {
                          x: !root.isVertical ? iconContainer.shiftOffset : 0
                          y: root.isVertical ? iconContainer.shiftOffset : 0

                          Behavior on x {
                            NumberAnimation {
                              duration: Style.animationFast
                              easing.type: Easing.OutQuad
                            }
                          }
                          Behavior on y {
                            NumberAnimation {
                              duration: Style.animationFast
                              easing.type: Easing.OutQuad
                            }
                          }
                        }

                        IconImage {
                          id: appIcon
                          anchors.fill: parent
                          source: {
                            root.iconRevision; // Force re-evaluation when revision changes
                            return dock.getAppIcon(modelData);
                          }
                          visible: source.toString() !== ""
                          smooth: true
                          asynchronous: true

                          // Dim pinned apps that aren't running
                          opacity: appButton.isRunning ? 1.0 : Settings.data.dock.deadOpacity

                          // Apply dock-specific colorization shader only to non-focused apps
                          layer.enabled: !appButton.isActive && Settings.data.dock.colorizeIcons
                          layer.effect: ShaderEffect {
                            property color targetColor: Settings.data.colorSchemes.darkMode ? Color.mOnSurface : Color.mSurfaceVariant
                            property real colorizeMode: 0.0 // Dock mode (grayscale)

                            fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
                          }

                          Behavior on opacity {
                            NumberAnimation {
                              duration: Style.animationFast
                              easing.type: Easing.OutQuad
                            }
                          }
                        }

                        // Fall back if no icon
                        NIcon {
                          anchors.centerIn: parent
                          visible: !appIcon.visible
                          icon: "question-mark"
                          pointSize: iconSize * 0.7
                          color: appButton.isActive ? Color.mPrimary : Color.mOnSurfaceVariant
                          opacity: appButton.isRunning ? 1.0 : 0.6

                          Behavior on opacity {
                            NumberAnimation {
                              duration: Style.animationFast
                              easing.type: Easing.OutQuad
                            }
                          }
                        }
                      }

                      // Context menu popup
                      DockMenu {
                        id: contextMenu
                        dockPosition: root.dockPosition // Pass dock position for menu placement
                        onHoveredChanged: {
                          // Only update menuHovered if this menu is current and visible
                          if (root.currentContextMenu === contextMenu && contextMenu.visible) {
                            menuHovered = hovered;
                          } else {
                            menuHovered = false;
                          }
                        }

                        Connections {
                          target: contextMenu
                          function onRequestClose() {
                            // Clear current menu immediately to prevent hover updates
                            root.currentContextMenu = null;
                            hideTimer.stop();
                            contextMenu.hide();
                            menuHovered = false;
                            anyAppHovered = false;
                          }
                        }
                        onAppClosed: root.updateDockApps // Force immediate dock update when app is closed
                        onVisibleChanged: {
                          if (visible) {
                            root.currentContextMenu = contextMenu;
                          } else if (root.currentContextMenu === contextMenu) {
                            root.currentContextMenu = null;
                            hideTimer.stop();
                            menuHovered = false;
                            // Restart hide timer after menu closes
                            if (autoHide && !dockHovered && !anyAppHovered && !peekHovered && !menuHovered) {
                              hideTimer.restart();
                            }
                          }
                        }
                      }

                      MouseArea {
                        id: appMouseArea
                        objectName: "appMouseArea"
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

                        // Only allow left-click dragging via axis control
                        drag.target: iconContainer
                        drag.axis: (pressedButtons & Qt.LeftButton) ? (root.isVertical ? Drag.YAxis : Drag.XAxis) : Drag.None

                        onPressed: {
                          var p1 = appButton.mapFromItem(dockContainer, 0, 0);
                          var p2 = appButton.mapFromItem(dockContainer, dockContainer.width, dockContainer.height);
                          drag.minimumX = p1.x;
                          drag.maximumX = p2.x - iconContainer.width;
                          drag.minimumY = p1.y;
                          drag.maximumY = p2.y - iconContainer.height;
                        }

                        onReleased: {
                          if (iconContainer.Drag.active) {
                            iconContainer.Drag.drop();
                          }
                        }

                        onEntered: {
                          anyAppHovered = true;
                          const appName = appButton.appTitle || appButton.appId || "Unknown";
                          const tooltipText = appName.length > 40 ? appName.substring(0, 37) + "..." : appName;
                          if (!contextMenu.visible) {
                            TooltipService.show(appButton, tooltipText, "top");
                          }
                          if (autoHide) {
                            showTimer.stop();
                            hideTimer.stop();
                            unloadTimer.stop(); // Cancel unload if hovering app
                            hidden = false; // Make sure dock is visible
                          }
                        }

                        onExited: {
                          anyAppHovered = false;
                          TooltipService.hide();
                          // Clear menuHovered if no current menu or menu not visible
                          if (!root.currentContextMenu || !root.currentContextMenu.visible) {
                            menuHovered = false;
                          }
                          if (autoHide && !dockHovered && !peekHovered && !menuHovered && root.dragSourceIndex === -1) {
                            hideTimer.restart();
                          }
                        }

                        onClicked: mouse => {
                                     if (mouse.button === Qt.RightButton) {
                                       // If right-clicking on the same app with an open context menu, close it
                                       if (root.currentContextMenu === contextMenu && contextMenu.visible) {
                                         root.closeAllContextMenus();
                                         return;
                                       }
                                       // Close any other existing context menu first
                                       root.closeAllContextMenus();
                                       // Hide tooltip when showing context menu
                                       TooltipService.hideImmediately();
                                       contextMenu.show(appButton, modelData.toplevel || modelData);
                                       return;
                                     }

                                     // Close any existing context menu for non-right-click actions
                                     root.closeAllContextMenus();

                                     // Check if toplevel is still valid (not a stale reference)
                                     const isValidToplevel = modelData?.toplevel && ToplevelManager && ToplevelManager.toplevels.values.includes(modelData.toplevel);

                                     if (mouse.button === Qt.MiddleButton && isValidToplevel && modelData.toplevel.close) {
                                       modelData.toplevel.close();
                                       Qt.callLater(root.updateDockApps); // Force immediate dock update
                                     } else if (mouse.button === Qt.LeftButton) {
                                       if (isValidToplevel && modelData.toplevel.activate) {
                                         // Running app - activate it
                                         modelData.toplevel.activate();
                                       } else if (modelData?.appId) {
                                         // Pinned app not running - launch it
                                         // Use ThemeIcons to robustly find the desktop entry
                                         const app = ThemeIcons.findAppEntry(modelData.appId);

                                         if (!app) {
                                           Logger.w("Dock", `Could not find desktop entry for pinned app: ${modelData.appId}`);
                                           return;
                                         }

                                         if (Settings.data.appLauncher.customLaunchPrefixEnabled && Settings.data.appLauncher.customLaunchPrefix) {
                                           // Use custom launch prefix
                                           const prefix = Settings.data.appLauncher.customLaunchPrefix.split(" ");

                                           if (app.runInTerminal) {
                                             const terminal = Settings.data.appLauncher.terminalCommand.split(" ");
                                             const command = prefix.concat(terminal.concat(app.command));
                                             Quickshell.execDetached(command);
                                           } else {
                                             const command = prefix.concat(app.command);
                                             Quickshell.execDetached(command);
                                           }
                                         } else if (Settings.data.appLauncher.useApp2Unit && ProgramCheckerService.app2unitAvailable && app.id) {
                                           Logger.d("Dock", `Using app2unit for: ${app.id}`);
                                           if (app.runInTerminal)
                                           Quickshell.execDetached(["app2unit", "--", app.id + ".desktop"]);
                                           else
                                           Quickshell.execDetached(["app2unit", "--"].concat(app.command));
                                         } else {
                                           // Fallback logic when app2unit is not used
                                           if (app.runInTerminal) {
                                             Logger.d("Dock", "Executing terminal app manually: " + app.name);
                                             const terminal = Settings.data.appLauncher.terminalCommand.split(" ");
                                             const command = terminal.concat(app.command);
                                             CompositorService.spawn(command);
                                           } else if (app.command && app.command.length > 0) {
                                             CompositorService.spawn(app.command);
                                           } else if (app.execute) {
                                             app.execute();
                                           } else {
                                             Logger.w("Dock", `Could not launch: ${app.name}. No valid launch method.`);
                                           }
                                         }
                                       }
                                     }
                                   }
                      }

                      // Active indicator - positioned at the edge of the delegate area
                      Rectangle {
                        visible: Settings.data.dock.inactiveIndicators ? isRunning : isActive
                        width: isVertical ? indicatorMargin * 0.6 : iconSize * 0.2
                        height: isVertical ? iconSize * 0.2 : indicatorMargin * 0.6
                        color: Color.mPrimary
                        radius: Style.radiusXS

                        // Anchor to the edge facing the screen center
                        anchors.bottom: !isVertical && dockPosition === "bottom" ? parent.bottom : undefined
                        anchors.top: !isVertical && dockPosition === "top" ? parent.top : undefined
                        anchors.left: isVertical && dockPosition === "left" ? parent.left : undefined
                        anchors.right: isVertical && dockPosition === "right" ? parent.right : undefined

                        anchors.horizontalCenter: isVertical ? undefined : parent.horizontalCenter
                        anchors.verticalCenter: isVertical ? parent.verticalCenter : undefined

                        // Offset slightly from the edge
                        anchors.bottomMargin: !isVertical && dockPosition === "bottom" ? 2 : 0
                        anchors.topMargin: !isVertical && dockPosition === "top" ? 2 : 0
                        anchors.leftMargin: isVertical && dockPosition === "left" ? 2 : 0
                        anchors.rightMargin: isVertical && dockPosition === "right" ? 2 : 0
                      }

                      // Multiple instances badge - positioned opposite to active indicator
                      Rectangle {
                        visible: modelData && modelData.instanceCount && modelData.instanceCount > 1
                        width: isVertical ? iconSize * 0.28 : indicatorMargin * 0.8
                        height: isVertical ? indicatorMargin * 0.8 : iconSize * 0.28
                        color: Color.mPrimaryContainer
                        radius: width / 2

                        // Anchor to the edge opposite to screen center
                        anchors.bottom: !isVertical && dockPosition === "top" ? parent.bottom : undefined
                        anchors.top: !isVertical && dockPosition === "bottom" ? parent.top : undefined
                        anchors.left: isVertical && dockPosition === "right" ? parent.left : undefined
                        anchors.right: isVertical && dockPosition === "left" ? parent.right : undefined

                        anchors.horizontalCenter: isVertical ? undefined : parent.horizontalCenter
                        anchors.verticalCenter: isVertical ? parent.verticalCenter : undefined

                        // Offset slightly from the edge
                        anchors.bottomMargin: !isVertical && dockPosition === "top" ? 2 : 0
                        anchors.topMargin: !isVertical && dockPosition === "bottom" ? 2 : 0
                        anchors.leftMargin: isVertical && dockPosition === "right" ? 2 : 0
                        anchors.rightMargin: isVertical && dockPosition === "left" ? 2 : 0

                        Text {
                          anchors.centerIn: parent
                          text: modelData.instanceCount > 9 ? "9+" : modelData.instanceCount.toString()
                          font.pixelSize: Math.max(8, Math.round(width * 0.6))
                          color: Color.mOnPrimaryContainer
                          horizontalAlignment: Text.AlignHCenter
                          verticalAlignment: Text.AlignVCenter
                          renderType: Text.NativeRendering
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
