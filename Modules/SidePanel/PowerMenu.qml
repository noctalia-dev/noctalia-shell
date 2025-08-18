import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.LockScreen

NPanel {
  id: powerMenu
  visible: false

  // Anchors will be set by the parent component
  function show() {
    visible = true
  }

  function hide() {
    visible = false
  }

  Rectangle {
    width: 160 * scaling
    height: 220 * scaling
    radius: Style.radiusMedium * scaling
    border.color: Color.mOutline
    border.width: Math.max(1, Style.borderThin * scaling)
    color: Color.mSurface

    visible: true
    z: 9999

    anchors.top: parent.top
    anchors.right: parent.right
    anchors.rightMargin: Style.marginLarge * scaling
    anchors.topMargin: 86 * scaling

    // Prevent closing when clicking in the panel bg
    MouseArea {
      anchors.fill: parent
      onClicked: {

      }
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginSmall * scaling
      spacing: Style.marginTiny * scaling

      // --------------
      // Lock
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.barHeight * scaling
        radius: Style.radiusSmall * scaling
        color: lockButtonArea.containsMouse ? Color.mTertiary : Color.transparent

        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.marginMedium * scaling
          anchors.rightMargin: Style.marginMedium * scaling

          Row {
            id: lockRow
            spacing: Style.marginSmall * scaling
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            NIcon {
              text: "lock_outline"
              color: lockButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }

            Text {
              text: "Lock Screen"
              color: lockButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              verticalAlignment: Text.AlignVCenter
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }
          }
        }

        MouseArea {
          id: lockButtonArea

          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            Logger.log("PowerMenu", "Lock screen requested")
            // Lock the screen
            lockScreen.locked = true
            powerMenu.visible = false
          }
        }
      }

      // --------------
      // Suspend
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.barHeight * scaling
        radius: Style.radiusSmall * scaling
        color: suspendButtonArea.containsMouse ? Color.mTertiary : Color.transparent

        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.marginMedium * scaling
          anchors.rightMargin: Style.marginMedium * scaling

          Row {
            id: suspendRow
            spacing: Style.marginSmall * scaling
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            NIcon {
              text: "bedtime"
              color: suspendButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }

            Text {
              text: "Suspend"
              color: suspendButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              verticalAlignment: Text.AlignVCenter
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }
          }
        }

        MouseArea {
          id: suspendButtonArea

          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            suspend()
            powerMenu.visible = false
          }
        }
      }

      // --------------
      // Reboot
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.barHeight * scaling
        radius: Style.radiusSmall * scaling
        color: rebootButtonArea.containsMouse ? Color.mTertiary : Color.transparent

        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.marginMedium * scaling
          anchors.rightMargin: Style.marginMedium * scaling

          Row {
            id: rebootRow
            spacing: Style.marginSmall * scaling
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            NIcon {
              text: "refresh"
              color: rebootButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }

            Text {
              text: "Reboot"
              color: rebootButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              verticalAlignment: Text.AlignVCenter
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }
          }
        }

        MouseArea {
          id: rebootButtonArea

          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            reboot()
            powerMenu.visible = false
          }
        }
      }

      // --------------
      // Logout
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.barHeight * scaling
        radius: Style.radiusSmall * scaling
        color: logoutButtonArea.containsMouse ? Color.mTertiary : Color.transparent

        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.marginMedium * scaling
          anchors.rightMargin: Style.marginMedium * scaling

          Row {
            id: logoutRow
            spacing: Style.marginSmall * scaling
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            NIcon {
              text: "exit_to_app"
              color: logoutButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }

            Text {
              text: "Logout"
              color: logoutButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              verticalAlignment: Text.AlignVCenter
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }
          }
        }

        MouseArea {
          id: logoutButtonArea

          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            logout()
            powerMenu.visible = false
          }
        }
      }

      // --------------
      // Shutdown
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Style.barHeight * scaling
        radius: Style.radiusSmall * scaling
        color: shutdownButtonArea.containsMouse ? Color.mTertiary : Color.transparent

        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.marginMedium * scaling
          anchors.rightMargin: Style.marginMedium * scaling

          Row {
            id: shutdownRow
            spacing: Style.marginSmall * scaling
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            NIcon {
              text: "power_settings_new"
              color: shutdownButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }

            Text {
              text: "Shutdown"
              color: shutdownButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurface
              verticalAlignment: Text.AlignVCenter
              anchors.verticalCenter: parent.verticalCenter
              anchors.verticalCenterOffset: 1 * scaling
            }
          }
        }

        MouseArea {
          id: shutdownButtonArea

          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            shutdown()
            powerMenu.visible = false
          }
        }
      }
    }
  }

  // ----------------------------------
  // System functions
  function logout() {
    CompositorService.logout()
  }

  function suspend() {
    suspendProcess.running = true
  }

  function shutdown() {
    shutdownProcess.running = true
  }

  function reboot() {
    rebootProcess.running = true
  }

  Process {
    id: shutdownProcess

    command: ["shutdown", "-h", "now"]
    running: false
  }

  Process {
    id: rebootProcess

    command: ["reboot"]
    running: false
  }

  Process {
    id: suspendProcess

    command: ["systemctl", "suspend"]
    running: false
  }

  Process {
    id: logoutProcess

    command: ["loginctl", "terminate-user", Quickshell.env("USER")]
    running: false
  }

  // LockScreen instance
  LockScreen {
    id: lockScreen
  }
}
