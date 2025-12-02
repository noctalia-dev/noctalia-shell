import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Services.UI
import qs.Services.Compositor
import qs.Widgets

Loader {

  active: Settings.data.dock.enabled
  sourceComponent: Variants {
    model: Quickshell.screens

    delegate: Item {
      id: root

      required property ShellScreen modelData

      property bool barIsReady: modelData ? BarService.isBarReady(modelData.name) : false

      property ListModel localWorkspaces: ListModel {}
      readonly property bool hideUnoccupied: false 

      property int wheelAccumulatedDelta: 0
      property bool wheelCooldown: false

      function refreshWorkspaces() {
        localWorkspaces.clear();
        if (!modelData) return;
        const screenName = modelData.name.toLowerCase();

        for (var i = 0; i < CompositorService.workspaces.count; i++) {
          const ws = CompositorService.workspaces.get(i);

          if (ws.output.toLowerCase() !== screenName)
            continue;
          if (hideUnoccupied && !ws.isOccupied && !ws.isFocused)
            continue;

          var workspaceData = Object.assign({}, ws);
          workspaceData.windows = CompositorService.getWindowsForWorkspace(ws.id);

          localWorkspaces.append(workspaceData);
        }
      }

      function getFocusedLocalIndex() {
        for (var i = 0; i < localWorkspaces.count; i++) {
          if (localWorkspaces.get(i).isFocused === true)
            return i;
        }
        return -1;
      }

      function switchByOffset(offset) {
        if (localWorkspaces.count === 0)
          return;
        var current = getFocusedLocalIndex();
        if (current < 0)
          current = 0;
        var next = (current + offset) % localWorkspaces.count;
        if (next < 0)
          next = localWorkspaces.count - 1;
        const ws = localWorkspaces.get(next);
        if (ws && ws.idx !== undefined)
          CompositorService.switchToWorkspace(ws);
      }

      // --- Reordering Logic ---
      function reorderPinnedApps(fromIndex, toIndex) {
        var arr = (Settings.data.dock.pinnedApps || []).slice();
        
        // Safety checks
        if (fromIndex < 0 || fromIndex >= arr.length || toIndex < 0 || toIndex >= arr.length) return;
        if (fromIndex === toIndex) return;

        // Move the item
        var item = arr.splice(fromIndex, 1)[0];
        arr.splice(toIndex, 0, item);

        // Update settings and force refresh
        Settings.data.dock.pinnedApps = arr;
        var temp = Settings.data.dock;
        Settings.data.dock = temp;
      }

      Timer {
        id: wheelDebounce
        interval: 150
        repeat: false
        onTriggered: {
          root.wheelCooldown = false;
          root.wheelAccumulatedDelta = 0;
        }
      }
      
      Connections {
        target: CompositorService
        function onWorkspacesChanged() { refreshWorkspaces(); }
        function onWindowListChanged() { refreshWorkspaces(); }
      }

      Connections {
        target: BarService
        function onBarReadyChanged(screenName) {
          if (screenName === modelData.name) {
            barIsReady = true;
          }
        }
      }

      Component.onCompleted: {
        refreshWorkspaces();
      }

      readonly property string displayMode: Settings.data.dock.displayMode
      readonly property bool autoHide: displayMode === "auto_hide"
      readonly property bool exclusive: displayMode === "exclusive"
      readonly property int hideDelay: 500
      readonly property int showDelay: 100
      readonly property int hideAnimationDuration: Style.animationFast
      readonly property int showAnimationDuration: Style.animationFast
      readonly property int peekHeight: 1
      readonly property int iconSize: Math.round(12 + 24 * (Settings.data.dock.size ?? 1))
      readonly property int floatingMargin: Settings.data.dock.floatingRatio * Style.marginL

      readonly property bool hasBar: modelData && modelData.name ? (Settings.data.bar.monitors.includes(modelData.name) || (Settings.data.bar.monitors.length === 0)) : false
      
      property bool dockHovered: false
      property bool anyAppHovered: false
      property bool menuHovered: false
      property bool hidden: autoHide
      property bool peekHovered: false
      property bool dockLoaded: !autoHide 
      
      onDockLoadedChanged: {
        if (dockLoaded) {
            refreshWorkspaces();
        }
      }

      property var currentContextMenu: null

      function closeAllContextMenus() {
        if (currentContextMenu && currentContextMenu.visible) {
          currentContextMenu.hide();
        }
      }

      Timer {
        id: unloadTimer
        interval: hideAnimationDuration + 50 
        onTriggered: {
          if (hidden && autoHide) {
            dockLoaded = false;
          }
        }
      }

      Timer {
        id: hideTimer
        interval: hideDelay
        onTriggered: {
          if (!root.currentContextMenu || !root.currentContextMenu.visible) {
            menuHovered = false;
          }
          if (autoHide && !dockHovered && !anyAppHovered && !peekHovered && !menuHovered) {
            hidden = true;
            unloadTimer.restart(); 
          } else if (autoHide && !dockHovered && !peekHovered) {
            restart();
          }
        }
      }

      Timer {
        id: showTimer
        interval: showDelay
        onTriggered: {
          if (autoHide) {
            dockLoaded = true;
            hidden = false; 
            unloadTimer.stop(); 
          }
        }
      }

      onAutoHideChanged: {
        if (!autoHide) {
          hidden = false;
          dockLoaded = true;
          hideTimer.stop();
          showTimer.stop();
          unloadTimer.stop();
        } else {
          hidden = true;
          unloadTimer.restart();
        }
      }

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
              if (!hidden && !dockHovered && !anyAppHovered && !menuHovered) {
                hideTimer.restart();
              }
            }
          }
        }
      }

      Loader {
        id: dockWindowLoader
        active: Settings.data.dock.enabled && (barIsReady || !hasBar) && modelData && (Settings.data.dock.monitors.length === 0 || Settings.data.dock.monitors.includes(modelData.name)) && dockLoaded && ToplevelManager

        sourceComponent: PanelWindow {
          id: dockWindow
          screen: modelData
          focusable: false
          color: Color.transparent
          WlrLayershell.namespace: "noctalia-dock-" + (screen?.name || "unknown")
          WlrLayershell.exclusionMode: exclusive ? ExclusionMode.Auto : ExclusionMode.Ignore
          implicitWidth: dockContainerWrapper.width
          implicitHeight: dockContainerWrapper.height
          anchors.bottom: true

          margins.bottom: {
            switch (Settings.data.bar.position) {
            case "bottom":
              return (Style.barHeight + Style.marginM) + (Settings.data.bar.floating ? Settings.data.bar.marginVertical * Style.marginXL + floatingMargin : floatingMargin);
            default:
              return floatingMargin;
            }
          }

          Item {
            id: dockContainerWrapper
            width: dockContainer.width
            height: dockContainer.height
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            
            WheelHandler {
                id: wheelHandler
                target: dockContainerWrapper
                
                onWheel: (event) => {
                  if (root.wheelCooldown)
                    return;
                  var dy = event.angleDelta.y;
                  var dx = event.angleDelta.x;
                  var useDy = Math.abs(dy) >= Math.abs(dx);
                  var delta = useDy ? dy : dx;
                  root.wheelAccumulatedDelta += delta;
                  var step = 120;
                  if (Math.abs(root.wheelAccumulatedDelta) >= step) {
                    var direction = root.wheelAccumulatedDelta > 0 ? -1 : 1;
                    root.switchByOffset(direction);
                    root.wheelCooldown = true;
                    wheelDebounce.restart();
                    root.wheelAccumulatedDelta = 0;
                    event.accepted = true;
                  }
                }
            }

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
              width: dockLayout.implicitWidth + (Style.marginL * 2)
              height: Math.round(iconSize * 1.5)
              color: Qt.alpha(Color.mSurface, Settings.data.dock.backgroundOpacity)
              anchors.centerIn: parent
              radius: height * 0.5 * Settings.data.dock.radiusRatio
              border.width: Style.borderS
              border.color: Qt.alpha(Color.mOutline, Settings.data.dock.backgroundOpacity)
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
                    unloadTimer.stop(); 
                  }
                }

                onExited: {
                  dockHovered = false;
                  if (autoHide && !anyAppHovered && !peekHovered && !menuHovered) {
                    hideTimer.restart();
                  }
                }

                onClicked: {
                  closeAllContextMenus();
                }
              }

              RowLayout {
                  id: dockLayout
                  spacing: Style.marginS
                  Layout.preferredHeight: parent.height
                  anchors.centerIn: parent

                  // --- Pinned Apps Section ---
                  Repeater {
                      model: Settings.data.dock.pinnedApps || []
                      
                      delegate: Item {
                          id: pinnedAppBtn
                          Layout.preferredWidth: iconSize
                          Layout.preferredHeight: iconSize
                          Layout.alignment: Qt.AlignCenter
                          
                          property string appId: modelData
                          property bool hovered: pinnedMouseArea.containsMouse
                          
                          property var runningWindow: {
                              if (!ToplevelManager) return null;
                              const list = ToplevelManager.toplevels.values;
                              for (let i=0; i<list.length; i++) {
                                  if (list[i].appId === appId) return list[i];
                              }
                              return null;
                          }
                          property bool isRunning: runningWindow !== null

                          Image {
                              id: pinnedAppIcon
                              anchors.fill: parent
                              source: ThemeIcons.iconForAppId(appId)
                              sourceSize.width: iconSize * 2
                              sourceSize.height: iconSize * 2
                              fillMode: Image.PreserveAspectFit
                              smooth: true
                              mipmap: true
                              // Fix: Check for Image.Ready status to prevent invisible but space-occupying icons
                              visible: status === Image.Ready && source.toString() !== "" 
                              scale: hovered ? 1.15 : 1.0
                              Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                          }

                          // Fallback Icon for Pinned Apps
                          NIcon {
                              anchors.centerIn: parent
                              visible: !pinnedAppIcon.visible
                              icon: "question-mark"
                              pointSize: iconSize * 0.7
                              color: Color.mOnSurfaceVariant
                              scale: hovered ? 1.15 : 1.0
                              Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                          }

                          Rectangle {
                              visible: isRunning
                              width: 4
                              height: 4
                              radius: 2
                              color: Color.mOnSurfaceVariant
                              opacity: 0.7
                              anchors.bottom: parent.bottom
                              anchors.horizontalCenter: parent.horizontalCenter
                              anchors.bottomMargin: 2
                          }

                          DockMenu {
                            id: pinnedContextMenu
                            onHoveredChanged: {
                              if (root.currentContextMenu === pinnedContextMenu && pinnedContextMenu.visible) {
                                menuHovered = hovered;
                              } else {
                                menuHovered = false;
                              }
                            }
                            
                            // -- Listen for move requests from menu --
                            Connections {
                                target: pinnedContextMenu
                                function onRequestMove(offset) {
                                    root.reorderPinnedApps(index, index + offset);
                                    root.closeAllContextMenus();
                                }
                                function onRequestClose() {
                                    root.currentContextMenu = null;
                                    hideTimer.stop();
                                    pinnedContextMenu.hide();
                                    menuHovered = false;
                                    anyAppHovered = false;
                                }
                            }
                            onVisibleChanged: {
                              if (visible) {
                                root.currentContextMenu = pinnedContextMenu;
                                anyAppHovered = false;
                              } else if (root.currentContextMenu === pinnedContextMenu) {
                                root.currentContextMenu = null;
                                hideTimer.stop();
                                menuHovered = false;
                                anyAppHovered = false;
                                if (autoHide && !dockHovered && !anyAppHovered && !peekHovered && !menuHovered) {
                                  hideTimer.restart();
                                }
                              }
                            }
                          }

                          MouseArea {
                              id: pinnedMouseArea
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              acceptedButtons: Qt.LeftButton | Qt.RightButton
                              
                              onEntered: {
                                  anyAppHovered = true;
                                  var displayName = appId;
                                  if (typeof DesktopEntries !== 'undefined') {
                                      var entry = (DesktopEntries.heuristicLookup) ? DesktopEntries.heuristicLookup(appId) : DesktopEntries.byId(appId);
                                      if (entry && entry.name) displayName = entry.name;
                                  }

                                  if (!pinnedContextMenu.visible) TooltipService.show(pinnedAppBtn, displayName, "top");
                                  if (autoHide) { showTimer.stop(); hideTimer.stop(); unloadTimer.stop(); }
                              }
                              onExited: {
                                  anyAppHovered = false;
                                  TooltipService.hide();
                                  if (!root.currentContextMenu || !root.currentContextMenu.visible) menuHovered = false;
                                  if (autoHide && !dockHovered && !peekHovered && !menuHovered) hideTimer.restart();
                              }
                              onClicked: (mouse) => {
                                  if (mouse.button === Qt.RightButton) {
                                      root.closeAllContextMenus();
                                      TooltipService.hideImmediately();
                                      // Pass index and total count for move logic
                                      pinnedContextMenu.showPinned(pinnedAppBtn, appId, index, (Settings.data.dock.pinnedApps || []).length);
                                  } else {
                                      root.closeAllContextMenus();
                                      Quickshell.execDetached(["gtk-launch", appId]);
                                  }
                              }
                          }
                      }
                  }

                  // --- Vertical Separator ---
                  Rectangle {
                      visible: (Settings.data.dock.pinnedApps || []).length > 0
                      width: 1
                      height: iconSize * 0.6
                      color: Color.mOutline
                      opacity: 0.5
                      Layout.alignment: Qt.AlignCenter
                      Layout.leftMargin: Style.marginS
                      Layout.rightMargin: Style.marginS
                  }

                  // --- Workspaces Section ---
                  Repeater {
                      model: localWorkspaces
                      
                      delegate: Rectangle {
                          id: workspaceCapsule
                          
                          property var workspaceModel: model
                          property bool hasWindows: workspaceModel.windows.count > 0
                          
                          color: Style.capsuleColor
                          radius: Style.radiusS
                          
                          border.color: workspaceModel.isFocused ? Color.mPrimary : Color.mOutline
                          border.width: Style.borderS
                          
                          Layout.preferredHeight: iconSize + Style.marginS
                          Layout.preferredWidth: (hasWindows ? windowsRow.implicitWidth + Style.marginM : iconSize)
                          Layout.alignment: Qt.AlignCenter

                          Behavior on Layout.preferredWidth { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

                          MouseArea {
                              anchors.fill: parent
                              hoverEnabled: true
                              enabled: !hasWindows
                              cursorShape: Qt.PointingHandCursor
                              onClicked: {
                                  CompositorService.switchToWorkspace(workspaceModel);
                              }
                          }
                          
                          Row {
                              id: windowsRow
                              anchors.centerIn: parent
                              spacing: Style.marginXS
                              
                              Repeater {
                                  model: workspaceModel.windows
                                  
                                  delegate: Item {
                                      id: appButton
                                      width: iconSize
                                      height: iconSize
                                      
                                      property bool isActive: model.isFocused
                                      property bool hovered: appMouseArea.containsMouse
                                      property string appId: model.appId
                                      property string appTitle: model.title
                                      
                                      Image {
                                          id: appIcon
                                          anchors.fill: parent
                                          source: ThemeIcons.iconForAppId(model.appId)
                                          // Fix: Check for Image.Ready status here too for consistency
                                          visible: status === Image.Ready && source.toString() !== ""
                                          fillMode: Image.PreserveAspectFit
                                          
                                          sourceSize.width: iconSize * 2
                                          sourceSize.height: iconSize * 2
                                          
                                          smooth: true
                                          mipmap: true
                                          
                                          scale: appButton.hovered ? 1.15 : 1.0
                                          Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                          
                                          layer.enabled: !appButton.isActive && Settings.data.dock.colorizeIcons
                                          layer.effect: ShaderEffect {
                                              property color targetColor: Settings.data.colorSchemes.darkMode ? Color.mOnSurface : Color.mSurfaceVariant
                                              property real colorizeMode: 0.0
                                              fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
                                          }
                                      }
                                      
                                      NIcon {
                                          anchors.centerIn: parent
                                          visible: !appIcon.visible
                                          icon: "question-mark"
                                          pointSize: iconSize * 0.7
                                          color: Color.mOnSurfaceVariant
                                      }

                                      DockMenu {
                                        id: contextMenu
                                        onHoveredChanged: {
                                          if (root.currentContextMenu === contextMenu && contextMenu.visible) {
                                            menuHovered = hovered;
                                          } else {
                                            menuHovered = false;
                                          }
                                        }
                                        Connections {
                                            target: contextMenu
                                            function onRequestClose() {
                                                root.currentContextMenu = null;
                                                hideTimer.stop();
                                                contextMenu.hide();
                                                menuHovered = false;
                                                anyAppHovered = false;
                                            }
                                        }
                                        onVisibleChanged: {
                                          if (visible) {
                                            root.currentContextMenu = contextMenu;
                                            anyAppHovered = false;
                                          } else if (root.currentContextMenu === contextMenu) {
                                            root.currentContextMenu = null;
                                            hideTimer.stop();
                                            menuHovered = false;
                                            anyAppHovered = false;
                                            if (autoHide && !dockHovered && !anyAppHovered && !peekHovered && !menuHovered) {
                                              hideTimer.restart();
                                            }
                                          }
                                        }
                                      }

                                      MouseArea {
                                          id: appMouseArea
                                          anchors.fill: parent
                                          hoverEnabled: true
                                          cursorShape: Qt.PointingHandCursor
                                          acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton // Enable Middle Button
                                          
                                          onEntered: {
                                              anyAppHovered = true;
                                              if (!contextMenu.visible) TooltipService.show(appButton, appButton.appTitle, "top");
                                              if (autoHide) { showTimer.stop(); hideTimer.stop(); unloadTimer.stop(); }
                                          }
                                          onExited: {
                                              anyAppHovered = false;
                                              TooltipService.hide();
                                              if (!root.currentContextMenu || !root.currentContextMenu.visible) menuHovered = false;
                                              if (autoHide && !dockHovered && !peekHovered && !menuHovered) hideTimer.restart();
                                          }
                                          onClicked: (mouse) => {
                                              if (mouse.button === Qt.RightButton) {
                                                  root.closeAllContextMenus();
                                                  TooltipService.hideImmediately();
                                                  contextMenu.show(appButton, model, "workspace");
                                              } else if (mouse.button === Qt.MiddleButton) {
                                                  // Middle click to close
                                                  root.closeAllContextMenus();
                                                  CompositorService.closeWindow(model);
                                              } else {
                                                  root.closeAllContextMenus();
                                                  CompositorService.focusWindow(model);
                                              }
                                          }
                                      }
                                      
                                      Rectangle {
                                          visible: isActive
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

                  Rectangle {
                      width: 1
                      height: iconSize * 0.6
                      color: Color.mOutline
                      opacity: 0.5
                      Layout.alignment: Qt.AlignCenter
                      Layout.leftMargin: Style.marginS
                      Layout.rightMargin: Style.marginS
                  }

                  Item {
                      id: autoHideBtn
                      implicitWidth: iconSize
                      implicitHeight: iconSize
                      Layout.preferredWidth: iconSize
                      Layout.preferredHeight: iconSize
                      Layout.alignment: Qt.AlignCenter

                      property bool hovered: autoHideMouseArea.containsMouse
                      property string iconName: root.autoHide ? "pin" : "arrow-down" 
                      property string tooltipText: root.autoHide ? I18n.tr("settings.dock.appearance.display.always-visible") : I18n.tr("settings.dock.appearance.display.auto-hide")

                      NIcon {
                          anchors.centerIn: parent
                          icon: parent.iconName
                          pointSize: iconSize * 0.6
                          color: parent.hovered ? Color.mOnSurface : Color.mOnSurfaceVariant
                          
                          scale: parent.hovered ? 1.15 : 1.0
                          Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                      }

                      MouseArea {
                          id: autoHideMouseArea
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor

                          onEntered: {
                              anyAppHovered = true;
                              TooltipService.show(autoHideBtn, autoHideBtn.tooltipText, "top");
                              if (root.autoHide) { showTimer.stop(); hideTimer.stop(); unloadTimer.stop(); }
                          }
                          onExited: {
                              anyAppHovered = false;
                              TooltipService.hide();
                              if (root.autoHide && !dockHovered && !peekHovered && !menuHovered) hideTimer.restart();
                          }
                          onClicked: {
                              if (root.autoHide) {
                                  Settings.data.dock.displayMode = "always_visible";
                              } else {
                                  Settings.data.dock.displayMode = "auto_hide";
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
