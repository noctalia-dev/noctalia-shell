import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Compositor
import qs.Services.Hardware
import qs.Services.Keyboard
import qs.Services.Location
import qs.Services.Media
import qs.Widgets
import qs.Widgets.AudioSpectrum

Item {
  id: root
  anchors.fill: parent

  required property var lockContext
  required property var batteryIndicator
  required property var keyboardLayout
  required property TextInput passwordInput

  // Compact status indicators container (compact mode only)
  Rectangle {
    width: {
      var hasBattery = batteryIndicator.isReady && BatteryService.hasAnyBattery();
      var hasKeyboard = keyboardLayout.currentLayout !== "Unknown";

      if (hasBattery && hasKeyboard) {
        return 200;
      } else if (hasBattery || hasKeyboard) {
        return 120;
      } else {
        return 0;
      }
    }
    height: 40
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 96 + (Settings.data.general.compactLockScreen ? 116 : 220)
    topLeftRadius: Style.radiusL
    topRightRadius: Style.radiusL
    color: Color.mSurface
    visible: Settings.data.general.compactLockScreen && ((batteryIndicator.isReady && BatteryService.hasAnyBattery()) || keyboardLayout.currentLayout !== "Unknown")

    RowLayout {
      anchors.centerIn: parent
      spacing: Style.marginL

      // Battery indicator
      RowLayout {
        spacing: Style.marginS
        visible: batteryIndicator.isReady && BatteryService.hasAnyBattery()

        NIcon {
          icon: BatteryService.getIcon(Math.round(batteryIndicator.percent), batteryIndicator.charging, batteryIndicator.isReady)
          pointSize: Style.fontSizeM
          color: batteryIndicator.charging ? Color.mPrimary : Color.mOnSurfaceVariant
        }

        NText {
          text: Math.round(batteryIndicator.percent) + "%"
          color: Color.mOnSurfaceVariant
          pointSize: Style.fontSizeM
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
          elide: Text.ElideRight
        }
      }
    }
  }

  // Bottom container with weather, password input and controls
  Rectangle {
    id: bottomContainer

    // Support for removing the session/power buttons at the bottom.
    readonly property int deltaY: Settings.data.general.showSessionButtonsOnLockScreen ? 0 : (Settings.data.general.compactLockScreen ? 36 : 48) + 14

    height: {
      let calcHeight = Settings.data.general.compactLockScreen ? 120 : 220;
      if (!Settings.data.general.showSessionButtonsOnLockScreen) {
        calcHeight -= bottomContainer.deltaY;
      }
      return calcHeight;
    }
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 100 + bottomContainer.deltaY
    radius: Style.radiusL
    color: Color.mSurface

    width: Settings.data.general.showHibernateOnLockScreen ? 800 : 750

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 14
      spacing: Style.marginL

      // Top info row
      RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 65
        spacing: Style.marginXL
        visible: !Settings.data.general.compactLockScreen

        // Media widget with visualizer
        Item {
          Layout.preferredWidth: Style.marginM
          visible: MediaService.currentPlayer && MediaService.canPlay
        }

        Rectangle {
          Layout.preferredWidth: 220
          // Expand to take remaining space when weather is hidden
          Layout.fillWidth: !(Settings.data.location.weatherEnabled && LocationService.data.weather !== null)
          Layout.preferredHeight: 50
          radius: Style.radiusL
          color: "transparent"
          clip: true
          visible: MediaService.currentPlayer && MediaService.canPlay

          Loader {
            anchors.fill: parent
            anchors.margins: 4
            active: Settings.data.audio.visualizerType === "linear"
            z: 0
            sourceComponent: NLinearSpectrum {
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
            sourceComponent: NMirroredSpectrum {
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
            sourceComponent: NWaveSpectrum {
              anchors.fill: parent
              values: CavaService.values
              fillColor: Color.mPrimary
              opacity: 0.4
            }
          }

          RowLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: Style.marginM
            z: 1

            Rectangle {
              Layout.preferredWidth: 34
              Layout.preferredHeight: 34
              radius: Math.min(Style.radiusL, width / 2)
              color: "transparent"
              clip: true

              NImageRounded {
                anchors.fill: parent
                anchors.margins: 2
                radius: Math.min(Style.radiusL, width / 2)
                imagePath: MediaService.trackArtUrl
                fallbackIcon: "disc"
                fallbackIconSize: Style.fontSizeM
                borderColor: Color.mOutline
                borderWidth: Style.borderS
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.marginXXS

              NText {
                text: MediaService.trackTitle || "No media"
                pointSize: Style.fontSizeM
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
          spacing: Style.marginM

          NIcon {
            Layout.alignment: Qt.AlignVCenter
            icon: LocationService.weatherSymbolFromCode(LocationService.data.weather.current_weather.weathercode)
            pointSize: Style.fontSizeXXXL
            color: Color.mPrimary
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginXXS

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginL

              NText {
                text: {
                  var temp = LocationService.data.weather.current_weather.temperature;
                  var suffix = "C";
                  if (Settings.data.location.useFahrenheit) {
                    temp = LocationService.celsiusToFahrenheit(temp);
                    suffix = "F";
                  }
                  temp = Math.round(temp);
                  return temp + "°" + suffix;
                }
                pointSize: Style.fontSizeXL
                font.weight: Style.fontWeightBold
                color: Color.mOnSurface
              }

              NText {
                text: {
                  var wind = LocationService.data.weather.current_weather.windspeed;
                  var unit = "km/h";
                  if (Settings.data.location.useFahrenheit) {
                    wind = wind * 0.621371; // Convert km/h to mph
                    unit = "mph";
                  }
                  wind = Math.round(wind);
                  return wind + " " + unit;
                }
                pointSize: Style.fontSizeM
                color: Color.mOnSurfaceVariant
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginM

              NText {
                text: Settings.data.location.name.split(",")[0]
                pointSize: Style.fontSizeM
                color: Color.mOnSurfaceVariant
                visible: !Settings.data.location.hideWeatherCityName
              }

              NText {
                text: (LocationService.data.weather.current && LocationService.data.weather.current.relativehumidity_2m) ? LocationService.data.weather.current.relativehumidity_2m + "% humidity" : ""
                pointSize: Style.fontSizeM
                color: Color.mOnSurfaceVariant
              }
            }
          }
        }

        // Forecast
        RowLayout {
          visible: Settings.data.location.weatherEnabled && LocationService.data.weather !== null
          Layout.preferredWidth: 260
          Layout.rightMargin: 8
          spacing: Style.marginXS

          Repeater {
            model: MediaService.currentPlayer && MediaService.canPlay ? 2 : 4
            delegate: ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.marginXXS + 1

              NText {
                text: {
                  var weatherDate = new Date(LocationService.data.weather.daily.time[index].replace(/-/g, "/"));
                  return I18n.locale.toString(weatherDate, "ddd");
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
                  var max = LocationService.data.weather.daily.temperature_2m_max[index];
                  var min = LocationService.data.weather.daily.temperature_2m_min[index];
                  if (Settings.data.location.useFahrenheit) {
                    max = LocationService.celsiusToFahrenheit(max);
                    min = LocationService.celsiusToFahrenheit(min);
                  }
                  max = Math.round(max);
                  min = Math.round(min);
                  return max + "°/" + min + "°";
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
          Layout.fillWidth: batteryIndicator.isReady && BatteryService.hasAnyBattery()
        }

        // Battery and Keyboard Layout (full mode only)
        ColumnLayout {
          Layout.alignment: (batteryIndicator.isReady && BatteryService.hasAnyBattery()) ? (Qt.AlignRight | Qt.AlignVCenter) : Qt.AlignVCenter
          spacing: Style.marginM
          visible: (batteryIndicator.isReady && BatteryService.hasAnyBattery()) || keyboardLayout.currentLayout !== "Unknown"

          // Battery
          RowLayout {
            spacing: Style.marginXS
            visible: batteryIndicator.isReady && BatteryService.hasAnyBattery()

            NIcon {
              icon: BatteryService.getIcon(Math.round(batteryIndicator.percent), batteryIndicator.charging, batteryIndicator.isReady)
              pointSize: Style.fontSizeM
              color: batteryIndicator.charging ? Color.mPrimary : Color.mOnSurfaceVariant
            }

            NText {
              text: Math.round(batteryIndicator.percent) + "%"
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeM
            }
          }

          // Keyboard Layout
          RowLayout {
            spacing: Style.marginXS
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
              elide: Text.ElideRight
            }
          }
        }

        Item {
          Layout.preferredWidth: Style.marginM
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
          radius: Style.iRadiusL
          color: Color.mSurface
          border.color: passwordInput.activeFocus ? Color.mPrimary : Qt.alpha(Color.mOutline, 0.3)
          border.width: passwordInput.activeFocus ? 2 : 1

          property bool passwordVisible: false

          Row {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.marginL

            NIcon {
              icon: "lock"
              pointSize: Style.fontSizeL
              color: passwordInput.activeFocus ? Color.mPrimary : Color.mOnSurfaceVariant
              anchors.verticalCenter: parent.verticalCenter
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
                  spacing: Style.marginS
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
            radius: Math.min(Style.iRadiusL, width / 2)
            color: eyeButtonArea.containsMouse ? Color.mPrimary : "transparent"
            visible: passwordInput.text.length > 0
            enabled: !lockContext || !lockContext.unlockInProgress || lockContext.waitingForPassword

            NIcon {
              anchors.centerIn: parent
              icon: parent.parent.passwordVisible ? "eye-off" : "eye"
              pointSize: Style.fontSizeM
              color: eyeButtonArea.containsMouse ? Color.mOnPrimary : Color.mOnSurfaceVariant

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                  easing.type: Easing.OutCubic
                }
              }
            }

            MouseArea {
              id: eyeButtonArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: parent.parent.passwordVisible = !parent.parent.passwordVisible
            }

            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
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
            radius: Math.min(Style.iRadiusL, width / 2)
            color: submitButtonArea.containsMouse ? Color.mPrimary : "transparent"
            border.color: Color.mPrimary
            border.width: Style.borderS
            enabled: !lockContext || !lockContext.unlockInProgress || lockContext.waitingForPassword

            NIcon {
              anchors.centerIn: parent
              icon: "arrow-forward"
              pointSize: Style.fontSizeM
              color: submitButtonArea.containsMouse ? Color.mOnPrimary : Color.mPrimary

              Behavior on color {
                ColorAnimation {
                  duration: Style.animationFast
                  easing.type: Easing.OutCubic
                }
              }
            }

            MouseArea {
              id: submitButtonArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (lockContext)
                           lockContext.tryUnlock()
            }

            Behavior on color {
              ColorAnimation {
                duration: Style.animationFast
                easing.type: Easing.OutCubic
              }
            }
          }

          Behavior on border.color {
            ColorAnimation {
              duration: Style.animationFast
              easing.type: Easing.OutCubic
            }
          }
        }

        Item {
          Layout.preferredWidth: Style.marginM
        }
      }

      // Session control buttons
      RowLayout {
        id: sessionButtonRow
        Layout.fillWidth: true
        Layout.preferredHeight: Settings.data.general.compactLockScreen ? 36 : 48
        Layout.alignment: Qt.AlignHCenter
        spacing: Style.marginM
        visible: Settings.data.general.showSessionButtonsOnLockScreen

        readonly property int buttonCount: Settings.data.general.showHibernateOnLockScreen ? 5 : 4
        readonly property real availableWidth: bottomContainer.width - 48
        readonly property real buttonWidth: (availableWidth - (buttonCount - 1) * spacing) / buttonCount
        readonly property real buttonHeight: sessionButtonRow.height

        Item {
          Layout.preferredWidth: sessionButtonRow.buttonWidth
          Layout.preferredHeight: sessionButtonRow.buttonHeight

          NButton {
            anchors.fill: parent
            icon: "logout"
            text: I18n.tr("common.logout")
            outlined: true
            backgroundColor: Color.mOnSurfaceVariant
            textColor: Color.mOnPrimary
            hoverColor: Color.mPrimary
            fontSize: Settings.data.general.compactLockScreen ? Style.fontSizeS : Style.fontSizeM
            iconSize: Settings.data.general.compactLockScreen ? Style.fontSizeM : Style.fontSizeL
            horizontalAlignment: Qt.AlignHCenter
            buttonRadius: Style.radiusL
            onClicked: CompositorService.logout()
          }
        }

        Item {
          Layout.preferredWidth: sessionButtonRow.buttonWidth
          Layout.preferredHeight: sessionButtonRow.buttonHeight

          NButton {
            anchors.fill: parent
            icon: "suspend"
            text: I18n.tr("common.suspend")
            outlined: true
            backgroundColor: Color.mOnSurfaceVariant
            textColor: Color.mOnPrimary
            hoverColor: Color.mPrimary
            fontSize: Settings.data.general.compactLockScreen ? Style.fontSizeS : Style.fontSizeM
            iconSize: Settings.data.general.compactLockScreen ? Style.fontSizeM : Style.fontSizeL
            horizontalAlignment: Qt.AlignHCenter
            buttonRadius: Style.radiusL
            onClicked: CompositorService.suspend()
          }
        }

        Item {
          Layout.preferredWidth: sessionButtonRow.buttonWidth
          Layout.preferredHeight: sessionButtonRow.buttonHeight
          visible: Settings.data.general.showHibernateOnLockScreen

          NButton {
            anchors.fill: parent
            icon: "hibernate"
            text: I18n.tr("common.hibernate")
            outlined: true
            backgroundColor: Color.mOnSurfaceVariant
            textColor: Color.mOnPrimary
            hoverColor: Color.mPrimary
            fontSize: Settings.data.general.compactLockScreen ? Style.fontSizeS : Style.fontSizeM
            iconSize: Settings.data.general.compactLockScreen ? Style.fontSizeM : Style.fontSizeL
            horizontalAlignment: Qt.AlignHCenter
            buttonRadius: Style.radiusL
            onClicked: CompositorService.hibernate()
          }
        }

        Item {
          Layout.preferredWidth: sessionButtonRow.buttonWidth
          Layout.preferredHeight: sessionButtonRow.buttonHeight

          NButton {
            anchors.fill: parent
            icon: "reboot"
            text: I18n.tr("common.reboot")
            outlined: true
            backgroundColor: Color.mOnSurfaceVariant
            textColor: Color.mOnPrimary
            hoverColor: Color.mPrimary
            fontSize: Settings.data.general.compactLockScreen ? Style.fontSizeS : Style.fontSizeM
            iconSize: Settings.data.general.compactLockScreen ? Style.fontSizeM : Style.fontSizeL
            horizontalAlignment: Qt.AlignHCenter
            buttonRadius: Style.radiusL
            onClicked: CompositorService.reboot()
          }
        }

        Item {
          Layout.preferredWidth: sessionButtonRow.buttonWidth
          Layout.preferredHeight: sessionButtonRow.buttonHeight

          NButton {
            anchors.fill: parent
            icon: "shutdown"
            text: I18n.tr("common.shutdown")
            outlined: true
            backgroundColor: Color.mError
            textColor: Color.mOnError
            hoverColor: Color.mError
            fontSize: Settings.data.general.compactLockScreen ? Style.fontSizeS : Style.fontSizeM
            iconSize: Settings.data.general.compactLockScreen ? Style.fontSizeM : Style.fontSizeL
            horizontalAlignment: Qt.AlignHCenter
            buttonRadius: Style.radiusL
            onClicked: CompositorService.shutdown()
          }
        }
      }
    }
  }
}
