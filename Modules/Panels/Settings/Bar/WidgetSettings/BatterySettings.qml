import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Services.UPower
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  // Local state
  property string valueDisplayMode: widgetData.displayMode !== undefined ? widgetData.displayMode : widgetMetadata.displayMode
  property int valueWarningThreshold: widgetData.warningThreshold !== undefined ? widgetData.warningThreshold : widgetMetadata.warningThreshold
  property string valueDeviceNativePath: widgetData.deviceNativePath !== undefined ? widgetData.deviceNativePath : ""
  property bool valueShowPowerProfiles: widgetData.showPowerProfiles !== undefined ? widgetData.showPowerProfiles : widgetMetadata.showPowerProfiles
  property bool valueShowNoctaliaPerformance: widgetData.showNoctaliaPerformance !== undefined ? widgetData.showNoctaliaPerformance : widgetMetadata.showNoctaliaPerformance
  property bool valueHideIfNotDetected: widgetData.hideIfNotDetected !== undefined ? widgetData.hideIfNotDetected : widgetMetadata.hideIfNotDetected

  // Build model of available battery devices
  function buildDeviceModel() {
    var model = [
          {
            "key": "",
            "name": I18n.tr("bar.widget-settings.battery.device.default")
          }
        ];

    if (!UPower.devices) {
      return model;
    }

    var deviceArray = UPower.devices.values || [];
    for (var i = 0; i < deviceArray.length; i++) {
      var device = deviceArray[i];
      if (!device || device.type === UPowerDeviceType.LinePower) {
        continue;
      }
      var displayName = device.model || device.nativePath || "Unknown";
      model.push({
                   "key": device.nativePath || "",
                   "name": displayName
                 });
    }
    return model;
  }

  readonly property int _deviceCount: (UPower.devices && UPower.devices.values) ? UPower.devices.values.length : 0
  property var deviceModel: buildDeviceModel()

  on_DeviceCountChanged: {
    deviceModel = buildDeviceModel();
  }

  Connections {
    target: UPower.devices
    function onValuesChanged() {
      deviceModel = buildDeviceModel();
    }
  }

  Timer {
    id: refreshTimer
    interval: 2000
    running: true
    repeat: true
    onTriggered: {
      var currentCount = (UPower.devices && UPower.devices.values) ? UPower.devices.values.length : 0;
      if (currentCount !== root._deviceCount) {
        deviceModel = buildDeviceModel();
      }
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
      label: I18n.tr("bar.widget-settings.battery.device.label")
      description: I18n.tr("bar.widget-settings.battery.device.description")
      minimumWidth: 134
      model: root.deviceModel
      currentKey: root.valueDeviceNativePath
      onSelected: key => root.valueDeviceNativePath = key
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
      tooltipText: "Refresh device list"
      onClicked: deviceModel = buildDeviceModel()
    }
  }

  NComboBox {
    label: I18n.tr("bar.widget-settings.battery.display-mode.label")
    description: I18n.tr("bar.widget-settings.battery.display-mode.description")
    minimumWidth: 134
    model: [
      {
        "key": "onhover",
        "name": I18n.tr("options.display-mode.on-hover")
      },
      {
        "key": "alwaysShow",
        "name": I18n.tr("options.display-mode.always-show")
      },
      {
        "key": "alwaysHide",
        "name": I18n.tr("options.display-mode.always-hide")
      }
    ]
    currentKey: root.valueDisplayMode
    onSelected: key => root.valueDisplayMode = key
  }

  NSpinBox {
    label: I18n.tr("bar.widget-settings.battery.low-battery-threshold.label")
    description: I18n.tr("bar.widget-settings.battery.low-battery-threshold.description")
    value: valueWarningThreshold
    suffix: "%"
    minimum: 5
    maximum: 50
    onValueChanged: valueWarningThreshold = value
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.battery.show-power-profile.label")
    description: I18n.tr("bar.widget-settings.battery.show-power-profile.description")
    checked: valueShowPowerProfiles
    onToggled: checked => valueShowPowerProfiles = checked
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.battery.show-noctalia-performance.label")
    description: I18n.tr("bar.widget-settings.battery.show-noctalia-performance.description")
    checked: valueShowNoctaliaPerformance
    onToggled: checked => valueShowNoctaliaPerformance = checked
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.battery.hide-if-not-detected.label")
    description: I18n.tr("bar.widget-settings.battery.hide-if-not-detected.description")
    checked: root.valueHideIfNotDetected
    onToggled: checked => root.valueHideIfNotDetected = checked
  }
}
