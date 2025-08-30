pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Widgets
import Quickshell.Wayland
import qs.Commons
import qs.Services

Rectangle {
  id: root
  property var screen
  readonly property real scaling: screen ? ScalingService.scale(screen) : 1
  readonly property real itemSize: 32 * scaling

  // Always visible when there are toplevels
  implicitWidth: taskbarRow.width + Style.marginM * scaling * 2
  implicitHeight: Math.round(Style.capsuleHeight * scaling)
  radius: Math.round(Style.radiusM * scaling)
  color: Color.mSurfaceVariant

  Component.onCompleted: {
    Logger.log("Taskbar", "Taskbar loaded")
  }

  Row {
    id: taskbarRow
    anchors.verticalCenter: parent.verticalCenter
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: Style.marginXS * root.scaling

    Repeater {
      model: ToplevelManager && ToplevelManager.toplevels ? ToplevelManager.toplevels : []
      delegate: Item {
        id: taskbarItem
        required property Toplevel modelData
        property Toplevel toplevel: modelData
        property bool isActive: ToplevelManager.activeToplevel === modelData
        width: root.itemSize
        height: root.itemSize

        Rectangle {
          id: iconBackground
          anchors.centerIn: parent
          width: root.itemSize * 0.75
          height: root.itemSize * 0.75
          color: {
            if (taskbarItem.isActive) {
              return Color.mPrimary
            } 
            return root.color
          }
          border.width: 0
          border.color: "transparent"
          z: -1

          IconImage {
            id: appIcon
            anchors.centerIn: parent
            width: Style.marginL * root.scaling
            height: Style.marginL * root.scaling
            source: Icons.iconForAppId(taskbarItem.modelData.appId)
            smooth: true
          }
        }

        MouseArea {
          id: appMouseArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.RightButton

          onPressed: function(mouse) {
            if (!taskbarItem.modelData) return
            
            if (mouse.button === Qt.LeftButton) {
              try {
                taskbarItem.modelData.activate()
              } catch (error) {
                Logger.log("Taskbar", "Failed to activate toplevel: " + error)
              }
            } else if (mouse.button === Qt.RightButton) {
              try {
                taskbarItem.modelData.close()
              } catch (error) {
                Logger.log("Taskbar", "Failed to close toplevel: " + error)
              }
            }
          }

          ToolTip {
            parent: appIcon
            visible: appMouseArea.containsMouse
            delay: 500
            text: taskbarItem.modelData.title || taskbarItem.modelData.appId || "Unknown App"
            background: Rectangle {
              color: Color.mSurface
              border.color: Color.mOutline
              radius: Style.radiusS * root.scaling
            }
            contentItem: Label {
              color: Color.mOnSurface
              font.pixelSize: Style.fontSizeS * root.scaling
              text: taskbarItem.modelData.title || taskbarItem.modelData.appId || "Unknown App"
            }
          }
        }
      }
    }
  }
}
