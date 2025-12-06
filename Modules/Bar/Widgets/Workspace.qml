import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
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
  readonly property bool density: Settings.data.bar.density
  readonly property real baseDimensionRatio: {
    const b = (density === "compact") ? 0.85 : 0.65;
    if (widgetSettings.labelMode === "none") {
      return b * 0.75;
    }
    return b;
  }

  readonly property string labelMode: (widgetSettings.labelMode !== undefined) ? widgetSettings.labelMode : widgetMetadata.labelMode
  readonly property bool hideUnoccupied: (widgetSettings.hideUnoccupied !== undefined) ? widgetSettings.hideUnoccupied : widgetMetadata.hideUnoccupied
  readonly property bool followFocusedScreen: (widgetSettings.followFocusedScreen !== undefined) ? widgetSettings.followFocusedScreen : widgetMetadata.followFocusedScreen
  readonly property int characterCount: isVertical ? 2 : ((widgetSettings.characterCount !== undefined) ? widgetSettings.characterCount : widgetMetadata.characterCount)

  property bool isDestroying: false
  property bool hovered: false

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

  implicitWidth: isVertical ? Style.barHeight : computeWidth()
  implicitHeight: isVertical ? computeHeight() : Style.barHeight

  function getWorkspaceWidth(ws) {
    const d = Style.capsuleHeight * root.baseDimensionRatio;
    const factor = ws.isActive ? 2.2 : 1;

    // Don't calculate text width if labels are off
    if (labelMode === "none") {
      return d * factor;
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
    return Math.max(d * factor, textWidth + padding);
  }

  function getWorkspaceHeight(ws) {
    const d = Style.capsuleHeight * root.baseDimensionRatio;
    const factor = ws.isActive ? 2.2 : 1;
    return d * factor;
  }

  function computeWidth() {
    let total = 0;
    for (var i = 0; i < localWorkspaces.count; i++) {
      const ws = localWorkspaces.get(i);
      total += getWorkspaceWidth(ws);
    }
    total += Math.max(localWorkspaces.count - 1, 0) * spacingBetweenPills;
    total += horizontalPadding * 2;
    return Math.round(total);
  }

  function computeHeight() {
    let total = 0;
    for (var i = 0; i < localWorkspaces.count; i++) {
      const ws = localWorkspaces.get(i);
      total += getWorkspaceHeight(ws);
    }
    total += Math.max(localWorkspaces.count - 1, 0) * spacingBetweenPills;
    total += horizontalPadding * 2;
    return Math.round(total);
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

  Component.onDestruction: {
    root.isDestroying = true;
  }

  onScreenChanged: refreshWorkspaces()
  onHideUnoccupiedChanged: refreshWorkspaces()

  Connections {
    target: CompositorService
    function onWorkspacesChanged() {
      refreshWorkspaces();
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
      for (var i = 0; i < CompositorService.workspaces.count; i++) {
        const ws = CompositorService.workspaces.get(i);
        if ((followFocusedScreen && ws.output.toLowerCase() == focusedOutput) || (!followFocusedScreen && ws.output.toLowerCase() == screen.name.toLowerCase())) {
          if (hideUnoccupied && !ws.isOccupied && !ws.isFocused) {
            continue;
          }
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
        root.triggerUnifiedWave();
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

    model: [
      {
        "label": I18n.tr("context-menu.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.close();
                   }

                   if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  Rectangle {
    id: workspaceBackground
    width: isVertical ? Style.capsuleHeight : parent.width
    height: isVertical ? parent.height : Style.capsuleHeight
    radius: Style.radiusM
    color: Style.capsuleColor

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.RightButton
      onClicked: mouse => {
                   if (mouse.button === Qt.RightButton) {
                     var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                     if (popupMenuWindow) {
                       popupMenuWindow.showContextMenu(contextMenu);
                       const pos = BarService.getContextMenuPosition(workspaceBackground, contextMenu.implicitWidth, contextMenu.implicitHeight);
                       contextMenu.openAtItem(workspaceBackground, pos.x, pos.y);
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
    anchors.verticalCenter: workspaceBackground.verticalCenter
    x: horizontalPadding
    visible: !isVertical

    Repeater {
      id: workspaceRepeaterHorizontal
      model: localWorkspaces
      Item {
        id: workspacePillContainer
        width: root.getWorkspaceWidth(model)
        height: Style.capsuleHeight * root.baseDimensionRatio

        Rectangle {
          id: pill
          anchors.fill: parent

          Loader {
            active: (labelMode !== "none")
            sourceComponent: Component {
              NText {
                x: (pill.width - width) / 2
                y: (pill.height - height) / 2 + (height - contentHeight) / 2
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
                pointSize: model.isActive ? workspacePillContainer.height * 0.45 : workspacePillContainer.height * 0.42
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
          scale: model.isActive ? 1.0 : 0.9
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
          color: Color.transparent
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
    anchors.horizontalCenter: workspaceBackground.horizontalCenter
    y: horizontalPadding
    visible: isVertical

    Repeater {
      id: workspaceRepeaterVertical
      model: localWorkspaces
      Item {
        id: workspacePillContainerVertical
        width: Style.capsuleHeight * root.baseDimensionRatio
        height: root.getWorkspaceHeight(model)

        Rectangle {
          id: pillVertical
          anchors.fill: parent

          Loader {
            active: (labelMode !== "none")
            sourceComponent: Component {
              NText {
                x: (pillVertical.width - width) / 2
                y: (pillVertical.height - height) / 2 + (height - contentHeight) / 2
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
                pointSize: model.isActive ? workspacePillContainerVertical.width * 0.45 : workspacePillContainerVertical.width * 0.42
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

                  return Color.mOnSurface;
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

            return Color.mOutline;
          }
          scale: model.isActive ? 1.0 : 0.9
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
          color: Color.transparent
          border.color: root.effectColor
          border.width: Math.max(1, Math.round((2 + 6 * (1.0 - root.masterProgress))))
          opacity: root.effectsActive && model.isFocused ? (1.0 - root.masterProgress) * 0.7 : 0
          visible: root.effectsActive && model.isFocused
          z: 1
        }
      }
    }
  }
}
