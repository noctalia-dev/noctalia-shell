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

Item {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property bool isVerticalBar: Settings.data.bar.position === "left" || Settings.data.bar.position === "right"
  readonly property string density: Settings.data.bar.density
  readonly property real itemSize: (density === "compact") ? Style.capsuleHeight * 0.9 : Style.capsuleHeight * 0.8
  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }
  readonly property bool hideUnoccupied: (widgetSettings.hideUnoccupied !== undefined) ? widgetSettings.hideUnoccupied : false
  property ListModel localWorkspaces: ListModel {}

  function refreshWorkspaces() {
    localWorkspaces.clear()
    if (!screen)
      return

    const screenName = screen.name.toLowerCase()

    for (var i = 0; i < CompositorService.workspaces.count; i++) {
      const ws = CompositorService.workspaces.get(i)

      if (ws.output.toLowerCase() !== screenName)
        continue
      if (hideUnoccupied && !ws.isOccupied && !ws.isFocused)
        continue

      // Copy all properties from ws and add windows
      var workspaceData = Object.assign({}, ws)
      workspaceData.windows = CompositorService.getWindowsForWorkspace(ws.id)

      localWorkspaces.append(workspaceData)
    }
  }

  Component.onCompleted: {
    refreshWorkspaces()
  }

  onScreenChanged: refreshWorkspaces()

  implicitWidth: isVerticalBar ? taskbarGrid.implicitWidth + Style.marginM * 2 : Math.round(taskbarGrid.implicitWidth + Style.marginM * 2)
  implicitHeight: isVerticalBar ? Math.round(taskbarGrid.implicitHeight + Style.marginM * 2) : Style.barHeight

  Connections {
    target: CompositorService

    function onWorkspacesChanged() {
      refreshWorkspaces()
    }

    function onWindowListChanged() {
      refreshWorkspaces()
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
      border.width: 1
      width: (hasWindows ? iconsFlow.implicitWidth : root.itemSize * 0.8) + (root.isVerticalBar ? Style.marginXS : Style.marginL)
      height: (hasWindows ? iconsFlow.implicitHeight : root.itemSize * 0.8) + (root.isVerticalBar ? Style.marginL : Style.marginXS)
      color: Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        enabled: !hasWindows
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
          CompositorService.switchToWorkspace(workspaceModel)
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
              layer.enabled: widgetSettings.colorizeIcons === true

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
                radius: width * 0.5
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

              onPressed: function (mouse) {
                if (!model) {
                  return
                }

                if (mouse.button === Qt.LeftButton) {
                  CompositorService.focusWindow(model)
                } else if (mouse.button === Qt.RightButton) {
                  CompositorService.closeWindow(model)
                }
              }
              onEntered: {
                taskbarItem.itemHovered = true
                TooltipService.show(Screen, taskbarItem, model.title || model.appId || "Unknown app.", BarService.getTooltipDirection())
              }
              onExited: {
                taskbarItem.itemHovered = false
                TooltipService.hide()
              }
            }
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
}
