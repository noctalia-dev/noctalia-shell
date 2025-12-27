import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
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

      // Bar detection and positioning properties
      readonly property bool hasBar: modelData && modelData.name ? (Settings.data.bar.monitors.includes(modelData.name) || (Settings.data.bar.monitors.length === 0)) : false
      readonly property bool barAtBottom: hasBar && Settings.data.bar.position === "bottom"
      readonly property int barHeight: Style.barHeight

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

      // Function to close any open context menu
      function closeAllContextMenus() {
        if (currentContextMenu && currentContextMenu.visible) {
          currentContextMenu.hide();
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

        //push an app onto combined with the given appType
        function pushApp(appType, toplevel, appId, title) {
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
                            "appId": appId,
                            "title": title
                          });
            processedToplevels.add(toplevel);
          } else {
            // For pinned apps that aren't running, track by appId to avoid duplicates
            if (processedPinnedAppIds.has(appId)) {
              return; // Already processed this pinned app
            }
            combined.push({
                            "type": appType,
                            "toplevel": toplevel,
                            "appId": appId,
                            "title": title
                          });
            processedPinnedAppIds.add(appId);
          }
        }

        function pushRunning(first) {
          runningApps.forEach(toplevel => {
                                if (toplevel) {
                                  // Skip pinned apps if they were already processed (when pinnedStatic is true)
                                  const isPinned = pinnedApps.includes(toplevel.appId);
                                  if (!first && isPinned && processedToplevels.has(toplevel)) {
                                    return; // Already added by pushPinned()
                                  }
                                  pushApp((first && isPinned) ? "pinned-running" : "running", toplevel, toplevel.appId, toplevel.title);
                                }
                              });
        }

        function pushPinned() {
          pinnedApps.forEach(pinnedAppId => {
                               // Find all running instances of this pinned app
                               const matchingToplevels = runningApps.filter(app => app && app.appId === pinnedAppId);

                               if (matchingToplevels.length > 0) {
                                 // Add all running instances as pinned-running
                                 matchingToplevels.forEach(toplevel => {
                                                             pushApp("pinned-running", toplevel, pinnedAppId, toplevel.title);
                                                           });
                               } else {
                                 // App is pinned but not running - add once
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

        dockApps = combined;
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

      // PEEK WINDOW - Always visible when auto-hide is enabled
      Loader {
        active: (barIsReady || !hasBar) && modelData && (Settings.data.dock.monitors.length === 0 || Settings.data.dock.monitors.includes(modelData.name)) && autoHide

        sourceComponent: PanelWindow {
          id: peekWindow

          screen: modelData
          anchors.bottom: true
          anchors.left: true
          anchors.right: true
          focusable: false
          color: Color.transparent

          WlrLayershell.namespace: "noctalia-dock-peek-" + (screen?.name || "unknown")
          WlrLayershell.exclusionMode: ExclusionMode.Ignore
          implicitHeight: peekHeight

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

      // DOCK WINDOW
      Loader {
        id: dockWindowLoader
        active: Settings.data.dock.enabled && (barIsReady || !hasBar) && modelData && (Settings.data.dock.monitors.length === 0 || Settings.data.dock.monitors.includes(modelData.name)) && dockLoaded && ToplevelManager && (dockApps.length > 0)

        sourceComponent: PanelWindow {
          id: dockWindow

          screen: modelData

          focusable: false
          color: Color.transparent

          WlrLayershell.namespace: "noctalia-dock-" + (screen?.name || "unknown")
          WlrLayershell.exclusionMode: exclusive ? ExclusionMode.Auto : ExclusionMode.Ignore

          // Size to fit the dock container exactly
          implicitWidth: dockContainerWrapper.width
          implicitHeight: dockContainerWrapper.height

          // Position above the bar if it's at bottom
          anchors.bottom: true

          margins.bottom: {
            switch (Settings.data.bar.position) {
            case "bottom":
              return (Style.barHeight + Style.marginM) + (Settings.data.bar.floating ? Settings.data.bar.marginVertical * Style.marginXL + floatingMargin : floatingMargin);
            default:
              return floatingMargin;
            }
          }

          // Wrapper item for scale/opacity animations
          Item {
            id: dockContainerWrapper
            width: dockContainer.width
            height: dockContainer.height
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom

            // Apply animations to this wrapper
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
              width: dockLayout.implicitWidth + Style.marginM * 2
              height: Math.round(iconSize * 1.5)
              color: Qt.alpha(Color.mSurface, Settings.data.dock.backgroundOpacity)
              anchors.centerIn: parent
              radius: Style.radiusL
              border.width: Style.borderS
              border.color: Qt.alpha(Color.mOutline, Settings.data.dock.backgroundOpacity)

              // Enable layer caching to reduce GPU usage from continuous animations
              // (pulse animations on active indicators run infinitely)
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
                width: dockLayout.implicitWidth
                height: parent.height - (Style.marginM * 2)
                anchors.centerIn: parent

                function getAppIcon(appData): string {
                  if (!appData || !appData.appId)
                    return "";
                  return ThemeIcons.iconForAppId(appData.appId?.toLowerCase());
                }

                RowLayout {
                  id: dockLayout
                  spacing: Style.marginM
                  Layout.preferredHeight: parent.height
                  anchors.centerIn: parent

                  Repeater {
                    model: dockApps

                    delegate: Item {
                      id: appButton
                      Layout.preferredWidth: iconSize
                      Layout.preferredHeight: iconSize
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

                      // Listen for the toplevel being closed
                      Connections {
                        target: modelData?.toplevel
                        function onClosed() {
                          Qt.callLater(root.updateDockApps);
                        }
                      }

                      Image {
                        id: appIcon
                        width: iconSize
                        height: iconSize
                        anchors.centerIn: parent
                        source: dock.getAppIcon(modelData)
                        visible: source.toString() !== ""
                        sourceSize.width: iconSize * 2
                        sourceSize.height: iconSize * 2
                        smooth: true
                        mipmap: true
                        antialiasing: true
                        fillMode: Image.PreserveAspectFit
                        cache: true

                        // Dim pinned apps that aren't running
                        opacity: appButton.isRunning ? 1.0 : Settings.data.dock.deadOpacity

                        scale: appButton.hovered ? 1.15 : 1.0

                        // Apply dock-specific colorization shader only to non-focused apps
                        layer.enabled: !appButton.isActive && Settings.data.dock.colorizeIcons
                        layer.effect: ShaderEffect {
                          property color targetColor: Settings.data.colorSchemes.darkMode ? Color.mOnSurface : Color.mSurfaceVariant
                          property real colorizeMode: 0.0 // Dock mode (grayscale)

                          fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
                        }

                        Behavior on scale {
                          NumberAnimation {
                            duration: Style.animationNormal
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.2
                          }
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
                        scale: appButton.hovered ? 1.15 : 1.0

                        Behavior on scale {
                          NumberAnimation {
                            duration: Style.animationFast
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.2
                          }
                        }

                        Behavior on opacity {
                          NumberAnimation {
                            duration: Style.animationFast
                            easing.type: Easing.OutQuad
                          }
                        }
                      }

                      // Context menu popup
                      DockMenu {
                        id: contextMenu
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
                              const app = DesktopEntries.byId(modelData.appId);

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

                      // Active indicator
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
