import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Services.Compositor
import qs.Services.UI
import qs.Widgets

Rectangle {
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

  property bool hasWindow: false
  readonly property string hideMode: (widgetSettings.hideMode !== undefined) ? widgetSettings.hideMode : widgetMetadata.hideMode
  readonly property bool onlySameOutput: (widgetSettings.onlySameOutput !== undefined) ? widgetSettings.onlySameOutput : widgetMetadata.onlySameOutput
  readonly property bool onlyActiveWorkspaces: (widgetSettings.onlyActiveWorkspaces !== undefined) ? widgetSettings.onlyActiveWorkspaces : widgetMetadata.onlyActiveWorkspaces

  // Context menu state
  property var selectedWindow: null
  property string selectedAppName: ""
  property int modelUpdateTrigger: 0  // Dummy property to force model re-evaluation

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

  function updateHasWindow() {
    try {
      var total = CompositorService.windows.count || 0;
      var activeIds = CompositorService.getActiveWorkspaces().map(function (ws) {
        return ws.id;
      });
      var found = false;
      for (var i = 0; i < total; i++) {
        var w = CompositorService.windows.get(i);
        if (!w)
          continue;
        var passOutput = (!onlySameOutput) || (w.output == screen.name);
        var passWorkspace = (!onlyActiveWorkspaces) || (activeIds.includes(w.workspaceId));
        if (passOutput && passWorkspace) {
          found = true;
          break;
        }
      }
      hasWindow = found;
    } catch (e) {
      hasWindow = false;
    }
  }

  Connections {
    target: CompositorService
    function onWindowListChanged() {
      updateHasWindow();
    }
    function onWorkspaceChanged() {
      updateHasWindow();
    }
  }

  Component.onCompleted: updateHasWindow()
  onScreenChanged: updateHasWindow()

  // "visible": Always Visible, "hidden": Hide When Empty, "transparent": Transparent When Empty
  visible: hideMode !== "hidden" || hasWindow
  opacity: (hideMode !== "transparent" || hasWindow) ? 1.0 : 0
  Behavior on opacity {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.OutCubic
    }
  }

  implicitWidth: visible ? (isVerticalBar ? Style.capsuleHeight : Math.round(taskbarLayout.implicitWidth + Style.marginM * 2)) : 0
  implicitHeight: visible ? (isVerticalBar ? Math.round(taskbarLayout.implicitHeight + Style.marginM * 2) : Style.capsuleHeight) : 0
  radius: Style.radiusM
  color: Style.capsuleColor

  GridLayout {
    id: taskbarLayout
    anchors.fill: parent
    anchors {
      leftMargin: isVerticalBar ? undefined : Style.marginM
      rightMargin: isVerticalBar ? undefined : Style.marginM
      topMargin: (density === "compact") ? 0 : isVerticalBar ? Style.marginM : undefined
      bottomMargin: (density === "compact") ? 0 : isVerticalBar ? Style.marginM : undefined
    }

    // Configure GridLayout to behave like RowLayout or ColumnLayout
    rows: isVerticalBar ? -1 : 1 // -1 means unlimited
    columns: isVerticalBar ? 1 : -1 // -1 means unlimited

    rowSpacing: isVerticalBar ? Style.marginXXS : 0
    columnSpacing: isVerticalBar ? 0 : Style.marginXXS

    Repeater {
      model: CompositorService.windows
      delegate: Item {
        id: taskbarItem
        required property var modelData
        property ShellScreen screen: root.screen

        visible: (!onlySameOutput || modelData.output === screen?.name) && (!onlyActiveWorkspaces || CompositorService.getActiveWorkspaces().map(function (ws) {
          return ws.id;
        }).includes(modelData.workspaceId))

        Layout.preferredWidth: root.itemSize
        Layout.preferredHeight: root.itemSize
        Layout.alignment: Qt.AlignCenter

        IconImage {
          id: appIcon
          width: parent.width
          height: parent.height
          source: ThemeIcons.iconForAppId(taskbarItem.modelData.appId)
          smooth: true
          asynchronous: true
          opacity: modelData.isFocused ? Style.opacityFull : 0.6

          // Apply dock shader to all taskbar icons
          layer.enabled: widgetSettings.colorizeIcons !== false
          layer.effect: ShaderEffect {
            property color targetColor: Settings.data.colorSchemes.darkMode ? Color.mOnSurface : Color.mSurfaceVariant
            property real colorizeMode: 0.0 // Dock mode (grayscale)

            fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
          }

          Rectangle {
            id: iconBackground
            anchors.bottomMargin: -2
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: 4
            height: 4
            color: modelData.isFocused ? Color.mPrimary : Color.transparent
            radius: Math.min(Style.radiusXXS, width / 2)
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          preventStealing: true

          onPressed: function (mouse) {
            if (!taskbarItem.modelData)
              return;
            if (mouse.button === Qt.LeftButton) {
              try {
                CompositorService.focusWindow(taskbarItem.modelData);
              } catch (error) {
                Logger.e("Taskbar", "Failed to activate toplevel: " + error);
              }
            }
          }

          onReleased: function (mouse) {
            if (!taskbarItem.modelData)
              return;
            if (mouse.button === Qt.RightButton) {
              mouse.accepted = true;
              TooltipService.hide();
              root.selectedWindow = taskbarItem.modelData;
              root.selectedAppName = CompositorService.getCleanAppName(taskbarItem.modelData.appId, taskbarItem.modelData.title);

              // Store position and size for timer callback
              const globalPos = taskbarItem.mapToItem(root, 0, 0);
              contextMenuOpenTimer.globalX = globalPos.x;
              contextMenuOpenTimer.globalY = globalPos.y;
              contextMenuOpenTimer.itemWidth = taskbarItem.width;
              contextMenuOpenTimer.itemHeight = taskbarItem.height;
              contextMenuOpenTimer.restart();
            }
          }
          onEntered: TooltipService.show(taskbarItem, taskbarItem.modelData.title || taskbarItem.modelData.appId || "Unknown app.", BarService.getTooltipDirection())
          onExited: TooltipService.hide()
        }
      }
    }
  }

  Timer {
    id: contextMenuOpenTimer
    interval: 10
    repeat: false
    property real globalX: 0
    property real globalY: 0
    property real itemWidth: 0
    property real itemHeight: 0

    onTriggered: {
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
}
