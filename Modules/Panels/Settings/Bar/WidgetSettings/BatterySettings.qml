import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Hardware
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  // Local state
  property string valueDisplayMode: widgetData.displayMode !== undefined ? widgetData.displayMode : widgetMetadata.displayMode
  property int valueWarningThreshold: widgetData.warningThreshold !== undefined ? widgetData.warningThreshold : widgetMetadata.warningThreshold
  property string valueDeviceNativePath: widgetData.deviceNativePath !== undefined ? widgetData.deviceNativePath : ""
  property bool valueShowPowerProfiles: widgetData.showPowerProfiles !== undefined ? widgetData.showPowerProfiles : widgetMetadata.showPowerProfiles
  property bool valueShowNoctaliaPerformance: widgetData.showNoctaliaPerformance !== undefined ? widgetData.showNoctaliaPerformance : widgetMetadata.showNoctaliaPerformance
  property bool valueHideIfNotDetected: widgetData.hideIfNotDetected !== undefined ? widgetData.hideIfNotDetected : widgetMetadata.hideIfNotDetected
  property bool valueHideIfIdle: widgetData.hideIfIdle !== undefined ? widgetData.hideIfIdle : widgetMetadata.hideIfIdle

  property var deviceModel: BatteryService.getDeviceOptionsModel()

  Connections {
    target: BatteryService
    function onDevicesChanged() {
      deviceModel = BatteryService.getDeviceOptionsModel();
    }
  }

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    if (widgetData && widgetData.id) {
      settings.id = widgetData.id;
    }
    settings.displayMode = valueDisplayMode;
    settings.warningThreshold = valueWarningThreshold;
    settings.showPowerProfiles = valueShowPowerProfiles;
    settings.showNoctaliaPerformance = valueShowNoctaliaPerformance;
    settings.hideIfNotDetected = valueHideIfNotDetected;
    settings.hideIfIdle = valueHideIfIdle;
    if (valueDeviceNativePath && valueDeviceNativePath !== "") {
      settings.deviceNativePath = valueDeviceNativePath;
    } else {
      delete settings.deviceNativePath;
    }
    return settings;
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    NComboBox {
      id: deviceComboBox
      Layout.fillWidth: true
      label: I18n.tr("bar.battery.device-label")
      description: I18n.tr("bar.battery.device-description")
      minimumWidth: 200
      model: root.deviceModel
      currentKey: root.valueDeviceNativePath
      onSelected: key => {
                    root.valueDeviceNativePath = key;
                    settingsChanged(saveSettings());
                  }
    }

    // Update currentKey when model changes to ensure selection is preserved
    Connections {
      target: root
      function onDeviceModelChanged() {
        // Force update of currentKey to trigger selection update
        deviceComboBox.currentKey = root.valueDeviceNativePath;
      }
    }

    NIconButton {
      icon: "refresh"
      // TODO i18n
      tooltipText: "Refresh device list"
      onClicked: deviceModel = BatteryService.getDeviceOptionsModel()
    }
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("bar.volume.display-mode-label")
    description: I18n.tr("bar.volume.display-mode-description")
    minimumWidth: 240
    model: [
      {
        "key": "onhover",
        "name": I18n.tr("display-modes.on-hover")
      },
      {
        "key": "alwaysShow",
        "name": I18n.tr("display-modes.always-show")
      },
      {
        "key": "alwaysHide",
        "name": I18n.tr("display-modes.always-hide")
      }
    ]
    currentKey: root.valueDisplayMode
    onSelected: key => {
                  root.valueDisplayMode = key;
                  settingsChanged(saveSettings());
                }
  }

  NSpinBox {
    label: I18n.tr("bar.battery.low-battery-threshold-label")
    description: I18n.tr("bar.battery.low-battery-threshold-description")
    value: valueWarningThreshold
    suffix: "%"
    minimum: 5
    maximum: 50
    onValueChanged: {
      valueWarningThreshold = value;
      settingsChanged(saveSettings());
    }
  }

  NToggle {
    label: I18n.tr("bar.battery.show-power-profile-label")
    description: I18n.tr("bar.battery.show-power-profile-description")
    checked: valueShowPowerProfiles
    onToggled: checked => {
                 valueShowPowerProfiles = checked;
                 settingsChanged(saveSettings());
               }
  }

  NToggle {
    label: I18n.tr("bar.battery.show-noctalia-performance-label")
    description: I18n.tr("bar.battery.show-noctalia-performance-description")
    checked: valueShowNoctaliaPerformance
    onToggled: checked => {
                 valueShowNoctaliaPerformance = checked;
                 settingsChanged(saveSettings());
               }
  }

  NToggle {
    label: I18n.tr("bar.battery.hide-if-not-detected-label")
    description: I18n.tr("bar.battery.hide-if-not-detected-description")
    checked: valueHideIfNotDetected
    onToggled: checked => {
                 valueHideIfNotDetected = checked;
                 settingsChanged(saveSettings());
               }
  }

  NToggle {
    label: I18n.tr("bar.battery.hide-if-idle-label")
    description: I18n.tr("bar.battery.hide-if-idle-description")
    checked: valueHideIfIdle
    onToggled: checked => {
                 valueHideIfIdle = checked;
                 settingsChanged(saveSettings());
               }
  }
}
