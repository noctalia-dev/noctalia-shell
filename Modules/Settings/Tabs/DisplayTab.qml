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

            RowLayout {
              spacing: Style.marginL * scaling
              Layout.fillWidth: true

              NText {
                text: I18n.tr("settings.display.monitors.scale")
                Layout.preferredWidth: 90 * scaling
                Layout.alignment: Qt.AlignVCenter
              }

              NValueSlider {
                id: scaleSlider
                from: 0.7
                to: 1.8
                stepSize: 0.01
                value: localScaling
                onPressedChanged: (pressed, value) => ScalingService.setScreenScale(modelData, value)
                Layout.fillWidth: true
              }

              NText {
                text: I18n.tr("system.scaling-percentage", {
                                "percentage": Math.round(scaleSlider.value * 100)
                              })
                Layout.preferredWidth: 55 * scaling
                horizontalAlignment: Text.AlignRight
                Layout.alignment: Qt.AlignVCenter
              }

              Item {
                Layout.preferredWidth: 30 * scaling
                Layout.fillHeight: true
                NIconButton {
                  icon: "refresh"
                  baseSize: Style.baseWidgetSize * 0.8
                  tooltipText: I18n.tr("settings.display.monitors.reset-scaling")
                  onClicked: ScalingService.setScreenScale(modelData, 1.0)
                  anchors.centerIn: parent
                }
              }
            }
          }

          // Brightness
          ColumnLayout {
            spacing: Style.marginS * scaling
            Layout.fillWidth: true
            visible: brightnessMonitor !== undefined && brightnessMonitor !== null

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginL * scaling

              NText {
                text: I18n.tr("settings.display.monitors.brightness")
                Layout.preferredWidth: 90 * scaling
                Layout.alignment: Qt.AlignVCenter
              }

              NValueSlider {
                id: brightnessSlider
                from: 0
                to: 1
                value: brightnessMonitor ? brightnessMonitor.brightness : 0.5
                stepSize: 0.01
                onMoved: value => {
                           if (brightnessMonitor.method === "internal") {
                             brightnessMonitor.setBrightness(value)
                           }
                         }
                onPressedChanged: (pressed, value) => brightnessMonitor.setBrightness(value)
                Layout.fillWidth: true
              }

              NText {
                text: brightnessMonitor ? Math.round(brightnessSlider.value * 100) + "%" : "N/A"
                Layout.preferredWidth: 55 * scaling
                horizontalAlignment: Text.AlignRight
                Layout.alignment: Qt.AlignVCenter
              }

              Item {
                Layout.preferredWidth: 30 * scaling
                Layout.fillHeight: true
                NIcon {
                  icon: brightnessMonitor.method == "internal" ? "device-laptop" : "device-desktop"
                  anchors.centerIn: parent
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
