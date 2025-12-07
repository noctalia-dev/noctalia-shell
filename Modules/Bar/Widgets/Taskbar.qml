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
  readonly property bool showPinnedApps: (widgetSettings.showPinnedApps !== undefined) ? widgetSettings.showPinnedApps : widgetMetadata.showPinnedApps

  // Context menu state
  property var selectedWindow: null
  property string selectedAppName: ""
  property int modelUpdateTrigger: 0  // Dummy property to force model re-evaluation

  // Combined model of running windows and pinned apps
  property var combinedModel: []

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

  // Function to update the combined model
  function updateCombinedModel() {
    const runningWindows = [];
    const pinnedApps = Settings.data.dock.pinnedApps || [];
    const processedAppIds = new Set();

    // First pass: Add all running windows
    try {
      const total = CompositorService.windows.count || 0;
      const activeIds = CompositorService.getActiveWorkspaces().map(function (ws) {
        return ws.id;
      });

      for (var i = 0; i < total; i++) {
        var w = CompositorService.windows.get(i);
        if (!w)
          continue;
        var passOutput = (!onlySameOutput) || (w.output == screen?.name);
        var passWorkspace = (!onlyActiveWorkspaces) || (activeIds.includes(w.workspaceId));
        if (passOutput && passWorkspace) {
          const isPinned = isAppIdPinned(w.appId, pinnedApps);
          runningWindows.push({
                                "type": isPinned ? "pinned-running" : "running",
                                "window": w,
                                "appId": w.appId,
                                "title": w.title || getAppNameFromDesktopEntry(w.appId)
                              });
          processedAppIds.add(normalizeAppId(w.appId));
        }
      }
    } catch (e)
      // Ignore errors
    {}

    // Second pass: Add non-running pinned apps (only if showPinnedApps is enabled)
    if (showPinnedApps) {
      pinnedApps.forEach(pinnedAppId => {
                           const normalizedPinnedId = normalizeAppId(pinnedAppId);
                           if (!processedAppIds.has(normalizedPinnedId)) {
                             const appName = getAppNameFromDesktopEntry(pinnedAppId);
                             runningWindows.push({
                                                   "type": "pinned",
                                                   "window": null,
                                                   "appId": pinnedAppId,
                                                   "title": appName
                                                 });
                           }
                         });
    }

    combinedModel = runningWindows;
    updateHasWindow();
  }

  // Function to launch a pinned app
  function launchPinnedApp(appId) {
    if (!appId)
      return;

    try {
      const app = DesktopEntries.byId(appId);

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
        Logger.d("Taskbar", `Using app2unit for: ${app.id}`);
        if (app.runInTerminal)
          Quickshell.execDetached(["app2unit", "--", app.id + ".desktop"]);
        else
          Quickshell.execDetached(["app2unit", "--"].concat(app.command));
      } else {
        // Fallback logic when app2unit is not used
        if (app.runInTerminal) {
          Logger.d("Taskbar", "Executing terminal app manually: " + app.name);
          const terminal = Settings.data.appLauncher.terminalCommand.split(" ");
          const command = terminal.concat(app.command);
          Quickshell.execDetached(command);
        } else if (app.execute) {
          // Default execution for GUI apps
          app.execute();
        } else {
          Logger.w("Taskbar", `Could not launch: ${app.name}. No valid launch method.`);
        }
      }
    } catch (e) {
      Logger.e("Taskbar", "Failed to launch app: " + e);
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
    // Check if we have any items in the combined model (windows or pinned apps)
    hasWindow = combinedModel.length > 0;
  }

  Connections {
    target: CompositorService
    function onWindowListChanged() {
      updateCombinedModel();
    }
    function onWorkspaceChanged() {
      updateCombinedModel();
    }
  }

  Connections {
    target: Settings.data.dock
    function onPinnedAppsChanged() {
      updateCombinedModel();
    }
  }

  Component.onCompleted: {
    updateCombinedModel();
  }
  onScreenChanged: updateCombinedModel()

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
      model: root.combinedModel
      delegate: Item {
        id: taskbarItem
        required property var modelData
        property ShellScreen screen: root.screen

        readonly property bool isRunning: modelData.window !== null
        readonly property bool isPinned: modelData.type === "pinned" || modelData.type === "pinned-running"
        readonly property bool isFocused: isRunning && modelData.window && modelData.window.isFocused
        readonly property bool isPinnedRunning: isPinned && isRunning && !isFocused

        Layout.preferredWidth: root.itemSize
        Layout.preferredHeight: root.itemSize
        Layout.alignment: Qt.AlignCenter

        IconImage {
          id: appIcon
          width: parent.width
          height: parent.height
          source: ThemeIcons.iconForAppId(modelData.appId)
          smooth: true
          asynchronous: true
          // Opacity: Focused (1.0) > Pinned Running (0.7) > Regular Running (0.6) > Just Pinned (0.4)
          opacity: isFocused ? Style.opacityFull : (isPinnedRunning ? 0.7 : (isRunning ? 0.6 : 0.4))

          // For pinned apps that aren't running: use a muted color to indicate not running
          // For other apps: use standard colorization if enabled
          layer.enabled: (isPinned && !isRunning) || (root.widgetSettings.colorizeIcons !== false && !isFocused)
          layer.effect: ShaderEffect {
            property color targetColor: {
              // Pinned but not running: use a muted/desaturated color to indicate not running
              if (isPinned && !isRunning) {
                // Use a muted secondary or outline color
                return Settings.data.colorSchemes.darkMode ? Qt.darker(Color.mSecondary, 1.3) : Qt.lighter(Color.mSecondary, 1.5);
              }
              // Standard colorization for other cases
              return Settings.data.colorSchemes.darkMode ? Color.mOnSurface : Color.mSurfaceVariant;
            }
            property real colorizeMode: 0.0 // Dock mode (grayscale)

            fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
          }

          // Active indicator (focused window)
          Rectangle {
            id: iconBackground
            anchors.bottomMargin: -2
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: 4
            height: 4
            color: isFocused ? Color.mPrimary : Color.transparent
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
            if (!modelData)
              return;
            if (mouse.button === Qt.LeftButton) {
              if (isRunning && modelData.window) {
                // Running app - focus it
                try {
                  CompositorService.focusWindow(modelData.window);
                } catch (error) {
                  Logger.e("Taskbar", "Failed to activate toplevel: " + error);
                }
              } else if (isPinned) {
                // Pinned app not running - launch it
                root.launchPinnedApp(modelData.appId);
              }
            }
          }

          onReleased: function (mouse) {
            if (!modelData)
              return;
            if (mouse.button === Qt.RightButton) {
              mouse.accepted = true;
              TooltipService.hide();
              // Only show context menu for running apps
              if (isRunning && modelData.window) {
                root.selectedWindow = modelData.window;
                root.selectedAppName = CompositorService.getCleanAppName(modelData.appId, modelData.title);

                // Store position and size for timer callback
                const globalPos = taskbarItem.mapToItem(root, 0, 0);
                contextMenuOpenTimer.globalX = globalPos.x;
                contextMenuOpenTimer.globalY = globalPos.y;
                contextMenuOpenTimer.itemWidth = taskbarItem.width;
                contextMenuOpenTimer.itemHeight = taskbarItem.height;
                contextMenuOpenTimer.restart();
              }
            }
          }
          onEntered: TooltipService.show(taskbarItem, modelData.title || modelData.appId || "Unknown app.", BarService.getTooltipDirection())
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
