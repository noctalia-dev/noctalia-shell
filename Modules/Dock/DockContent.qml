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

Item {
  required property var dockRoot
  required property int extraTop
  required property int extraBottom
  required property int extraLeft
  required property int extraRight
  property alias dockContainer: dockContainer
  readonly property bool isStaticMode: Settings.data.dock.dockType === "static"

  Rectangle {
    id: dockContainer
    // For vertical dock, swap width and height logic
    width: dockRoot.isVertical ? Math.round(dockRoot.iconSize * 1.5) : Math.min(dockLayout.implicitWidth + Style.marginXL, dockRoot.maxWidth)
    height: dockRoot.isVertical ? Math.min(dockLayout.implicitHeight + Style.marginXL, dockRoot.maxHeight) : Math.round(dockRoot.iconSize * 1.5)
    color: Qt.alpha(Color.mSurface, (isStaticMode ? 0 : Settings.data.dock.backgroundOpacity))

    // Anchor based on padding to achieve centering shift
    anchors.horizontalCenter: extraLeft > 0 || extraRight > 0 ? undefined : parent.horizontalCenter
    anchors.right: extraLeft > 0 ? parent.right : undefined
    anchors.left: extraRight > 0 ? parent.left : undefined

    anchors.verticalCenter: extraTop > 0 || extraBottom > 0 ? undefined : parent.verticalCenter
    anchors.bottom: extraTop > 0 ? parent.bottom : undefined
    anchors.top: extraBottom > 0 ? parent.top : undefined

    radius: Style.radiusL
    border.width: Style.borderS
    border.color: Qt.alpha(Color.mOutline, (isStaticMode ? 0 : Settings.data.dock.backgroundOpacity))

    // Enable layer caching to reduce GPU usage from continuous animations
    layer.enabled: true

    MouseArea {
      id: dockMouseArea
      anchors.fill: parent
      hoverEnabled: true

      onEntered: {
        dockRoot.dockHovered = true;
        if (dockRoot.autoHide) {
          dockRoot.showTimer.stop();
          dockRoot.hideTimer.stop();
          dockRoot.unloadTimer.stop(); // Cancel unload if hovering
          dockRoot.hidden = false; // Make sure dock is visible
        }
      }

      onExited: {
        dockRoot.dockHovered = false;
        if (dockRoot.autoHide && !dockRoot.anyAppHovered && !dockRoot.peekHovered && !dockRoot.menuHovered && dockRoot.dragSourceIndex === -1) {
          dockRoot.hideTimer.restart();
        }
      }

      onClicked: {
        // Close any open context menu when clicking on the dock background
        dockRoot.closeAllContextMenus();
      }
    }

    Flickable {
      id: dock
      // Use parent dimensions more directly to avoid clipping
      width: dockRoot.isVertical ? parent.width : Math.min(dockLayout.implicitWidth, parent.width - Style.marginXL)
      height: !dockRoot.isVertical ? parent.height : Math.min(dockLayout.implicitHeight, parent.height - Style.marginXL)
      contentWidth: dockLayout.implicitWidth
      contentHeight: dockLayout.implicitHeight
      anchors.centerIn: parent
      clip: true

      flickableDirection: dockRoot.isVertical ? Flickable.VerticalFlick : Flickable.HorizontalFlick

      // Keep interactive dependent on overflow
      interactive: dockRoot.isVertical ? contentHeight > height : contentWidth > width

      // Centering margins
      contentX: dockRoot.isVertical && contentWidth < width ? (contentWidth - width) / 2 : 0
      contentY: !dockRoot.isVertical && contentHeight < height ? (contentHeight - height) / 2 : 0

      WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
                   var delta = (event.angleDelta.y !== 0) ? event.angleDelta.y : event.angleDelta.x;
                   if (dockRoot.isVertical) {
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
        visible: !dockRoot.isVertical && dock.interactive
        policy: ScrollBar.AsNeeded
      }
      ScrollBar.vertical: ScrollBar {
        visible: dockRoot.isVertical && dock.interactive
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
        columns: dockRoot.isVertical ? 1 : -1
        rows: dockRoot.isVertical ? -1 : 1
        rowSpacing: Style.marginS
        columnSpacing: Style.marginS

        // Ensure the layout takes its full implicit size
        width: implicitWidth
        height: implicitHeight

        Component {
          id: launcherButtonComponent

          Item {
            id: launcherButton
            anchors.fill: parent
            readonly property string screenName: dockRoot.modelData ? dockRoot.modelData.name : (dockRoot.screen ? dockRoot.screen.name : "")
            readonly property var launcherWidgetSettings: {
              const widgetsBySection = screenName ? Settings.getBarWidgetsForScreen(screenName) : Settings.data.bar.widgets;
              if (!widgetsBySection)
                return {};
              const sections = ["left", "center", "right"];
              for (let i = 0; i < sections.length; i++) {
                const sectionWidgets = widgetsBySection[sections[i]] || [];
                for (let j = 0; j < sectionWidgets.length; j++) {
                  const widget = sectionWidgets[j];
                  if (widget && widget.id === "Launcher")
                    return widget;
                }
              }
              return {};
            }
            readonly property string launcherWidgetSection: {
              const widgetsBySection = screenName ? Settings.getBarWidgetsForScreen(screenName) : Settings.data.bar.widgets;
              if (!widgetsBySection)
                return "";
              const sections = ["left", "center", "right"];
              for (let i = 0; i < sections.length; i++) {
                const sectionWidgets = widgetsBySection[sections[i]] || [];
                for (let j = 0; j < sectionWidgets.length; j++) {
                  const widget = sectionWidgets[j];
                  if (widget && widget.id === "Launcher")
                    return sections[i];
                }
              }
              return "";
            }
            readonly property int launcherWidgetIndex: {
              const widgetsBySection = screenName ? Settings.getBarWidgetsForScreen(screenName) : Settings.data.bar.widgets;
              if (!widgetsBySection)
                return -1;
              const sections = ["left", "center", "right"];
              for (let i = 0; i < sections.length; i++) {
                const sectionWidgets = widgetsBySection[sections[i]] || [];
                for (let j = 0; j < sectionWidgets.length; j++) {
                  const widget = sectionWidgets[j];
                  if (widget && widget.id === "Launcher")
                    return j;
                }
              }
              return -1;
            }
            readonly property var launcherMetadata: BarWidgetRegistry.widgetMetadata["Launcher"]
            readonly property string launcherIcon: launcherWidgetSettings.icon || (launcherMetadata && launcherMetadata.icon ? launcherMetadata.icon : "search")
            readonly property string launcherIconColorKey: launcherWidgetSettings.iconColor !== undefined ? launcherWidgetSettings.iconColor : (launcherMetadata && launcherMetadata.iconColor !== undefined ? launcherMetadata.iconColor : "none")

            Item {
              id: launcherIconContainer
              width: dockRoot.iconSize
              height: dockRoot.iconSize
              anchors.centerIn: parent

              scale: launcherMouseArea.containsMouse ? 1.15 : 1.0
              Behavior on scale {
                NumberAnimation {
                  duration: Style.animationNormal
                  easing.type: Easing.OutBack
                  easing.overshoot: 1.2
                }
              }

              NIcon {
                anchors.centerIn: parent
                icon: launcherButton.launcherIcon
                pointSize: dockRoot.iconSize * 0.7
                color: Color.resolveColorKey(launcherButton.launcherIconColorKey)
              }
            }

            MouseArea {
              id: launcherMouseArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

              onEntered: {
                dockRoot.anyAppHovered = true;
                TooltipService.show(launcherButton, I18n.tr("actions.open-launcher"), "top");
                if (dockRoot.autoHide) {
                  dockRoot.showTimer.stop();
                  dockRoot.hideTimer.stop();
                  dockRoot.unloadTimer.stop();
                  dockRoot.hidden = false;
                }
              }

              onExited: {
                dockRoot.anyAppHovered = false;
                TooltipService.hide();
                if (dockRoot.autoHide && !dockRoot.dockHovered && !dockRoot.peekHovered && !dockRoot.menuHovered && dockRoot.dragSourceIndex === -1) {
                  dockRoot.hideTimer.restart();
                }
              }

              onClicked: mouse => {
                           const targetScreen = dockRoot.modelData || dockRoot.screen || null;
                           if (!targetScreen) {
                             return;
                           }

                           if (mouse.button === Qt.RightButton) {
                             if (dockRoot.currentContextMenu === launcherContextMenu && launcherContextMenu.visible) {
                               dockRoot.closeAllContextMenus();
                               return;
                             }
                             dockRoot.closeAllContextMenus();
                             TooltipService.hideImmediately();
                             launcherContextMenu.show(launcherButton, null, targetScreen);
                             return;
                           }

                           if (mouse.button === Qt.LeftButton || mouse.button === Qt.MiddleButton) {
                             dockRoot.closeAllContextMenus();
                             PanelService.toggleLauncher(targetScreen);
                           }
                         }
            }

            DockMenu {
              id: launcherContextMenu
              dockPosition: dockRoot.dockPosition
              menuMode: "launcher"
              launcherWidgetSection: launcherButton.launcherWidgetSection
              launcherWidgetIndex: launcherButton.launcherWidgetIndex
              launcherWidgetSettings: launcherButton.launcherWidgetSettings

              onHoveredChanged: {
                if (dockRoot.currentContextMenu === launcherContextMenu && launcherContextMenu.visible) {
                  dockRoot.menuHovered = hovered;
                } else {
                  dockRoot.menuHovered = false;
                }
              }

              Connections {
                target: launcherContextMenu
                function onRequestClose() {
                  dockRoot.currentContextMenu = null;
                  dockRoot.hideTimer.stop();
                  launcherContextMenu.hide();
                  dockRoot.menuHovered = false;
                  dockRoot.anyAppHovered = false;
                }
              }

              onVisibleChanged: {
                if (visible) {
                  dockRoot.currentContextMenu = launcherContextMenu;
                } else if (dockRoot.currentContextMenu === launcherContextMenu) {
                  dockRoot.currentContextMenu = null;
                  dockRoot.hideTimer.stop();
                  dockRoot.menuHovered = false;
                  if (dockRoot.autoHide && !dockRoot.dockHovered && !dockRoot.anyAppHovered && !dockRoot.peekHovered && !dockRoot.menuHovered) {
                    dockRoot.hideTimer.restart();
                  }
                }
              }
            }
          }
        }

        Loader {
          id: launcherButtonStart
          active: Settings.data.dock.showLauncherIcon && Settings.data.dock.launcherPosition === "start"
          visible: active
          sourceComponent: launcherButtonComponent
          readonly property real indicatorMargin: Math.max(3, Math.round(dockRoot.iconSize * 0.18))
          Layout.preferredWidth: active ? (dockRoot.isVertical ? dockRoot.iconSize + indicatorMargin * 2 : dockRoot.iconSize) : 0
          Layout.preferredHeight: active ? (dockRoot.isVertical ? dockRoot.iconSize : dockRoot.iconSize + indicatorMargin * 2) : 0
          Layout.minimumWidth: active ? Layout.preferredWidth : 0
          Layout.minimumHeight: active ? Layout.preferredHeight : 0
          Layout.maximumWidth: active ? Layout.preferredWidth : 0
          Layout.maximumHeight: active ? Layout.preferredHeight : 0
          Layout.alignment: Qt.AlignCenter
        }

        Repeater {
          model: dockRoot.dockApps

          delegate: Item {
            id: appButton
            readonly property real indicatorMargin: Math.max(3, Math.round(dockRoot.iconSize * 0.18))
            Layout.preferredWidth: dockRoot.isVertical ? dockRoot.iconSize + indicatorMargin * 2 : dockRoot.iconSize
            Layout.preferredHeight: dockRoot.isVertical ? dockRoot.iconSize : dockRoot.iconSize + indicatorMargin * 2
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
                  return dockRoot.getAppNameFromDesktopEntry(modelData.appId) || modelData.appId;
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
                  dockRoot.dragTargetIndex = appButton.modelIndex;
                }
              }
              onExited: function () {
                if (dockRoot.dragTargetIndex === appButton.modelIndex) {
                  dockRoot.dragTargetIndex = -1;
                }
              }
              onDropped: function (drop) {
                dockRoot.dragSourceIndex = -1;
                dockRoot.dragTargetIndex = -1;
                if (drop.source && drop.source.objectName === "dockAppButton" && drop.source !== appButton) {
                  dockRoot.reorderApps(drop.source.modelIndex, appButton.modelIndex);
                }
              }
            }

            // Listen for the toplevel being closed
            Connections {
              target: modelData?.toplevel
              function onClosed() {
                Qt.callLater(dockRoot.updateDockApps);
              }
            }

            // Draggable container for the icon
            Item {
              id: iconContainer
              width: dockRoot.iconSize
              height: dockRoot.iconSize

              // When dragging, remove anchors so MouseArea can position it
              anchors.centerIn: dragging ? undefined : parent

              property bool dragging: appMouseArea.drag.active
              onDraggingChanged: {
                if (dragging) {
                  dockRoot.dragSourceIndex = index;
                } else {
                  // Reset if not handled by drop (e.g. dropped outside)
                  Qt.callLater(() => {
                                 if (!appMouseArea.drag.active && dockRoot.dragSourceIndex === index) {
                                   dockRoot.dragSourceIndex = -1;
                                   dockRoot.dragTargetIndex = -1;
                                 }
                               });
                }
              }

              Drag.active: dragging
              Drag.source: appButton
              Drag.hotSpot.x: width / 2
              Drag.hotSpot.y: height / 2
              Drag.keys: ["dock-app"]

              z: (dockRoot.dragSourceIndex === index) ? 1000 : ((dragging ? 1000 : 0))
              scale: dragging ? 1.1 : (appButton.hovered ? 1.15 : 1.0)
              Behavior on scale {
                NumberAnimation {
                  duration: Style.animationNormal
                  easing.type: Easing.OutBack
                  easing.overshoot: 1.2
                }
              }

              // Visual shifting logic
              readonly property bool isDragged: dockRoot.dragSourceIndex === index
              property real shiftOffset: 0

              Binding on shiftOffset {
                value: {
                  if (dockRoot.dragSourceIndex !== -1 && dockRoot.dragTargetIndex !== -1 && !iconContainer.isDragged) {
                    if (dockRoot.dragSourceIndex < dockRoot.dragTargetIndex) {
                      // Dragging Forward: Items between source and target shift Backward
                      if (index > dockRoot.dragSourceIndex && index <= dockRoot.dragTargetIndex) {
                        return -1 * (dockRoot.isVertical ? dockRoot.iconSize + Style.marginS : dockRoot.iconSize + Style.marginS);
                      }
                    } else if (dockRoot.dragSourceIndex > dockRoot.dragTargetIndex) {
                      // Dragging Backward: Items between target and source shift Forward
                      if (index >= dockRoot.dragTargetIndex && index < dockRoot.dragSourceIndex) {
                        return (dockRoot.isVertical ? dockRoot.iconSize + Style.marginS : dockRoot.iconSize + Style.marginS);
                      }
                    }
                  }
                  return 0;
                }
              }

              transform: Translate {
                x: !dockRoot.isVertical ? iconContainer.shiftOffset : 0
                y: dockRoot.isVertical ? iconContainer.shiftOffset : 0

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
                  dockRoot.iconRevision; // Force re-evaluation when revision changes
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
                pointSize: dockRoot.iconSize * 0.7
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
              dockPosition: dockRoot.dockPosition // Pass dock position for menu placement
              onHoveredChanged: {
                // Only update menuHovered if this menu is current and visible
                if (dockRoot.currentContextMenu === contextMenu && contextMenu.visible) {
                  dockRoot.menuHovered = hovered;
                } else {
                  dockRoot.menuHovered = false;
                }
              }

              Connections {
                target: contextMenu
                function onRequestClose() {
                  // Clear current menu immediately to prevent hover updates
                  dockRoot.currentContextMenu = null;
                  dockRoot.hideTimer.stop();
                  contextMenu.hide();
                  dockRoot.menuHovered = false;
                  dockRoot.anyAppHovered = false;
                }
              }
              onAppClosed: dockRoot.updateDockApps // Force immediate dock update when app is closed
              onVisibleChanged: {
                if (visible) {
                  dockRoot.currentContextMenu = contextMenu;
                } else if (dockRoot.currentContextMenu === contextMenu) {
                  dockRoot.currentContextMenu = null;
                  dockRoot.hideTimer.stop();
                  dockRoot.menuHovered = false;
                  // Restart hide timer after menu closes
                  if (dockRoot.autoHide && !dockRoot.dockHovered && !dockRoot.anyAppHovered && !dockRoot.peekHovered && !dockRoot.menuHovered) {
                    dockRoot.hideTimer.restart();
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
              drag.axis: (pressedButtons & Qt.LeftButton) ? (dockRoot.isVertical ? Drag.YAxis : Drag.XAxis) : Drag.None

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
                dockRoot.anyAppHovered = true;
                const appName = appButton.appTitle || appButton.appId || "Unknown";
                const tooltipText = appName.length > 40 ? appName.substring(0, 37) + "..." : appName;
                if (!contextMenu.visible) {
                  TooltipService.show(appButton, tooltipText, "top");
                }
                if (dockRoot.autoHide) {
                  dockRoot.showTimer.stop();
                  dockRoot.hideTimer.stop();
                  dockRoot.unloadTimer.stop(); // Cancel unload if hovering app
                  dockRoot.hidden = false; // Make sure dock is visible
                }
              }

              onExited: {
                dockRoot.anyAppHovered = false;
                TooltipService.hide();
                // Clear menuHovered if no current menu or menu not visible
                if (!dockRoot.currentContextMenu || !dockRoot.currentContextMenu.visible) {
                  dockRoot.menuHovered = false;
                }
                if (dockRoot.autoHide && !dockRoot.dockHovered && !dockRoot.peekHovered && !dockRoot.menuHovered && dockRoot.dragSourceIndex === -1) {
                  dockRoot.hideTimer.restart();
                }
              }

              onClicked: mouse => {
                           if (mouse.button === Qt.RightButton) {
                             const targetScreen = dockRoot.modelData || dockRoot.screen || null;
                             // If right-clicking on the same app with an open context menu, close it
                             if (dockRoot.currentContextMenu === contextMenu && contextMenu.visible) {
                               dockRoot.closeAllContextMenus();
                               return;
                             }
                             // Close any other existing context menu first
                             dockRoot.closeAllContextMenus();
                             // Hide tooltip when showing context menu
                             TooltipService.hideImmediately();
                             contextMenu.show(appButton, modelData.toplevel || modelData, targetScreen);
                             return;
                           }

                           // Close any existing context menu for non-right-click actions
                           dockRoot.closeAllContextMenus();

                           // Check if toplevel is still valid (not a stale reference)
                           const isValidToplevel = modelData?.toplevel && ToplevelManager && ToplevelManager.toplevels.values.includes(modelData.toplevel);

                           if (mouse.button === Qt.MiddleButton && isValidToplevel && modelData.toplevel.close) {
                             modelData.toplevel.close();
                             Qt.callLater(dockRoot.updateDockApps); // Force immediate dock update
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
              width: dockRoot.isVertical ? indicatorMargin * 0.6 : dockRoot.iconSize * 0.2
              height: dockRoot.isVertical ? dockRoot.iconSize * 0.2 : indicatorMargin * 0.6
              color: Color.mPrimary
              radius: Style.radiusXS

              // Anchor to the edge facing the screen center
              anchors.bottom: !dockRoot.isVertical && dockRoot.dockPosition === "bottom" ? parent.bottom : undefined
              anchors.top: !dockRoot.isVertical && dockRoot.dockPosition === "top" ? parent.top : undefined
              anchors.left: dockRoot.isVertical && dockRoot.dockPosition === "left" ? parent.left : undefined
              anchors.right: dockRoot.isVertical && dockRoot.dockPosition === "right" ? parent.right : undefined

              anchors.horizontalCenter: dockRoot.isVertical ? undefined : parent.horizontalCenter
              anchors.verticalCenter: dockRoot.isVertical ? parent.verticalCenter : undefined

              // Offset slightly from the edge
              anchors.bottomMargin: !dockRoot.isVertical && dockRoot.dockPosition === "bottom" ? 2 : 0
              anchors.topMargin: !dockRoot.isVertical && dockRoot.dockPosition === "top" ? 2 : 0
              anchors.leftMargin: dockRoot.isVertical && dockRoot.dockPosition === "left" ? 2 : 0
              anchors.rightMargin: dockRoot.isVertical && dockRoot.dockPosition === "right" ? 2 : 0
            }
          }
        }

        Loader {
          id: launcherButtonEnd
          active: Settings.data.dock.showLauncherIcon && Settings.data.dock.launcherPosition === "end"
          visible: active
          sourceComponent: launcherButtonComponent
          readonly property real indicatorMargin: Math.max(3, Math.round(dockRoot.iconSize * 0.18))
          Layout.preferredWidth: active ? (dockRoot.isVertical ? dockRoot.iconSize + indicatorMargin * 2 : dockRoot.iconSize) : 0
          Layout.preferredHeight: active ? (dockRoot.isVertical ? dockRoot.iconSize : dockRoot.iconSize + indicatorMargin * 2) : 0
          Layout.minimumWidth: active ? Layout.preferredWidth : 0
          Layout.minimumHeight: active ? Layout.preferredHeight : 0
          Layout.maximumWidth: active ? Layout.preferredWidth : 0
          Layout.maximumHeight: active ? Layout.preferredHeight : 0
          Layout.alignment: Qt.AlignCenter
        }
      }
    }
  }
}
