pragma ComponentBehavior

import QtQuick
import QtQuick.Layouts

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower

import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.Background
import qs.Modules.LockScreen
import qs.Modules.Greeter as Greeter

Item {
  id: root

  // Config via environment variables
  readonly property string instant_auth: Quickshell.env("NOCTALIA_GREETER_INSTANT_AUTH")
  readonly property string preferred_user: Quickshell.env("NOCTALIA_GREETER_PREFERRED_USER")

  property bool i18nLoaded: false
  property bool settingsLoaded: false

  Connections {
    target: I18n
    function onTranslationsLoaded() {
      i18nLoaded = true
    }
  }

  Connections {
    target: Settings
    function onSettingsLoaded() {
      settingsLoaded = true
    }
  }

  Loader {
    active: i18nLoaded && settingsLoaded

    sourceComponent: Item {
      Component.onCompleted: {
        Logger.i("Greeter", "---------------------------")
        WallpaperService.init()
        AppThemeService.init()
        ColorSchemeService.init()
        FontService.init()
        BatteryService.init()
      }

      Connections {
        target: GreeterService

        function onUnlocked() {
          sessionLock.locked = false
        }
      }

      // User management process
      Process {
        id: users

        property string current_user: users_list[current_user_index] ?? ""
        property int current_user_index: 0
        property list<string> users_list: []

        function next() {
          current_user_index = (current_user_index + 1) % users_list.length
        }

        command: ["awk", `BEGIN { FS = ":"} /\\/home/ { print $1 }`, "/etc/passwd"]
        running: true

        stderr: SplitParser {
          onRead: data => console.log("[ERR] " + data)
        }
        stdout: SplitParser {
          onRead: data => {
            console.log("[USERS] " + data)
            if (data == root.preferred_user) {
              console.log("[INFO] Found preferred user " + root.preferred_user)
              users.current_user_index = users.users_list.length
            }
            users.users_list.push(data)
          }
        }

        onExited: if (root.instant_auth && !users.running) {
          console.log("[USERS EXIT]")
          GreeterService.authenticate(users.current_user, "")
        }
      }

      // Main greeter interface
      WlSessionLock {
        id: sessionLock

        property string fakeBuffer: ""
        property string passwdBuffer: ""

        locked: true

        function tryUnlock() {
          GreeterService.authenticate(users.current_user, passwdBuffer)
          passwdBuffer = ""
          fakeBuffer = ""
        }

        WlSessionLockSurface {
          Item {
            id: batteryIndicator
            property var battery: UPower.displayDevice
            property bool isReady: battery && battery.ready && battery.isLaptopBattery && battery.isPresent
            property real percent: isReady ? (battery.percentage * 100) : 0
            property bool charging: isReady ? battery.state === UPowerDeviceState.Charging : false
            property bool batteryVisible: isReady && percent > 0
          }

          Item {
            id: keyboardLayout
            property string currentLayout: (typeof KeyboardLayoutService !== 'undefined' && KeyboardLayoutService.currentLayout) ? KeyboardLayoutService.currentLayout : "Unknown"
          }

          Background {}

          Image {
            id: lockBgImage
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            source: screen ? WallpaperService.getWallpaper(screen.name) : ""
            cache: true
            smooth: true
            mipmap: false
          }

          BackgroundGradient {}

          LockScreenCorners {}

          // Time, Date, and User Profile Container
          Greeter.TopContainer {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 100
          }

          Item {
            anchors.fill: parent

            // Error notification
            Rectangle {
              width: 450
              height: 60
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: (Settings.data.general.compactLockScreen ? 240 : 320) * Style.uiScaleRatio
              radius: 30
              color: Color.mError
              border.color: Color.mError
              border.width: 1
              visible: GreeterService.showFailure && GreeterService.errorMessage
              opacity: visible ? 1.0 : 0.0

              RowLayout {
                anchors.centerIn: parent
                spacing: 10

                NIcon {
                  icon: "alert-circle"
                  pointSize: Style.fontSizeL
                  color: Color.mOnError
                }

                NText {
                  text: GreeterService.errorMessage || "Authentication failed"
                  color: Color.mOnError
                  pointSize: Style.fontSizeL
                  font.weight: Font.Medium
                  horizontalAlignment: Text.AlignHCenter
                }
              }

              Behavior on opacity {
                NumberAnimation {
                  duration: 300
                  easing.type: Easing.OutCubic
                }
              }
            }

            Rectangle {
              width: {
                var hasBattery = UPower.displayDevice && UPower.displayDevice.ready && UPower.displayDevice.isPresent
                var hasKeyboard = keyboardLayout.currentLayout !== "Unknown"

                if (hasBattery && hasKeyboard) {
                  return 200
                } else if (hasBattery || hasKeyboard) {
                  return 120
                } else {
                  return 0
                }
              }
              height: 40
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 100 + 48 + 3 * 14 + (Settings.data.general.compactLockScreen ? 36 : 48)
              topLeftRadius: Style.radiusL
              topRightRadius: Style.radiusL
              color: Color.mSurface

              RowLayout {
                anchors.centerIn: parent
                spacing: 16

                // Battery indicator
                RowLayout {
                  spacing: 6
                  visible: UPower.displayDevice && UPower.displayDevice.ready && UPower.displayDevice.isPresent

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

                // Keyboard layout indicator
                RowLayout {
                  spacing: 6
                  visible: keyboardLayout.currentLayout !== "Unknown"

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
              width: 750
              height: bottomContainer.implicitHeight + 2 * 14

              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 100

              Rectangle {
                anchors.fill: parent
                radius: Style.radiusL
                color: Color.mSurface
              }

              ColumnLayout {
                id: bottomContainer
                anchors.fill: parent
                anchors.margins: 14
                spacing: 14

                // Password input
                PasswordInput {
                  id: passwordInput
                  enabled: GreeterService.idle

                  Layout.fillWidth: true

                  onActivated: {
                    GreeterService.authenticate(users.current_user, passwordInput.password)
                  }
                }

                SessionButtons {
                  showLogout: false

                  Layout.fillWidth: true
                }
              }
            }
          }
        }
      }
    }
  }
}
