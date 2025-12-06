import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool isVerticalBar: barPosition === "left" || barPosition === "right"
  readonly property string density: Settings.data.bar.density
  readonly property real itemSize: (density === "compact") ? Style.capsuleHeight * 0.9 : Style.capsuleHeight * 0.8
  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property int characterCount: 2
  readonly property bool hideUnoccupied: (widgetSettings.hideUnoccupied !== undefined) ? widgetSettings.hideUnoccupied : widgetMetadata.hideUnoccupied
  readonly property string labelMode: (widgetSettings.labelMode !== undefined) ? widgetSettings.labelMode : widgetMetadata.labelMode
  readonly property bool showLabelsOnlyWhenOccupied: (widgetSettings.showLabelsOnlyWhenOccupied !== undefined) ? widgetSettings.showLabelsOnlyWhenOccupied : widgetMetadata.showLabelsOnlyWhenOccupied
  readonly property bool colorizeIcons: (widgetSettings.colorizeIcons !== undefined) ? widgetSettings.colorizeIcons : widgetMetadata.colorizeIcons

  property ListModel localWorkspaces: ListModel {}
  property real masterProgress: 0.0
  property bool effectsActive: false
  property color effectColor: Color.mPrimary

  // Wheel scroll handling
  property int wheelAccumulatedDelta: 0
  property bool wheelCooldown: false

  // Context menu state
  property var selectedWindow: null
  property string selectedAppName: ""
  property int modelUpdateTrigger: 0  // Dummy property to force model re-evaluation

  function refreshWorkspaces() {
    localWorkspaces.clear();
    if (!screen)
      return;
    const screenName = screen.name.toLowerCase();

    for (var i = 0; i < CompositorService.workspaces.count; i++) {
      const ws = CompositorService.workspaces.get(i);

      if (ws.output.toLowerCase() !== screenName)
        continue;
      if (hideUnoccupied && !ws.isOccupied && !ws.isFocused)
        continue;

      // Copy all properties from ws and add windows
      var workspaceData = Object.assign({}, ws);
      workspaceData.windows = CompositorService.getWindowsForWorkspace(ws.id);

      localWorkspaces.append(workspaceData);
    }

    updateWorkspaceFocus();
  }

  function triggerUnifiedWave() {
    effectColor = Color.mPrimary;
    masterAnimation.restart();
  }

  function updateWorkspaceFocus() {
    for (var i = 0; i < localWorkspaces.count; i++) {
      const ws = localWorkspaces.get(i);
      if (ws.isFocused === true) {
        root.triggerUnifiedWave();
        break;
      }
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

  Component.onCompleted: {
    refreshWorkspaces();
  }

  onScreenChanged: refreshWorkspaces()
  onHideUnoccupiedChanged: refreshWorkspaces()

  implicitWidth: isVerticalBar ? taskbarGrid.implicitWidth + Style.marginM * 2 : Math.round(taskbarGrid.implicitWidth + Style.marginM * 2)
  implicitHeight: isVerticalBar ? Math.round(taskbarGrid.implicitHeight + Style.marginM * 2) : Style.barHeight

  Connections {
    target: CompositorService

    function onWorkspacesChanged() {
      refreshWorkspaces();
    }

    function onWindowListChanged() {
      refreshWorkspaces();
    }
  }

  SequentialAnimation {
    id: masterAnimation
    PropertyAction {
      target: root
      property: "effectsActive"
      value: true
    }
    NumberAnimation {
      target: root
      property: "masterProgress"
      from: 0.0
      to: 1.0
      duration: Style.animationSlow * 2
      easing.type: Easing.OutQuint
    }
    PropertyAction {
      target: root
      property: "effectsActive"
      value: false
    }
    PropertyAction {
      target: root
      property: "masterProgress"
      value: 0.0
    }
  }

  NPopupContextMenu {
    id: contextMenu

    model: {
      // Reference modelUpdateTrigger to make binding reactive
      const _ = root.modelUpdateTrigger;

      var items = [];
      if (root.selectedWindow) {
        items.push({
                     "label": I18n.tr("context-menu.activate-app", {
                                        "app": root.selectedAppName
                                      }),
                     "action": "activate",
                     "icon": "focus"
                   });
        items.push({
                     "label": I18n.tr("context-menu.close-app", {
                                        "app": root.selectedAppName
                                      }),
                     "action": "close",
                     "icon": "x"
                   });
      }
      items.push({
                   "label": I18n.tr("context-menu.widget-settings"),
                   "action": "widget-settings",
                   "icon": "settings"
                 });
      return items;
    }

    onTriggered: action => {
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.close();
                   }

                   if (action === "activate" && selectedWindow) {
                     CompositorService.focusWindow(selectedWindow);
                   } else if (action === "close" && selectedWindow) {
                     CompositorService.closeWindow(selectedWindow);
                   } else if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                   selectedWindow = null;
                   selectedAppName = "";
                 }
  }

  // Debounce timer for wheel interactions
  Timer {
    id: wheelDebounce
    interval: 150
    repeat: false
    onTriggered: {
      root.wheelCooldown = false;
      root.wheelAccumulatedDelta = 0;
    }
  }

  // Scroll to switch workspaces
  WheelHandler {
    id: wheelHandler
    target: root
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function (event) {
      if (root.wheelCooldown)
        return;
      // Prefer vertical delta, fall back to horizontal if needed
      var dy = event.angleDelta.y;
      var dx = event.angleDelta.x;
      var useDy = Math.abs(dy) >= Math.abs(dx);
      var delta = useDy ? dy : dx;
      // One notch is typically 120
      root.wheelAccumulatedDelta += delta;
      var step = 120;
      if (Math.abs(root.wheelAccumulatedDelta) >= step) {
        var direction = root.wheelAccumulatedDelta > 0 ? -1 : 1;
        // For vertical layout, natural mapping: wheel up -> previous, down -> next (already handled by sign)
        // For horizontal layout, same mapping using vertical wheel
        root.switchByOffset(direction);
        root.wheelCooldown = true;
        wheelDebounce.restart();
        root.wheelAccumulatedDelta = 0;
        event.accepted = true;
      }
    }
  }

  Component {
    id: workspaceRepeaterDelegate

    Rectangle {
      id: container

      required property var model
      property var workspaceModel: model
      property bool hasWindows: workspaceModel.windows.count > 0

      radius: Style.radiusS
      border.color: workspaceModel.isFocused ? Color.mPrimary : Color.mOutline
      border.width: Style.borderS
      width: (hasWindows ? iconsFlow.implicitWidth : root.itemSize * 0.8) + (root.isVerticalBar ? Style.marginXS : Style.marginL)
      height: (hasWindows ? iconsFlow.implicitHeight : root.itemSize * 0.8) + (root.isVerticalBar ? Style.marginL : Style.marginXS)
      color: Style.capsuleColor

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        enabled: !hasWindows
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        onPressed: mouse => {
                     if (mouse.button === Qt.LeftButton) {
                       CompositorService.switchToWorkspace(workspaceModel);
                     }
                   }
        onReleased: mouse => {
                      if (mouse.button === Qt.RightButton) {
                        mouse.accepted = true;
                        TooltipService.hide();
                        root.selectedWindow = "";
                        root.selectedAppName = "";

                        // Store position and size for timer callback
                        const globalPos = container.mapToItem(root, 0, 0);
                        contextMenuOpenTimer1.globalX = globalPos.x;
                        contextMenuOpenTimer1.globalY = globalPos.y;
                        contextMenuOpenTimer1.itemWidth = container.width;
                        contextMenuOpenTimer1.itemHeight = container.height;
                        contextMenuOpenTimer1.restart();
                      }
                    }
      }

      Flow {
        id: iconsFlow

        anchors.centerIn: parent
        spacing: 4
        flow: root.isVerticalBar ? Flow.TopToBottom : Flow.LeftToRight

        Repeater {
          model: workspaceModel.windows

          delegate: Item {
            id: taskbarItem

            property bool itemHovered: false

            width: root.itemSize * 0.8
            height: root.itemSize * 0.8

            // Smooth scale animation on hover
            scale: itemHovered ? 1.1 : 1.0

            Behavior on scale {
              NumberAnimation {
                duration: Style.animationNormal
                easing.type: Easing.OutBack
              }
            }

            IconImage {
              id: appIcon

              width: parent.width
              height: parent.height
              source: ThemeIcons.iconForAppId(model.appId)
              smooth: true
              asynchronous: true
              opacity: model.isFocused ? Style.opacityFull : 0.6
              layer.enabled: root.colorizeIcons && !model.isFocused

              Behavior on opacity {
                NumberAnimation {
                  duration: Style.animationNormal
                  easing.type: Easing.InOutCubic
                }
              }

              Rectangle {
                id: focusIndicator
                anchors.bottomMargin: -2
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: model.isFocused ? 4 : 0
                height: model.isFocused ? 4 : 0
                color: model.isFocused ? Color.mPrimary : Color.transparent
                radius: Math.min(Style.radiusXXS, width / 2)
              }

              layer.effect: ShaderEffect {
                property color targetColor: Settings.data.colorSchemes.darkMode ? Color.mOnSurface : Color.mSurfaceVariant
                property real colorizeMode: 0
                fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              preventStealing: true

              onPressed: mouse => {
                           if (!model) {
                             return;
                           }

                           if (mouse.button === Qt.LeftButton) {
                             CompositorService.focusWindow(model);
                           }
                         }

              onReleased: mouse => {
                            if (!model) {
                              return;
                            }

                            if (mouse.button === Qt.RightButton) {
                              mouse.accepted = true;
                              TooltipService.hide();
                              root.selectedWindow = model;
                              root.selectedAppName = CompositorService.getCleanAppName(model.appId, model.title);

                              // Store position and size for timer callback
                              const globalPos = taskbarItem.mapToItem(root, 0, 0);
                              contextMenuOpenTimer2.globalX = globalPos.x;
                              contextMenuOpenTimer2.globalY = globalPos.y;
                              contextMenuOpenTimer2.itemWidth = taskbarItem.width;
                              contextMenuOpenTimer2.itemHeight = taskbarItem.height;
                              contextMenuOpenTimer2.restart();
                            }
                          }
              onEntered: {
                taskbarItem.itemHovered = true;
                TooltipService.show(taskbarItem, model.title || model.appId || "Unknown app.", BarService.getTooltipDirection());
              }
              onExited: {
                taskbarItem.itemHovered = false;
                TooltipService.hide();
              }
            }
          }
        }
      }

      Item {
        id: workspaceNumberContainer

        visible: root.labelMode !== "none" && (!root.showLabelsOnlyWhenOccupied || container.hasWindows)

        anchors {
          left: parent.left
          top: parent.top
          leftMargin: -Style.fontSizeXS * 0.5
          topMargin: -Style.fontSizeXS * 0.5
        }

        // Doube width margin necessary here for Name or Name+Index, but double height not needed.
        width: Math.max(workspaceNumber.implicitWidth + (Style.marginXS * 2), Style.fontSizeXXS * 2)
        height: Math.max(workspaceNumber.implicitHeight + Style.marginXS, Style.fontSizeXXS * 2)

        Rectangle {
          id: workspaceNumberBackground

          anchors.fill: parent
          radius: Math.min(Style.radiusL, width / 2)

          color: {
            if (workspaceModel.isFocused)
              return Color.mPrimary;
            if (workspaceModel.isUrgent)
              return Color.mError;
            if (hasWindows)
              return Color.mSecondary;

            if (Settings.data.colorSchemes.darkMode) {
              return Qt.darker(Color.mSecondary, 1.5);
            } else {
              return Qt.lighter(Color.mSecondary, 1.5);
            }
          }

          scale: workspaceModel.isActive ? 1.0 : 0.9

          Behavior on scale {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutBack
            }
          }

          Behavior on color {
            ColorAnimation {
              duration: Style.animationFast
              easing.type: Easing.InOutCubic
            }
          }
        }

        // Burst effect overlay for focused workspace number (smaller outline)
        Rectangle {
          id: workspaceNumberBurst
          anchors.centerIn: workspaceNumberContainer
          width: workspaceNumberContainer.width + 12 * root.masterProgress
          height: workspaceNumberContainer.height + 12 * root.masterProgress
          radius: width / 2
          color: Color.transparent
          border.color: root.effectColor
          border.width: Math.max(1, Math.round((2 + 4 * (1.0 - root.masterProgress))))
          opacity: root.effectsActive && workspaceModel.isFocused ? (1.0 - root.masterProgress) * 0.7 : 0
          visible: root.effectsActive && workspaceModel.isFocused
          z: 1
        }

        NText {
          id: workspaceNumber

          anchors.centerIn: parent

          text: {
            if (workspaceModel.name && workspaceModel.name.length > 0) {
              if (root.labelMode === "name") {
                return workspaceModel.name.substring(0, root.characterCount);
              }
              if (root.labelMode === "index+name") {
                return (workspaceModel.idx.toString() + workspaceModel.name.substring(0, 1));
              }
            }
            return workspaceModel.idx.toString();
          }

          family: Settings.data.ui.fontFixed
          font {
            pointSize: Style.fontSizeXXS
            weight: Style.fontWeightBold
            capitalization: Font.AllUppercase
          }
          applyUiScale: false

          color: {
            if (workspaceModel.isFocused)
              return Color.mOnPrimary;
            if (workspaceModel.isUrgent)
              return Color.mOnError;
            // if (hasWindows)
            //   return Color.mOnSecondary;

            return Color.mOnSecondary;
          }

          Behavior on opacity {
            NumberAnimation {
              duration: Style.animationFast
              easing.type: Easing.InOutCubic
            }
          }
        }

        Behavior on opacity {
          NumberAnimation {
            duration: Style.animationFast
            easing.type: Easing.InOutCubic
          }
        }
      }
    }
  }

  Flow {
    id: taskbarGrid

    anchors.verticalCenter: isVerticalBar ? undefined : parent.verticalCenter
    anchors.left: isVerticalBar ? undefined : parent.left
    anchors.leftMargin: isVerticalBar ? 0 : Style.marginM
    anchors.horizontalCenter: isVerticalBar ? parent.horizontalCenter : undefined
    anchors.top: isVerticalBar ? parent.top : undefined
    anchors.topMargin: isVerticalBar ? Style.marginM : 0

    spacing: Style.marginS
    flow: isVerticalBar ? Flow.TopToBottom : Flow.LeftToRight

    Repeater {
      model: localWorkspaces
      delegate: workspaceRepeaterDelegate
    }
  }

  Timer {
    id: contextMenuOpenTimer1
    interval: 10
    repeat: false
    property real globalX: 0
    property real globalY: 0
    property real itemWidth: 0
    property real itemHeight: 0
    onTriggered: openContextMenu(globalX, globalY, itemWidth, itemHeight)
  }

  Timer {
    id: contextMenuOpenTimer2
    interval: 10
    repeat: false
    property real globalX: 0
    property real globalY: 0
    property real itemWidth: 0
    property real itemHeight: 0
    onTriggered: openContextMenu(globalX, globalY, itemWidth, itemHeight)
  }

  // --------------------------------------------------
  function openContextMenu(globalX, globalY, itemWidth, itemHeight) {
    // Directly build and set model as a new array (bypass binding issues)
    var items = [];
    if (root.selectedWindow) {
      items.push({
                   "label": I18n.tr("context-menu.activate-app", {
                                      "app": root.selectedAppName
                                    }),
                   "action": "activate",
                   "icon": "focus"
                 });
      items.push({
                   "label": I18n.tr("context-menu.close-app", {
                                      "app": root.selectedAppName
                                    }),
                   "action": "close",
                   "icon": "x"
                 });
    }
    items.push({
                 "label": I18n.tr("context-menu.widget-settings"),
                 "action": "widget-settings",
                 "icon": "settings"
               });

    // Set the model directly
    contextMenu.model = items;

    var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
    if (popupMenuWindow) {
      popupMenuWindow.open();

      // Calculate menu position
      let menuX, menuY;
      if (root.barPosition === "top") {
        menuX = globalX + (itemWidth / 2) - (contextMenu.implicitWidth / 2);
        menuY = Style.barHeight + Style.marginS;
      } else if (root.barPosition === "bottom") {
        const menuHeight = 12 + contextMenu.model.length * contextMenu.itemHeight;
        menuX = globalX + (itemWidth / 2) - (contextMenu.implicitWidth / 2);
        menuY = -menuHeight - Style.marginS;
      } else if (root.barPosition === "left") {
        menuX = Style.barHeight + Style.marginS;
        menuY = globalY + (itemHeight / 2) - (contextMenu.implicitHeight / 2);
      } else {
        // right
        menuX = -contextMenu.implicitWidth - Style.marginS;
        menuY = globalY + (itemHeight / 2) - (contextMenu.implicitHeight / 2);
      }

      contextMenu.openAtItem(root, menuX, menuY);
      popupMenuWindow.contentItem = contextMenu;
    }
  }
}
