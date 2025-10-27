pragma ComponentBehavior

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd

import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.Audio

Item {
  id: root

  // Config via environment variables
  readonly property string instant_auth: Quickshell.env("NOCTALIA_DM_INSTANTAUTH")
  readonly property string preferred_session: Quickshell.env("NOCTALIA_DM_PREF_SES")
  readonly property string preferred_user: Quickshell.env("NOCTALIA_DM_PREF_USR")
  // Fallback to empty string and log later to avoid assigning console.log result
  readonly property string sessions: Quickshell.env("NOCTALIA_DM_SESSIONS") || ""
  readonly property string wallpaper_path: Quickshell.env("NOCTALIA_DM_WALLPATH")

  // Noctalia config paths
  readonly property string noctaliaConfigDir: Quickshell.env("NOCTALIA_CONFIG_DIR") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/noctalia/"
  readonly property string noctaliaSettingsFile: noctaliaConfigDir + "settings.json"

  // Wallpaper state from noctalia config
  property string noctaliaWallpaper: ""
  property string currentMonitorName: ""

  property bool i18nLoaded: false
  property bool settingsLoaded: false

  Connections {
    target: I18n ? I18n : null
    function onTranslationsLoaded() {
      i18nLoaded = true
    }
  }

  Connections {
    target: Settings ? Settings : null
    function onSettingsLoaded() {
      settingsLoaded = true
    }
  }

  function authenticate() {
    sessionLock.showFailure = false
    Greetd.createSession(users.current_user)
  }

  Component.onCompleted: {
    if (sessions == "") {
      console.log("[WARN] empty sessions list, defaulting to hyprland")
      sessions.current_session = "hyprland"
      sessions.current_session_name = "hyprland"
    }

    // Initialize session from saved settings after UI load (final check occurs after sessions load too)
    const saved = GreeterSettings.lastSessionId
    if (saved && sessions.session_execs.length > 0) {
      for (var i = 0; i < sessions.session_names.length; i++) {
        if (sessions.session_execs[i].toLowerCase().includes(saved.toLowerCase()) || sessions.session_names[i].toLowerCase().includes(saved.toLowerCase())) {
          sessions.current_ses_index = i
          break
        }
      }
    }
  }

  // Load noctalia settings to get wallpaper
  FileView {
    id: noctaliaSettingsLoader
    path: root.noctaliaSettingsFile
    watchChanges: true

    JsonAdapter {
      id: noctaliaSettings
      property JsonObject wallpaper: JsonObject {
        property bool enabled: true
        property string directory: ""
        property bool setWallpaperOnAllMonitors: true
        property list<var> monitors: []
      }
    }

    onLoaded: {
      console.log("[INFO] Loaded noctalia settings from:", root.noctaliaSettingsFile)
      updateWallpaperFromNoctaliaConfig()
    }

    onLoadFailed: function (error) {
      console.log("[WARN] Failed to load noctalia settings:", error)
      console.log("[INFO] Using fallback wallpaper from environment variable")
    }

    Component.onCompleted: reload()
  }

  function updateWallpaperFromNoctaliaConfig() {
    if (!noctaliaSettings.wallpaper.enabled) {
      console.log("[INFO] Wallpaper disabled in noctalia config")
      return
    }

    // Get current monitor name (you may need to adapt this based on your setup)
    if (Quickshell.screens.length > 0) {
      currentMonitorName = Quickshell.screens[0].name
    }

    // Look for monitor-specific wallpaper
    const monitors = noctaliaSettings.wallpaper.monitors
    let foundWallpaper = ""

    if (monitors && monitors.length > 0) {
      for (var i = 0; i < monitors.length; i++) {
        const monitor = monitors[i]
        if (monitor && monitor.name === currentMonitorName && monitor.wallpaper) {
          foundWallpaper = monitor.wallpaper
          console.log("[INFO] Found monitor-specific wallpaper for", currentMonitorName + ":", foundWallpaper)
          break
        }
      }
    }

    // Fallback to directory + some default logic if no specific wallpaper found
    if (!foundWallpaper && noctaliaSettings.wallpaper.directory) {
      console.log("[INFO] No monitor-specific wallpaper found, using directory:", noctaliaSettings.wallpaper.directory)
      // You might want to implement directory scanning logic here
      // For now, we'll just use the directory path as a fallback
      foundWallpaper = noctaliaSettings.wallpaper.directory
    }

    if (foundWallpaper) {
      root.noctaliaWallpaper = foundWallpaper
      console.log("[INFO] Using noctalia wallpaper:", foundWallpaper)
    } else {
      console.log("[INFO] No wallpaper found in noctalia config, using environment fallback")
    }
  }

  // Main greeter interface
  WlSessionLock {
    id: sessionLock

    property string fakeBuffer: ""
    property string passwdBuffer: ""
    readonly property bool unlocking: Greetd.state == GreetdState.Authenticating

    property bool showFailure: false
    property string errorMessage: ""

    locked: true

    WlSessionLockSurface {
      // Background with wallpaper and gradient overlay
      Rectangle {
        anchors.fill: parent
        color: Color.mSurface

        // Wallpaper - prioritize noctalia config, fallback to environment variable
        Image {
          anchors.fill: parent
          source: root.noctaliaWallpaper || root.wallpaper_path
          fillMode: Image.PreserveAspectCrop
          visible: (root.noctaliaWallpaper || root.wallpaper_path) !== ""

          onStatusChanged: {
            if (status === Image.Error) {
              console.log("[ERROR] Failed to load wallpaper:", source)
            } else if (status === Image.Ready) {
              console.log("[INFO] Successfully loaded wallpaper:", source)
            }
          }
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
          visible: sessionLock.showFailure && sessionLock.errorMessage
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
              text: sessionLock.errorMessage || "Authentication failed"
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
                    // enabled: !lockContext.unlockInProgress // TODO: Implement unlock progress tracking
                    font.pointSize: Style.fontSizeM
                    color: Color.mPrimary
                    echoMode: parent.parent.passwordVisible ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    passwordMaskDelay: 0
                    text: sessionLock.passwdBuffer
                    onTextChanged: sessionLock.passwdBuffer = text

                    Keys.onPressed: kevent => {
                      if (kevent.key === Qt.Key_Enter || kevent.key === Qt.Key_Return) {
                        if (Greetd.state == GreetdState.Inactive) {
                          root.authenticate()
                        }
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
                  enabled: !lockContext.unlockInProgress

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
                  enabled: !lockContext.unlockInProgress

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
                    onClicked: lockContext.tryUnlock()
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

  // Greetd connections
  Connections {
    target: Greetd

    function onAuthMessage(message, error, responseRequired, echoResponse) {
      console.log("[GREETD] msg='" + message + "' err='" + error + "' resreq=" + responseRequired + " echo=" + echoResponse)

      if (responseRequired) {
        Greetd.respond(sessionLock.passwdBuffer)
        sessionLock.passwdBuffer = ""
        sessionLock.fakeBuffer = ""
        return
      }

      // Finger print support
      Greetd.respond("")
    }

    function onReadyToLaunch() {
      sessionLock.locked = false
      console.log("[GREETD EXEC] " + sessions.current_session)
      // Let greetd handle quitting to avoid compositor handoff glitches
      Greetd.launch(sessions.current_session.split(" "), [], true)
    }

    function onAuthFailure(message) {
      sessionLock.showFailure = true
      sessionLock.errorMessage = message
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
      root.authenticate()
    }
  }

  // Session management process
  Process {
    id: sessions

    property int current_ses_index: 0
    property string current_session: session_execs[current_ses_index] ?? "hyprland"
    property string current_session_name: session_names[current_ses_index] ?? "Hyprland"
    property list<string> session_execs: []
    property list<string> session_names: []
    property bool restoredFromSettings: false

    function next() {
      current_ses_index = (current_ses_index + 1) % session_execs.length
    }

    function moveToFront(index) {
      if (index <= 0 || index >= session_execs.length)
        return
      const exec = session_execs[index]
      const name = session_names[index]
      session_execs.splice(index, 1)
      session_names.splice(index, 1)
      session_execs.unshift(exec)
      session_names.unshift(name)
      current_ses_index = 0
    }

    command: [Qt.resolvedUrl("./scripts/session.sh"), root.sessions]
    running: true

    stderr: SplitParser {
      onRead: data => console.log("[ERR] " + data)
    }
    stdout: SplitParser {
      onRead: data => {
        const parsedData = data.split(",")
        console.log("[SESSIONS] " + parsedData[2])
        if (parsedData[0] == root.preferred_session) {
          console.log("[INFO] Found preferred session " + root.preferred_session)
          sessions.current_ses_index = sessions.session_names.length
        }
        sessions.session_names.push(parsedData[1])
        sessions.session_execs.push(parsedData[2])
      }
    }

    onExited: {
      // After sessions populated, prefer saved session as first entry
      if (!restoredFromSettings && GreeterSettings.lastSessionId && session_execs.length > 0) {
        const saved = GreeterSettings.lastSessionId.toLowerCase()
        let idx = -1
        for (var i = 0; i < session_execs.length; i++) {
          if (session_execs[i].toLowerCase().includes(saved) || session_names[i].toLowerCase().includes(saved)) {
            idx = i
            break
          }
        }
        if (idx >= 0) {
          moveToFront(idx)
          restoredFromSettings = true
        }
      }

      if (root.instant_auth && !users.running) {
        console.log("[SESSIONS EXIT]")
        root.authenticate()
      }
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
}
