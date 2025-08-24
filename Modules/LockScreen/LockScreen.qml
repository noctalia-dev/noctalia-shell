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
import qs.Modules.Audio

Loader {
  id: lockScreen
  active: false

  // Log state changes to help debug lock screen issues
  onActiveChanged: {
    Logger.log("LockScreen", "State changed:", active)
  }

  // Allow a small grace period after unlocking so the compositor releases the lock surfaces
  Timer {
    id: unloadAfterUnlockTimer
    interval: 250
    repeat: false
    onTriggered: {
      Logger.log("LockScreen", "Unload timer triggered - deactivating")
      lockScreen.active = false
    }
  }
  function scheduleUnloadAfterUnlock() {
    Logger.log("LockScreen", "Scheduling unload after unlock")
    unloadAfterUnlockTimer.start()
  }
  sourceComponent: Component {
    WlSessionLock {
      id: lock

      // Tie session lock to loader visibility
      locked: lockScreen.active

      property string errorMessage: ""
      property bool authenticating: false
      property string password: ""
      property bool pamAvailable: typeof PamContext !== "undefined"



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
            // First release the Wayland session lock, then unload after a short delay
            lock.locked = false
            lockScreen.scheduleUnloadAfterUnlock()
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

        // WlSessionLockSurface provides a screen variable for the current screen.
        // Also we use a different scaling algorithm based on the resolution, as the design is full screen.
        readonly property real scaling: ScalingService.dynamicScale(screen)

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

        // Keyboard layout indicator component
        Item {
          id: keyboardLayout

          property string currentLayout: (typeof KeyboardLayoutService !== 'undefined'
                                          && KeyboardLayoutService.currentLayout) ? KeyboardLayoutService.currentLayout : "Unknown"
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
              spacing: Style.marginXS * scaling
              Layout.alignment: Qt.AlignHCenter

              NText {
                id: timeText
                text: Qt.formatDateTime(new Date(), "HH:mm")
                font.family: Settings.data.ui.fontBillboard
                font.pointSize: Style.fontSizeXXXL * 6 * scaling
                font.weight: Style.fontWeightBold
                font.letterSpacing: -2 * scaling
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

              NText {
                id: dateText
                text: Qt.formatDateTime(new Date(), "dddd, MMMM d")
                font.family: Settings.data.ui.fontBillboard
                font.pointSize: Style.fontSizeXXL * scaling
                font.weight: Font.Light
                color: Color.mOnSurface
                horizontalAlignment: Text.AlignHCenter
                width: timeText.width
              }
            }

            // User section with animated avatar
            Column {
              spacing: Style.marginM * scaling
              Layout.alignment: Qt.AlignHCenter

              // Animated avatar with glow effect or audio visualizer
              Rectangle {
                width: 108 * scaling
                height: 108 * scaling
                radius: width * 0.5
                color: Color.transparent
                border.color: Color.mPrimary
                border.width: Math.max(1, Style.borderL * scaling)
                anchors.horizontalCenter: parent.horizontalCenter
                z: 10

                // Circular audio visualizer when music is playing
                Loader {
                  active: MediaService.isPlaying && Settings.data.audio.visualizerType == "linear"
                  anchors.centerIn: parent
                  width: 160 * scaling
                  height: 160 * scaling

                  sourceComponent: Item {
                    Repeater {
                      model: CavaService.values.length

                      Rectangle {
                        property real linearAngle: (index / CavaService.values.length) * 2 * Math.PI
                        property real linearRadius: 70 * scaling
                        property real linearBarLength: Math.max(2, CavaService.values[index] * 30 * scaling)
                        property real linearBarWidth: 3 * scaling

                        width: linearBarWidth
                        height: linearBarLength
                        color: Color.mPrimary
                        radius: linearBarWidth * 0.5

                        x: parent.width * 0.5 + Math.cos(linearAngle) * linearRadius - width * 0.5
                        y: parent.height * 0.5 + Math.sin(linearAngle) * linearRadius - height * 0.5

                        transform: Rotation {
                          origin.x: linearBarWidth * 0.5
                          origin.y: linearBarLength * 0.5
                          angle: (linearAngle * 180 / Math.PI) + 90
                        }
                      }
                    }
                  }
                }

                Loader {
                  active: MediaService.isPlaying && Settings.data.audio.visualizerType == "mirrored"
                  anchors.centerIn: parent
                  width: 160 * scaling
                  height: 160 * scaling

                  sourceComponent: Item {
                    Repeater {
                      model: CavaService.values.length * 2

                      Rectangle {
                        property int mirroredValueIndex: index < CavaService.values.length ? index : (CavaService.values.length
                                                                                                      * 2 - 1 - index)
                        property real mirroredAngle: (index / (CavaService.values.length * 2)) * 2 * Math.PI
                        property real mirroredRadius: 70 * scaling
                        property real mirroredBarLength: Math.max(2,
                                                                  CavaService.values[mirroredValueIndex] * 30 * scaling)
                        property real mirroredBarWidth: 3 * scaling

                        width: mirroredBarWidth
                        height: mirroredBarLength
                        color: Color.mPrimary
                        radius: mirroredBarWidth * 0.5

                        x: parent.width * 0.5 + Math.cos(mirroredAngle) * mirroredRadius - width * 0.5
                        y: parent.height * 0.5 + Math.sin(mirroredAngle) * mirroredRadius - height * 0.5

                        transform: Rotation {
                          origin.x: mirroredBarWidth * 0.5
                          origin.y: mirroredBarLength * 0.5
                          angle: (mirroredAngle * 180 / Math.PI) + 90
                        }
                      }
                    }
                  }
                }

                Loader {
                  active: MediaService.isPlaying && Settings.data.audio.visualizerType == "wave"
                  anchors.centerIn: parent
                  width: 160 * scaling
                  height: 160 * scaling

                  sourceComponent: Item {
                    Canvas {
                      id: waveCanvas
                      anchors.fill: parent
                      antialiasing: true

                      onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()

                        if (CavaService.values.length === 0) {
                          return
                        }

                        ctx.strokeStyle = Color.mPrimary
                        ctx.lineWidth = 2 * scaling
                        ctx.lineCap = "round"

                        var centerX = width * 0.5
                        var centerY = height * 0.5
                        var baseRadius = 60 * scaling
                        var maxAmplitude = 20 * scaling

                        ctx.beginPath()

                        for (var i = 0; i <= CavaService.values.length; i++) {
                          var index = i % CavaService.values.length
                          var angle = (i / CavaService.values.length) * 2 * Math.PI
                          var amplitude = CavaService.values[index] * maxAmplitude
                          var radius = baseRadius + amplitude

                          var x = centerX + Math.cos(angle) * radius
                          var y = centerY + Math.sin(angle) * radius

                          if (i === 0) {
                            ctx.moveTo(x, y)
                          } else {
                            ctx.lineTo(x, y)
                          }
                        }

                        ctx.closePath()
                        ctx.stroke()
                      }
                    }

                    Timer {
                      interval: 16 // ~60 FPS
                      running: true
                      repeat: true
                      onTriggered: {
                        waveCanvas.requestPaint()
                      }
                    }
                  }
                }

                // Glow effect when no music is playing
                Rectangle {
                  anchors.centerIn: parent
                  width: parent.width + 24 * scaling
                  height: parent.height + 24 * scaling
                  radius: width * 0.5
                  color: Color.transparent
                  border.color: Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.3)
                  border.width: Math.max(1, Style.borderM * scaling)
                  z: -1
                  visible: !MediaService.isPlaying

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

                NImageCircled {
                  anchors.centerIn: parent
                  width: 100 * scaling
                  height: 100 * scaling
                  imagePath: Settings.data.general.avatarImage
                  fallbackIcon: "person"
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

            // Futuristic Terminal-Style Input
            Item {
              width: parent.width
              height: 280 * scaling
              Layout.fillWidth: true

              // Terminal background with scanlines
              Rectangle {
                id: terminalBackground
                anchors.fill: parent
                radius: Style.radiusM * scaling
                color: Color.applyOpacity(Color.mSurface, "E6")
                border.color: Color.mPrimary
                border.width: Math.max(1, Style.borderM * scaling)

                // Scanline effect
                Repeater {
                  model: 20
                  Rectangle {
                    width: parent.width
                    height: 1
                    color: Color.applyOpacity(Color.mPrimary, "1A")
                    y: index * 10 * scaling
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
                  topLeftRadius: Style.radiusS * scaling
                  topRightRadius: Style.radiusS * scaling

                  RowLayout {
                    anchors.fill: parent
                    anchors.topMargin: Style.marginM * scaling
                    anchors.bottomMargin: Style.marginM * scaling
                    anchors.leftMargin: Style.marginL * scaling
                    anchors.rightMargin: Style.marginL * scaling
                    spacing: Style.marginM * scaling

                    NText {
                      text: "SECURE TERMINAL"
                      color: Color.mOnSurface
                      font.family: Settings.data.ui.fontFixed
                      font.pointSize: Style.fontSizeL * scaling
                      font.weight: Style.fontWeightBold
                      Layout.fillWidth: true
                    }

                    // Battery indicator
                    Row {
                      spacing: Style.marginS * scaling
                      visible: batteryIndicator.batteryVisible

                      NIcon {
                        text: batteryIndicator.getIcon()
                        font.pointSize: Style.fontSizeM * scaling
                        color: batteryIndicator.charging ? Color.mPrimary : Color.mOnSurface
                      }

                      NText {
                        text: Math.round(batteryIndicator.percent) + "%"
                        color: Color.mOnSurface
                        font.family: Settings.data.ui.fontFixed
                        font.pointSize: Style.fontSizeM * scaling
                        font.weight: Style.fontWeightBold
                      }
                    }

                    // Keyboard layout indicator
                    Row {
                      spacing: Style.marginS * scaling

                      NText {
                        text: keyboardLayout.currentLayout
                        color: Color.mOnSurface
                        font.family: Settings.data.ui.fontFixed
                        font.pointSize: Style.fontSizeM * scaling
                        font.weight: Style.fontWeightBold
                      }

                      NIcon {
                        text: "keyboard_alt"
                        font.pointSize: Style.fontSizeM * scaling
                        color: Color.mOnSurface
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
                  anchors.margins: Style.marginL * scaling
                  anchors.topMargin: 70 * scaling
                  spacing: Style.marginM * scaling

                  // Welcome back typing effect
                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginM * scaling

                    NText {
                      text: Quickshell.env("USER") + "@noctalia:~$"
                      color: Color.mPrimary
                      font.family: Settings.data.ui.fontFixed
                      font.pointSize: Style.fontSizeL * scaling
                      font.weight: Style.fontWeightBold
                    }

                    NText {
                      id: welcomeText
                      text: ""
                      color: Color.mOnSurface
                      font.family: Settings.data.ui.fontFixed
                      font.pointSize: Style.fontSizeL * scaling
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
                    spacing: Style.marginM * scaling

                    NText {
                      text: Quickshell.env("USER") + "@noctalia:~$"
                      color: Color.mPrimary
                      font.family: Settings.data.ui.fontFixed
                      font.pointSize: Style.fontSizeL * scaling
                      font.weight: Style.fontWeightBold
                    }

                    NText {
                      text: "sudo unlock-session"
                      color: Color.mOnSurface
                      font.family: Settings.data.ui.fontFixed
                      font.pointSize: Style.fontSizeL * scaling
                    }

                    // Integrated password input (invisible, just for functionality)
                    TextInput {
                      id: passwordInput
                      width: 0
                      height: 0
                      visible: false
                      font.family: Settings.data.ui.fontFixed
                      font.pointSize: Style.fontSizeL * scaling
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
                    NText {
                      id: asterisksText
                      text: "*".repeat(passwordInput.text.length)
                      color: Color.mOnSurface
                      font.family: Settings.data.ui.fontFixed
                      font.pointSize: Style.fontSizeL * scaling
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
                      Layout.leftMargin: -Style.marginS * scaling
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
                  NText {
                    text: lock.authenticating ? "Authenticating..." : (lock.errorMessage !== "" ? "Authentication failed." : "")
                    color: lock.authenticating ? Color.mPrimary : (lock.errorMessage !== "" ? Color.mError : Color.transparent)
                    font.family: "DejaVu Sans Mono"
                    font.pointSize: Style.fontSizeL * scaling
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
                  Row {
                    Layout.alignment: Qt.AlignRight
                    Layout.bottomMargin: -10 * scaling
                    Rectangle {
                      width: 120 * scaling
                      height: 40 * scaling
                      radius: Style.radiusS * scaling
                      color: executeButtonArea.containsMouse ? Color.mPrimary : Color.applyOpacity(Color.mPrimary, "33")
                      border.color: Color.mPrimary
                      border.width: Math.max(1, Style.borderS * scaling)
                      enabled: !lock.authenticating

                      NText {
                        anchors.centerIn: parent
                        text: lock.authenticating ? "EXECUTING" : "EXECUTE"
                        color: executeButtonArea.containsMouse ? Color.mOnPrimary : Color.mPrimary
                        font.family: Settings.data.ui.fontFixed
                        font.pointSize: Style.fontSizeM * scaling
                        font.weight: Style.fontWeightBold
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
                }

                // Terminal glow effect
                Rectangle {
                  anchors.fill: parent
                  radius: parent.radius
                  color: Color.transparent
                  border.color: Color.applyOpacity(Color.mPrimary, "4D")
                  border.width: Math.max(1, Style.borderS * scaling)
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
            radius: Style.radiusL * scaling
            color: shutdownArea.containsMouse ? Color.applyOpacity(Color.mError,
                                                                   "DD") : Color.applyOpacity(Color.mError, "22")
            border.color: Color.mError
            border.width: Math.max(1, Style.borderM * scaling)

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
                CompositorService.shutdown()
              }
            }

            NIcon {
              text: "power_settings_new"
              font.pointSize: Style.fontSizeXXXL * scaling
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
            radius: Style.radiusL * scaling
            color: rebootArea.containsMouse ? Color.applyOpacity(Color.mPrimary,
                                                                 "DD") : Color.applyOpacity(Color.mPrimary, "22")
            border.color: Color.mPrimary
            border.width: Math.max(1, Style.borderM * scaling)

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
                CompositorService.reboot()
              }
            }

            NIcon {
              text: "refresh"
              font.pointSize: Style.fontSizeXXXL * scaling
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
            radius: Style.radiusL * scaling
            color: logoutArea.containsMouse ? Color.applyOpacity(Color.mSecondary,
                                                                 "DD") : Color.applyOpacity(Color.mSecondary, "22")
            border.color: Color.mSecondary
            border.width: Math.max(1, Style.borderM * scaling)

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
                CompositorService.logout()
              }
            }

            NIcon {
              text: "exit_to_app"
              font.pointSize: Style.fontSizeXXXL * scaling
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
  }
}
