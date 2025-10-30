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
      root.i18nLoaded = true
    }
  }

  Connections {
    target: Settings
    function onSettingsLoaded() {
      root.settingsLoaded = true
    }
  }

  Loader {
    active: root.i18nLoaded && root.settingsLoaded

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
        locked: true

        WlSessionLockSurface {
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

            userName: users.current_user
          }

          ColumnLayout {
            spacing: -1 // prevents a small line from appearing
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 100

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
                    GreeterService.authenticate(users.current_user, passwordInput.password)
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
        }
      }
    }
  }
}
