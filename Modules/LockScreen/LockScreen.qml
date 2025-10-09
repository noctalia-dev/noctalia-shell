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

  Timer {
    id: unloadAfterUnlockTimer
    interval: 250
    repeat: false
    onTriggered: lockScreen.active = false
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
          readonly property real scaling: ScalingService.dynamicScale(screen)

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
            property real cornerRadius: Style.screenRadius * scaling
            property real cornerSize: Style.screenRadius * scaling

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
              width: Math.max(500 * scaling, contentRow.implicitWidth + 24 * scaling)
              height: 120 * scaling
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.topMargin: 100 * scaling
              radius: 32 * scaling
              color: Color.mSurface
              border.color: Qt.alpha(Color.mOutline, 0.2)
              border.width: 1

              RowLayout {
                id: contentRow
                anchors.fill: parent
                anchors.margins: 12 * scaling
                spacing: 8 * scaling

                // Left side: Avatar
                Rectangle {
                  Layout.preferredWidth: 70 * scaling
                  Layout.preferredHeight: 70 * scaling
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
                    width: 66 * scaling
                    height: 66 * scaling
                    imagePath: Settings.data.general.avatarImage
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

                // Spacer to center the text section
                Item {
                  Layout.fillWidth: true
                }

                // Center: User Info Column (left-aligned text)
                ColumnLayout {
                  Layout.alignment: Qt.AlignVCenter
                  spacing: 2 * scaling

                  // Welcome back + Username on one line
                  NText {
                    text: I18n.tr("lock-screen.welcome-back") + " " + Quickshell.env("USER") + "!"
                    pointSize: Style.fontSizeXXXL * scaling
                    font.weight: Font.Medium
                    color: Color.mOnSurface
                    horizontalAlignment: Text.AlignLeft
                  }

                  // Date below
                  NText {
                    text: Qt.locale().toString(Time.date, "dddd, MMMM d")
                    pointSize: Style.fontSizeXXL * scaling
                    font.weight: Font.Medium
                    color: Color.mOnSurfaceVariant
                    horizontalAlignment: Text.AlignLeft
                  }
                }

                // Spacer to push cool time to the right
                Item {
                  Layout.fillWidth: true
                }

                // Right side: Cool Time (from Calendar)
                Item {
                  Layout.preferredWidth: 70 * scaling
                  Layout.preferredHeight: 70 * scaling
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
                      var radius = Math.min(width, height) / 2 - 3 * scaling

                      ctx.reset()

                      // Background circle
                      ctx.beginPath()
                      ctx.arc(centerX, centerY, radius, 0, 2 * Math.PI)
                      ctx.lineWidth = 2.5 * scaling
                      ctx.strokeStyle = Qt.alpha(Color.mOnSurface, 0.15)
                      ctx.stroke()

                      // Progress arc
                      ctx.beginPath()
                      ctx.arc(centerX, centerY, radius, -Math.PI / 2, -Math.PI / 2 + progress * 2 * Math.PI)
                      ctx.lineWidth = 2.5 * scaling
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
                        var t = Settings.data.location.use12hourFormat ? Qt.locale().toString(new Date(), "hh AP") : Qt.locale().toString(new Date(), "HH")
                        return t
                      }
                      pointSize: Style.fontSizeL * scaling
                      font.weight: Style.fontWeightBold
                      color: Color.mOnSurface
                      horizontalAlignment: Text.AlignHCenter
                      Layout.alignment: Qt.AlignHCenter
                    }

                    NText {
                      text: Qt.formatTime(Time.date, "mm")
                      pointSize: Style.fontSizeL * scaling
                      font.weight: Style.fontWeightBold
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
              width: 450 * scaling
              height: 60 * scaling
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 300 * scaling
              radius: 30 * scaling
              color: Color.mError
              border.color: Color.mError
              border.width: 1
              visible: lockContext.showFailure && lockContext.errorMessage
              opacity: visible ? 1.0 : 0.0

              RowLayout {
                anchors.centerIn: parent
                spacing: 10 * scaling

                NIcon {
                  icon: "alert-circle"
                  pointSize: Style.fontSizeL * scaling
                  color: Color.mOnError
                }

                NText {
                  text: lockContext.errorMessage || "Authentication failed"
                  color: Color.mOnError
                  pointSize: Style.fontSizeL * scaling
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

            // Bottom container with weather, password input and controls
            Rectangle {
              width: 750 * scaling
              height: 220 * scaling
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 100 * scaling
              radius: 32 * scaling
              color: Color.mSurface
              border.color: Qt.alpha(Color.mOutline, 0.2)
              border.width: 1

              ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14 * scaling
                spacing: 14 * scaling

                // Weather section
                RowLayout {
                  Layout.fillWidth: true
                  Layout.preferredHeight: 65 * scaling
                  spacing: 18 * scaling
                  visible: LocationService.coordinatesReady && LocationService.data.weather !== null

                  // Media widget with visualizer
                  Rectangle {
                    Layout.preferredWidth: 220 * scaling
                    Layout.preferredHeight: 50 * scaling
                    radius: 25 * scaling
                    color: Color.transparent
                    clip: true
                    visible: MediaService.currentPlayer && MediaService.canPlay

                    Loader {
                      anchors.fill: parent
                      anchors.margins: 4 * scaling
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
                      anchors.margins: 4 * scaling
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
                      anchors.margins: 4 * scaling
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
                      anchors.margins: 8 * scaling
                      spacing: 8 * scaling
                      z: 1

                      Rectangle {
                        Layout.preferredWidth: 34 * scaling
                        Layout.preferredHeight: 34 * scaling
                        radius: width * 0.5
                        color: Color.transparent
                        clip: true

                        NImageCircled {
                          anchors.fill: parent
                          anchors.margins: 2 * scaling
                          imagePath: MediaService.trackArtUrl
                          fallbackIcon: "disc"
                          fallbackIconSize: Style.fontSizeM * scaling
                          borderColor: Color.mOutline
                          borderWidth: Math.max(1, Style.borderS * scaling)
                        }
                      }

                      ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2 * scaling

                        NText {
                          text: MediaService.trackTitle || "No media"
                          pointSize: Style.fontSizeM * scaling
                          font.weight: Style.fontWeightMedium
                          color: Color.mOnSurface
                          Layout.fillWidth: true
                          elide: Text.ElideRight
                        }

                        NText {
                          text: MediaService.trackArtist || ""
                          pointSize: Style.fontSizeM * scaling
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
                    Layout.rightMargin: 4 * scaling
                    color: Qt.alpha(Color.mOutline, 0.3)
                    visible: MediaService.currentPlayer && MediaService.canPlay
                  }

                  Item {
                    Layout.preferredWidth: Style.marginM * scaling
                    visible: !(MediaService.currentPlayer && MediaService.canPlay)
                  }

                  // Current weather
                  RowLayout {
                    Layout.preferredWidth: 180 * scaling
                    spacing: 8 * scaling

                    NIcon {
                      Layout.alignment: Qt.AlignVCenter
                      icon: LocationService.weatherSymbolFromCode(LocationService.data.weather.current_weather.weathercode)
                      pointSize: Style.fontSizeXXXL * scaling
                      color: Color.mPrimary
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: 2 * scaling

                      RowLayout {
                        Layout.fillWidth: true
                        spacing: 12 * scaling

                        NText {
                          text: Math.round(LocationService.data.weather.current_weather.temperature) + "°"
                          pointSize: Style.fontSizeXL * scaling
                          font.weight: Style.fontWeightBold
                          color: Color.mOnSurface
                        }

                        NText {
                          text: LocationService.data.weather.current_weather.windspeed + " km/h"
                          pointSize: Style.fontSizeM * scaling
                          color: Color.mOnSurfaceVariant
                          font.weight: Font.Normal
                        }
                      }

                      RowLayout {
                        Layout.fillWidth: true
                        spacing: 8 * scaling

                        NText {
                          text: Settings.data.location.name.split(",")[0]
                          pointSize: Style.fontSizeM * scaling
                          color: Color.mOnSurfaceVariant
                        }

                        NText {
                          text: (LocationService.data.weather.current && LocationService.data.weather.current.relativehumidity_2m) ? LocationService.data.weather.current.relativehumidity_2m + "% humidity" : ""
                          pointSize: Style.fontSizeM * scaling
                          color: Color.mOnSurfaceVariant
                        }
                      }
                    }
                  }

                  // 3-day forecast
                  RowLayout {
                    Layout.preferredWidth: 260 * scaling
                    Layout.rightMargin: 8 * scaling
                    spacing: 4 * scaling

                    Repeater {
                      model: 3
                      delegate: ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3 * scaling

                        NText {
                          text: Qt.locale().toString(new Date(LocationService.data.weather.daily.time[index].replace(/-/g, "/")), "ddd")
                          pointSize: Style.fontSizeM * scaling
                          color: Color.mOnSurfaceVariant
                          horizontalAlignment: Text.AlignHCenter
                          Layout.fillWidth: true
                        }

                        NIcon {
                          Layout.alignment: Qt.AlignHCenter
                          icon: LocationService.weatherSymbolFromCode(LocationService.data.weather.daily.weathercode[index])
                          pointSize: Style.fontSizeXL * scaling
                          color: Color.mOnSurfaceVariant
                        }

                        NText {
                          text: Math.round(LocationService.data.weather.daily.temperature_2m_max[index]) + "°/" + Math.round(LocationService.data.weather.daily.temperature_2m_min[index]) + "°"
                          pointSize: Style.fontSizeM * scaling
                          font.weight: Style.fontWeightMedium
                          color: Color.mOnSurfaceVariant
                          horizontalAlignment: Text.AlignHCenter
                          Layout.fillWidth: true
                        }
                      }
                    }
                  }

                  // Battery and Keyboard Layout
                  ColumnLayout {
                    Layout.preferredWidth: 60 * scaling
                    spacing: 4 * scaling

                    RowLayout {
                      Layout.preferredWidth: 60 * scaling
                      Layout.preferredHeight: 22 * scaling
                      spacing: 4 * scaling
                      visible: UPower.displayDevice && UPower.displayDevice.ready && UPower.displayDevice.isPresent

                      NIcon {
                        icon: BatteryService.getIcon(Math.round(UPower.displayDevice.percentage * 100), UPower.displayDevice.state === UPowerDeviceState.Charging, true)
                        pointSize: Style.fontSizeM * scaling
                        color: UPower.displayDevice.state === UPowerDeviceState.Charging ? Color.mPrimary : Color.mOnSurfaceVariant
                      }

                      NText {
                        text: Math.round(UPower.displayDevice.percentage * 100) + "%"
                        color: Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeM * scaling
                        font.weight: Font.Medium
                      }
                    }

                    RowLayout {
                      Layout.preferredWidth: 60 * scaling
                      Layout.preferredHeight: 22 * scaling
                      spacing: 4 * scaling

                      NIcon {
                        icon: "keyboard"
                        pointSize: Style.fontSizeM * scaling
                        color: Color.mOnSurfaceVariant
                      }

                      NText {
                        text: keyboardLayout.currentLayout
                        color: Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeM * scaling
                        font.weight: Font.Medium
                      }
                    }
                  }
                }

                // Password input
                RowLayout {
                  Layout.fillWidth: true
                  spacing: 0

                  Item {
                    Layout.preferredWidth: Style.marginM * scaling
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48 * scaling
                    radius: 24 * scaling
                    color: Color.mSurface
                    border.color: passwordInput.activeFocus ? Color.mPrimary : Qt.alpha(Color.mOutline, 0.3)
                    border.width: passwordInput.activeFocus ? 2 : 1

                    Row {
                      anchors.left: parent.left
                      anchors.leftMargin: 18 * scaling
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 14 * scaling

                      NIcon {
                        icon: "lock"
                        pointSize: Style.fontSizeL * scaling
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
                        font.pointSize: Style.fontSizeM * scaling
                        color: Color.mPrimary
                        echoMode: TextInput.Password
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
                          width: 2 * scaling
                          height: 20 * scaling
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

                        Row {
                          spacing: 6 * scaling
                          visible: passwordInput.text.length > 0
                          anchors.verticalCenter: parent.verticalCenter

                          Repeater {
                            model: passwordInput.text.length

                            NIcon {
                              icon: "circle-filled"
                              pointSize: Style.fontSizeS * scaling
                              color: Color.mPrimary
                              opacity: 1.0
                            }
                          }
                        }

                        Rectangle {
                          width: 2 * scaling
                          height: 20 * scaling
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

                    Rectangle {
                      anchors.right: parent.right
                      anchors.rightMargin: 8 * scaling
                      anchors.verticalCenter: parent.verticalCenter
                      width: 36 * scaling
                      height: 36 * scaling
                      radius: width * 0.5
                      color: submitButtonArea.containsMouse ? Color.mPrimary : Qt.alpha(Color.mPrimary, 0.8)
                      border.color: Color.mPrimary
                      border.width: 1
                      enabled: !lockContext.unlockInProgress

                      NIcon {
                        anchors.centerIn: parent
                        icon: "arrow-forward"
                        pointSize: Style.fontSizeM * scaling
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
                    Layout.preferredWidth: Style.marginM * scaling
                  }
                }

                // System control buttons
                RowLayout {
                  Layout.fillWidth: true
                  Layout.preferredHeight: 48 * scaling
                  spacing: 10 * scaling

                  Item {
                    Layout.preferredWidth: Style.marginM * scaling
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48 * scaling
                    radius: 24 * scaling
                    color: logoutButtonArea.containsMouse ? Color.mTertiary : "transparent"

                    RowLayout {
                      anchors.centerIn: parent
                      spacing: 6 * scaling

                      NIcon {
                        icon: "logout"
                        pointSize: Style.fontSizeL * scaling
                        color: logoutButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurfaceVariant
                      }

                      NText {
                        text: I18n.tr("session-menu.logout")
                        color: logoutButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeM * scaling
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
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48 * scaling
                    radius: 24 * scaling
                    color: rebootButtonArea.containsMouse ? Color.mTertiary : "transparent"

                    RowLayout {
                      anchors.centerIn: parent
                      spacing: 6 * scaling

                      NIcon {
                        icon: "reboot"
                        pointSize: Style.fontSizeL * scaling
                        color: rebootButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurfaceVariant
                      }

                      NText {
                        text: I18n.tr("session-menu.reboot")
                        color: rebootButtonArea.containsMouse ? Color.mOnTertiary : Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeM * scaling
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
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48 * scaling
                    radius: 24 * scaling
                    color: shutdownButtonArea.containsMouse ? Color.mError : "transparent"
                    border.color: shutdownButtonArea.containsMouse ? Color.mError : Color.transparent
                    border.width: 1

                    RowLayout {
                      anchors.centerIn: parent
                      spacing: 6 * scaling

                      NIcon {
                        icon: "shutdown"
                        pointSize: Style.fontSizeL * scaling
                        color: shutdownButtonArea.containsMouse ? Color.mOnError : Color.mOnSurfaceVariant
                      }

                      NText {
                        text: I18n.tr("session-menu.shutdown")
                        color: shutdownButtonArea.containsMouse ? Color.mOnError : Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeM * scaling
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
                    Layout.preferredWidth: Style.marginM * scaling
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
