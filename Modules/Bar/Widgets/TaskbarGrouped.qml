import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons
import qs.Services
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
  readonly property bool density: Settings.data.bar.density
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

  function getWindowsForWorkspace(workspaceId) {
    var windowsInWs = []
    for (var i = 0; i < CompositorService.windows.count; i++) {
      var window = CompositorService.windows.get(i)
      if (window.workspaceId === workspaceId) {
        windowsInWs.push(window)
      }
    }
    return windowsInWs
  }

  function refreshWorkspaces() {
    localWorkspaces.clear()
    if (screen !== null) {
      for (var i = 0; i < CompositorService.workspaces.count; i++) {
        const ws = CompositorService.workspaces.get(i)
        if (ws.output.toLowerCase() === screen.name.toLowerCase()) {
          if (hideUnoccupied && !ws.isOccupied && !ws.isFocused) {
            continue
          }

          var windowsInWs = getWindowsForWorkspace(ws.id)
          var windowsModel = Qt.createQmlObject('import QtQuick 2.0; ListModel {}', root)
          for (var j = 0; j < windowsInWs.length; j++) {
            windowsModel.append(windowsInWs[j])
          }
          localWorkspaces.append({
            "id": ws.id,
            "name": ws.name,
            "output": ws.output,
            "isFocused": ws.isFocused,
            "isOccupied": ws.isOccupied,
            "isActive": ws.isActive,
            "isUrgent": ws.isUrgent,
            "windows": windowsModel
          })
        }
      }
    }
  }

  Component.onCompleted: {
    refreshWorkspaces()
  }
  implicitWidth: isVerticalBar ? taskbarLayoutVertical.implicitWidth + Style.marginM * 2 : Math.round(taskbarLayoutHorizontal.implicitWidth + Style.marginM * 2)
  implicitHeight: isVerticalBar ? Math.round(taskbarLayoutVertical.implicitHeight + Style.marginM * 2) : Style.barHeight

  Connections {
    target: CompositorService

    function onWorkspacesChanged() {
      refreshWorkspaces()
    }

    function onWindowListChanged() {
      refreshWorkspaces()
    }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    y: isVerticalBar ? 0 : (parent.height - height) / 2
    height: isVerticalBar ? parent.height : Style.capsuleHeight
    radius: Style.radiusM
    color: Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent
  }

  Component {
    id: workspaceRepeaterDelegate

    Rectangle {
      id: container

      property var workspaceModel: model
      property bool hasWindows: workspaceModel.windows.count > 0

      radius: Style.radiusM
      color: "transparent"
      border.color: workspaceModel.isFocused ? Color.mPrimary : Color.mOutline
      border.width: 1
      // Dynamic sizing
      width: (hasWindows ? iconsFlow.implicitWidth : root.itemSize * 0.8) + Style.marginL
      height: (hasWindows ? iconsFlow.implicitHeight : root.itemSize * 0.8) + Style.marginXS

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

            width: root.itemSize * 0.8
            height: root.itemSize * 0.8

            IconImage {
              id: appIcon

              width: parent.width
              height: parent.height
              source: ThemeIcons.iconForAppId(model.appId)
              smooth: true
              asynchronous: true
              opacity: model.isFocused ? Style.opacityFull : 0.6
              layer.enabled: widgetSettings.colorizeIcons === true

              Rectangle {
                anchors.bottomMargin: -2
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: 4
                height: 4
                color: model.isFocused ? Color.mPrimary : Color.transparent
                radius: width * 0.5
              }

              layer.effect: ShaderEffect {
                property color targetColor: Color.mOnSurface
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
                  try {
                    CompositorService.focusWindow(model)
                  } catch (error) {
                    Logger.error("TaskbarGrouped", "Failed to focus window: " + error)
                  }
                } else if (mouse.button === Qt.RightButton) {
                  try {
                    CompositorService.closeWindow(model)
                  } catch (error) {
                    Logger.error("TaskbarGrouped", "Failed to close window: " + error)
                  }
                }
              }
              onEntered: TooltipService.show(Screen, taskbarItem, model.title || model.appId || "Unknown app.", BarService.getTooltipDirection())
              onExited: TooltipService.hide()
            }
          }
        }
      }

      // Animate size changes for a smooth look
      Behavior on width {
        NumberAnimation {
          duration: 200
          easing.type: Easing.InOutCubic
        }
      }

      Behavior on height {
        NumberAnimation {
          duration: 200
          easing.type: Easing.InOutCubic
        }
      }
    }
  }

  Row {
    id: taskbarLayoutHorizontal

    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: Style.marginM
    spacing: Style.marginS
    visible: !isVerticalBar

    Repeater {
      model: localWorkspaces
      delegate: workspaceRepeaterDelegate
    }
  }

  Column {
    id: taskbarLayoutVertical

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: Style.marginM
    spacing: Style.marginS
    visible: isVerticalBar

    Repeater {
      model: localWorkspaces
      delegate: workspaceRepeaterDelegate
    }
  }
}