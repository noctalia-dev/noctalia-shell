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
  // Explicit screenName property ensures reactive binding when screen changes
  readonly property string screenName: screen ? screen.name : ""
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0 && screenName) {
      var widgets = Settings.getBarWidgetsForScreen(screenName)[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"
  readonly property real barHeight: Style.getBarHeightForScreen(screenName)
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
  readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)
  readonly property real baseDimensionRatio: 0.65

  readonly property string labelMode: (widgetSettings.labelMode !== undefined) ? widgetSettings.labelMode : widgetMetadata.labelMode
  readonly property bool hasLabel: (labelMode !== "none")
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
  readonly property bool reverseScroll: (widgetSettings.reverseScroll !== undefined) ? widgetSettings.reverseScroll : (widgetMetadata.reverseScroll || false)
  readonly property real iconScale: (widgetSettings.iconScale !== undefined) ? widgetSettings.iconScale : widgetMetadata.iconScale
  readonly property string focusedColor: (widgetSettings.focusedColor !== undefined) ? widgetSettings.focusedColor : widgetMetadata.focusedColor
  readonly property string occupiedColor: (widgetSettings.occupiedColor !== undefined) ? widgetSettings.occupiedColor : widgetMetadata.occupiedColor
  readonly property string emptyColor: (widgetSettings.emptyColor !== undefined) ? widgetSettings.emptyColor : widgetMetadata.emptyColor
  readonly property bool showBadge: (widgetSettings.showBadge !== undefined) ? widgetSettings.showBadge : widgetMetadata.showBadge

  // Helper to safely get colors with proper reactivity
  // Accesses Color singleton directly to ensure fresh values
  function getColorPair(colorKey) {
    switch (colorKey) {
    case "primary":
      return [Color.mPrimary, Color.mOnPrimary];
    case "secondary":
      return [Color.mSecondary, Color.mOnSecondary];
    case "tertiary":
      return [Color.mTertiary, Color.mOnTertiary];
    case "onSurface":
      return [Color.mOnSurface, Color.mSurface];
    default:
      return [Color.mPrimary, Color.mOnPrimary];
    }
  }

  // Only for grouped mode / show apps
  readonly property int baseItemSize: Style.toOdd(capsuleHeight * 0.8)
  readonly property int iconSize: Style.toOdd(baseItemSize * iconScale)
  readonly property real textRatio: 0.50

  // Context menu state for grouped mode - store IDs instead of object references to avoid stale references
  property string selectedWindowId: ""
  property string selectedAppId: ""

  // Helper to get the current window object from ID
  function getSelectedWindow() {
    if (!selectedWindowId)
      return null;
    // Search directly in CompositorService to get the live window object
    for (var i = 0; i < CompositorService.windows.count; i++) {
      var win = CompositorService.windows.get(i);
      // Using loose equality on purpose (==)
      if (win && (win.id == selectedWindowId || win.address == selectedWindowId)) {
        return win;
      }
    }
    return null;
  }

  property bool isDestroying: false
  property bool hovered: false

  // Revision counter to force icon re-evaluation
  property int iconRevision: 0
  // Revision counter to force window list re-evaluation (for liveWindows binding in grouped mode)
  property int windowRevision: 0

  property ListModel localWorkspaces: ListModel {}
  property int lastFocusedWorkspaceId: -1
  property real masterProgress: 0.0
  property bool effectsActive: false
  property color effectColor: Color.mPrimary

  property int horizontalPadding: Style.marginS
  property int spacingBetweenPills: Style.marginXS

  // Wheel scroll handling
  property int wheelAccumulatedDelta: 0
  property bool wheelCooldown: false

  signal workspaceChanged(int workspaceId, color accentColor)

  implicitWidth: showApplications ? (isVertical ? groupedGrid.implicitWidth : Math.round(groupedGrid.implicitWidth + horizontalPadding * hasLabel)) : (isVertical ? barHeight : computeWidth())
  implicitHeight: showApplications ? (isVertical ? Math.round(groupedGrid.implicitHeight + horizontalPadding * 0.6 * hasLabel) : barHeight) : (isVertical ? computeHeight() : barHeight)

  function getWorkspaceWidth(ws, activeOverride) {
    const d = Math.round(capsuleHeight * root.baseDimensionRatio);
    const isActive = activeOverride !== undefined ? activeOverride : ws.isActive;
    const factor = isActive ? 2.2 : 1;

    // Don't calculate text width if labels are off
    if (labelMode === "none") {
      return Style.toOdd(d * factor);
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

  function getWorkspaceHeight(ws, activeOverride) {
    const d = Math.round(capsuleHeight * root.baseDimensionRatio);
    const isActive = activeOverride !== undefined ? activeOverride : ws.isActive;
    const factor = isActive ? 2.2 : 1;
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
  onScreenNameChanged: refreshWorkspaces()
  onHideUnoccupiedChanged: refreshWorkspaces()
  onShowApplicationsChanged: refreshWorkspaces()

  Connections {
    target: CompositorService
    function onWorkspacesChanged() {
      refreshWorkspaces();
    }
    function onWindowListChanged() {
      if (showApplications || showLabelsOnlyWhenOccupied) {
        root.windowRevision++;
        refreshWorkspaces();
      }
    }
    function onActiveWindowChanged() {
      if (showApplications) {
        root.windowRevision++;
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
    var targetList = [];
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

        // Create a plain JS object for the workspace data
        var workspaceData = {
          id: ws.id,
          idx: ws.idx,
          name: ws.name,
          output: ws.output,
          isFocused: ws.isFocused,
          isActive: ws.isActive,
          isUrgent: ws.isUrgent,
          isOccupied: ws.isOccupied
        };

        if (ws.handle !== null && ws.handle !== undefined) {
          workspaceData.handle = ws.handle;
        }

        // Windows are fetched live via liveWindows property in grouped mode
        // to avoid Qt 6.9 ListModel nested array serialization issues

        targetList.push(workspaceData);
      }
    }

    // In-place update to preserve delegates for animations
    var i = 0;
    while (i < localWorkspaces.count || i < targetList.length) {
      if (i < localWorkspaces.count && i < targetList.length) {
        var existing = localWorkspaces.get(i);
        var target = targetList[i];
        if (existing.id === target.id) {
          // Use set() to update all properties, including arrays like 'windows'
          // This is more reliable than repeated setProperty calls for complex types
          localWorkspaces.set(i, target);
          i++;
        } else {
          // ID mismatch, remove existing and re-evaluate this index
          localWorkspaces.remove(i);
        }
      } else if (i < localWorkspaces.count) {
        // Excess items in local, remove them
        localWorkspaces.remove(i);
      } else {
        // More items in target, append them
        localWorkspaces.append(targetList[i]);
        i++;
      }
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
        if (root.lastFocusedWorkspaceId !== -1 && root.lastFocusedWorkspaceId !== ws.id) {
          root.triggerUnifiedWave();
        }
        root.lastFocusedWorkspaceId = ws.id;
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
                   contextMenu.close();
                   PanelService.closeContextMenu(screen);

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
    width: isVertical ? capsuleHeight : parent.width
    height: isVertical ? parent.height : capsuleHeight
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
                     PanelService.showContextMenu(contextMenu, workspaceBackground, screen);
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
        if (root.reverseScroll)
          direction *= -1;
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
    y: 0
    visible: !isVertical && !showApplications

    Repeater {
      id: workspaceRepeaterHorizontal
      model: localWorkspaces
      delegate: WorkspacePill {
        required property var model
        workspace: model
        isVertical: false
        baseDimensionRatio: root.baseDimensionRatio
        capsuleHeight: root.capsuleHeight
        barHeight: root.barHeight
        labelMode: root.labelMode
        characterCount: root.characterCount
        textRatio: root.textRatio
        showLabelsOnlyWhenOccupied: root.showLabelsOnlyWhenOccupied
        focusedColor: root.focusedColor
        occupiedColor: root.occupiedColor
        emptyColor: root.emptyColor
        masterProgress: root.masterProgress
        effectsActive: root.effectsActive
        effectColor: root.effectColor
        getWorkspaceWidth: root.getWorkspaceWidth
        getWorkspaceHeight: root.getWorkspaceHeight
      }
    }
  }

  // Vertical layout for left/right bars
  Column {
    id: pillColumn
    spacing: spacingBetweenPills
    x: 0
    y: horizontalPadding
    visible: isVertical && !showApplications

    Repeater {
      id: workspaceRepeaterVertical
      model: localWorkspaces
      delegate: WorkspacePill {
        required property var model
        workspace: model
        isVertical: true
        baseDimensionRatio: root.baseDimensionRatio
        capsuleHeight: root.capsuleHeight
        barHeight: root.barHeight
        labelMode: root.labelMode
        characterCount: root.characterCount
        textRatio: root.textRatio
        showLabelsOnlyWhenOccupied: root.showLabelsOnlyWhenOccupied
        focusedColor: root.focusedColor
        occupiedColor: root.occupiedColor
        emptyColor: root.emptyColor
        masterProgress: root.masterProgress
        effectsActive: root.effectsActive
        effectColor: root.effectColor
        getWorkspaceWidth: root.getWorkspaceWidth
        getWorkspaceHeight: root.getWorkspaceHeight
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
      // Fetch windows directly from service to avoid Qt 6.9 ListModel nested array issues
      property var liveWindows: []
      property bool hasWindows: liveWindows.length > 0

      function updateWindows() {
        var wsId = workspaceModel?.id;
        if (wsId !== undefined && wsId !== null) {
          liveWindows = CompositorService.getWindowsForWorkspace(wsId);
        } else {
          liveWindows = [];
        }
      }

      Component.onCompleted: updateWindows()
      onWorkspaceModelChanged: updateWindows()

      Connections {
        target: root
        function onWindowRevisionChanged() {
          groupedContainer.updateWindows();
        }
      }

      width: Style.toOdd((hasWindows ? groupedIconsFlow.implicitWidth : root.iconSize) + (root.isVertical ? (root.baseItemSize - root.iconSize + Style.marginXS) : Style.marginXL))
      height: Style.toOdd((hasWindows ? groupedIconsFlow.implicitHeight : root.iconSize) + (root.isVertical ? Style.marginL : (root.baseItemSize - root.iconSize + Style.marginXS)))
      color: Style.capsuleColor
      radius: Style.radiusS
      border.color: Settings.data.bar.showOutline ? Style.capsuleBorderColor : Qt.alpha((workspaceModel.isFocused ? Color.mPrimary : Color.mOutline), root.groupedBorderOpacity)
      border.width: Style.borderS

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
          model: groupedContainer.liveWindows

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
                return ThemeIcons.iconForAppId(modelData.appId?.toLowerCase());
              }
              smooth: true
              asynchronous: true
              opacity: modelData.isFocused ? Style.opacityFull : unfocusedIconsOpacity
              layer.enabled: root.colorizeIcons && !modelData.isFocused

              Rectangle {
                id: groupedFocusIndicator
                visible: modelData.isFocused
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
                           if (mouse.button === Qt.LeftButton) {
                             CompositorService.focusWindow(modelData);
                           }
                         }

              onReleased: mouse => {
                            if (mouse.button === Qt.RightButton) {
                              mouse.accepted = true;
                              TooltipService.hide();
                              root.selectedWindowId = modelData.id || modelData.address || "";
                              root.selectedAppId = modelData.appId;
                              openGroupedContextMenu(groupedTaskbarItem);
                            }
                          }
              onEntered: {
                groupedTaskbarItem.itemHovered = true;
                TooltipService.show(groupedTaskbarItem, modelData.title || modelData.appId || "Unknown app.", BarService.getTooltipDirection(root.screenName));
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

        visible: root.labelMode !== "none" && root.showBadge && (!root.showLabelsOnlyWhenOccupied || groupedContainer.hasWindows || groupedContainer.workspaceModel.isFocused)

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
              return root.getColorPair(root.focusedColor)[0];
            if (groupedContainer.workspaceModel.isUrgent)
              return Color.mError;
            if (groupedContainer.hasWindows)
              return root.getColorPair(root.occupiedColor)[0];

            return root.getColorPair(root.emptyColor)[0];
          }

          scale: groupedContainer.workspaceModel.isActive ? 1.0 : 0.8

          Behavior on scale {
            NumberAnimation {
              duration: Style.animationNormal
              easing.type: Easing.OutBack
            }
          }

          Behavior on color {
            enabled: !Color.isTransitioning
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
            pointSize: barFontSize * 0.75
            weight: Style.fontWeightBold
            capitalization: Font.AllUppercase
          }
          applyUiScale: false

          color: {
            if (groupedContainer.workspaceModel.isFocused)
              return root.getColorPair(root.focusedColor)[1];
            if (groupedContainer.workspaceModel.isUrgent)
              return Color.mOnError;
            if (groupedContainer.hasWindows)
              return root.getColorPair(root.occupiedColor)[1];

            return root.getColorPair(root.emptyColor)[1];
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

    x: root.isVertical ? Style.pixelAlignCenter(parent.width, width) : Math.round(horizontalPadding * root.hasLabel)
    y: root.isVertical ? Math.round(horizontalPadding * 0.4 * root.hasLabel) : Style.pixelAlignCenter(parent.height, height)

    spacing: Style.marginS
    flow: root.isVertical ? Flow.TopToBottom : Flow.LeftToRight

    Repeater {
      model: showApplications ? localWorkspaces : null
      delegate: groupedWorkspaceDelegate
    }
  }

  function openGroupedContextMenu(item) {
    PanelService.showContextMenu(contextMenu, item, screen);
  }
}
