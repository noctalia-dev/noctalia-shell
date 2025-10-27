pragma ComponentBehavior

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower

import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.Audio
import qs.Modules.Background

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

      // Timer to update time
      Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
          if (typeof timeText !== 'undefined' && timeText) {
            timeText.text = Qt.formatDateTime(new Date(), "HH:mm")
          }
          if (typeof dateText !== 'undefined' && dateText) {
            dateText.text = Qt.formatDateTime(new Date(), "dddd, MMMM d")
          }
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

          // Gradient overlay similar to your lockscreen
          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              GradientStop {
                position: 0.0
                color: Qt.alpha(Color.mShadow, 0.8)
              }
              GradientStop {
                position: 0.3
                color: Qt.alpha(Color.mShadow, 0.4)
              }
              GradientStop {
                position: 0.7
                color: Qt.alpha(Color.mShadow, 0.5)
              }
              GradientStop {
                position: 1.0
                color: Qt.alpha(Color.mShadow, 0.9)
              }
            }
          }

          Item {
            anchors.fill: parent

            // Time, Date, and User Profile Container
            Rectangle {
              width: Math.max(500, contentRow.implicitWidth + 32)
              height: Math.max(120, contentRow.implicitHeight + 32)
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: 100
              radius: Style.radiusL
              color: Color.mSurface
              border.color: Qt.alpha(Color.mOutline, 0.2)
              border.width: 1

              RowLayout {
                id: contentRow
                anchors.fill: parent
                anchors.margins: 16
                spacing: 32

                // Left side: Avatar
                Rectangle {
                  Layout.preferredWidth: 70
                  Layout.preferredHeight: 70
                  Layout.alignment: Qt.AlignVCenter
                  radius: width * 0.5
                  color: Color.transparent

                  Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: Color.transparent
                    border.color: Qt.alpha(Color.mPrimary, 0.8)
                    border.width: 2

                    SequentialAnimation on border.color {
                      loops: Animation.Infinite
                      ColorAnimation {
                        to: Qt.alpha(Color.mPrimary, 1.0)
                        duration: 2000
                        easing.type: Easing.InOutQuad
                      }
                      ColorAnimation {
                        to: Qt.alpha(Color.mPrimary, 0.8)
                        duration: 2000
                        easing.type: Easing.InOutQuad
                      }
                    }
                  }

                  NImageCircled {
                    anchors.centerIn: parent
                    width: 66
                    height: 66
                    imagePath: Settings.preprocessPath(Settings.data.general.avatarImage)
                    fallbackIcon: "person"

                    SequentialAnimation on scale {
                      loops: Animation.Infinite
                      NumberAnimation {
                        to: 1.02
                        duration: 4000
                        easing.type: Easing.InOutQuad
                      }
                      NumberAnimation {
                        to: 1.0
                        duration: 4000
                        easing.type: Easing.InOutQuad
                      }
                    }
                  }
                }

                // Center: User Info Column (left-aligned text)
                ColumnLayout {
                  Layout.alignment: Qt.AlignVCenter
                  spacing: 2

                  // Welcome back + Username on one line
                  NText {
                    text: I18n.tr("lock-screen.welcome-back") + "!"
                    pointSize: Style.fontSizeXXL
                    font.weight: Font.Medium
                    color: Color.mOnSurface
                    horizontalAlignment: Text.AlignLeft
                  }

                  // Date below
                  NText {
                    text: {
                      var lang = Qt.locale().name.split("_")[0]
                      var formats = {
                        "de": "dddd, d. MMMM",
                        "es": "dddd, d 'de' MMMM",
                        "fr": "dddd d MMMM",
                        "pt": "dddd, d 'de' MMMM",
                        "zh": "yyyy年M月d日 dddd"
                      }
                      return Qt.locale().toString(Time.date, formats[lang] || "dddd, MMMM d")
                    }
                    pointSize: Style.fontSizeXL
                    font.weight: Font.Medium
                    color: Color.mOnSurfaceVariant
                    horizontalAlignment: Text.AlignLeft
                  }
                }

                // Spacer to push time to the right
                Item {
                  Layout.fillWidth: true
                }

                Item {
                  Layout.preferredWidth: 70
                  Layout.preferredHeight: 70
                  Layout.alignment: Qt.AlignVCenter

                  // Seconds circular progress
                  Canvas {
                    id: secondsProgress
                    anchors.fill: parent

                    property real progress: Time.date.getSeconds() / 60
                    onProgressChanged: requestPaint()

                    Connections {
                      target: Time
                      function onDateChanged() {
                        const total = Time.date.getSeconds() * 1000 + Time.date.getMilliseconds()
                        secondsProgress.progress = total / 60000
                      }
                    }

                    onPaint: {
                      var ctx = getContext("2d")
                      var centerX = width / 2
                      var centerY = height / 2
                      var radius = Math.min(width, height) / 2 - 3

                      ctx.reset()

                      // Background circle
                      ctx.beginPath()
                      ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI)
                      ctx.lineWidth = 2.5
                      ctx.strokeStyle = Qt.alpha(Color.mOnSurface, 0.15)
                      ctx.stroke()

                      // Progress arc
                      ctx.beginPath()
                      ctx.arc(centerX, centerY, radius, -Math.PI / 2, -Math.PI / 2 + progress * 2 * Math.PI)
                      ctx.lineWidth = 2.5
                      ctx.strokeStyle = Color.mPrimary
                      ctx.lineCap = "round"
                      ctx.stroke()
                    }
                  }

                  // Digital clock
                  ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0

                    NText {
                      text: {
                        var t = Settings.data.location.use12hourFormat ? Qt.locale().toString(Time.date, "hh AP") : Qt.locale().toString(Time.date, "HH")
                        return t
                      }
                      pointSize: Style.fontSizeM
                      font.weight: Style.fontWeightBold
                      family: Settings.data.ui.fontFixed
                      color: Color.mOnSurface
                      horizontalAlignment: Text.AlignHCenter
                      Layout.alignment: Qt.AlignHCenter
                    }

                    NText {
                      text: Qt.formatTime(Time.date, "mm")
                      pointSize: Style.fontSizeM
                      font.weight: Style.fontWeightBold
                      family: Settings.data.ui.fontFixed
                      color: Color.mOnSurfaceVariant
                      horizontalAlignment: Text.AlignHCenter
                      Layout.alignment: Qt.AlignHCenter
                    }
                  }
                }
              }
            }

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

            // Compact status indicators container (compact mode only)
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
              anchors.bottomMargin: 96 + (Settings.data.general.compactLockScreen ? 116 : 220)
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
            Rectangle {
              width: 750
              height: Settings.data.general.compactLockScreen ? 120 : 220
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 100
              radius: Style.radiusL
              color: Color.mSurface

              ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 14

                // Password input
                RowLayout {
                  Layout.fillWidth: true
                  spacing: 0

                  Item {
                    Layout.preferredWidth: Style.marginM
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    radius: 24
                    color: Color.mSurface
                    border.color: passwordInput.activeFocus ? Color.mPrimary : Qt.alpha(Color.mOutline, 0.3)
                    border.width: passwordInput.activeFocus ? 2 : 1

                    property bool passwordVisible: false

                    Row {
                      anchors.left: parent.left
                      anchors.leftMargin: 18
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 14

                      NIcon {
                        icon: "lock"
                        pointSize: Style.fontSizeL
                        color: passwordInput.activeFocus ? Color.mPrimary : Color.mOnSurfaceVariant
                        anchors.verticalCenter: parent.verticalCenter
                      }

                      // Hidden input that receives actual text
                      TextInput {
                        id: passwordInput
                        width: 0
                        height: 0
                        visible: false
                        font.pointSize: Style.fontSizeM
                        color: Color.mPrimary
                        echoMode: parent.parent.passwordVisible ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        passwordMaskDelay: 0
                        text: sessionLock.passwdBuffer
                        onTextChanged: sessionLock.passwdBuffer = text
                        enabled: GreeterService.idle

                        Keys.onPressed: kevent => {
                          if (kevent.key === Qt.Key_Enter || kevent.key === Qt.Key_Return) {
                            sessionLock.tryUnlock()
                            kevent.accepted = true
                          }
                        }

                        Component.onCompleted: forceActiveFocus()
                      }

                      Row {
                        spacing: 0

                        Rectangle {
                          width: 2
                          height: 20
                          color: Color.mPrimary
                          visible: passwordInput.activeFocus && passwordInput.text.length === 0
                          anchors.verticalCenter: parent.verticalCenter

                          SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: passwordInput.activeFocus && passwordInput.text.length === 0
                            NumberAnimation {
                              to: 0
                              duration: 530
                            }
                            NumberAnimation {
                              to: 1
                              duration: 530
                            }
                          }
                        }

                        // Password display - show dots or actual text based on passwordVisible
                        Item {
                          width: Math.min(passwordDisplayContent.width, 550)
                          height: 20
                          visible: passwordInput.text.length > 0 && !parent.parent.parent.passwordVisible
                          anchors.verticalCenter: parent.verticalCenter
                          clip: true

                          Row {
                            id: passwordDisplayContent
                            spacing: 6
                            anchors.verticalCenter: parent.verticalCenter

                            Repeater {
                              model: passwordInput.text.length

                              NIcon {
                                icon: "circle-filled"
                                pointSize: Style.fontSizeS
                                color: Color.mPrimary
                                opacity: 1.0
                              }
                            }
                          }
                        }

                        NText {
                          text: passwordInput.text
                          color: Color.mPrimary
                          pointSize: Style.fontSizeM
                          font.weight: Font.Medium
                          visible: passwordInput.text.length > 0 && parent.parent.parent.passwordVisible
                          anchors.verticalCenter: parent.verticalCenter
                          elide: Text.ElideRight
                          width: Math.min(implicitWidth, 550)
                        }

                        Rectangle {
                          width: 2
                          height: 20
                          color: Color.mPrimary
                          visible: passwordInput.activeFocus && passwordInput.text.length > 0
                          anchors.verticalCenter: parent.verticalCenter

                          SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: passwordInput.activeFocus && passwordInput.text.length > 0
                            NumberAnimation {
                              to: 0
                              duration: 530
                            }
                            NumberAnimation {
                              to: 1
                              duration: 530
                            }
                          }
                        }
                      }
                    }

                    // Eye button to toggle password visibility
                    Rectangle {
                      anchors.right: submitButton.left
                      anchors.rightMargin: 4
                      anchors.verticalCenter: parent.verticalCenter
                      width: 36
                      height: 36
                      radius: width * 0.5
                      color: eyeButtonArea.containsMouse ? Qt.alpha(Color.mOnSurface, 0.1) : "transparent"
                      visible: passwordInput.text.length > 0
                      enabled: GreeterService.idle

                      NIcon {
                        anchors.centerIn: parent
                        icon: parent.parent.passwordVisible ? "eye-off" : "eye"
                        pointSize: Style.fontSizeM
                        color: Color.mOnSurfaceVariant
                      }

                      MouseArea {
                        id: eyeButtonArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: parent.parent.passwordVisible = !parent.parent.passwordVisible
                      }

                      Behavior on color {
                        ColorAnimation {
                          duration: 200
                          easing.type: Easing.OutCubic
                        }
                      }
                    }

                    // Submit button
                    Rectangle {
                      id: submitButton
                      anchors.right: parent.right
                      anchors.rightMargin: 8
                      anchors.verticalCenter: parent.verticalCenter
                      width: 36
                      height: 36
                      radius: width * 0.5
                      color: submitButtonArea.containsMouse ? Color.mPrimary : Qt.alpha(Color.mPrimary, 0.8)
                      border.color: Color.mPrimary
                      border.width: 1
                      enabled: GreeterService.idle

                      NIcon {
                        anchors.centerIn: parent
                        icon: "arrow-forward"
                        pointSize: Style.fontSizeM
                        color: Color.mOnPrimary
                      }

                      MouseArea {
                        id: submitButtonArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: sessionLock.tryUnlock()
                      }
                    }

                    Behavior on border.color {
                      ColorAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                      }
                    }
                  }

                  Item {
                    Layout.preferredWidth: Style.marginM
                  }
                }

                // System control buttons
                RowLayout {
                  Layout.fillWidth: true
                  Layout.preferredHeight: Settings.data.general.compactLockScreen ? 36 : 48
                  spacing: 10

                  Item {
                    Layout.preferredWidth: Style.marginM
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
                        color: suspendButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurfaceVariant
                      }

                      NText {
                        text: I18n.tr("session-menu.suspend")
                        color: suspendButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurfaceVariant
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
                        color: rebootButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurfaceVariant
                      }

                      NText {
                        text: I18n.tr("session-menu.reboot")
                        color: rebootButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurfaceVariant
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

                  Item {
                    Layout.preferredWidth: Style.marginM
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
