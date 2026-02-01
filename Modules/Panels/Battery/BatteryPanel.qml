import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Hardware
import qs.Services.Networking
import qs.Services.Power
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(440 * Style.uiScaleRatio)
  preferredHeight: Math.round(460 * Style.uiScaleRatio)

  onOpened: {
    BatteryService.refreshHealth();
  }

  panelContent: Item {
    id: panelContent
    property real contentPreferredHeight: mainLayout.implicitHeight + Style.marginL * 2

    readonly property string deviceNativePath: resolveWidgetSetting("deviceNativePath", "__default__")
    readonly property var selectedBattery: BatteryService.findUPowerDevice(deviceNativePath)
    readonly property var selectedBluetoothDevice: BatteryService.findBluetoothDevice(deviceNativePath)
    readonly property var selectedDevice: {
      if (BatteryService.isDevicePresent(selectedBluetoothDevice)) {
        return selectedBluetoothDevice;
      }
      if (BatteryService.isDevicePresent(selectedBattery)) {
        return selectedBattery;
      }
      return null;
    }

    // Check if selected device is actually present/connected
    readonly property bool isPresent: BatteryService.isDevicePresent(selectedDevice)
    readonly property bool isReady: BatteryService.isDeviceReady(selectedDevice)

    readonly property int percent: isReady ? Math.round(BatteryService.getPercentage(selectedDevice)) : -1
    readonly property bool isCharging: isReady ? BatteryService.isCharging(selectedDevice) : false
    readonly property bool isPluggedIn: isReady ? BatteryService.isPluggedIn(selectedDevice) : false
    readonly property bool healthAvailable: (isReady && selectedBattery && selectedBattery.healthSupported) || (selectedBattery && BatteryService.healthAvailable)
    readonly property int healthPercent: (isReady && selectedBattery && selectedBattery.healthSupported) ? Math.round(selectedBattery.healthPercentage) : BatteryService.healthPercent

    readonly property string deviceName: BatteryService.getDeviceName(selectedDevice)
    readonly property string panelTitle: deviceName ? `${deviceName}` : I18n.tr("common.battery")

    readonly property var allDevices: {
      var list = [];
      var seenPaths = new Set();

      // Add UPower batteries
      if (UPower.devices) {
        var upowerArray = UPower.devices.values || [];
        for (var i = 0; i < upowerArray.length; i++) {
          var d = upowerArray[i];
          if (BatteryService.isDevicePresent(d) && d.type === UPowerDeviceType.Battery) {
            if (d.nativePath && !seenPaths.has(d.nativePath)) {
              list.push(d);
              seenPaths.add(d.nativePath);
            }
          }
        }
      }
      // Add Bluetooth batteries
      if (BluetoothService.devices) {
        var btArray = BluetoothService.devices.values || [];
        for (var j = 0; j < btArray.length; j++) {
          var btd = btArray[j];
          if (BatteryService.isDevicePresent(btd) && btd.batteryAvailable) {
            // Bluetooth devices use address as unique ID
            if (btd.address && !seenPaths.has(btd.address)) {
              list.push(btd);
              seenPaths.add(btd.address);
            }
          }
        }
      }

      // Fallback: if no specific batteries found but display device is a battery, use it
      if (list.length === 0 && UPower.displayDevice && UPower.displayDevice.type === UPowerDeviceType.Battery && BatteryService.isDevicePresent(UPower.displayDevice)) {
        list.push(UPower.displayDevice);
      }

      return list;
    }

    readonly property var laptopBatteries: allDevices.filter(d => !BatteryService.isBluetoothDevice(d))
    readonly property var otherDevices: allDevices.filter(d => BatteryService.isBluetoothDevice(d))

    readonly property string iconName: BatteryService.getIcon(percent, isCharging, isPluggedIn, isReady)

    property var batteryWidgetInstance: BarService.lookupWidget("Battery", screen ? screen.name : null)
    readonly property var batteryWidgetSettings: batteryWidgetInstance ? batteryWidgetInstance.widgetSettings : null
    readonly property var batteryWidgetMetadata: BarWidgetRegistry.widgetMetadata["Battery"]
    readonly property bool powerProfileAvailable: PowerProfileService.available
    readonly property var powerProfiles: [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
    readonly property bool profilesAvailable: PowerProfileService.available
    property int profileIndex: profileToIndex(PowerProfileService.profile)
    readonly property bool showPowerProfiles: resolveWidgetSetting("showPowerProfiles", false)
    readonly property bool showNoctaliaPerformance: resolveWidgetSetting("showNoctaliaPerformance", false)

    function profileToIndex(p) {
      return powerProfiles.indexOf(p) ?? 1;
    }

    function indexToProfile(idx) {
      return powerProfiles[idx] ?? PowerProfile.Balanced;
    }

    function setProfileByIndex(idx) {
      var prof = indexToProfile(idx);
      profileIndex = idx;
      PowerProfileService.setProfile(prof);
    }

    function resolveWidgetSetting(key, defaultValue) {
      if (batteryWidgetSettings && batteryWidgetSettings[key] !== undefined)
        return batteryWidgetSettings[key];
      if (batteryWidgetMetadata && batteryWidgetMetadata[key] !== undefined)
        return batteryWidgetMetadata[key];
      return defaultValue;
    }

    Connections {
      target: PowerProfileService
      function onProfileChanged() {
        panelContent.profileIndex = panelContent.profileToIndex(PowerProfileService.profile);
      }
    }

    Connections {
      target: BarService
      function onActiveWidgetsChanged() {
        panelContent.batteryWidgetInstance = BarService.lookupWidget("Battery", screen ? screen.name : null);
      }
    }

    ColumnLayout {
      id: mainLayout
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // HEADER
      NBox {
        Layout.fillWidth: true
        implicitHeight: headerRow.implicitHeight + (Style.marginXL)

        RowLayout {
          id: headerRow
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          NIcon {
            pointSize: Style.fontSizeXXL
            color: (isCharging || isPluggedIn) ? Color.mPrimary : Color.mOnSurface
            icon: iconName
          }

          ColumnLayout {
            spacing: Style.marginXXS
            Layout.fillWidth: true

            NText {
              text: panelTitle
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
              Layout.fillWidth: true
              elide: Text.ElideRight
            }

            NText {
              text: BatteryService.getTimeRemainingText(selectedDevice)
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
              wrapMode: Text.Wrap
              Layout.fillWidth: true
            }
          }

          NIconButton {
            icon: "close"
            tooltipText: I18n.tr("common.close")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: root.close()
          }
        }
      }

      // Charge level + health/time
      NBox {
        Layout.fillWidth: true
        implicitHeight: chargeLayout.implicitHeight + Style.marginL * 2
        visible: allDevices.length > 0

        ColumnLayout {
          id: chargeLayout
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginL

          // Laptop batteries section
          Repeater {
            model: laptopBatteries
            delegate: ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.marginS

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS

                  RowLayout {
                    NIcon {
                      color: (isCharging || isPluggedIn) ? Color.mPrimary : Color.mOnSurface
                      icon: iconName
                    }

                    NText {
                      readonly property string dName: BatteryService.getDeviceName(modelData)
                      text: dName ? dName : I18n.tr("common.battery")
                      color: Color.mOnSurface
                      pointSize: Style.fontSizeS
                    }
                  }

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS
                    Rectangle {
                      Layout.fillWidth: true
                      height: Math.round(8 * Style.uiScaleRatio)
                      radius: Math.min(Style.radiusL, height / 2)
                      color: Color.mSurface

                      Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height
                        radius: parent.radius
                        width: {
                          var p = BatteryService.getPercentage(modelData);
                          var ratio = Math.max(0, Math.min(1, p / 100));
                          return parent.width * ratio;
                        }
                        color: Color.mPrimary
                      }
                    }
                    NText {
                      Layout.preferredWidth: 40 * Style.uiScaleRatio
                      horizontalAlignment: Text.AlignRight
                      text: `${Math.round(BatteryService.getPercentage(modelData))}%`
                      color: Color.mOnSurface
                      pointSize: Style.fontSizeS
                      font.weight: Style.fontWeightBold
                    }
                  }
                }
              }

              // Health for this specific laptop battery
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginS
                visible: modelData.healthSupported || (modelData === selectedBattery && BatteryService.healthAvailable)
                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS

                  NIcon {
                    icon: "heart"
                  }

                  NText {
                    text: I18n.tr("battery.battery-health")
                    color: Color.mOnSurface
                    pointSize: Style.fontSizeS
                  }
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS

                  Rectangle {
                    Layout.fillWidth: true
                    height: Math.round(8 * Style.uiScaleRatio)
                    radius: height / 2
                    color: Color.mSurface

                    Rectangle {
                      anchors.verticalCenter: parent.verticalCenter
                      height: parent.height
                      radius: parent.radius
                      width: {
                        var h = modelData.healthSupported ? modelData.healthPercentage : (modelData === selectedBattery ? BatteryService.healthPercent : 0);
                        if (h <= 0)
                          return 0;
                        var ratio = Math.max(0, Math.min(1, h / 100));
                        return parent.width * ratio;
                      }
                      color: {
                        var h = modelData.healthSupported ? modelData.healthPercentage : (modelData === selectedBattery ? BatteryService.healthPercent : 0);
                        return h >= 80 ? Color.mPrimary : (h >= 50 ? Color.mTertiary : Color.mError);
                      }
                    }
                  }
                  NText {
                    Layout.preferredWidth: 40 * Style.uiScaleRatio
                    horizontalAlignment: Text.AlignRight

                    readonly property int h: modelData.healthSupported ? Math.round(modelData.healthPercentage) : (modelData === selectedBattery ? BatteryService.healthPercent : -1)
                    text: h >= 0 ? `${h}%` : "--"
                    color: Color.mOnSurface
                    pointSize: Style.fontSizeS
                    font.weight: Style.fontWeightBold
                  }
                }
              }
            }
          }

          NDivider {
            Layout.fillWidth: true
            visible: laptopBatteries.length > 0 && otherDevices.length > 0
          }

          // Other devices (Bluetooth) section
          Repeater {
            model: otherDevices
            delegate: ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.marginS
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                NIcon {
                  icon: BluetoothService.getDeviceIcon(modelData)
                }

                NText {
                  readonly property string dName: BatteryService.getDeviceName(modelData)
                  text: dName ? dName : I18n.tr("common.bluetooth")
                  color: Color.mOnSurface
                  pointSize: Style.fontSizeS
                }
              }
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                Rectangle {
                  Layout.fillWidth: true
                  height: Math.round(8 * Style.uiScaleRatio)
                  radius: Math.min(Style.radiusL, height / 2)
                  color: Color.mSurface

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height
                    radius: parent.radius
                    width: {
                      var p = BatteryService.getPercentage(modelData);
                      var ratio = Math.max(0, Math.min(1, p / 100));
                      return parent.width * ratio;
                    }
                    color: Color.mPrimary
                  }
                }
                NText {
                  Layout.preferredWidth: 40 * Style.uiScaleRatio
                  horizontalAlignment: Text.AlignRight
                  text: `${Math.round(BatteryService.getPercentage(modelData))}%`
                  color: Color.mOnSurface
                  pointSize: Style.fontSizeS
                  font.weight: Style.fontWeightBold
                }
              }
            }
          }
        }
      }

      NBox {
        Layout.fillWidth: true
        height: controlsLayout.implicitHeight + Style.marginL * 2
        visible: showPowerProfiles || showNoctaliaPerformance

        ColumnLayout {
          id: controlsLayout
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginM

          ColumnLayout {
            visible: powerProfileAvailable && showPowerProfiles

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS

              NText {
                text: I18n.tr("battery.power-profile")
                font.weight: Style.fontWeightBold
                color: Color.mOnSurface
                Layout.fillWidth: true
              }
              NText {
                text: PowerProfileService.getName(profileIndex)
                color: Color.mOnSurfaceVariant
              }
            }

            NValueSlider {
              Layout.fillWidth: true
              from: 0
              to: 2
              stepSize: 1
              snapAlways: true
              heightRatio: 0.5
              value: profileIndex
              enabled: profilesAvailable
              onPressedChanged: (pressed, v) => {
                                  if (!pressed) {
                                    setProfileByIndex(v);
                                  }
                                }
              onMoved: v => {
                         profileIndex = v;
                       }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS

              NIcon {
                icon: "powersaver"
                pointSize: Style.fontSizeS
                color: PowerProfileService.getIcon() === "powersaver" ? Color.mPrimary : Color.mOnSurfaceVariant
              }
              NIcon {
                icon: "balanced"
                pointSize: Style.fontSizeS
                color: PowerProfileService.getIcon() === "balanced" ? Color.mPrimary : Color.mOnSurfaceVariant
                Layout.fillWidth: true
              }
              NIcon {
                icon: "performance"
                pointSize: Style.fontSizeS
                color: PowerProfileService.getIcon() === "performance" ? Color.mPrimary : Color.mOnSurfaceVariant
              }
            }
          }

          NDivider {
            Layout.fillWidth: true
            visible: showPowerProfiles && PowerProfileService.available && showNoctaliaPerformance
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            visible: showNoctaliaPerformance

            NText {
              text: I18n.tr("toast.noctalia-performance.label")
              pointSize: Style.fontSizeM
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
              Layout.fillWidth: true
            }
            NIcon {
              icon: PowerProfileService.noctaliaPerformanceMode ? "rocket" : "rocket-off"
              pointSize: Style.fontSizeL
              color: PowerProfileService.noctaliaPerformanceMode ? Color.mPrimary : Color.mOnSurfaceVariant
            }
            NToggle {
              checked: PowerProfileService.noctaliaPerformanceMode
              onToggled: checked => PowerProfileService.noctaliaPerformanceMode = checked
            }
          }
        }
      }
    }
  }
}
