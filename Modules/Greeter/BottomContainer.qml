import QtQuick
import QtQuick.Layouts

import Quickshell.Services.UPower

import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.LockScreen

ColumnLayout {
  id: root

  required property string userName

  spacing: -1 // prevents a small line from appearing

  ErrorNotification {
    message: GreeterService.errorMessage
    visible: GreeterService.showFailure && GreeterService.errorMessage

    Layout.alignment: Qt.AlignHCenter
    Layout.bottomMargin: Style.marginL
  }

  // Compact status indicators container
  Item {
    Layout.alignment: Qt.AlignHCenter
    Layout.preferredWidth: statusIndicators.implicitWidth + 2 * Style.marginL
    Layout.preferredHeight: statusIndicators.implicitHeight + 2 * Style.marginL

    // Background
    Rectangle {
      anchors.fill: parent
      topLeftRadius: Style.radiusL
      topRightRadius: Style.radiusL
      color: Color.mSurface
    }

    RowLayout {
      id: statusIndicators
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginL

      // Battery indicator
      RowLayout {
        spacing: Style.marginS
        visible: UPower.displayDevice && UPower.displayDevice.ready && UPower.displayDevice.isPresent

        Item {
          id: batteryIndicator
          property var battery: UPower.displayDevice
          property bool isReady: battery && battery.ready && battery.isLaptopBattery && battery.isPresent
          property real percent: isReady ? (battery.percentage * 100) : 0
          property bool charging: isReady ? battery.state === UPowerDeviceState.Charging : false
          property bool batteryVisible: isReady && percent > 0
        }

        NIcon {
          icon: BatteryService.getIcon(Math.round(UPower.displayDevice.percentage * 100), UPower.displayDevice.state === UPowerDeviceState.Charging, true)
          pointSize: Style.fontSizeM
          color: UPower.displayDevice.state === UPowerDeviceState.Charging ? Color.mPrimary : Color.mOnSurfaceVariant
        }

        NText {
          text: Math.round(UPower.displayDevice.percentage * 100) + "%"
          color: Color.mOnSurfaceVariant
          pointSize: Style.fontSizeM
          font.weight: Font.Medium
        }
      }

      // Session indicator
      RowLayout {
        spacing: Style.marginS

        NIcon {
          icon: "device-desktop-cog"
          pointSize: Style.fontSizeM
          color: Color.mOnSurfaceVariant
        }

        NText {
          text: SessionService.currentSessionName
          color: Color.mOnSurfaceVariant
          pointSize: Style.fontSizeM
          font.weight: Font.Medium
          elide: Text.ElideRight
        }

        // TODO: Make session selctable
        // This currently breaks the focus of the password input and looks bad
        // NComboBox {
        //   model: SessionService.availableSessions.map((session, index) => ({
        //                                                                      "key": index,
        //                                                                      "name": session.name
        //                                                                    }))
        //   currentKey: SessionService.currentSessionIndex
        //   placeholder: SessionService.currentSessionName
        //   onSelected: key => SessionService.selectSession(key)
        // }
      }

      // Keyboard layout indicator
      RowLayout {
        spacing: Style.marginS
        visible: keyboardLayout.currentLayout !== "Unknown"

        Item {
          id: keyboardLayout
          property string currentLayout: (typeof KeyboardLayoutService !== 'undefined' && KeyboardLayoutService.currentLayout) ? KeyboardLayoutService.currentLayout : "Unknown"
        }

        NIcon {
          icon: "keyboard"
          pointSize: Style.fontSizeM
          color: Color.mOnSurfaceVariant
        }

        NText {
          text: keyboardLayout.currentLayout
          color: Color.mOnSurfaceVariant
          pointSize: Style.fontSizeM
          font.weight: Font.Medium
          elide: Text.ElideRight
        }
      }
    }
  }

  // Bottom container with password input and controls
  Item {
    Layout.preferredWidth: 750
    Layout.preferredHeight: bottomContainer.implicitHeight + 2 * Style.marginL

    Rectangle {
      anchors.fill: parent
      radius: Style.radiusL
      color: Color.mSurface
    }

    ColumnLayout {
      id: bottomContainer
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginL

      // Password input
      PasswordInput {
        id: passwordInput
        enabled: GreeterService.idle

        Layout.fillWidth: true

        onPasswordChanged: {
          GreeterService.showFailure = false
          GreeterService.errorMessage = ""
        }

        onActivated: {
          GreeterService.authenticate(users.currentUser, passwordInput.password)
          passwordInput.password = ""
        }
      }

      SessionButtons {
        showLogout: false

        Layout.fillWidth: true
      }
    }
  }
}
