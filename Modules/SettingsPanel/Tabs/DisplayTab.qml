import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root

  // Time dropdown options (00:00 .. 23:30)
  ListModel {
    id: timeOptions
  }
  Component.onCompleted: {
    for (var h = 0; h < 24; h++) {
      for (var m = 0; m < 60; m += 30) {
        var hh = ("0" + h).slice(-2)
        var mm = ("0" + m).slice(-2)
        var key = hh + ":" + mm
        timeOptions.append({
                             "key": key,
                             "name": key
                           })
      }
    }
  }

  // Check for wlsunset availability when enabling Night Light
  Process {
    id: wlsunsetCheck
    command: ["which", "wlsunset"]
    running: false

    onExited: function (exitCode) {
      if (exitCode === 0) {
        Settings.data.nightLight.enabled = true
        NightLightService.apply()
        ToastService.showNotice("Night light", "Enabled")
      } else {
        Settings.data.nightLight.enabled = false
        ToastService.showWarning("Night light", "wlsunset not installed")
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  spacing: Style.marginL * scaling

  NHeader {
    label: "Per-monitor settings"
    description: "Adjust scaling and brightness for each display."
  }

  ColumnLayout {
    spacing: Style.marginL * scaling

    Repeater {
      model: Quickshell.screens || []
      delegate: Rectangle {
        Layout.fillWidth: true
        implicitHeight: contentCol.implicitHeight + Style.marginXL * 2 * scaling
        radius: Style.radiusM * scaling
        color: Color.mSurfaceVariant
        border.color: Color.mOutline
        border.width: Math.max(1, Style.borderS * scaling)

        property real localScaling: ScalingService.getScreenScale(modelData)
        property var brightnessMonitor: BrightnessService.getMonitorForScreen(modelData)

        Connections {
          target: ScalingService
          function onScaleChanged(screenName, scale) {
            if (screenName === modelData.name) {
              localScaling = scale
            }
          }
        }

        ColumnLayout {
          id: contentCol
          anchors.fill: parent
          anchors.margins: Style.marginL * scaling
          spacing: Style.marginXXS * scaling

          NLabel {
            label: modelData.name || "Unknown"
            description: `${modelData.model} (${modelData.width}x${modelData.height})`
          }

          // Scale
          ColumnLayout {
            spacing: Style.marginS * scaling
            Layout.fillWidth: true

            RowLayout {
              spacing: Style.marginM * scaling
              Layout.fillWidth: true

              NText {
                text: "Scale"
                Layout.preferredWidth: 80 * scaling
              }

              NValueSlider {
                id: scaleSlider
                from: 0.7
                to: 1.8
                stepSize: 0.01
                value: localScaling
                onPressedChanged: (pressed, value) => ScalingService.setScreenScale(modelData, value)
                text: `${Math.round(localScaling * 100)}%`
                Layout.fillWidth: true
              }

              // Reset button container
              Item {
                Layout.preferredWidth: 40 * scaling
                Layout.preferredHeight: 30 * scaling

                NIconButton {
                  icon: "refresh"
                  baseSize: Style.baseWidgetSize * 0.9
                  tooltipText: "Reset scaling"
                  onClicked: ScalingService.setScreenScale(modelData, 1.0)
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                }
              }
            }
          }

          // Brightness
          ColumnLayout {
            spacing: Style.marginL * scaling
            Layout.fillWidth: true
            visible: brightnessMonitor !== undefined && brightnessMonitor !== null

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginM * scaling

              NText {
                text: "Brightness"
                Layout.preferredWidth: 80 * scaling
              }

              NValueSlider {
                Layout.fillWidth: true
                from: 0
                to: 1
                value: brightnessMonitor ? brightnessMonitor.brightness : 0.5
                stepSize: 0.01
                onPressedChanged: (pressed, value) => brightnessMonitor.setBrightness(value)
                text: brightnessMonitor ? Math.round(brightnessMonitor.brightness * 100) + "% " : "N/A"
              }

              // Empty container to match scale row layout
              Item {
                Layout.preferredWidth: 40 * scaling
                Layout.preferredHeight: 30 * scaling

                // Method text positioned in the button area
                NText {
                  text: brightnessMonitor ? brightnessMonitor.method : ""
                  font.pointSize: Style.fontSizeXS * scaling
                  color: Color.mOnSurfaceVariant
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  horizontalAlignment: Text.AlignRight
                }
              }
            }
          }
        }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }

  // Brightness Section
  ColumnLayout {
    spacing: Style.marginS * scaling
    Layout.fillWidth: true

    NHeader {
      label: "Brightness"
      description: "Adjust brightness related settings."
    }

    // Brightness Step Section
    ColumnLayout {
      spacing: Style.marginS * scaling
      Layout.fillWidth: true

      NSpinBox {
        Layout.fillWidth: true
        label: "Brightness step size"
        description: "Adjust the step size for brightness changes (scroll wheel and keyboard shortcuts)."
        minimum: 1
        maximum: 50
        value: Settings.data.brightness.brightnessStep
        stepSize: 1
        suffix: "%"
        onValueChanged: Settings.data.brightness.brightnessStep = value
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }

  // Night Light Section
  ColumnLayout {
    spacing: Style.marginXS * scaling
    Layout.fillWidth: true

    NHeader {
      label: "Night light"
      description: "Reduce blue light emission to help you sleep better and reduce eye strain."
    }
  }

  NToggle {
    label: "Enable night light"
    description: "Apply a warm color filter to reduce blue light emission."
    checked: Settings.data.nightLight.enabled
    onToggled: checked => {
                 if (checked) {
                   // Verify wlsunset exists before enabling
                   wlsunsetCheck.running = true
                 } else {
                   Settings.data.nightLight.enabled = false
                   Settings.data.nightLight.forced = false
                   NightLightService.apply()
                   ToastService.showNotice("Night light", "Disabled")
                 }
               }
  }

  // Temperature
  ColumnLayout {
    spacing: Style.marginXS * scaling
    Layout.alignment: Qt.AlignVCenter

    NLabel {
      label: "Color temperature"
      description: "Set the color warmth for nighttime and daytime."
    }

    RowLayout {
      visible: Settings.data.nightLight.enabled
      spacing: Style.marginM * scaling
      Layout.fillWidth: false
      Layout.fillHeight: true
      Layout.alignment: Qt.AlignVCenter

      NText {
        text: "Night"
        font.pointSize: Style.fontSizeM * scaling
        color: Color.mOnSurfaceVariant
        Layout.alignment: Qt.AlignVCenter
      }

      NTextInput {
        text: Settings.data.nightLight.nightTemp
        inputMethodHints: Qt.ImhDigitsOnly
        Layout.alignment: Qt.AlignVCenter
        onEditingFinished: {
          var nightTemp = parseInt(text)
          var dayTemp = parseInt(Settings.data.nightLight.dayTemp)
          if (!isNaN(nightTemp) && !isNaN(dayTemp)) {
            // Clamp value between [1000 .. (dayTemp-500)]
            var clampedValue = Math.min(dayTemp - 500, Math.max(1000, nightTemp))
            text = Settings.data.nightLight.nightTemp = clampedValue.toString()
          }
        }
      }

      Item {}

      NText {
        text: "Day"
        font.pointSize: Style.fontSizeM * scaling
        color: Color.mOnSurfaceVariant
        Layout.alignment: Qt.AlignVCenter
      }
      NTextInput {
        text: Settings.data.nightLight.dayTemp
        inputMethodHints: Qt.ImhDigitsOnly
        Layout.alignment: Qt.AlignVCenter
        onEditingFinished: {
          var dayTemp = parseInt(text)
          var nightTemp = parseInt(Settings.data.nightLight.nightTemp)
          if (!isNaN(nightTemp) && !isNaN(dayTemp)) {
            // Clamp value between [(nightTemp+500) .. 6500]
            var clampedValue = Math.max(nightTemp + 500, Math.min(6500, dayTemp))
            text = Settings.data.nightLight.dayTemp = clampedValue.toString()
          }
        }
      }
    }
  }

  NToggle {
    label: "Automatic scheduling"
    description: `Based on the sunset and sunrise time in <i>${LocationService.stableName}</i> - recommended.`
    checked: Settings.data.nightLight.autoSchedule
    onToggled: checked => Settings.data.nightLight.autoSchedule = checked
    visible: Settings.data.nightLight.enabled
  }

  // Schedule settings
  ColumnLayout {
    spacing: Style.marginXS * scaling
    visible: Settings.data.nightLight.enabled && !Settings.data.nightLight.autoSchedule && !Settings.data.nightLight.forced

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM * scaling

      NLabel {
        label: "Manual scheduling"
        description: "Edit sunrise and sunset manually."
      }

      NComboBox {
        model: timeOptions
        currentKey: Settings.data.nightLight.manualSunrise
        placeholder: "Select start time"
        onSelected: key => Settings.data.nightLight.manualSunrise = key
        minimumWidth: 120 * scaling
      }

      NComboBox {
        model: timeOptions
        currentKey: Settings.data.nightLight.manualSunset
        placeholder: "Select stop time"
        onSelected: key => Settings.data.nightLight.manualSunset = key
        minimumWidth: 120 * scaling
      }
    }
  }

  // Force activation toggle
  NToggle {
    label: "Force activation"
    description: "Ignores the schedule and applies the night filter immediately."
    checked: Settings.data.nightLight.forced
    onToggled: checked => {
                 Settings.data.nightLight.forced = checked
                 if (checked && !Settings.data.nightLight.enabled) {
                   // Ensure enabled when forcing
                   wlsunsetCheck.running = true
                 } else {
                   NightLightService.apply()
                 }
               }
    visible: Settings.data.nightLight.enabled
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }
}
