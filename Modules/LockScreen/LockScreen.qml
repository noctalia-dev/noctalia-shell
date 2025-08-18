import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.UPower
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Services
import qs.Widgets

WlSessionLock {
  id: lock

  // Lockscreen is a different beast, needs a capital 'S' in 'Screen' to get the current screen
  readonly property real scaling: ScalingService.scale(Screen)

  property string errorMessage: ""
  property bool authenticating: false
  property string password: ""
  property bool pamAvailable: typeof PamContext !== "undefined"
  locked: false

  function unlockAttempt() {
    Logger.log("LockScreen", "Unlock attempt started")

    // Real PAM authentication
    if (!pamAvailable) {
      lock.errorMessage = "PAM authentication not available."
      Logger.log("LockScreen", "PAM not available")
      return
    }
    if (!lock.password) {
      lock.errorMessage = "Password required."
      Logger.log("LockScreen", "No password entered")
      return
    }
    Logger.log("LockScreen", "Starting PAM authentication")
    lock.authenticating = true
    lock.errorMessage = ""

    Logger.log("LockScreen", "About to create PAM context with userName:", Quickshell.env("USER"))
    var pam = Qt.createQmlObject(
          'import Quickshell.Services.Pam; PamContext { config: "login"; user: "' + Quickshell.env("USER") + '" }',
          lock)
    Logger.log("LockScreen", "PamContext created", pam)

    pam.onCompleted.connect(function (result) {
      Logger.log("LockScreen", "PAM completed with result:", result)
      lock.authenticating = false
      if (result === PamResult.Success) {
        Logger.log("LockScreen", "Authentication successful, unlocking")
        lock.locked = false
        lock.password = ""
        lock.errorMessage = ""
      } else {
        Logger.log("LockScreen", "Authentication failed")
        lock.errorMessage = "Authentication failed."
        lock.password = ""
      }
      pam.destroy()
    })

    pam.onError.connect(function (error) {
      Logger.log("LockScreen", "PAM error:", error)
      lock.authenticating = false
      lock.errorMessage = pam.message || "Authentication error."
      lock.password = ""
      pam.destroy()
    })

    pam.onPamMessage.connect(function () {
      Logger.log("LockScreen", "PAM message:", pam.message, "isError:", pam.messageIsError)
      if (pam.messageIsError) {
        lock.errorMessage = pam.message
      }
    })

    pam.onResponseRequiredChanged.connect(function () {
      Logger.log("LockScreen", "PAM response required:", pam.responseRequired)
      if (pam.responseRequired && lock.authenticating) {
        Logger.log("LockScreen", "Responding to PAM with password")
        pam.respond(lock.password)
      }
    })

    var started = pam.start()
    Logger.log("LockScreen", "PAM start result:", started)
  }

  WlSessionLockSurface {
    // Battery indicator component
    Item {
      id: batteryIndicator

      // Import UPower for battery data
      property var battery: UPower.displayDevice
      property bool isReady: battery && battery.ready && battery.isLaptopBattery && battery.isPresent
      property real percent: isReady ? (battery.percentage * 100) : 0
      property bool charging: isReady ? battery.state === UPowerDeviceState.Charging : false
      property bool batteryVisible: isReady && percent > 0

      // Choose icon based on charge and charging state
      function getIcon() {
        if (!batteryVisible)
          return ""

        if (charging)
          return "battery_android_bolt"

        if (percent >= 95)
          return "battery_android_full"

        // Hardcoded battery symbols
        if (percent >= 85)
          return "battery_android_6"
        if (percent >= 70)
          return "battery_android_5"
        if (percent >= 55)
          return "battery_android_4"
        if (percent >= 40)
          return "battery_android_3"
        if (percent >= 25)
          return "battery_android_2"
        if (percent >= 10)
          return "battery_android_1"
        if (percent >= 0)
          return "battery_android_0"
      }
    }

    // Wallpaper image
    Image {
      id: lockBgImage
      anchors.fill: parent
      fillMode: Image.PreserveAspectCrop
      source: WallpaperService.currentWallpaper !== "" ? WallpaperService.currentWallpaper : ""
      cache: true
      smooth: true
      mipmap: false
    }

    // Blurred background
    Rectangle {
      anchors.fill: parent
      color: Color.transparent

      // Simple blur effect
      layer.enabled: true
      layer.smooth: true
      layer.samples: 4
    }

    // Animated gradient overlay
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop {
          position: 0.0
          color: Qt.rgba(0, 0, 0, 0.6)
        }
        GradientStop {
          position: 0.3
          color: Qt.rgba(0, 0, 0, 0.3)
        }
        GradientStop {
          position: 0.7
          color: Qt.rgba(0, 0, 0, 0.4)
        }
        GradientStop {
          position: 1.0
          color: Qt.rgba(0, 0, 0, 0.7)
        }
      }

      // Subtle animated particles
      Repeater {
        model: 20
        Rectangle {
          width: Math.random() * 4 + 2
          height: width
          radius: width * 0.5
          color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.3)
          x: Math.random() * parent.width
          y: Math.random() * parent.height

          SequentialAnimation on opacity {
            loops: Animation.Infinite
            NumberAnimation {
              to: 0.8
              duration: 2000 + Math.random() * 3000
            }
            NumberAnimation {
              to: 0.1
              duration: 2000 + Math.random() * 3000
            }
          }
        }
      }
    }

    // Main content - Centered design
    Item {
      anchors.fill: parent

      // Top section - Time, date, and user info
      ColumnLayout {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 80 * scaling
        spacing: 40 * scaling

        // Time display - Large and prominent with pulse animation
        Column {
          spacing: Style.marginSmall * scaling
          Layout.alignment: Qt.AlignHCenter

          Text {
            id: timeText
            text: Qt.formatDateTime(new Date(), "HH:mm")
            font.family: "Inter"
            font.pointSize: Style.fontSizeXXL * 6
            font.weight: Font.Bold
            font.letterSpacing: -2
            color: Color.mOnSurface
            horizontalAlignment: Text.AlignHCenter

            SequentialAnimation on scale {
              loops: Animation.Infinite
              NumberAnimation {
                to: 1.02
                duration: 2000
                easing.type: Easing.InOutQuad
              }
              NumberAnimation {
                to: 1.0
                duration: 2000
                easing.type: Easing.InOutQuad
              }
            }
          }

          Text {
            id: dateText
            text: Qt.formatDateTime(new Date(), "dddd, MMMM d")
            font.family: "Inter"
            font.pointSize: Style.fontSizeXL
            font.weight: Font.Light
            color: Color.mOnSurface
            horizontalAlignment: Text.AlignHCenter
            width: timeText.width
          }
        }

        // User section with animated avatar
        Column {
          spacing: Style.marginMedium * scaling
          Layout.alignment: Qt.AlignHCenter

          // Animated avatar with glow effect
          Rectangle {
            width: 120 * scaling
            height: 120 * scaling
            radius: width * 0.5
            color: Color.transparent
            border.color: Color.mPrimary
            border.width: Math.max(1, Style.borderThick * scaling)
            anchors.horizontalCenter: parent.horizontalCenter

            // Glow effect
            Rectangle {
              anchors.centerIn: parent
              width: parent.width + 24 * scaling
              height: parent.height + 24 * scaling
              radius: width * 0.5
              color: Color.transparent
              border.color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.3)
              border.width: Math.max(1, Style.borderMedium * scaling)
              z: -1

              SequentialAnimation on scale {
                loops: Animation.Infinite
                NumberAnimation {
                  to: 1.1
                  duration: 1500
                  easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                  to: 1.0
                  duration: 1500
                  easing.type: Easing.InOutQuad
                }
              }
            }

            NImageRounded {
              anchors.centerIn: parent
              width: 100 * scaling
              height: 100 * scaling
              imagePath: Quickshell.env("HOME") + "/.face"
              fallbackIcon: "person"
              imageRadius: width * 0.5
            }

            // Hover animation
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: parent.scale = 1.05
              onExited: parent.scale = 1.0
            }

            Behavior on scale {
              NumberAnimation {
                duration: Style.animationFast
                easing.type: Easing.OutBack
              }
            }
          }
        }
      }

      // Centered terminal section
      Item {
        width: 720 * scaling
        height: 280 * scaling
        anchors.centerIn: parent

        ColumnLayout {
          anchors.centerIn: parent
          spacing: 20 * scaling
          width: parent.width

          // Futuristic Terminal-Style Input
          Item {
            width: parent.width
            height: 280 * scaling
            Layout.fillWidth: true

            // Terminal background with scanlines
            Rectangle {
              id: terminalBackground
              anchors.fill: parent
              radius: Style.radiusMedium * scaling
              color: Color.applyOpacity(Color.mSurface, "E6")
              border.color: Color.mPrimary
              border.width: Math.max(1, Style.borderMedium * scaling)

              // Scanline effect
              Repeater {
                model: 20
                Rectangle {
                  width: parent.width
                  height: 1
                  color: Color.applyOpacity(Color.mPrimary, "1A")
                  y: index * 10
                  opacity: Style.opacityMedium

                  SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    NumberAnimation {
                      to: 0.6
                      duration: 2000 + Math.random() * 1000
                    }
                    NumberAnimation {
                      to: 0.1
                      duration: 2000 + Math.random() * 1000
                    }
                  }
                }
              }

              // Terminal header
              Rectangle {
                width: parent.width
                height: 40 * scaling
                color: Color.applyOpacity(Color.mPrimary, "33")
                topLeftRadius: Style.radiusSmall * scaling
                topRightRadius: Style.radiusSmall * scaling

                RowLayout {
                  anchors.fill: parent
                  anchors.margins: Style.marginMedium * scaling
                  spacing: Style.marginMedium * scaling

                  Text {
                    text: "SECURE TERMINAL"
                    color: Color.mOnSurface
                    font.family: "DejaVu Sans Mono"
                    font.pointSize: Style.fontSizeLarge
                    font.weight: Font.Bold
                    Layout.fillWidth: true
                  }

                  // Battery indicator
                  Row {
                    spacing: Style.marginSmall * scaling
                    visible: batteryIndicator.batteryVisible

                    NIcon {
                      text: batteryIndicator.getIcon()
                      font.pointSize: Style.fontSizeMedium
                      color: batteryIndicator.charging ? Color.mPrimary : Color.mOnSurface
                    }

                    Text {
                      text: Math.round(batteryIndicator.percent) + "%"
                      color: Color.mOnSurface
                      font.family: "DejaVu Sans Mono"
                      font.pointSize: Style.fontSizeMedium
                      font.weight: Font.Bold
                    }
                  }
                }
              }

              // Terminal content area
              ColumnLayout {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.topMargin: 70 * scaling
                anchors.margins: Style.marginMedium * scaling
                spacing: Style.marginMedium * scaling

                // Welcome back typing effect
                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginMedium * scaling

                  Text {
                    text: "root@noctalia:~$"
                    color: Color.mPrimary
                    font.family: "DejaVu Sans Mono"
                    font.pointSize: Style.fontSizeLarge
                    font.weight: Font.Bold
                  }

                  Text {
                    id: welcomeText
                    text: ""
                    color: Color.mOnSurface
                    font.family: "DejaVu Sans Mono"
                    font.pointSize: Style.fontSizeLarge
                    property int currentIndex: 0
                    property string fullText: "Welcome back, " + Quickshell.env("USER") + "!"

                    Timer {
                      interval: Style.animationFast
                      running: true
                      repeat: true
                      onTriggered: {
                        if (parent.currentIndex < parent.fullText.length) {
                          parent.text = parent.fullText.substring(0, parent.currentIndex + 1)
                          parent.currentIndex++
                        } else {
                          running = false
                        }
                      }
                    }
                  }
                }

                // Command line with integrated password input
                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginMedium * scaling

                  Text {
                    text: "root@noctalia:~$"
                    color: Color.mPrimary
                    font.family: "DejaVu Sans Mono"
                    font.pointSize: Style.fontSizeLarge
                    font.weight: Font.Bold
                  }

                  Text {
                    text: "sudo unlock-session"
                    color: Color.mOnSurface
                    font.family: "DejaVu Sans Mono"
                    font.pointSize: Style.fontSizeLarge
                  }

                  // Integrated password input (invisible, just for functionality)
                  TextInput {
                    id: passwordInput
                    width: 0
                    height: 0
                    visible: false
                    font.family: "DejaVu Sans Mono"
                    font.pointSize: Style.fontSizeLarge
                    color: Color.mOnSurface
                    echoMode: TextInput.Password
                    passwordCharacter: "*"
                    passwordMaskDelay: 0

                    text: lock.password
                    onTextChanged: {
                      lock.password = text
                      // Terminal typing sound effect (visual)
                      typingEffect.start()
                    }

                    Keys.onPressed: function (event) {
                      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        lock.unlockAttempt()
                      }
                    }

                    Component.onCompleted: {
                      forceActiveFocus()
                    }
                  }

                  // Visual password display with integrated cursor
                  Text {
                    id: asterisksText
                    text: "*".repeat(passwordInput.text.length)
                    color: Color.mOnSurface
                    font.family: "DejaVu Sans Mono"
                    font.pointSize: Style.fontSizeLarge
                    visible: passwordInput.activeFocus

                    // Typing effect animation
                    SequentialAnimation {
                      id: typingEffect
                      NumberAnimation {
                        target: passwordInput
                        property: "scale"
                        to: 1.01
                        duration: 50
                      }
                      NumberAnimation {
                        target: passwordInput
                        property: "scale"
                        to: 1.0
                        duration: 50
                      }
                    }
                  }

                  // Blinking cursor positioned right after the asterisks
                  Rectangle {
                    width: 8 * scaling
                    height: 20 * scaling
                    color: Color.mPrimary
                    visible: passwordInput.activeFocus
                    Layout.leftMargin: -Style.marginSmall * scaling
                    Layout.alignment: Qt.AlignVCenter

                    SequentialAnimation on opacity {
                      loops: Animation.Infinite
                      NumberAnimation {
                        to: 1.0
                        duration: 500
                      }
                      NumberAnimation {
                        to: 0.0
                        duration: 500
                      }
                    }
                  }
                }

                // Status messages
                Text {
                  text: lock.authenticating ? "Authenticating..." : (lock.errorMessage !== "" ? "Authentication failed." : "")
                  color: lock.authenticating ? Color.mPrimary : (lock.errorMessage !== "" ? Color.mError : Color.transparent)
                  font.family: "DejaVu Sans Mono"
                  font.pointSize: Style.fontSizeLarge
                  Layout.fillWidth: true

                  SequentialAnimation on opacity {
                    running: lock.authenticating
                    loops: Animation.Infinite
                    NumberAnimation {
                      to: 1.0
                      duration: 800
                    }
                    NumberAnimation {
                      to: 0.5
                      duration: 800
                    }
                  }
                }

                // Execute button
                Rectangle {
                  width: 120 * scaling
                  height: 40 * scaling
                  radius: Style.radiusSmall * scaling
                  color: executeButtonArea.containsMouse ? Color.mPrimary : Color.applyOpacity(Color.mPrimary, "33")
                  border.color: Color.mPrimary
                  border.width: Math.max(1, Style.borderThin * scaling)
                  enabled: !lock.authenticating
                  Layout.alignment: Qt.AlignRight
                  Layout.bottomMargin: -12 * scaling

                  Text {
                    anchors.centerIn: parent
                    text: lock.authenticating ? "EXECUTING" : "EXECUTE"
                    color: executeButtonArea.containsMouse ? Color.mOnPrimary : Color.mPrimary
                    font.family: "DejaVu Sans Mono"
                    font.pointSize: Style.fontSizeMedium
                    font.weight: Font.Bold
                  }

                  MouseArea {
                    id: executeButtonArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: lock.unlockAttempt()

                    SequentialAnimation on scale {
                      running: executeButtonArea.containsMouse
                      NumberAnimation {
                        to: 1.05
                        duration: Style.animationFast
                        easing.type: Easing.OutCubic
                      }
                    }

                    SequentialAnimation on scale {
                      running: !executeButtonArea.containsMouse
                      NumberAnimation {
                        to: 1.0
                        duration: Style.animationFast
                        easing.type: Easing.OutCubic
                      }
                    }
                  }

                  // Processing animation
                  SequentialAnimation on scale {
                    loops: Animation.Infinite
                    running: lock.authenticating
                    NumberAnimation {
                      to: 1.02
                      duration: 600
                      easing.type: Easing.InOutQuad
                    }
                    NumberAnimation {
                      to: 1.0
                      duration: 600
                      easing.type: Easing.InOutQuad
                    }
                  }
                }
              }

              // Terminal glow effect
              Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Color.transparent
                border.color: Color.applyOpacity(Color.mPrimary, "4D")
                border.width: Math.max(1, Style.borderThin * scaling)
                z: -1

                SequentialAnimation on opacity {
                  loops: Animation.Infinite
                  NumberAnimation {
                    to: 0.6
                    duration: 2000
                    easing.type: Easing.InOutQuad
                  }
                  NumberAnimation {
                    to: 0.2
                    duration: 2000
                    easing.type: Easing.InOutQuad
                  }
                }
              }
            }
          }
        }
      }
    }

    // Enhanced power buttons with hover effects
    Row {
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 50 * scaling
      spacing: 20 * scaling

      // Shutdown with enhanced styling
      Rectangle {
        width: 64 * scaling
        height: 64 * scaling
        radius: Style.radiusLarge * scaling
        color: shutdownArea.containsMouse ? Color.applyOpacity(Color.mError,
                                                               "DD") : Color.applyOpacity(Color.mError, "22")
        border.color: Color.mError
        border.width: Math.max(1, Style.borderMedium * scaling)

        // Glow effect
        Rectangle {
          anchors.centerIn: parent
          width: parent.width + 10 * scaling
          height: parent.height + 10 * scaling
          radius: width * 0.5
          color: Color.transparent
          opacity: shutdownArea.containsMouse ? 1 : 0
          z: -1

          Behavior on opacity {
            NumberAnimation {
              duration: Style.animationFast
              easing.type: Easing.OutCubic
            }
          }
        }

        MouseArea {
          id: shutdownArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            Qt.createQmlObject('import Quickshell.Io; Process { command: ["shutdown", "-h", "now"]; running: true }',
                               lock)
          }
        }

        NIcon {
          text: "power_settings_new"
          font.pointSize: Style.fontSizeXXL * scaling
          color: shutdownArea.containsMouse ? Color.mOnPrimary : Color.mError
          anchors.centerIn: parent
        }

        Behavior on color {
          ColorAnimation {
            duration: Style.animationFast
            easing.type: Easing.OutCubic
          }
        }
        scale: shutdownArea.containsMouse ? 1.1 : 1.0
      }

      // Reboot with enhanced styling
      Rectangle {
        width: 64 * scaling
        height: 64 * scaling
        radius: Style.radiusLarge * scaling
        color: rebootArea.containsMouse ? Color.applyOpacity(Color.mPrimary,
                                                             "DD") : Color.applyOpacity(Color.mPrimary, "22")
        border.color: Color.mPrimary
        border.width: Math.max(1, Style.borderMedium * scaling)

        // Glow effect
        Rectangle {
          anchors.centerIn: parent
          width: parent.width + 10 * scaling
          height: parent.height + 10 * scaling
          radius: width * 0.5
          color: Color.transparent
          opacity: rebootArea.containsMouse ? 1 : 0
          z: -1

          Behavior on opacity {
            NumberAnimation {
              duration: Style.animationMedium
              easing.type: Easing.OutCubic
            }
          }
        }

        MouseArea {
          id: rebootArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            Qt.createQmlObject('import Quickshell.Io; Process { command: ["reboot"]; running: true }', lock)
          }
        }

        NIcon {
          text: "refresh"
          font.pointSize: Style.fontSizeXXL * scaling
          color: rebootArea.containsMouse ? Color.mOnPrimary : Color.mPrimary
          anchors.centerIn: parent
        }

        Behavior on color {
          ColorAnimation {
            duration: Style.animationMedium
            easing.type: Easing.OutCubic
          }
        }
        scale: rebootArea.containsMouse ? 1.1 : 1.0
      }

      // Logout with enhanced styling
      Rectangle {
        width: 64 * scaling
        height: 64 * scaling
        radius: Style.radiusLarge * scaling
        color: logoutArea.containsMouse ? Color.applyOpacity(Color.mSecondary,
                                                             "DD") : Color.applyOpacity(Color.mSecondary, "22")
        border.color: Color.mSecondary
        border.width: Math.max(1, Style.borderMedium * scaling)

        // Glow effect
        Rectangle {
          anchors.centerIn: parent
          width: parent.width + 10 * scaling
          height: parent.height + 10 * scaling
          radius: width * 0.5
          color: Color.transparent
          opacity: logoutArea.containsMouse ? 1 : 0
          z: -1

          Behavior on opacity {
            NumberAnimation {
              duration: Style.animationMedium
              easing.type: Easing.OutCubic
            }
          }
        }

        MouseArea {
          id: logoutArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            Qt.createQmlObject(
                  'import Quickshell.Io; Process { command: ["loginctl", "terminate-user", "' + Quickshell.env(
                    "USER") + '"]; running: true }', lock)
          }
        }

        NIcon {
          text: "exit_to_app"
          font.pointSize: Style.fontSizeXXL * scaling
          color: logoutArea.containsMouse ? Color.mOnPrimary : Color.mSecondary
          anchors.centerIn: parent
        }

        Behavior on color {
          ColorAnimation {
            duration: Style.animationFast
            easing.type: Easing.OutCubic
          }
        }
        scale: logoutArea.containsMouse ? 1.1 : 1.0
      }
    }

    // Timer for updating time
    Timer {
      interval: 1000
      running: true
      repeat: true
      onTriggered: {
        timeText.text = Qt.formatDateTime(new Date(), "HH:mm")
        dateText.text = Qt.formatDateTime(new Date(), "dddd, MMMM d")
      }
    }
  }
}
