import QtQuick
import QtQuick.Layouts

import qs.Commons
import qs.Services
import qs.Widgets

RowLayout {
  id: root

  required property bool showLogout

  Layout.fillWidth: true
  Layout.preferredHeight: Settings.data.general.compactLockScreen ? 36 : 48
  spacing: 10

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: Settings.data.general.compactLockScreen ? 36 : 48
    radius: Settings.data.general.compactLockScreen ? 18 : 24
    color: logoutButtonArea.containsMouse ? Color.mTertiary : "transparent"
    border.color: Color.mOutline
    border.width: 1
    visible: root.showLogout

    RowLayout {
      anchors.centerIn: parent
      spacing: 6

      NIcon {
        icon: "logout"
        pointSize: Settings.data.general.compactLockScreen ? Style.fontSizeM : Style.fontSizeL
        color: logoutButtonArea.containsMouse ? Color.mHover : Color.mOnSurfaceVariant
      }

      NText {
        text: I18n.tr("session-menu.logout")
        color: logoutButtonArea.containsMouse ? Color.mHover : Color.mOnSurfaceVariant
        pointSize: Settings.data.general.compactLockScreen ? Style.fontSizeS : Style.fontSizeM
        font.weight: Font.Medium
      }
    }

    MouseArea {
      id: logoutButtonArea
      anchors.fill: parent
      hoverEnabled: true
      onClicked: CompositorService.logout()
    }

    Behavior on color {
      ColorAnimation {
        duration: 200
        easing.type: Easing.OutCubic
      }
    }

    Behavior on border.color {
      ColorAnimation {
        duration: 200
        easing.type: Easing.OutCubic
      }
    }
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: Settings.data.general.compactLockScreen ? 36 : 48
    radius: Settings.data.general.compactLockScreen ? 18 : 24
    color: suspendButtonArea.containsMouse ? Color.mTertiary : "transparent"
    border.color: Color.mOutline
    border.width: 1

    RowLayout {
      anchors.centerIn: parent
      spacing: 6

      NIcon {
        icon: "suspend"
        pointSize: Settings.data.general.compactLockScreen ? Style.fontSizeM : Style.fontSizeL
        color: suspendButtonArea.containsMouse ? Color.mHover : Color.mOnSurfaceVariant
      }

      NText {
        text: I18n.tr("session-menu.suspend")
        color: suspendButtonArea.containsMouse ? Color.mHover : Color.mOnSurfaceVariant
        pointSize: Settings.data.general.compactLockScreen ? Style.fontSizeS : Style.fontSizeM
        font.weight: Font.Medium
      }
    }

    MouseArea {
      id: suspendButtonArea
      anchors.fill: parent
      hoverEnabled: true
      onClicked: CompositorService.suspend()
    }

    Behavior on color {
      ColorAnimation {
        duration: 200
        easing.type: Easing.OutCubic
      }
    }

    Behavior on border.color {
      ColorAnimation {
        duration: 200
        easing.type: Easing.OutCubic
      }
    }
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: Settings.data.general.compactLockScreen ? 36 : 48
    radius: Settings.data.general.compactLockScreen ? 18 : 24
    color: rebootButtonArea.containsMouse ? Color.mTertiary : "transparent"
    border.color: Color.mOutline
    border.width: 1

    RowLayout {
      anchors.centerIn: parent
      spacing: 6

      NIcon {
        icon: "reboot"
        pointSize: Settings.data.general.compactLockScreen ? Style.fontSizeM : Style.fontSizeL
        color: rebootButtonArea.containsMouse ? Color.mHover : Color.mOnSurfaceVariant
      }

      NText {
        text: I18n.tr("session-menu.reboot")
        color: rebootButtonArea.containsMouse ? Color.mHover : Color.mOnSurfaceVariant
        pointSize: Settings.data.general.compactLockScreen ? Style.fontSizeS : Style.fontSizeM
        font.weight: Font.Medium
      }
    }

    MouseArea {
      id: rebootButtonArea
      anchors.fill: parent
      hoverEnabled: true
      onClicked: CompositorService.reboot()
    }

    Behavior on color {
      ColorAnimation {
        duration: 200
        easing.type: Easing.OutCubic
      }
    }

    Behavior on border.color {
      ColorAnimation {
        duration: 200
        easing.type: Easing.OutCubic
      }
    }
  }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: Settings.data.general.compactLockScreen ? 36 : 48
    radius: Settings.data.general.compactLockScreen ? 18 : 24
    color: shutdownButtonArea.containsMouse ? Color.mError : "transparent"
    border.color: shutdownButtonArea.containsMouse ? Color.mError : Color.mOutline
    border.width: 1

    RowLayout {
      anchors.centerIn: parent
      spacing: 6

      NIcon {
        icon: "shutdown"
        pointSize: Settings.data.general.compactLockScreen ? Style.fontSizeM : Style.fontSizeL
        color: shutdownButtonArea.containsMouse ? Color.mOnError : Color.mOnSurfaceVariant
      }

      NText {
        text: I18n.tr("session-menu.shutdown")
        color: shutdownButtonArea.containsMouse ? Color.mOnError : Color.mOnSurfaceVariant
        pointSize: Settings.data.general.compactLockScreen ? Style.fontSizeS : Style.fontSizeM
        font.weight: Font.Medium
      }
    }

    MouseArea {
      id: shutdownButtonArea
      anchors.fill: parent
      hoverEnabled: true
      onClicked: CompositorService.shutdown()
    }

    Behavior on color {
      ColorAnimation {
        duration: 200
        easing.type: Easing.OutCubic
      }
    }

    Behavior on border.color {
      ColorAnimation {
        duration: 200
        easing.type: Easing.OutCubic
      }
    }
  }
}
