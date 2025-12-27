import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.Compositor
import qs.Services.Hardware
import qs.Services.Location
import qs.Services.UI
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
        var hh = ("0" + h).slice(-2);
        var mm = ("0" + m).slice(-2);
        var key = hh + ":" + mm;
        timeOptions.append({
                             "key": key,
                             "name": key
                           });
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
        Settings.data.nightLight.enabled = true;
        NightLightService.apply();
        ToastService.showNotice(I18n.tr("settings.display.night-light.section.label"), I18n.tr("toast.night-light.enabled"), "nightlight-on");
      } else {
        Settings.data.nightLight.enabled = false;
        ToastService.showWarning(I18n.tr("settings.display.night-light.section.label"), I18n.tr("toast.night-light.not-installed"));
      }
    }

    stdout: StdioCollector {}
    stderr: StdioCollector {}
  }

  spacing: Style.marginL

  NHeader {
    label: I18n.tr("settings.display.monitors.section.label")
    description: I18n.tr("settings.display.monitors.section.description")
  }

  ColumnLayout {
    spacing: Style.marginL

    Repeater {
      model: Quickshell.screens || []
      delegate: Rectangle {
        Layout.fillWidth: true
        implicitHeight: contentCol.implicitHeight + Style.marginL * 2
        radius: Style.radiusM
        color: Color.mSurfaceVariant
        border.color: Color.mOutline
        border.width: Style.borderS

        property var brightnessMonitor: BrightnessService.getMonitorForScreen(modelData)

        ColumnLayout {
          id: contentCol
          width: parent.width - 2 * Style.marginL
          x: Style.marginL
          y: Style.marginL
          spacing: Style.marginXXS

          NLabel {
            label: modelData.name || "Unknown"
            description: {
              const compositorScale = CompositorService.getDisplayScale(modelData.name);
              I18n.tr("system.monitor-description", {
                        "model": modelData.model,
                        "width": modelData.width * compositorScale,
                        "height": modelData.height * compositorScale,
                        "scale": compositorScale
                      });
            }
          }

          // Brightness
          ColumnLayout {
            spacing: Style.marginS
            Layout.fillWidth: true
            visible: brightnessMonitor !== undefined && brightnessMonitor !== null

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginL

              NText {
                text: I18n.tr("settings.display.monitors.brightness")
                Layout.preferredWidth: 90
                Layout.alignment: Qt.AlignVCenter
              }

              NValueSlider {
                id: brightnessSlider
                from: 0
                to: 1
                value: brightnessMonitor ? brightnessMonitor.brightness : 0.5
                stepSize: 0.01
                enabled: brightnessMonitor ? brightnessMonitor.brightnessControlAvailable : false
                onMoved: value => {
                           if (brightnessMonitor && brightnessMonitor.brightnessControlAvailable) {
                             brightnessMonitor.setBrightness(value);
                           }
                         }
                onPressedChanged: (pressed, value) => {
                                    if (brightnessMonitor && brightnessMonitor.brightnessControlAvailable) {
                                      brightnessMonitor.setBrightness(value);
                                    }
                                  }
                Layout.fillWidth: true
              }

              NText {
                text: brightnessMonitor ? Math.round(brightnessSlider.value * 100) + "%" : "N/A"
                Layout.preferredWidth: 55
                horizontalAlignment: Text.AlignRight
                Layout.alignment: Qt.AlignVCenter
                opacity: brightnessMonitor && !brightnessMonitor.brightnessControlAvailable ? 0.5 : 1.0
              }

              Item {
                Layout.preferredWidth: 30
                Layout.fillHeight: true
                NIcon {
                  icon: brightnessMonitor && brightnessMonitor.method == "internal" ? "device-laptop" : "device-desktop"
                  anchors.centerIn: parent
                  opacity: brightnessMonitor && !brightnessMonitor.brightnessControlAvailable ? 0.5 : 1.0
                }
              }
            }

            // Show message when brightness control is not available
            NText {
              visible: brightnessMonitor && !brightnessMonitor.brightnessControlAvailable
              text: !Settings.data.brightness.enableDdcSupport ? I18n.tr("settings.display.monitors.brightness-unavailable.ddc-disabled") : I18n.tr("settings.display.monitors.brightness-unavailable.generic")
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
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
      isSettings: true
      defaultValue: Settings.getDefaultValue("brightness.brightnessStep")
    }

    NToggle {
      Layout.fillWidth: true
      label: I18n.tr("settings.display.monitors.enforce-minimum.label")
      description: I18n.tr("settings.display.monitors.enforce-minimum.description")
      checked: Settings.data.brightness.enforceMinimum
      onToggled: checked => Settings.data.brightness.enforceMinimum = checked
      isSettings: true
      defaultValue: Settings.getDefaultValue("brightness.enforceMinimum")
    }

    NToggle {
      Layout.fillWidth: true
      label: I18n.tr("settings.display.monitors.external-brightness.label")
      description: I18n.tr("settings.display.monitors.external-brightness.description")
      checked: Settings.data.brightness.enableDdcSupport
      onToggled: checked => {
                   Settings.data.brightness.enableDdcSupport = checked;
                   // DDC detection will run on next monitor change when enabled
                   // Monitors will stop using DDC immediately when disabled
                 }
      isSettings: true
      defaultValue: Settings.getDefaultValue("brightness.enableDdcSupport")
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // Night Light Section
  ColumnLayout {
    spacing: Style.marginXS
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
                   wlsunsetCheck.running = true;
                 } else {
                   Settings.data.nightLight.enabled = false;
                   Settings.data.nightLight.forced = false;
                   NightLightService.apply();
                   ToastService.showNotice(I18n.tr("settings.display.night-light.section.label"), I18n.tr("toast.night-light.disabled"), "nightlight-off");
                 }
               }
  }

  // Temperature
  ColumnLayout {
    visible: Settings.data.nightLight.enabled
    spacing: Style.marginM
    Layout.fillWidth: true

    // Night temperature
    NLabel {
      label: I18n.tr("settings.display.night-light.temperature.night")
      description: I18n.tr("settings.display.night-light.temperature.night-description")
      Layout.fillWidth: true
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NSlider {
        id: nightSlider
        Layout.fillWidth: true

        from: 1000
        to: 6500
        value: Settings.data.nightLight.nightTemp

        // Clamp as the thumb moves, but do NOT change Settings here
        onValueChanged: {
          var dayTemp = parseInt(Settings.data.nightLight.dayTemp);
          var v = Math.round(value);

          if (!isNaN(dayTemp)) {
            var maxNight = dayTemp - 500;
            v = Math.min(maxNight, Math.max(1000, v));
          } else {
            v = Math.max(1000, v);
          }

          if (v !== value)
            value = v;
        }

        // Only write back to Settings when the user releases the slider
        onPressedChanged: {
          if (!pressed) {
            var dayTemp = parseInt(Settings.data.nightLight.dayTemp);
            var v = Math.round(value);

            if (!isNaN(dayTemp)) {
              var maxNight = dayTemp - 500;
              v = Math.min(maxNight, Math.max(1000, v));
            } else {
              v = Math.max(1000, v);
            }

            Settings.data.nightLight.nightTemp = v;
          }
        }
      }

      NText {
        text: nightSlider.value + "K"
        pointSize: Style.fontSizeM
        color: Color.mOnSurfaceVariant
        Layout.alignment: Qt.AlignVCenter
      }
    }

    // Day temperature
    NLabel {
      label: I18n.tr("settings.display.night-light.temperature.day")
      description: I18n.tr("settings.display.night-light.temperature.day-description")
      Layout.fillWidth: true
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NSlider {
        id: daySlider
        Layout.fillWidth: true

        from: 1000
        to: 6500
        value: Settings.data.nightLight.dayTemp

        // Clamp as the thumb moves, but do NOT change Settings here
        onValueChanged: {
          var nightTemp = parseInt(Settings.data.nightLight.nightTemp);
          var v = Math.round(value);

          if (!isNaN(nightTemp)) {
            var minDay = nightTemp + 500;
            v = Math.max(minDay, Math.min(6500, v));
          } else {
            v = Math.min(6500, v);
          }

          if (v !== value)
            value = v;
        }

        // Only write back to Settings when the user releases the slider
        onPressedChanged: {
          if (!pressed) {
            var nightTemp = parseInt(Settings.data.nightLight.nightTemp);
            var v = Math.round(value);

            if (!isNaN(nightTemp)) {
              var minDay = nightTemp + 500;
              v = Math.max(minDay, Math.min(6500, v));
            } else {
              v = Math.min(6500, v);
            }

            Settings.data.nightLight.dayTemp = v;
          }
        }
      }

      NText {
        text: daySlider.value + "K"
        pointSize: Style.fontSizeM
        color: Color.mOnSurfaceVariant
        Layout.alignment: Qt.AlignVCenter
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
    spacing: Style.marginS
    Layout.fillWidth: true
    visible: Settings.data.nightLight.enabled && !Settings.data.nightLight.autoSchedule && !Settings.data.nightLight.forced

    NLabel {
      label: I18n.tr("settings.display.night-light.manual-schedule.label")
      description: I18n.tr("settings.display.night-light.manual-schedule.description")
    }

    // Sunrise time
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NText {
        text: I18n.tr("settings.display.night-light.manual-schedule.sunrise")
        pointSize: Style.fontSizeM
        color: Color.mOnSurfaceVariant
        Layout.alignment: Qt.AlignVCenter
      }

      NComboBox {
        model: timeOptions
        currentKey: Settings.data.nightLight.manualSunrise
        placeholder: I18n.tr("settings.display.night-light.manual-schedule.select-start")
        onSelected: key => Settings.data.nightLight.manualSunrise = key
        Layout.fillWidth: true
      }
    }

    // Sunset time
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NText {
        text: I18n.tr("settings.display.night-light.manual-schedule.sunset")
        pointSize: Style.fontSizeM
        color: Color.mOnSurfaceVariant
        Layout.alignment: Qt.AlignVCenter
      }

      NComboBox {
        model: timeOptions
        currentKey: Settings.data.nightLight.manualSunset
        placeholder: I18n.tr("settings.display.night-light.manual-schedule.select-stop")
        onSelected: key => Settings.data.nightLight.manualSunset = key
        Layout.fillWidth: true
      }
    }
  }

  // Force activation toggle
  NToggle {
    label: I18n.tr("settings.display.night-light.force-activation.label")
    description: I18n.tr("settings.display.night-light.force-activation.description")
    checked: Settings.data.nightLight.forced
    onToggled: checked => {
                 Settings.data.nightLight.forced = checked;
                 if (checked && !Settings.data.nightLight.enabled) {
                   // Ensure enabled when forcing
                   wlsunsetCheck.running = true;
                 } else {
                   NightLightService.apply();
                 }
               }
    visible: Settings.data.nightLight.enabled
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }
}
