import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
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

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"
  readonly property real baseDimensionRatio: 0.65 * (widgetSettings.labelMode === "none" ? 0.75 : 1)

  readonly property string labelMode: (widgetSettings.labelMode !== undefined) ? widgetSettings.labelMode : widgetMetadata.labelMode
  readonly property bool hideUnoccupied: (widgetSettings.hideUnoccupied !== undefined) ? widgetSettings.hideUnoccupied : widgetMetadata.hideUnoccupied
  readonly property bool followFocusedScreen: (widgetSettings.followFocusedScreen !== undefined) ? widgetSettings.followFocusedScreen : widgetMetadata.followFocusedScreen
  readonly property int characterCount: isVertical ? 2 : ((widgetSettings.characterCount !== undefined) ? widgetSettings.characterCount : widgetMetadata.characterCount)

  // Grouped mode (show applications) settings
  readonly property bool showApplications: (widgetSettings.showApplications !== undefined) ? widgetSettings.showApplications : widgetMetadata.showApplications
  readonly property bool showLabelsOnlyWhenOccupied: (widgetSettings.showLabelsOnlyWhenOccupied !== undefined) ? widgetSettings.showLabelsOnlyWhenOccupied : widgetMetadata.showLabelsOnlyWhenOccupied
  readonly property bool colorizeIcons: (widgetSettings.colorizeIcons !== undefined) ? widgetSettings.colorizeIcons : widgetMetadata.colorizeIcons
  readonly property real unfocusedIconsOpacity: (widgetSettings.unfocusedIconsOpacity !== undefined) ? widgetSettings.unfocusedIconsOpacity : widgetMetadata.unfocusedIconsOpacity
  readonly property real groupedBorderOpacity: (widgetSettings.groupedBorderOpacity !== undefined) ? widgetSettings.groupedBorderOpacity : widgetMetadata.groupedBorderOpacity
  readonly property bool enableScrollWheel: (widgetSettings.enableScrollWheel !== undefined) ? widgetSettings.enableScrollWheel : widgetMetadata.enableScrollWheel
  readonly property real iconScale: (widgetSettings.iconScale !== undefined) ? widgetSettings.iconScale : widgetMetadata.iconScale

  // Only for grouped mode / show apps
  readonly property int baseItemSize: Style.toOdd(Style.capsuleHeight * 0.8)
  readonly property int iconSize: Style.toOdd(baseItemSize * iconScale)
  readonly property real textRatio: 0.50

  // Context menu state for grouped mode - store IDs instead of object references to avoid stale references
  property string selectedWindowId: ""
  property string selectedAppId: ""

  // Helper to get the current window object from ID
  function getSelectedWindow() {
    if (!selectedWindowId)
      return null;
    for (var i = 0; i < localWorkspaces.count; i++) {
      var ws = localWorkspaces.get(i);
      if (ws && ws.windows) {
        for (var j = 0; j < ws.windows.count; j++) {
          var win = ws.windows.get(j);
          // Using loose equality on purpose (==)
          if (win && (win.id == selectedWindowId || win.address == selectedWindowId)) {
            return win;
          }
        }
      }
    }
    return null;
  }

  property bool isDestroying: false
  property bool hovered: false

  // Revision counter to force icon re-evaluation
  property int iconRevision: 0

  property ListModel localWorkspaces: ListModel {}
  property real masterProgress: 0.0
  property bool effectsActive: false
  property color effectColor: Color.mPrimary

  property int horizontalPadding: Style.marginS
  property int spacingBetweenPills: Style.marginXS

  // Wheel scroll handling
  property int wheelAccumulatedDelta: 0
  property bool wheelCooldown: false

  signal workspaceChanged(int workspaceId, color accentColor)

  implicitWidth: showApplications ? (isVertical ? groupedGrid.implicitWidth + Style.marginM * 2 : Math.round(groupedGrid.implicitWidth + Style.marginM * 2)) : (isVertical ? Style.barHeight : computeWidth())
  implicitHeight: showApplications ? (isVertical ? Math.round(groupedGrid.implicitHeight + Style.marginM * 2) : Style.barHeight) : (isVertical ? computeHeight() : Style.barHeight)

  function getWorkspaceWidth(ws) {
    const d = Math.round(Style.capsuleHeight * root.baseDimensionRatio);
    const factor = ws.isActive ? 2.2 : 1;

    // Don't calculate text width if labels are off
    if (labelMode === "none") {
      return Math.round(d * factor);
    }

    var displayText = ws.idx.toString();

    if (ws.name && ws.name.length > 0) {
      if (root.labelMode === "name") {
        displayText = ws.name.substring(0, characterCount);
      } else if (root.labelMode === "index+name") {
        displayText = ws.idx.toString() + " " + ws.name.substring(0, characterCount);
      }
    }

    const textWidth = displayText.length * (d * 0.4); // Approximate width per character
    const padding = d * 0.6;
    return Style.toOdd(Math.max(d * factor, textWidth + padding));
  }

  function getWorkspaceHeight(ws) {
    const d = Math.round(Style.capsuleHeight * root.baseDimensionRatio);
    const factor = ws.isActive ? 2.2 : 1;
    return Style.toOdd(d * factor);
  }

  function computeWidth() {
    let total = 0;
    for (var i = 0; i < localWorkspaces.count; i++) {
      const ws = localWorkspaces.get(i);
      total += getWorkspaceWidth(ws);
    }
    total += Math.max(localWorkspaces.count - 1, 0) * spacingBetweenPills;
    total += horizontalPadding * 2;
    return Style.toOdd(total);
  }

  function computeHeight() {
    let total = 0;
    for (var i = 0; i < localWorkspaces.count; i++) {
      const ws = localWorkspaces.get(i);
      total += getWorkspaceHeight(ws);
    }
    total += Math.max(localWorkspaces.count - 1, 0) * spacingBetweenPills;
    total += horizontalPadding * 2;
    return Style.toOdd(total);
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

  // Helper function to normalize app IDs for case-insensitive matching
  function normalizeAppId(appId) {
    if (!appId || typeof appId !== 'string')
      return "";
    return appId.toLowerCase().trim();
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

    const normalizedId = normalizeAppId(appId);
    let pinnedApps = (Settings.data.dock.pinnedApps || []).slice();

    const existingIndex = pinnedApps.findIndex(pinnedId => normalizeAppId(pinnedId) === normalizedId);
    const isPinned = existingIndex >= 0;

    if (isPinned) {
      pinnedApps.splice(existingIndex, 1);
    } else {
      pinnedApps.push(appId);
    }

    Settings.data.dock.pinnedApps = pinnedApps;
  }

  Component.onCompleted: {
    refreshWorkspaces();
  }

  Component.onDestruction: {
    root.isDestroying = true;
  }

  onScreenChanged: refreshWorkspaces()
  onHideUnoccupiedChanged: refreshWorkspaces()

  Connections {
    target: CompositorService
    function onWorkspacesChanged() {
      refreshWorkspaces();
      root.triggerUnifiedWave();
    }
    function onWindowListChanged() {
      if (showApplications || showLabelsOnlyWhenOccupied) {
        refreshWorkspaces();
      }
    }
    function onActiveWindowChanged() {
      if (showApplications) {
        refreshWorkspaces();
      }
    }
  }

  // Refresh icons when DesktopEntries becomes available
  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      root.iconRevision++;
    }
  }

  function refreshWorkspaces() {
    localWorkspaces.clear();

    var focusedOutput = null;
    if (followFocusedScreen) {
      for (var i = 0; i < CompositorService.workspaces.count; i++) {
        const ws = CompositorService.workspaces.get(i);
        if (ws.isFocused)
          focusedOutput = ws.output.toLowerCase();
      }
    }

    if (screen !== null) {
      const screenName = screen.name.toLowerCase();
      for (var i = 0; i < CompositorService.workspaces.count; i++) {
        const ws = CompositorService.workspaces.get(i);
        const matchesScreen = (followFocusedScreen && ws.output.toLowerCase() == focusedOutput) || (!followFocusedScreen && ws.output.toLowerCase() == screenName);

        if (!matchesScreen)
          continue;
        if (hideUnoccupied && !ws.isOccupied && !ws.isFocused)
          continue;

        if (showApplications) {
          // For grouped mode, attach windows to each workspace
          var workspaceData = Object.assign({}, ws);
          workspaceData.windows = CompositorService.getWindowsForWorkspace(ws.id);
          localWorkspaces.append(workspaceData);
        } else {
          localWorkspaces.append(ws);
        }
      }
    }
    workspaceRepeaterHorizontal.model = localWorkspaces;
    workspaceRepeaterVertical.model = localWorkspaces;
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
        root.workspaceChanged(ws.id, Color.mPrimary);
        break;
      }
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
      var items = [];
      if (root.selectedWindowId) {
        // Focus item
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
                     "icon": !isPinned ? "pin" : "pinned-off"
                   });

        // Close item
        items.push({
                     "label": I18n.tr("common.close"),
                     "action": "close",
                     "icon": "x"
                   });

        // Add desktop entry actions
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
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.close();
                   }

                   const selectedWindow = root.getSelectedWindow();

                   if (action === "focus" && selectedWindow) {
                     CompositorService.focusWindow(selectedWindow);
                   } else if (action === "pin" && selectedAppId) {
                     root.toggleAppPin(selectedAppId);
                   } else if (action === "close" && selectedWindow) {
                     CompositorService.closeWindow(selectedWindow);
                   } else if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   } else if (action.startsWith("desktop-action-") && item && item.desktopAction) {
                     if (item.desktopAction.command && item.desktopAction.command.length > 0) {
                       Quickshell.execDetached(item.desktopAction.command);
                     } else if (item.desktopAction.execute) {
                       item.desktopAction.execute();
                     }
                   }
                   selectedWindowId = "";
                   selectedAppId = "";
                 }
  }

  Rectangle {
    id: workspaceBackground
    visible: !showApplications
    width: isVertical ? Style.capsuleHeight : parent.width
    height: isVertical ? parent.height : Style.capsuleHeight
    radius: Style.radiusM
    color: Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    x: isVertical ? Style.pixelAlignCenter(parent.width, width) : 0
    y: isVertical ? 0 : Style.pixelAlignCenter(parent.height, height)

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.RightButton
      onClicked: mouse => {
                   if (mouse.button === Qt.RightButton) {
                     var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                     if (popupMenuWindow) {
                       popupMenuWindow.showContextMenu(contextMenu);
                       contextMenu.openAtItem(workspaceBackground, screen);
                     }
                   }
                 }
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
    enabled: root.enableScrollWheel
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

  // Horizontal layout for top/bottom bars
  Row {
    id: pillRow
    spacing: spacingBetweenPills
    x: horizontalPadding
    y: workspaceBackground.y + Style.pixelAlignCenter(workspaceBackground.height, height)
    visible: !isVertical && !showApplications

    Repeater {
      id: workspaceRepeaterHorizontal
      model: localWorkspaces
      Item {
        id: workspacePillContainer
        width: root.getWorkspaceWidth(model)
        height: Style.toOdd(Style.capsuleHeight * root.baseDimensionRatio)

        Rectangle {
          id: pill
          anchors.fill: parent

          Loader {
            active: (labelMode !== "none") && (!root.showLabelsOnlyWhenOccupied || model.isOccupied || model.isFocused)
            sourceComponent: Component {
              NText {
                x: Style.pixelAlignCenter(pill.width, width)
                y: Style.pixelAlignCenter(pill.height, height)
                text: {
                  if (model.name && model.name.length > 0) {
                    if (root.labelMode === "name") {
                      return model.name.substring(0, characterCount);
                    }
                    if (root.labelMode === "index+name") {
                      return (model.idx.toString() + " " + model.name.substring(0, characterCount));
                    }
                  }
                  return model.idx.toString();
                }
                family: Settings.data.ui.fontFixed
                pointSize: workspacePillContainer.height * root.textRatio
                applyUiScale: false
                font.capitalization: Font.AllUppercase
                font.weight: Style.fontWeightBold
                wrapMode: Text.Wrap
                color: {
                  if (model.isFocused)
                    return Color.mOnPrimary;
                  if (model.isUrgent)
                    return Color.mOnError;
                  if (model.isOccupied)
                    return Color.mOnSecondary;

                  return Color.mOnSecondary;
                }
              }
            }
          }

          radius: Style.radiusM
          color: {
            if (model.isFocused)
              return Color.mPrimary;
            if (model.isUrgent)
              return Color.mError;
            if (model.isOccupied)
              return Color.mSecondary;

            return Qt.alpha(Color.mSecondary, 0.3);
          }
          z: 0

          MouseArea {
            id: pillMouseArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              CompositorService.switchToWorkspace(model);
            }
            hoverEnabled: true
          }
          // Material 3-inspired smooth animation for width, height, scale, color, opacity, and radius
          Behavior on width {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutBack
            }
          }
          Behavior on height {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutBack
            }
          }
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
          Behavior on opacity {
            NumberAnimation {
              duration: Style.animationFast
              easing.type: Easing.InOutCubic
            }
          }
          Behavior on radius {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutBack
            }
          }
        }

        Behavior on width {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutBack
          }
        }
        Behavior on height {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutBack
          }
        }
        // Burst effect overlay for focused pill (smaller outline)
        Rectangle {
          id: pillBurst
          anchors.centerIn: workspacePillContainer
          width: workspacePillContainer.width + 18 * root.masterProgress * scale
          height: workspacePillContainer.height + 18 * root.masterProgress * scale
          radius: width / 2
          color: "transparent"
          border.color: root.effectColor
          border.width: Math.max(1, Math.round((2 + 6 * (1.0 - root.masterProgress))))
          opacity: root.effectsActive && model.isFocused ? (1.0 - root.masterProgress) * 0.7 : 0
          visible: root.effectsActive && model.isFocused
          z: 1
        }
      }
    }
  }

  // Vertical layout for left/right bars
  Column {
    id: pillColumn
    spacing: spacingBetweenPills
    x: workspaceBackground.x + Style.pixelAlignCenter(workspaceBackground.width, width)
    y: horizontalPadding
    visible: isVertical && !showApplications

    Repeater {
      id: workspaceRepeaterVertical
      model: localWorkspaces
      Item {
        id: workspacePillContainerVertical
        width: Style.toOdd(Style.capsuleHeight * root.baseDimensionRatio)
        height: root.getWorkspaceHeight(model)

        Rectangle {
          id: pillVertical
          anchors.fill: parent

          Loader {
            active: (labelMode !== "none") && (!root.showLabelsOnlyWhenOccupied || model.isOccupied || model.isFocused)
            sourceComponent: Component {
              NText {
                x: Style.pixelAlignCenter(pillVertical.width, width)
                y: Style.pixelAlignCenter(pillVertical.height, height)
                text: {
                  if (model.name && model.name.length > 0) {
                    if (root.labelMode === "name") {
                      return model.name.substring(0, characterCount);
                    }
                    if (root.labelMode === "index+name") {
                      return (model.idx.toString() + model.name.substring(0, 1));
                    }
                  }
                  return model.idx.toString();
                }
                family: Settings.data.ui.fontFixed
                pointSize: workspacePillContainerVertical.width * root.textRatio
                applyUiScale: false
                font.capitalization: Font.AllUppercase
                font.weight: Style.fontWeightBold
                wrapMode: Text.Wrap
                color: {
                  if (model.isFocused)
                    return Color.mOnPrimary;
                  if (model.isUrgent)
                    return Color.mOnError;
                  if (model.isOccupied)
                    return Color.mOnSecondary;

                  return Color.mOnSecondary;
                }
              }
            }
          }

          radius: Style.radiusM
          color: {
            if (model.isFocused)
              return Color.mPrimary;
            if (model.isUrgent)
              return Color.mError;
            if (model.isOccupied)
              return Color.mSecondary;

            return Qt.alpha(Color.mSecondary, 0.3);
          }
          z: 0

          MouseArea {
            id: pillMouseAreaVertical
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              CompositorService.switchToWorkspace(model);
            }
            hoverEnabled: true
          }
          // Material 3-inspired smooth animation for width, height, scale, color, opacity, and radius
          Behavior on width {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutBack
            }
          }
          Behavior on height {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutBack
            }
          }
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
          Behavior on opacity {
            NumberAnimation {
              duration: Style.animationFast
              easing.type: Easing.InOutCubic
            }
          }
          Behavior on radius {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutBack
            }
          }
        }

        Behavior on width {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutBack
          }
        }
        Behavior on height {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutBack
          }
        }
        // Burst effect overlay for focused pill (smaller outline)
        Rectangle {
          id: pillBurstVertical
          anchors.centerIn: workspacePillContainerVertical
          width: workspacePillContainerVertical.width + 18 * root.masterProgress * scale
          height: workspacePillContainerVertical.height + 18 * root.masterProgress * scale
          radius: width / 2
          color: "transparent"
          border.color: root.effectColor
          border.width: Math.max(1, Math.round((2 + 6 * (1.0 - root.masterProgress))))
          opacity: root.effectsActive && model.isFocused ? (1.0 - root.masterProgress) * 0.7 : 0
          visible: root.effectsActive && model.isFocused
          z: 1
        }
      }
    }
  }

  // ========================================
  // Grouped mode (showApplications = true)
  // ========================================

  Component {
    id: groupedWorkspaceDelegate

    Rectangle {
      id: groupedContainer

      required property var model
      property var workspaceModel: model
      property bool hasWindows: (workspaceModel?.windows?.count ?? 0) > 0

      width: Style.toOdd((hasWindows ? groupedIconsFlow.implicitWidth : root.iconSize) + (root.isVertical ? (root.baseItemSize - root.iconSize + Style.marginXS) : Style.marginXL))
      height: Style.toOdd((hasWindows ? groupedIconsFlow.implicitHeight : root.iconSize) + (root.isVertical ? Style.marginL : (root.baseItemSize - root.iconSize + Style.marginXS)))
      color: Style.capsuleColor
      radius: Style.radiusS
      border.color: Settings.data.bar.showOutline ? Style.capsuleBorderColor : Qt.alpha((workspaceModel.isFocused ? Color.mPrimary : Color.mOutline), root.groupedBorderOpacity)
      border.width: Style.borderS

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        enabled: !groupedContainer.hasWindows
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        onPressed: mouse => {
                     if (mouse.button === Qt.LeftButton) {
                       CompositorService.switchToWorkspace(groupedContainer.workspaceModel);
                     }
                   }
        onReleased: mouse => {
                      if (mouse.button === Qt.RightButton) {
                        mouse.accepted = true;
                        TooltipService.hide();
                        root.selectedWindowId = "";
                        root.selectedAppId = "";
                        openGroupedContextMenu(groupedContainer);
                      }
                    }
      }

      Flow {
        id: groupedIconsFlow

        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        spacing: 2
        flow: root.isVertical ? Flow.TopToBottom : Flow.LeftToRight

        Repeater {
          model: groupedContainer.workspaceModel.windows

          delegate: Item {
            id: groupedTaskbarItem

            property bool itemHovered: false

            width: root.iconSize
            height: root.iconSize

            IconImage {
              id: groupedAppIcon

              width: parent.width
              height: parent.height
              source: {
                root.iconRevision; // Force re-evaluation when revision changes
                return ThemeIcons.iconForAppId(model.appId?.toLowerCase());
              }
              smooth: true
              asynchronous: true
              opacity: model.isFocused ? Style.opacityFull : unfocusedIconsOpacity
              layer.enabled: root.colorizeIcons && !model.isFocused

              Rectangle {
                id: groupedFocusIndicator
                visible: model.isFocused
                anchors.bottomMargin: -2
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.toOdd(root.iconSize * 0.25)
                height: 4
                color: Color.mPrimary
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
                           if (!model)
                           return;
                           if (mouse.button === Qt.LeftButton) {
                             CompositorService.focusWindow(model);
                           }
                         }

              onReleased: mouse => {
                            if (!model)
                            return;
                            if (mouse.button === Qt.RightButton) {
                              mouse.accepted = true;
                              TooltipService.hide();
                              root.selectedWindowId = model.id || model.address || "";
                              root.selectedAppId = model.appId;
                              openGroupedContextMenu(groupedTaskbarItem);
                            }
                          }
              onEntered: {
                groupedTaskbarItem.itemHovered = true;
                TooltipService.show(groupedTaskbarItem, model.title || model.appId || "Unknown app.", BarService.getTooltipDirection());
              }
              onExited: {
                groupedTaskbarItem.itemHovered = false;
                TooltipService.hide();
              }
            }
          }
        }
      }

      Item {
        id: groupedWorkspaceNumberContainer

        visible: root.labelMode !== "none" && (!root.showLabelsOnlyWhenOccupied || groupedContainer.hasWindows || groupedContainer.workspaceModel.isFocused)

        anchors {
          left: parent.left
          top: parent.top
          leftMargin: -Style.fontSizeXS * 0.55
          topMargin: -Style.fontSizeXS * 0.25
        }

        width: Math.max(groupedWorkspaceNumber.implicitWidth + (Style.marginXS * 2), Style.fontSizeXXS * 2)
        height: Math.max(groupedWorkspaceNumber.implicitHeight + Style.marginXS, Style.fontSizeXXS * 2)

        Rectangle {
          id: groupedWorkspaceNumberBackground

          anchors.fill: parent
          radius: Math.min(Style.radiusL, width / 2)

          color: {
            if (groupedContainer.workspaceModel.isFocused)
              return Color.mPrimary;
            if (groupedContainer.workspaceModel.isUrgent)
              return Color.mError;
            if (groupedContainer.hasWindows)
              return Color.mSecondary;

            if (Settings.data.colorSchemes.darkMode) {
              return Qt.darker(Color.mSecondary, 1.5);
            } else {
              return Qt.lighter(Color.mSecondary, 1.5);
            }
          }

          scale: groupedContainer.workspaceModel.isActive ? 1.0 : 0.8

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

        // Burst effect overlay for focused workspace number
        Rectangle {
          id: groupedWorkspaceNumberBurst
          anchors.centerIn: groupedWorkspaceNumberContainer
          width: groupedWorkspaceNumberContainer.width + 12 * root.masterProgress
          height: groupedWorkspaceNumberContainer.height + 12 * root.masterProgress
          radius: width / 2
          color: "transparent"
          border.color: root.effectColor
          border.width: Math.max(1, Math.round((2 + 4 * (1.0 - root.masterProgress))))
          opacity: root.effectsActive && groupedContainer.workspaceModel.isFocused ? (1.0 - root.masterProgress) * 0.7 : 0
          visible: root.effectsActive && groupedContainer.workspaceModel.isFocused
          z: 1
        }

        NText {
          id: groupedWorkspaceNumber

          anchors.centerIn: parent

          text: {
            if (groupedContainer.workspaceModel.name && groupedContainer.workspaceModel.name.length > 0) {
              if (root.labelMode === "name") {
                return groupedContainer.workspaceModel.name.substring(0, root.characterCount);
              }
              if (root.labelMode === "index+name") {
                return (groupedContainer.workspaceModel.idx.toString() + groupedContainer.workspaceModel.name.substring(0, 1));
              }
            }
            return groupedContainer.workspaceModel.idx.toString();
          }

          family: Settings.data.ui.fontFixed
          font {
            pointSize: Style.barFontSize * 0.75
            weight: Style.fontWeightBold
            capitalization: Font.AllUppercase
          }
          applyUiScale: false

          color: {
            if (groupedContainer.workspaceModel.isFocused)
              return Color.mOnPrimary;
            if (groupedContainer.workspaceModel.isUrgent)
              return Color.mOnError;

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
    id: groupedGrid
    visible: showApplications

    x: root.isVertical ? Style.pixelAlignCenter(parent.width, width) : Style.marginM
    y: root.isVertical ? Style.marginM : Style.pixelAlignCenter(parent.height, height)

    spacing: Style.marginS
    flow: root.isVertical ? Flow.TopToBottom : Flow.LeftToRight

    Repeater {
      model: showApplications ? localWorkspaces : null
      delegate: groupedWorkspaceDelegate
    }
  }

  function openGroupedContextMenu(item) {
    var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
    if (popupMenuWindow) {
      popupMenuWindow.showContextMenu(contextMenu);
      contextMenu.openAtItem(item, screen);
    }
  }
}
