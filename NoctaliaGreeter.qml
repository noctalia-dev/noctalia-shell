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
  readonly property string instantAuth: Quickshell.env("NOCTALIA_GREETER_INSTANT_AUTH")
  readonly property string preferredUser: Quickshell.env("NOCTALIA_GREETER_PREFERRED_USER")

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

        property int currentUserIndex: 0
        property list<string> availableUsers: []
        property string currentUser: availableUsers[currentUserIndex] ?? ""

        function next() {
          currentUserIndex = (currentUserIndex + 1) % availableUsers.length
        }

        command: ["awk", `BEGIN { FS = ":"} /\\/home/ { print $1 }`, "/etc/passwd"]
        running: true

        stderr: SplitParser {
          onRead: data => Logger.e("Greeter", "Failed to read user: " + data)
        }

        stdout: SplitParser {
          onRead: data => {
            Logger.i("Greeter", "Found user: " + data)
            if (data == root.preferredUser) {
              Logger.i("Greeter", "'" + data + "' is now the preferred user")
              users.currentUserIndex = users.availableUsers.length
            }
            users.availableUsers.push(data)
          }
        }

        onExited: if (root.instantAuth && !users.running) {
          Logger.i("Performing instant authentication for user " + users.currentUser)
          GreeterService.authenticate(users.currentUser, "")
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

            userName: users.currentUser
          }

          Greeter.BottomContainer {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 100

            userName: users.currentUser
          }
        }
      }
    }
  }
}
