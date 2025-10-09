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
        ToastService.showNotice(I18n.tr("settings.display.night-light.section.label"), I18n.tr("toast.night-light.enabled"))
      } else {
        Settings.data.nightLight.enabled = false
        ToastService.showWarning(I18n.tr("settings.display.night-light.section.label"), I18n.tr("toast.night-light.not-installed"))
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  spacing: Style.marginL * scaling

  NHeader {
    label: I18n.tr("settings.display.monitors.section.label")
    description: I18n.tr("settings.display.monitors.section.description")
  }

  ColumnLayout {
    spacing: Style.marginL * scaling

    Repeater {
      model: Quickshell.screens || []
      delegate: Rectangle {
        Layout.fillWidth: true
        implicitHeight: contentCol.implicitHeight + Style.marginL * 2 * scaling
        radius: Style.radiusM * scaling
        color: Color.mSurfaceVariant
        border.color: Color.mOutline
        border.width: Math.max(1, Style.borderS * scaling)

        property real localScaling: ScalingService.getScreenScale(modelData)
        property var brightnessMonitor: BrightnessService.getMonitorForScreen(modelData)
        property real compositorScale: ScalingService.getCompositorScale(modelData.name)
        property real userAdjustment: ScalingService.getUserAdjustment(modelData.name)
        property bool hasCompositorScale: compositorScale > 0 && ScalingService.autoDetectScale

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
          width: parent.width - 2 * Style.marginL * scaling
          x: Style.marginL * scaling
          y: Style.marginL * scaling
          spacing: Style.marginXXS * scaling

          NLabel {
            label: modelData.name || "Unknown"
            description: I18n.tr("system.monitor-description", {
                                   "model": modelData.model,
                                   "width": modelData.width,
                                   "height": modelData.height
                                 })
          }

          // Scale
          ColumnLayout {
            spacing: Style.marginS * scaling
            Layout.fillWidth: true

            // Info row showing compositor scale
            RowLayout {
              spacing: Style.marginM * scaling
              Layout.fillWidth: true
              visible: hasCompositorScale

              NText {
                text: I18n.tr("settings.display.monitors.compositor-scale")
                pointSize: Style.fontSizeS * scaling
                color: Color.mOnSurfaceVariant
              }

              NText {
                text: compositorScale.toFixed(2) + "×"
                pointSize: Style.fontSizeS * scaling
                color: Color.mPrimary
                font.weight: Font.Medium
              }

              NText {
                text: I18n.tr("settings.display.monitors.user-adjustment") + ":"
                pointSize: Style.fontSizeS * scaling
                color: Color.mOnSurfaceVariant
                visible: Math.abs(userAdjustment - 1.0) > 0.01
              }

              NText {
                text: (userAdjustment > 1 ? "+" : "") + Math.round((userAdjustment - 1.0) * 100) + "%"
                pointSize: Style.fontSizeS * scaling
                color: userAdjustment > 1 ? Color.mSuccess : Color.mWarning
                font.weight: Font.Medium
                visible: Math.abs(userAdjustment - 1.0) > 0.01
              }

              Item { Layout.fillWidth: true }
            }

            RowLayout {
              spacing: Style.marginL * scaling
              Layout.fillWidth: true

              NText {
                text: I18n.tr("settings.display.monitors.scale")
                Layout.preferredWidth: 80 * scaling
              }

              NValueSlider {
                id: scaleSlider
                from: 0.5
                to: 3.0
                stepSize: 0.05
                value: localScaling
                onPressedChanged: (pressed, value) => ScalingService.setScreenScale(modelData, value)
                text: I18n.tr("system.scaling-percentage", {
                                "percentage": Math.round(localScaling * 100)
                              })
                Layout.fillWidth: true
              }

              // Reset button container
              Item {
                Layout.preferredWidth: 30 * scaling
                Layout.preferredHeight: 30 * scaling

                NIconButton {
                  icon: "refresh"
                  baseSize: Style.baseWidgetSize * 0.9
                  tooltipText: hasCompositorScale
                    ? I18n.tr("settings.display.monitors.reset-to-compositor")
                    : I18n.tr("settings.display.monitors.reset-scaling")
                  onClicked: ScalingService.setScreenScale(modelData, compositorScale > 0 ? compositorScale : 1.0)
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
              spacing: Style.marginL * scaling

              NText {
                text: I18n.tr("settings.display.monitors.brightness")
                Layout.preferredWidth: 80 * scaling
              }

              NValueSlider {
                Layout.fillWidth: true
                from: 0
                to: 1
                value: brightnessMonitor ? brightnessMonitor.brightness : 0.5
                stepSize: 0.01
                onPressedChanged: (pressed, value) => brightnessMonitor.setBrightness(value)
                text: brightnessMonitor ? Math.round(brightnessMonitor.brightness * 100) + "%" : "N/A"
              }

              // Empty container to match scale row layout
              Item {
                Layout.preferredWidth: 30 * scaling
                Layout.preferredHeight: 30 * scaling

                // Method text positioned in the button area
                NText {
                  text: brightnessMonitor ? brightnessMonitor.method : ""
                  pointSize: Style.fontSizeXS * scaling
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

    // Brightness Step
    NSpinBox {
      Layout.fillWidth: true
      label: I18n.tr("settings.display.monitors.brightness-step.label")
      description: I18n.tr("settings.display.monitors.brightness-step.description")
      minimum: 1
      maximum: 50
      value: Settings.data.brightness.brightnessStep
      stepSize: 1
      suffix: "%"
      onValueChanged: Settings.data.brightness.brightnessStep = value
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
      label: I18n.tr("settings.display.night-light.section.label")
      description: I18n.tr("settings.display.night-light.section.description")
    }
  }

  NToggle {
    label: I18n.tr("settings.display.night-light.enable.label")
    description: I18n.tr("settings.display.night-light.enable.description")
    checked: Settings.data.nightLight.enabled
    onToggled: checked => {
                 if (checked) {
                   // Verify wlsunset exists before enabling
                   wlsunsetCheck.running = true
                 } else {
                   Settings.data.nightLight.enabled = false
                   Settings.data.nightLight.forced = false
                   NightLightService.apply()
                   ToastService.showNotice(I18n.tr("settings.display.night-light.section.label"), I18n.tr("toast.night-light.disabled"))
                 }
               }
  }

  // Temperature
  ColumnLayout {
    spacing: Style.marginXS * scaling
    Layout.alignment: Qt.AlignVCenter

    NLabel {
      label: I18n.tr("settings.display.night-light.temperature.label")
      description: I18n.tr("settings.display.night-light.temperature.description")
    }

    RowLayout {
      visible: Settings.data.nightLight.enabled
      spacing: Style.marginM * scaling
      Layout.fillWidth: false
      Layout.fillHeight: true
      Layout.alignment: Qt.AlignVCenter

      NText {
        text: I18n.tr("settings.display.night-light.temperature.night")
        pointSize: Style.fontSizeM * scaling
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

      NText {
        text: I18n.tr("settings.display.night-light.temperature.day")
        pointSize: Style.fontSizeM * scaling
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
    label: I18n.tr("settings.display.night-light.auto-schedule.label")
    description: I18n.tr("settings.display.night-light.auto-schedule.description", {
                           "location": LocationService.stableName
                         })
    checked: Settings.data.nightLight.autoSchedule
    onToggled: checked => Settings.data.nightLight.autoSchedule = checked
    visible: Settings.data.nightLight.enabled
  }

  // Manual scheduling
  ColumnLayout {
    spacing: Style.marginS * scaling
    visible: Settings.data.nightLight.enabled && !Settings.data.nightLight.autoSchedule && !Settings.data.nightLight.forced

    NLabel {
      label: I18n.tr("settings.display.night-light.manual-schedule.label")
      description: I18n.tr("settings.display.night-light.manual-schedule.description")
    }

    RowLayout {
      Layout.fillWidth: false
      spacing: Style.marginS * scaling

      NText {
        text: I18n.tr("settings.display.night-light.manual-schedule.sunrise")
        pointSize: Style.fontSizeM * scaling
        color: Color.mOnSurfaceVariant
      }

      NComboBox {
        model: timeOptions
        currentKey: Settings.data.nightLight.manualSunrise
        placeholder: I18n.tr("settings.display.night-light.manual-schedule.select-start")
        onSelected: key => Settings.data.nightLight.manualSunrise = key
        minimumWidth: 120 * scaling
      }

      Item {
        Layout.preferredWidth: 20 * scaling
      }

      NText {
        text: I18n.tr("settings.display.night-light.manual-schedule.sunset")
        pointSize: Style.fontSizeM * scaling
        color: Color.mOnSurfaceVariant
      }

      NComboBox {
        model: timeOptions
        currentKey: Settings.data.nightLight.manualSunset
        placeholder: I18n.tr("settings.display.night-light.manual-schedule.select-stop")
        onSelected: key => Settings.data.nightLight.manualSunset = key
        minimumWidth: 120 * scaling
      }
    }
  }

  // Force activation toggle
  NToggle {
    label: I18n.tr("settings.display.night-light.force-activation.label")
    description: I18n.tr("settings.display.night-light.force-activation.description")
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
