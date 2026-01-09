import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Location
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  property var timeOptions

  signal checkWlsunset

  NToggle {
    label: I18n.tr("panels.display.night-light-enable-label")
    description: I18n.tr("panels.display.night-light-enable-description")
    checked: Settings.data.nightLight.enabled
    onToggled: checked => {
                 if (checked) {
                   root.checkWlsunset();
                 } else {
                   Settings.data.nightLight.enabled = false;
                   Settings.data.nightLight.forced = false;
                   NightLightService.apply();
                   ToastService.showNotice(I18n.tr("common.night-light"), I18n.tr("toast.wifi.disabled"), "nightlight-off");
                 }
               }
  }

  ColumnLayout {
    enabled: Settings.data.nightLight.enabled
    spacing: Style.marginL
    Layout.fillWidth: true

    NLabel {
      label: I18n.tr("panels.display.night-light-temperature-night")
      description: I18n.tr("panels.display.night-light-temperature-night-description")
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

    NLabel {
      label: I18n.tr("panels.display.night-light-temperature-day")
      description: I18n.tr("panels.display.night-light-temperature-day-description")
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

    NToggle {
      label: I18n.tr("panels.display.night-light-auto-schedule-label")
      description: I18n.tr("panels.display.night-light-auto-schedule-description", {
                             "location": LocationService.stableName
                           })
      checked: Settings.data.nightLight.autoSchedule
      onToggled: checked => Settings.data.nightLight.autoSchedule = checked
    }

    ColumnLayout {
      spacing: Style.marginS
      Layout.fillWidth: true
      visible: !Settings.data.nightLight.autoSchedule && !Settings.data.nightLight.forced

      NLabel {
        label: I18n.tr("panels.display.night-light-manual-schedule-label")
        description: I18n.tr("panels.display.night-light-manual-schedule-description")
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NText {
          text: I18n.tr("panels.display.night-light-manual-schedule-sunrise")
          pointSize: Style.fontSizeM
          color: Color.mOnSurfaceVariant
          Layout.alignment: Qt.AlignVCenter
        }

        NComboBox {
          model: root.timeOptions
          currentKey: Settings.data.nightLight.manualSunrise
          placeholder: I18n.tr("panels.display.night-light-manual-schedule-select-start")
          onSelected: key => Settings.data.nightLight.manualSunrise = key
          Layout.fillWidth: true
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NText {
          text: I18n.tr("panels.display.night-light-manual-schedule-sunset")
          pointSize: Style.fontSizeM
          color: Color.mOnSurfaceVariant
          Layout.alignment: Qt.AlignVCenter
        }

        NComboBox {
          model: root.timeOptions
          currentKey: Settings.data.nightLight.manualSunset
          placeholder: I18n.tr("panels.display.night-light-manual-schedule-select-stop")
          onSelected: key => Settings.data.nightLight.manualSunset = key
          Layout.fillWidth: true
        }
      }
    }

    NToggle {
      label: I18n.tr("panels.display.night-light-force-activation-label")
      description: I18n.tr("panels.display.night-light-force-activation-description")
      checked: Settings.data.nightLight.forced
      onToggled: checked => {
                   Settings.data.nightLight.forced = checked;
                   if (checked && !Settings.data.nightLight.enabled) {
                     root.checkWlsunset();
                   } else {
                     NightLightService.apply();
                   }
                 }
    }
  }
}
