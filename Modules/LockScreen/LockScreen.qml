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
import qs.Modules.Bar.Calendar

Loader {
  id: lockScreen
  active: false

  // Track if triggered via deprecated IPC call
  property bool triggeredViaDeprecatedCall: false

  Timer {
    id: unloadAfterUnlockTimer
    interval: 250
    repeat: false
    onTriggered: {
      lockScreen.active = false
      // Reset the deprecation flag when unlocking
      lockScreen.triggeredViaDeprecatedCall = false
    }
  }

  function scheduleUnloadAfterUnlock() {
    unloadAfterUnlockTimer.start()
  }

  sourceComponent: Component {
    Item {
      id: lockContainer

      LockContext {
        id: lockContext
        onUnlocked: {
          lockSession.locked = false
          lockScreen.scheduleUnloadAfterUnlock()
          lockContext.currentText = ""
        }
        onFailed: {
          lockContext.currentText = ""
        }
      }

      WlSessionLock {
        id: lockSession
        locked: lockScreen.active

        WlSessionLockSurface {
          readonly property var now: Time.date

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

          Image {
            id: lockBgImage
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            source: screen ? WallpaperService.getWallpaper(screen.name) : ""
            cache: true
            smooth: true
            mipmap: false
          }

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

          // Screen corners for lock screen
          Item {
            anchors.fill: parent
            visible: Settings.data.general.showScreenCorners

            property color cornerColor: Settings.data.general.forceBlackScreenCorners ? Qt.rgba(0, 0, 0, 1) : Qt.alpha(Color.mSurface, Settings.data.bar.backgroundOpacity)
            property real cornerRadius: Style.screenRadius
            property real cornerSize: Style.screenRadius

            // Top-left concave corner
            Canvas {
              anchors.top: parent.top
              anchors.left: parent.left
              width: parent.cornerSize
              height: parent.cornerSize
              antialiasing: true
              renderTarget: Canvas.FramebufferObject
              smooth: false

              onPaint: {
                const ctx = getContext("2d")
                if (!ctx)
                  return

                ctx.reset()
                ctx.clearRect(0, 0, width, height)

                ctx.fillStyle = parent.cornerColor
                ctx.fillRect(0, 0, width, height)

                ctx.globalCompositeOperation = "destination-out"
                ctx.fillStyle = "#ffffff"
                ctx.beginPath()
                ctx.arc(width, height, parent.cornerRadius, 0, 2 * Math.PI)
                ctx.fill()
              }

              onWidthChanged: if (available)
                                requestPaint()
              onHeightChanged: if (available)
                                 requestPaint()
            }

            // Top-right concave corner
            Canvas {
              anchors.top: parent.top
              anchors.right: parent.right
              width: parent.cornerSize
              height: parent.cornerSize
              antialiasing: true
              renderTarget: Canvas.FramebufferObject
              smooth: true

              onPaint: {
                const ctx = getContext("2d")
                if (!ctx)
                  return

                ctx.reset()
                ctx.clearRect(0, 0, width, height)

                ctx.fillStyle = parent.cornerColor
                ctx.fillRect(0, 0, width, height)

                ctx.globalCompositeOperation = "destination-out"
                ctx.fillStyle = "#ffffff"
                ctx.beginPath()
                ctx.arc(0, height, parent.cornerRadius, 0, 2 * Math.PI)
                ctx.fill()
              }

              onWidthChanged: if (available)
                                requestPaint()
              onHeightChanged: if (available)
                                 requestPaint()
            }

            // Bottom-left concave corner
            Canvas {
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              width: parent.cornerSize
              height: parent.cornerSize
              antialiasing: true
              renderTarget: Canvas.FramebufferObject
              smooth: true

              onPaint: {
                const ctx = getContext("2d")
                if (!ctx)
                  return

                ctx.reset()
                ctx.clearRect(0, 0, width, height)

                ctx.fillStyle = parent.cornerColor
                ctx.fillRect(0, 0, width, height)

                ctx.globalCompositeOperation = "destination-out"
                ctx.fillStyle = "#ffffff"
                ctx.beginPath()
                ctx.arc(width, 0, parent.cornerRadius, 0, 2 * Math.PI)
                ctx.fill()
              }

              onWidthChanged: if (available)
                                requestPaint()
              onHeightChanged: if (available)
                                 requestPaint()
            }

            // Bottom-right concave corner
            Canvas {
              anchors.bottom: parent.bottom
              anchors.right: parent.right
              width: parent.cornerSize
              height: parent.cornerSize
              antialiasing: true
              renderTarget: Canvas.FramebufferObject
              smooth: true

              onPaint: {
                const ctx = getContext("2d")
                if (!ctx)
                  return

                ctx.reset()
                ctx.clearRect(0, 0, width, height)

                ctx.fillStyle = parent.cornerColor
                ctx.fillRect(0, 0, width, height)

                ctx.globalCompositeOperation = "destination-out"
                ctx.fillStyle = "#ffffff"
                ctx.beginPath()
                ctx.arc(0, 0, parent.cornerRadius, 0, 2 * Math.PI)
                ctx.fill()
              }

              onWidthChanged: if (available)
                                requestPaint()
              onHeightChanged: if (available)
                                 requestPaint()
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
                    text: I18n.tr("lock-screen.welcome-back") + " " + (Quickshell.env("USER").charAt(0).toUpperCase() + Quickshell.env("USER").slice(1)) + "!"
                    pointSize: Style.fontSizeXXL
                    font.weight: Font.Medium
                    color: Color.mOnSurface
                    horizontalAlignment: Text.AlignLeft
                  }

                  // Date below
                  NText {
                    text: {
                      var lang = I18n.locale.name.split("_")[0]
                      var formats = {
                        "de": "dddd, d. MMMM",
                        "es": "dddd, d 'de' MMMM",
                        "fr": "dddd d MMMM",
                        "pt": "dddd, d 'de' MMMM",
                        "zh": "yyyy年M月d日 dddd"
                      }
                      return I18n.locale.toString(Time.date, formats[lang] || "dddd, MMMM d")
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

                // Clock
                ClockLoader {
                  now: Time.date
                  Layout.preferredWidth: 70
                  Layout.preferredHeight: 70
                  Layout.alignment: Qt.AlignVCenter
                  backgroundColor: Color.mSurface
                  clockColor: Color.mOnSurface
                  secondHandColor: Color.mPrimary
                }
              }
            }

            // Deprecation warning (shown above error notification)
            Rectangle {
              width: Math.min(650, parent.width - 40)
              implicitHeight: deprecationContent.implicitHeight + 24
              height: implicitHeight
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: (Settings.data.general.compactLockScreen ? 320 : 400) * Style.uiScaleRatio
              radius: Style.radiusL
              color: Qt.alpha(Color.mTertiary, 0.95)
              border.color: Color.mTertiary
              border.width: 2
              visible: lockScreen.triggeredViaDeprecatedCall
              opacity: visible ? 1.0 : 0.0

              ColumnLayout {
                id: deprecationContent
                anchors.fill: parent
                anchors.margins: 12
                spacing: 6

                RowLayout {
                  Layout.alignment: Qt.AlignHCenter
                  spacing: 8

                  NIcon {
                    icon: "alert-triangle"
                    pointSize: Style.fontSizeL
                    color: Color.mOnTertiary
                  }

                  NText {
                    text: "Deprecated IPC Call"
                    color: Color.mOnTertiary
                    pointSize: Style.fontSizeL
                    font.weight: Font.Bold
                  }
                }

                NText {
                  text: "The 'lockScreen toggle' IPC call is deprecated. Use 'lockScreen lock' instead."
                  color: Color.mOnTertiary
                  pointSize: Style.fontSizeM
                  horizontalAlignment: Text.AlignHCenter
                  Layout.alignment: Qt.AlignHCenter
                  Layout.fillWidth: true
                  wrapMode: Text.WordWrap
                }
              }

              Behavior on opacity {
                NumberAnimation {
                  duration: 300
                  easing.type: Easing.OutCubic
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
              visible: lockContext.showFailure && lockContext.errorMessage
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
                  text: lockContext.errorMessage || "Authentication failed"
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
              visible: Settings.data.general.compactLockScreen && ((UPower.displayDevice && UPower.displayDevice.ready && UPower.displayDevice.isPresent) || keyboardLayout.currentLayout !== "Unknown")

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

            // Bottom container with weather, password input and controls
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

                // Top info row
                RowLayout {
                  Layout.fillWidth: true
                  Layout.preferredHeight: 65
                  spacing: 18
                  visible: !Settings.data.general.compactLockScreen

                  // Media widget with visualizer
                  Rectangle {
                    Layout.preferredWidth: 220
                    // Expand to take remaining space when weather is hidden
                    Layout.fillWidth: !(Settings.data.location.weatherEnabled && LocationService.data.weather !== null)
                    Layout.preferredHeight: 50
                    radius: 25
                    color: Color.transparent
                    clip: true
                    visible: MediaService.currentPlayer && MediaService.canPlay

                    Loader {
                      anchors.fill: parent
                      anchors.margins: 4
                      active: Settings.data.audio.visualizerType === "linear"
                      z: 0
                      sourceComponent: LinearSpectrum {
                        anchors.fill: parent
                        values: CavaService.values
                        fillColor: Color.mPrimary
                        opacity: 0.4
                      }
                    }

                    Loader {
                      anchors.fill: parent
                      anchors.margins: 4
                      active: Settings.data.audio.visualizerType === "mirrored"
                      z: 0
                      sourceComponent: MirroredSpectrum {
                        anchors.fill: parent
                        values: CavaService.values
                        fillColor: Color.mPrimary
                        opacity: 0.4
                      }
                    }

                    Loader {
                      anchors.fill: parent
                      anchors.margins: 4
                      active: Settings.data.audio.visualizerType === "wave"
                      z: 0
                      sourceComponent: WaveSpectrum {
                        anchors.fill: parent
                        values: CavaService.values
                        fillColor: Color.mPrimary
                        opacity: 0.4
                      }
                    }

                    RowLayout {
                      anchors.fill: parent
                      anchors.margins: 8
                      spacing: 8
                      z: 1

                      Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: width * 0.5
                        color: Color.transparent
                        clip: true

                        NImageCircled {
                          anchors.fill: parent
                          anchors.margins: 2
                          imagePath: MediaService.trackArtUrl
                          fallbackIcon: "disc"
                          fallbackIconSize: Style.fontSizeM
                          borderColor: Color.mOutline
                          borderWidth: Style.borderS
                        }
                      }

                      ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        NText {
                          text: MediaService.trackTitle || "No media"
                          pointSize: Style.fontSizeM
                          font.weight: Style.fontWeightMedium
                          color: Color.mOnSurface
                          Layout.fillWidth: true
                          elide: Text.ElideRight
                        }

                        NText {
                          text: MediaService.trackArtist || ""
                          pointSize: Style.fontSizeM
                          color: Color.mOnSurfaceVariant
                          Layout.fillWidth: true
                          elide: Text.ElideRight
                        }
                      }
                    }
                  }

                  Rectangle {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    Layout.rightMargin: 4
                    color: Qt.alpha(Color.mOutline, 0.3)
                    visible: MediaService.currentPlayer && MediaService.canPlay
                  }

                  Item {
                    Layout.preferredWidth: Style.marginM
                    visible: !(MediaService.currentPlayer && MediaService.canPlay)
                  }

                  // Current weather
                  RowLayout {
                    visible: Settings.data.location.weatherEnabled && LocationService.data.weather !== null
                    Layout.preferredWidth: 180
                    spacing: 8

                    NIcon {
                      Layout.alignment: Qt.AlignVCenter
                      icon: LocationService.weatherSymbolFromCode(LocationService.data.weather.current_weather.weathercode)
                      pointSize: Style.fontSizeXXXL
                      color: Color.mPrimary
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: 2

                      RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        NText {
                          text: {
                            var temp = LocationService.data.weather.current_weather.temperature
                            var suffix = "C"
                            if (Settings.data.location.useFahrenheit) {
                              temp = LocationService.celsiusToFahrenheit(temp)
                              suffix = "F"
                            }
                            temp = Math.round(temp)
                            return temp + "°" + suffix
                          }
                          pointSize: Style.fontSizeXL
                          font.weight: Style.fontWeightBold
                          color: Color.mOnSurface
                        }

                        NText {
                          text: {
                            var wind = LocationService.data.weather.current_weather.windspeed
                            var unit = "km/h"
                            if (Settings.data.location.useFahrenheit) {
                              wind = wind * 0.621371 // Convert km/h to mph
                              unit = "mph"
                            }
                            wind = Math.round(wind)
                            return wind + " " + unit
                          }
                          pointSize: Style.fontSizeM
                          color: Color.mOnSurfaceVariant
                          font.weight: Font.Normal
                        }
                      }

                      RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        NText {
                          text: Settings.data.location.name.split(",")[0]
                          pointSize: Style.fontSizeM
                          color: Color.mOnSurfaceVariant
                        }

                        NText {
                          text: (LocationService.data.weather.current && LocationService.data.weather.current.relativehumidity_2m) ? LocationService.data.weather.current.relativehumidity_2m + "% humidity" : ""
                          pointSize: Style.fontSizeM
                          color: Color.mOnSurfaceVariant
                        }
                      }
                    }
                  }

                  // 3-day forecast
                  RowLayout {
                    visible: Settings.data.location.weatherEnabled && LocationService.data.weather !== null
                    Layout.preferredWidth: 260
                    Layout.rightMargin: 8
                    spacing: 4

                    Repeater {
                      model: 3
                      delegate: ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3

                        NText {
                          text: {
                            var weatherDate = new Date(LocationService.data.weather.daily.time[index].replace(/-/g, "/"))
                            return I18n.locale.toString(weatherDate, "ddd")
                          }
                          pointSize: Style.fontSizeM
                          color: Color.mOnSurfaceVariant
                          horizontalAlignment: Text.AlignHCenter
                          Layout.fillWidth: true
                        }

                        NIcon {
                          Layout.alignment: Qt.AlignHCenter
                          icon: LocationService.weatherSymbolFromCode(LocationService.data.weather.daily.weathercode[index])
                          pointSize: Style.fontSizeXL
                          color: Color.mOnSurfaceVariant
                        }

                        NText {
                          text: {
                            var max = LocationService.data.weather.daily.temperature_2m_max[index]
                            var min = LocationService.data.weather.daily.temperature_2m_min[index]
                            if (Settings.data.location.useFahrenheit) {
                              max = LocationService.celsiusToFahrenheit(max)
                              min = LocationService.celsiusToFahrenheit(min)
                            }
                            max = Math.round(max)
                            min = Math.round(min)
                            return max + "°/" + min + "°"
                          }
                          pointSize: Style.fontSizeM
                          font.weight: Style.fontWeightMedium
                          color: Color.mOnSurfaceVariant
                          horizontalAlignment: Text.AlignHCenter
                          Layout.fillWidth: true
                        }
                      }
                    }
                  }

                  Item {
                    Layout.fillWidth: true
                    visible: !(Settings.data.location.weatherEnabled && LocationService.data.weather !== null)
                    Layout.preferredWidth: visible ? 1 : 0
                  }

                  // Battery and Keyboard Layout (full mode only)
                  ColumnLayout {
                    Layout.preferredWidth: 60
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    spacing: 8

                    // Battery
                    RowLayout {
                      spacing: 4
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
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                      }
                    }

                    // Keyboard Layout
                    RowLayout {
                      spacing: 4
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
                        Layout.fillWidth: true
                      }
                    }
                  }
                }

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
                        enabled: !lockContext.unlockInProgress
                        font.pointSize: Style.fontSizeM
                        color: Color.mPrimary
                        echoMode: parent.parent.passwordVisible ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        passwordMaskDelay: 0
                        text: lockContext.currentText
                        onTextChanged: lockContext.currentText = text

                        Keys.onPressed: function (event) {
                          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            lockContext.tryUnlock()
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
                    color: logoutButtonArea.containsMouse ? Color.mTertiary : "transparent"
                    border.color: Color.mOutline
                    border.width: 1

                    RowLayout {
                      anchors.centerIn: parent
                      spacing: 6

                      NIcon {
                        icon: "logout"
                        pointSize: Settings.data.general.compactLockScreen ? Style.fontSizeM : Style.fontSizeL
                        color: logoutButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurfaceVariant
                      }

                      NText {
                        text: I18n.tr("session-menu.logout")
                        color: logoutButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurfaceVariant
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
