import QtQuick
import QtQuick.Controls
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
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  // Explicit screenName property ensures reactive binding when screen changes
  readonly property string screenName: screen ? screen.name : ""
  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isVerticalBar: barPosition === "left" || barPosition === "right"
  readonly property real barHeight: Style.getBarHeightForScreen(screenName)
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
  readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0 && screenName) {
      var widgets = Settings.getBarWidgetsForScreen(screenName)[section];
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
  readonly property bool showTitle: isVerticalBar ? false : (widgetSettings.showTitle !== undefined) ? widgetSettings.showTitle : widgetMetadata.showTitle
  readonly property bool smartWidth: (widgetSettings.smartWidth !== undefined) ? widgetSettings.smartWidth : widgetMetadata.smartWidth
  readonly property int maxTaskbarWidthPercent: (widgetSettings.maxTaskbarWidth !== undefined) ? widgetSettings.maxTaskbarWidth : widgetMetadata.maxTaskbarWidth
  readonly property real iconScale: (widgetSettings.iconScale !== undefined) ? widgetSettings.iconScale : widgetMetadata.iconScale
  readonly property int itemSize: Style.toOdd(capsuleHeight * Math.max(0.1, iconScale))

  // Maximum width for the taskbar widget to prevent overlapping with other widgets
  readonly property real maxTaskbarWidth: {
    if (!screen || isVerticalBar || !smartWidth || maxTaskbarWidthPercent <= 0)
      return 0;
    var barFloating = Settings.data.bar.floating || false;
    var barMarginH = barFloating ? Math.ceil(Settings.data.bar.marginHorizontal) : 0;
    var availableWidth = screen.width - (barMarginH * 2);
    return Math.round(availableWidth * (maxTaskbarWidthPercent / 100));
  }

  readonly property int titleWidth: {
    // First, use user-defined title width if set
    var calculatedWidth = (widgetSettings.titleWidth !== undefined) ? widgetSettings.titleWidth : widgetMetadata.titleWidth;

    // Second, shrink title width if it exceeds maxTaskbarWidth when smartWidth is enabled
    if (smartWidth && combinedModel.length > 0) {
      if (maxTaskbarWidth > 0) {
        var entriesCount = combinedModel.length;
        var maxWidthPerEntry = (maxTaskbarWidth / entriesCount) - itemSize - Style.marginS - Style.marginXL;
        calculatedWidth = Math.min(calculatedWidth, maxWidthPerEntry);
      }

      calculatedWidth = Math.max(Math.round(calculatedWidth), 20);
    }

    return calculatedWidth;
  }
  readonly property bool showPinnedApps: (widgetSettings.showPinnedApps !== undefined) ? widgetSettings.showPinnedApps : widgetMetadata.showPinnedApps

  // Context menu state - store ID instead of object reference to avoid stale references
  property string selectedWindowId: ""
  property string selectedAppId: ""

  // Helper to get the current window object from ID
  function getSelectedWindow() {
    if (!selectedWindowId)
      return null;
    for (var i = 0; i < combinedModel.length; i++) {
      // Using loose equality on purpose (==)
      if (combinedModel[i].id == selectedWindowId && combinedModel[i].window) {
        return combinedModel[i].window;
      }
    }
    return null;
  }
  property int modelUpdateTrigger: 0  // Dummy property to force model re-evaluation

  // Hover state
  property var hoveredWindowId: ""
  // Combined model of running windows and pinned apps
  property var combinedModel: []

  // Wheel scroll handling
  property int wheelAccumulatedDelta: 0
  property bool wheelCooldown: false

  // Drag and Drop state for visual feedback
  property int dragSourceIndex: -1
  property int dragTargetIndex: -1

  // Track the session order of apps (transient reordering)
  property var sessionAppOrder: []

  function getAppKey(appData) {
    if (!appData)
      return null;
    // prefer window object identity for running apps to distinguish instances
    if (appData.window)
      return appData.window;
    // fallback to appId for pinned-only apps
    return appData.appId;
  }

  function sortApps(apps) {
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
    Logger.d("Taskbar", "Reordering apps from " + fromIndex + " to " + toIndex);
    if (fromIndex === toIndex || fromIndex < 0 || toIndex < 0 || fromIndex >= combinedModel.length || toIndex >= combinedModel.length)
      return;

    const list = [...combinedModel];
    const item = list.splice(fromIndex, 1)[0];
    list.splice(toIndex, 0, item);

    combinedModel = list;
    sessionAppOrder = combinedModel.map(getAppKey);
    savePinnedOrder();
  }

  function savePinnedOrder() {
    const currentPinned = Settings.data.dock.pinnedApps || [];
    const newPinned = [];
    const seen = new Set();

    // Extract pinned apps in their current visual order
    combinedModel.forEach(app => {
                            if (app.appId && !seen.has(app.appId)) {
                              const isPinned = currentPinned.some(p => normalizeAppId(p) === normalizeAppId(app.appId));

                              if (isPinned) {
                                newPinned.push(app.appId);
                                seen.add(app.appId);
                              }
                            }
                          });

    // Check if any pinned apps were missed (e.g. filtered out by workspace)
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

    // Return original appId if we can't find a desktop entry
    return appId;
  }

  // Helper function to get desktop entry ID from an app ID
  function getDesktopEntryId(appId) {
    if (!appId)
      return appId;

    // Try to find the desktop entry using heuristic lookup
    if (typeof DesktopEntries !== 'undefined' && DesktopEntries.heuristicLookup) {
      try {
        const entry = DesktopEntries.heuristicLookup(appId);
        if (entry && entry.id) {
          return entry.id;
        }
      } catch (e)
        // Fall through to return original appId
      {}
    }

    // Try direct lookup
    if (typeof DesktopEntries !== 'undefined' && DesktopEntries.byId) {
      try {
        const entry = DesktopEntries.byId(appId);
        if (entry && entry.id) {
          return entry.id;
        }
      } catch (e)
        // Fall through to return original appId
      {}
    }

    // Return original appId if we can't find a desktop entry
    return appId;
  }

  // Helper function to check if an app is pinned
  function isAppPinned(appId) {
    if (!appId)
      return false;
    const pinnedApps = Settings.data.dock.pinnedApps || [];
    const normalizedId = normalizeAppId(appId);
    return pinnedApps.some(pinnedId => normalizeAppId(pinnedId) === normalizedId);
  }

  // Helper function to toggle app pin/unpin
  function toggleAppPin(appId) {
    if (!appId)
      return;

    // Get the desktop entry ID for consistent pinning
    const desktopEntryId = getDesktopEntryId(appId);
    const normalizedId = normalizeAppId(desktopEntryId);

    let pinnedApps = (Settings.data.dock.pinnedApps || []).slice(); // Create a copy

    // Find existing pinned app with case-insensitive matching
    const existingIndex = pinnedApps.findIndex(pinnedId => normalizeAppId(pinnedId) === normalizedId);
    const isPinned = existingIndex >= 0;

    if (isPinned) {
      // Unpin: remove from array
      pinnedApps.splice(existingIndex, 1);
    } else {
      // Pin: add desktop entry ID to array
      pinnedApps.push(desktopEntryId);
    }

    // Update the settings
    Settings.data.dock.pinnedApps = pinnedApps;
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
                                "id": w.id,
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
                                                   "id": pinnedAppId,
                                                   "type": "pinned",
                                                   "window": null,
                                                   "appId": pinnedAppId,
                                                   "title": appName
                                                 });
                           }
                         });
    }

    combinedModel = sortApps(runningWindows);

    // Sync session order if needed (e.g. first run or new apps added)
    if (!sessionAppOrder || sessionAppOrder.length === 0 || sessionAppOrder.length !== combinedModel.length) {
      sessionAppOrder = combinedModel.map(getAppKey);
    }
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
      } else if (Settings.data.appLauncher.useApp2Unit && ProgramCheckerService.app2unitAvailable && app.id) {
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
          CompositorService.spawn(command);
        } else if (app.command && app.command.length > 0) {
          CompositorService.spawn(app.command);
        } else if (app.execute) {
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
      if (root.selectedWindowId) {
        // Focus item (for running apps)
        items.push({
                     "label": I18n.tr("common.focus"),
                     "action": "focus",
                     "icon": "eye"
                   });

        // Pin/Unpin item (always available when right-clicking an app)
        const isPinned = root.isAppPinned(root.selectedAppId);
        items.push({
                     "label": !isPinned ? I18n.tr("common.pin") : I18n.tr("common.unpin"),
                     "action": "pin",
                     "icon": !isPinned ? "pin" : "unpin"
                   });

        // Close item (for running apps)
        items.push({
                     "label": I18n.tr("common.close"),
                     "action": "close",
                     "icon": "x"
                   });

        // Add desktop entry actions (like "New Window", "Private Window", etc.)
        if (typeof DesktopEntries !== 'undefined' && DesktopEntries.byId && root.selectedAppId) {
          const entry = (DesktopEntries.heuristicLookup) ? DesktopEntries.heuristicLookup(root.selectedAppId) : DesktopEntries.byId(root.selectedAppId);
          if (entry != null && entry.actions) {
            entry.actions.forEach(function (action) {
              items.push({
                           "label": action.name,
                           "action": "desktop-action-" + action.name,
                           "icon": "chevron-right",
                           "desktopAction": action
                         });
            });
          }
        }
      }
      items.push({
                   "label": I18n.tr("actions.widget-settings"),
                   "action": "widget-settings",
                   "icon": "settings"
                 });
      return items;
    }
    onTriggered: (action, item) => {
                   contextMenu.close();
                   PanelService.closeContextMenu(root.screen);

                   // Look up the window fresh each time to avoid stale references
                   const selectedWindow = root.getSelectedWindow();

                   if (action === "focus" && selectedWindow) {
                     CompositorService.focusWindow(selectedWindow);
                   } else if (action === "pin" && root.selectedAppId) {
                     root.toggleAppPin(root.selectedAppId);
                   } else if (action === "close" && selectedWindow) {
                     CompositorService.closeWindow(selectedWindow);
                   } else if (action === "widget-settings") {
                     BarService.openWidgetSettings(root.screen, root.section, root.sectionWidgetIndex, root.widgetId, root.widgetSettings);
                   } else if (action.startsWith("desktop-action-") && item && item.desktopAction) {
                     if (item.desktopAction.command && item.desktopAction.command.length > 0) {
                       Quickshell.execDetached(item.desktopAction.command);
                     } else if (item.desktopAction.execute) {
                       item.desktopAction.execute();
                     }
                   }
                   root.selectedWindowId = "";
                   root.selectedAppId = "";
                 }
  }

  function updateHasWindow() {
    // Check if we have any items in the combined model (windows or pinned apps)
    hasWindow = combinedModel.length > 0;
  }

  Connections {
    target: CompositorService
    function onActiveWindowChanged() {
      updateCombinedModel();
    }
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

  // Scroll to switch between windows
  WheelHandler {
    id: wheelHandler
    target: root
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function (event) {
      if (root.wheelCooldown || root.combinedModel.length === 0)
        return;
      var dy = event.angleDelta.y;
      var dx = event.angleDelta.x;
      var useDy = Math.abs(dy) >= Math.abs(dx);
      var delta = useDy ? dy : dx;
      root.wheelAccumulatedDelta += delta;
      var step = 120;
      if (Math.abs(root.wheelAccumulatedDelta) >= step) {
        var direction = root.wheelAccumulatedDelta > 0 ? -1 : 1;
        // Find the focused window or first running window
        var currentIndex = -1;
        for (var i = 0; i < root.combinedModel.length; i++) {
          if (root.combinedModel[i].window && root.combinedModel[i].window.isFocused) {
            currentIndex = i;
            break;
          }
        }
        if (currentIndex < 0) {
          // No focused window, find first running window
          for (var j = 0; j < root.combinedModel.length; j++) {
            if (root.combinedModel[j].window) {
              currentIndex = j;
              break;
            }
          }
        }
        if (currentIndex >= 0) {
          var nextIndex = (currentIndex + direction + root.combinedModel.length) % root.combinedModel.length;
          var nextItem = root.combinedModel[nextIndex];
          if (nextItem && nextItem.window) {
            try {
              CompositorService.focusWindow(nextItem.window);
            } catch (error) {
              Logger.e("Taskbar", "Failed to focus window: " + error);
            }
          }
        }
        root.wheelCooldown = true;
        wheelDebounce.restart();
        root.wheelAccumulatedDelta = 0;
        event.accepted = true;
      }
    }
  }

  // "visible": Always Visible, "hidden": Hide When Empty, "transparent": Transparent When Empty
  visible: hideMode !== "hidden" || hasWindow
  opacity: ((hideMode !== "hidden" && hideMode !== "transparent") || hasWindow) ? 1.0 : 0.0
  Behavior on opacity {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Style.easingTypeDefault
      easing.bezierCurve: Style.easingCurveDefault
    }
  }

  // Content dimensions for implicit sizing
  readonly property real contentWidth: {
    if (!visible)
      return 0;
    if (isVerticalBar)
      return barHeight;

    var calculatedWidth = showTitle ? taskbarLayout.implicitWidth : taskbarLayout.implicitWidth + Style.marginXL;

    // Apply maximum width constraint when smartWidth is enabled
    if (smartWidth && maxTaskbarWidth > 0) {
      return Math.min(calculatedWidth, maxTaskbarWidth);
    }

    return Math.round(calculatedWidth);
  }
  readonly property real contentHeight: visible ? (isVerticalBar ? Math.round(taskbarLayout.implicitHeight + Style.marginS * 2) : capsuleHeight) : 0

  implicitWidth: contentWidth
  implicitHeight: contentHeight

  // Visual capsule centered in parent
  Rectangle {
    id: visualCapsule
    width: root.contentWidth
    height: root.contentHeight
    anchors.centerIn: parent
    radius: Style.radiusM
    color: Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    GridLayout {
      id: taskbarLayout

      // Pixel-perfect centering
      x: isVerticalBar ? Style.pixelAlignCenter(parent.width, width) : ((root.showTitle) ? Style.pixelAlignCenter(parent.width, width) : Style.marginM)
      y: Style.pixelAlignCenter(parent.height, height)

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
          required property int index
          property ShellScreen screen: root.screen

          readonly property bool isRunning: modelData.window !== null
          readonly property bool isPinned: modelData.type === "pinned" || modelData.type === "pinned-running"
          readonly property bool isFocused: isRunning && modelData.window && modelData.window.isFocused
          readonly property bool isPinnedRunning: isPinned && isRunning && !isFocused
          readonly property bool isHovered: root.hoveredWindowId === modelData.id

          readonly property bool shouldShowTitle: root.showTitle && modelData.type !== "pinned"
          readonly property real itemSpacing: Style.marginS
          readonly property real contentWidth: shouldShowTitle ? root.itemSize + itemSpacing + root.titleWidth : root.itemSize

          readonly property string title: modelData.title || modelData.appId || "Unknown application"
          readonly property color titleBgColor: (isHovered || isFocused) ? Color.mHover : Style.capsuleColor
          readonly property color titleFgColor: (isHovered || isFocused) ? Color.mOnHover : Color.mOnSurface

          Layout.preferredWidth: root.isVerticalBar ? root.barHeight : (root.showTitle ? Math.round(contentWidth + Style.marginXL) : Math.round(contentWidth)) // Add margins for both pinned and running apps
          Layout.preferredHeight: root.isVerticalBar ? root.itemSize : root.barHeight
          Layout.alignment: Qt.AlignCenter

          // Ensure dragged item is on top
          z: (root.dragSourceIndex === index) ? 1000 : 1

          property int modelIndex: index
          objectName: "taskbarAppItem"

          DropArea {
            anchors.fill: parent
            keys: ["taskbar-app"]
            onEntered: function (drag) {
              if (drag.source && drag.source.objectName === "taskbarAppItem") {
                root.dragTargetIndex = taskbarItem.modelIndex;
              }
            }
            onExited: function () {
              if (root.dragTargetIndex === taskbarItem.modelIndex) {
                root.dragTargetIndex = -1;
              }
            }
            onDropped: function (drop) {
              root.dragSourceIndex = -1;
              root.dragTargetIndex = -1;
              Logger.d("Taskbar", "Dropped! Source: " + (drop.source ? drop.source.objectName : "null") + " Index: " + (drop.source ? drop.source.modelIndex : "?") + " -> Target Index: " + taskbarItem.modelIndex);
              if (drop.source && drop.source.objectName === "taskbarAppItem" && drop.source !== taskbarItem) {
                root.reorderApps(drop.source.modelIndex, taskbarItem.modelIndex);
              } else {
                Logger.d("Taskbar", "Drop ignored. Source objectName: " + (drop.source ? drop.source.objectName : "null"));
              }
            }
          }

          Item {
            id: draggableContent
            width: parent.width
            height: parent.height
            anchors.centerIn: dragging ? undefined : parent

            // Visual shifting logic
            readonly property bool isDragged: root.dragSourceIndex === index
            property real shiftOffset: 0

            // Calculate shift based on drag state
            // If I am NOT the dragged item, but I am in the path of the drag
            Binding on shiftOffset {
              value: {
                if (root.dragSourceIndex !== -1 && root.dragTargetIndex !== -1 && !draggableContent.isDragged) {
                  if (root.dragSourceIndex < root.dragTargetIndex) {
                    // Dragging Right: Items between source and target shift Left
                    if (index > root.dragSourceIndex && index <= root.dragTargetIndex) {
                      return -1 * (root.isVerticalBar ? root.itemSize : draggableContent.width); // Simple approximation, could be refined
                    }
                  } else if (root.dragSourceIndex > root.dragTargetIndex) {
                    // Dragging Left: Items between target and source shift Right
                    if (index >= root.dragTargetIndex && index < root.dragSourceIndex) {
                      return (root.isVerticalBar ? root.itemSize : draggableContent.width);
                    }
                  }
                }
                return 0;
              }
            }

            transform: Translate {
              x: !root.isVerticalBar ? draggableContent.shiftOffset : 0
              y: root.isVerticalBar ? draggableContent.shiftOffset : 0

              Behavior on x {
                NumberAnimation {
                  duration: Style.animationFast
                  easing.type: Style.easingTypeFast
                  easing.bezierCurve: Style.easingCurveFast
                }
              }
              Behavior on y {
                NumberAnimation {
                  duration: Style.animationFast
                  easing.type: Style.easingTypeFast
                  easing.bezierCurve: Style.easingCurveFast
                }
              }
            }

            property bool dragging: taskbarMouseArea.drag.active
            onDraggingChanged: {
              if (dragging) {
                root.dragSourceIndex = index;
              } else {
                // Don't reset immediately on release to allow drop to handle it,
                // or use a timer if needed, but drop handler usually fires.
                // However, if dropped outside, we need to reset.
                // Let's reset if not handled by drop area quickly?
                // Actually, drag.active becomes false on release.
                // We might want to clear it if no drop happened.
                if (root.dragSourceIndex === index) {
                  // Slight delay/check? For now, let DropArea handle reset on success.
                  // If cancelled (dropped nowhere), we should reset.
                  Qt.callLater(() => {
                                 if (!taskbarMouseArea.drag.active && root.dragSourceIndex === index) {
                                   root.dragSourceIndex = -1;
                                   root.dragTargetIndex = -1;
                                 }
                               });
                }
              }
            }

            Drag.active: dragging
            Drag.source: taskbarItem
            Drag.hotSpot.x: width / 2
            Drag.hotSpot.y: height / 2
            Drag.keys: ["taskbar-app"]

            z: dragging ? 1000 : 0
            scale: dragging ? 1.05 : 1.0
            Behavior on scale {
              NumberAnimation {
                duration: Style.animationFast
              }
            }

            Rectangle {
              id: titleBackground
              visible: shouldShowTitle
              anchors.centerIn: parent
              width: parent.width
              height: root.capsuleHeight
              color: titleBgColor
              radius: Style.radiusM

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                  easing.type: Style.easingTypeSlow
                  easing.bezierCurve: Style.easingCurveSlow
                }
              }
            }

            Rectangle {
              anchors.centerIn: parent
              width: taskbarItem.contentWidth
              height: parent.height
              color: "transparent"

              RowLayout {
                id: itemLayout
                anchors.fill: parent
                spacing: taskbarItem.itemSpacing

                Item {
                  Layout.preferredWidth: root.itemSize
                  Layout.preferredHeight: root.itemSize
                  Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft

                  IconImage {
                    id: appIcon
                    anchors.fill: parent

                    source: ThemeIcons.iconForAppId(taskbarItem.modelData.appId)
                    smooth: true
                    asynchronous: true

                    // Apply dock shader to all taskbar icons
                    layer.enabled: widgetSettings.colorizeIcons !== false
                    layer.effect: ShaderEffect {
                      property color targetColor: Settings.data.colorSchemes.darkMode ? Color.mOnSurface : Color.mSurfaceVariant
                      property real colorizeMode: 0.0 // Dock mode (grayscale)

                      fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
                    }
                  }

                  Rectangle {
                    id: iconBackground
                    visible: !shouldShowTitle
                    anchors.bottomMargin: -2
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Style.toOdd(root.itemSize * 0.25)
                    height: 4
                    color: taskbarItem.isFocused ? Color.mPrimary : (taskbarItem.isHovered ? Color.mHover : "transparent")
                    radius: Math.min(Style.radiusXXS, width / 2)

                    Behavior on color {
                      ColorAnimation {
                        duration: Style.animationFast
                        easing.type: Style.easingTypeDefault
                        easing.bezierCurve: Style.easingCurveDefault
                      }
                    }
                  }
                }

                NText {
                  id: titleText
                  visible: shouldShowTitle
                  Layout.preferredWidth: root.titleWidth
                  Layout.preferredHeight: root.itemSize
                  Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
                  Layout.fillWidth: false

                  text: taskbarItem.title
                  elide: Text.ElideRight
                  verticalAlignment: Text.AlignVCenter
                  horizontalAlignment: Text.AlignLeft

                  pointSize: barFontSize
                  color: titleFgColor
                  opacity: Style.opacityFull
                }
              }
            }
          }

          MouseArea {
            id: taskbarMouseArea
            objectName: "taskbarMouseArea"
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton

            drag.target: draggableContent
            drag.axis: root.isVerticalBar ? Drag.YAxis : Drag.XAxis
            preventStealing: true

            onPressed: {
              // Constrain drag to roughly the taskbar area but allow some freedom
              // Or just let it be free since we only care about drops
            }

            onReleased: {
              if (draggableContent.Drag.active) {
                draggableContent.Drag.drop();
              }
            }

            onClicked: mouse => {
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
                         } else if (mouse.button === Qt.RightButton) {
                           TooltipService.hide();
                           // Only show context menu for running apps
                           if (isRunning && modelData.window) {
                             root.selectedWindowId = modelData.id;
                             root.selectedAppId = modelData.appId;
                             root.openTaskbarContextMenu(taskbarItem);
                           }
                         }
                       }
            onEntered: {
              root.hoveredWindowId = taskbarItem.modelData.id;
              TooltipService.show(taskbarItem, taskbarItem.title, BarService.getTooltipDirection(root.screen?.name));
            }
            onExited: {
              root.hoveredWindowId = "";
              TooltipService.hide();
            }
          }
        }
      }
    }
  }

  function openTaskbarContextMenu(item) {
    // Build menu model directly
    var items = [];
    if (root.selectedWindowId) {
      // Focus item (for running apps)
      items.push({
                   "label": I18n.tr("common.focus"),
                   "action": "focus",
                   "icon": "eye"
                 });

      // Pin/Unpin item
      const isPinned = root.isAppPinned(root.selectedAppId);
      items.push({
                   "label": !isPinned ? I18n.tr("common.pin") : I18n.tr("common.unpin"),
                   "action": "pin",
                   "icon": !isPinned ? "pin" : "unpin"
                 });

      // Close item
      items.push({
                   "label": I18n.tr("common.close"),
                   "action": "close",
                   "icon": "x"
                 });

      // Add desktop entry actions (like "New Window", "Private Window", etc.)
      if (typeof DesktopEntries !== 'undefined' && DesktopEntries.byId && root.selectedAppId) {
        const entry = (DesktopEntries.heuristicLookup) ? DesktopEntries.heuristicLookup(root.selectedAppId) : DesktopEntries.byId(root.selectedAppId);
        if (entry != null && entry.actions) {
          entry.actions.forEach(function (action) {
            items.push({
                         "label": action.name,
                         "action": "desktop-action-" + action.name,
                         "icon": "chevron-right",
                         "desktopAction": action
                       });
          });
        }
      }
    }
    items.push({
                 "label": I18n.tr("actions.widget-settings"),
                 "action": "widget-settings",
                 "icon": "settings"
               });

    // Set the model directly
    contextMenu.model = items;

    // Anchor to root (stable) but center horizontally on the clicked item
    PanelService.showContextMenu(contextMenu, root, screen, item);
  }
}
