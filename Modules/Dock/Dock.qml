import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Services.Compositor
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

      // Update dock apps when windows change
       Connections {
         target: CompositorService
         function onWindowListChanged() {
           updateDockApps();
         }
       }

       // Additional connection for workspace changes
       Connections {
         target: CompositorService
         function onWorkspaceChanged() {
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
         function onOnlyCurrentWorkspaceChanged() {
           updateDockApps();
         }
       }

      // Initial update when component is ready
      Component.onCompleted: {
        updateDockApps();
      }

      // Refresh icons when DesktopEntries becomes available
      Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
          root.iconRevision++;
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
        // prefer window object identity for running apps to distinguish instances
        if (appData.window)
          return appData.window;
        // fallback to appId for pinned-only apps
        return appData.appId;
      }

      function sortDockApps(apps) {
        if (!sessionAppOrder || sessionAppOrder.length === 0) {
          return apps;
        }

        const sorted = [];
        const remaining = [...apps];

        // 1. Pick apps that are in the session order
        for (let i = 0; i < sessionAppOrder.length; i++) {
          const key = sessionAppOrder[i];
          const idx = remaining.findIndex(app => getAppKey(app) === key);
          if (idx !== -1) {
            sorted.push(remaining[idx]);
            remaining.splice(idx, 1);
          }
        }

        // 2. Append any new/remaining apps
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
        return appId.toLowerCase().trim();
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
        return appId;
      }

      // Function to update the combined dock apps model
        function updateDockApps() {
          let activeIds = [];
          try {
            const activeWorkspaces = CompositorService.getActiveWorkspaces();
            activeIds = activeWorkspaces.map(function (ws) {
              return ws.id;
            });
          } catch (e) {
            console.warn("Could not get active workspaces:", e);
            activeIds = [];
          }


         // Use CompositorService.windows like Taskbar does for consistency
         const runningWindows = [];
         if (CompositorService.windows) {
           const total = CompositorService.windows.count || 0;
           for (let i = 0; i < total; i++) {
             const w = CompositorService.windows.get(i);
             if (w) {
                const passOutput = (!Settings.data.dock.onlySameOutput) || (w.output == modelData?.name);
                const passWorkspace = (!Settings.data.dock.onlyCurrentWorkspace) || (activeIds.length === 0) || (w.workspaceId !== undefined && w.workspaceId !== null && activeIds.includes(w.workspaceId));
               if (passOutput && passWorkspace) {
                 runningWindows.push(w);
               }
             }
           }
         }

         const pinnedApps = Settings.data.dock.pinnedApps || [];
         const combined = [];
         const processedWindows = new Set();
         const processedPinnedAppIds = new Set();

         //push an app onto combined with the given appType
         function pushApp(appType, window, appId, title) {
           if (window) {
             if (processedWindows.has(window)) {
               return;
             }
              combined.push({
                              "type": appType,
                              "window": window,
                              "appId": appId,
                              "title": title
                            });
             processedWindows.add(window);
           } else {
             // For pinned apps that aren't running, track by appId to avoid duplicates
             if (processedPinnedAppIds.has(appId)) {
               return;
             }
             combined.push({
                             "type": appType,
                             "window": null,
                             "appId": appId,
                             "title": title
                           });
             processedPinnedAppIds.add(appId);
           }
         }

         function pushRunning(first) {
           runningWindows.forEach(window => {
                                 if (window) {
                                   // Skip pinned apps if they were already processed (when pinnedStatic is true)
                                   const isPinned = pinnedApps.includes(window.appId);
                                   if (!first && isPinned && processedWindows.has(window)) {
                                     return;
                                   }
                                   pushApp((first && isPinned) ? "pinned-running" : "running", window, window.appId, window.title);
                                 }
                               });
         }

         function pushPinned() {
           pinnedApps.forEach(pinnedAppId => {
                                // Find all running instances of this pinned app
                                const matchingWindows = runningWindows.filter(app => app && app.appId === pinnedAppId);

                                if (matchingWindows.length > 0) {
                                  matchingWindows.forEach(window => {
                                                              pushApp("pinned-running", window, pinnedAppId, window.title);
                                                            });
                                } else {
                                  pushApp("pinned", null, pinnedAppId, pinnedAppId);
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
         // Sync session order if needed (e.g. first run or new apps added)
         if (!sessionAppOrder || sessionAppOrder.length === 0 || sessionAppOrder.length !== dockApps.length) {
           sessionAppOrder = dockApps.map(getAppKey);
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
          // Force menuHovered to false if no menu is current or visible
          if (!root.currentContextMenu || !root.currentContextMenu.visible) {
            menuHovered = false;
          }
          if (autoHide && !dockHovered && !anyAppHovered && !peekHovered && !menuHovered) {
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
         active: Settings.data.dock.enabled && (barIsReady || !hasBar) && modelData && (Settings.data.dock.monitors.length === 0 || Settings.data.dock.monitors.includes(modelData.name)) && dockLoaded && CompositorService && (dockApps.length > 0)

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
              width: isVertical ? Math.round(iconSize * 1.5) : dockLayout.implicitWidth + Style.marginXL
              height: isVertical ? dockLayout.implicitHeight + Style.marginXL : Math.round(iconSize * 1.5)
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
                  }
                }

                onExited: {
                  dockHovered = false;
                  if (autoHide && !anyAppHovered && !peekHovered && !menuHovered) {
                    hideTimer.restart();
                  }
                }

                onClicked: {
                  // Close any open context menu when clicking on the dock background
                  closeAllContextMenus();
                }
              }

              Item {
                id: dock
                // Swap dimensions based on orientation
                width: isVertical ? parent.width - (Style.marginXL) : dockLayout.implicitWidth
                height: isVertical ? dockLayout.implicitHeight : parent.height - (Style.marginXL)
                anchors.centerIn: parent

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
                  anchors.centerIn: parent

                  Repeater {
                    model: dockApps

                    delegate: Item {
                      id: appButton
                      Layout.preferredWidth: iconSize
                      Layout.preferredHeight: iconSize
                      Layout.alignment: Qt.AlignCenter

                       property bool isActive: modelData.window && modelData.window.isFocused
                       property bool hovered: appMouseArea.containsMouse
                       property string appId: modelData ? modelData.appId : ""
                         property string appTitle: {
                           if (!modelData)
                             return "";
                           // For running apps, use the window title directly (reactive)
                           if (modelData.window) {
                             const windowTitle = modelData.window.title || "";
                             // If title is "Loading..." or empty, use desktop entry name
                             if (!windowTitle || windowTitle === "Loading..." || windowTitle.trim() === "") {
                               return root.getAppNameFromDesktopEntry(modelData.appId) || modelData.appId;
                             }
                             return windowTitle;
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
                        onDropped: function (drop) {
                          if (drop.source && drop.source.objectName === "dockAppButton" && drop.source !== appButton) {
                            root.reorderApps(drop.source.modelIndex, appButton.modelIndex);
                          }
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

                        Drag.active: dragging
                        Drag.source: appButton
                        Drag.hotSpot.x: width / 2
                        Drag.hotSpot.y: height / 2
                        Drag.keys: ["dock-app"]

                        z: dragging ? 1000 : 0
                        scale: dragging ? 1.1 : (appButton.hovered ? 1.15 : 1.0)
                        Behavior on scale {
                          NumberAnimation {
                            duration: Style.animationNormal
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.2
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
                            anyAppHovered = false;
                          } else if (root.currentContextMenu === contextMenu) {
                            root.currentContextMenu = null;
                            hideTimer.stop();
                            menuHovered = false;
                            anyAppHovered = false;
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
                        drag.axis: (pressedButtons & Qt.LeftButton) ? Drag.XAndYAxis : Drag.None
                        preventStealing: true

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
                          }
                        }

                        onExited: {
                          anyAppHovered = false;
                          TooltipService.hide();
                          // Clear menuHovered if no current menu or menu not visible
                          if (!root.currentContextMenu || !root.currentContextMenu.visible) {
                            menuHovered = false;
                          }
                          if (autoHide && !dockHovered && !peekHovered && !menuHovered) {
                            hideTimer.restart();
                          }
                        }

                        onClicked: function (mouse) {
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
                            contextMenu.show(appButton, modelData.window || modelData);
                            return;
                          }

                           // Close any existing context menu for non-right-click actions
                          root.closeAllContextMenus();

                          // Check if window is valid
                          const isValidWindow = modelData?.window;

                          if (mouse.button === Qt.MiddleButton && isValidWindow) {
                            CompositorService.closeWindow(modelData.window);
                            Qt.callLater(root.updateDockApps); // Force immediate dock update
                          } else if (mouse.button === Qt.LeftButton) {
                            if (isValidWindow) {
                              // Running app - focus it
                              CompositorService.focusWindow(modelData.window);
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
                              } else if (Settings.data.appLauncher.useApp2Unit && app.id) {
                                Logger.d("Dock", `Using app2unit for: ${app.id}`);
                                if (app.runInTerminal)
                                  Quickshell.execDetached(["app2unit", "--", app.id + ".desktop"]);
                                else
                                  Quickshell.execDetached(["app2unit", "--"].concat(app.command));
                              } else {
                                // Fallback logic when app2unit is not used
                                if (app.runInTerminal) {
                                  // If app.execute() fails for terminal apps, we handle it manually.
                                  Logger.d("Dock", "Executing terminal app manually: " + app.name);
                                  const terminal = Settings.data.appLauncher.terminalCommand.split(" ");
                                  const command = terminal.concat(app.command);
                                  Quickshell.execDetached(command);
                                } else if (app.command && app.command.length > 0) {
                                  Quickshell.execDetached(app.command);
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

                      // Active indicator - always below the icon
                      Rectangle {
                        visible: Settings.data.dock.inactiveIndicators ? isRunning : isActive
                        width: iconSize * 0.2
                        height: iconSize * 0.1
                        color: Color.mPrimary
                        radius: Style.radiusXS
                        anchors.top: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
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