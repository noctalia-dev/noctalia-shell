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

  panelContent: Item {
    id: panelContent
    property real contentPreferredHeight: mainLayout.implicitHeight + Style.marginL * 2

    // Get device selection from Battery widget settings (check right section first, then any Battery widget)
    function getBatteryDevicePath() {
      var widget = BarService.lookupWidget("Battery");
      if (widget !== undefined && widget.deviceNativePath !== undefined) {
        return widget.deviceNativePath;
      }
      return "";
    }

    // Helper function to find battery device by nativePath
    function findBatteryDevice(nativePath) {
      if (!nativePath || nativePath === "") {
        return UPower.displayDevice;
      }

      if (!UPower.devices) {
        return UPower.displayDevice;
      }

      var deviceArray = UPower.devices.values || [];
      for (var i = 0; i < deviceArray.length; i++) {
        var device = deviceArray[i];
        if (device && device.nativePath === nativePath) {
          if (device.type === UPowerDeviceType.LinePower) {
            continue;
          }
          if (device.percentage !== undefined) {
            return device;
          }
        }
      }
      return UPower.displayDevice;
    }

    // Helper function to find Bluetooth device by MAC address from nativePath
    function findBluetoothDevice(nativePath) {
      if (!nativePath || !BluetoothService.devices) {
        return null;
      }

      var macMatch = nativePath.match(/([0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2})/);
      if (!macMatch) {
        return null;
      }

      var macAddress = macMatch[1].toUpperCase();
      var deviceArray = BluetoothService.devices.values || [];

      for (var i = 0; i < deviceArray.length; i++) {
        var device = deviceArray[i];
        if (device && device.address && device.address.toUpperCase() === macAddress) {
          return device;
        }
      }
      return null;
    }

    readonly property string deviceNativePath: getBatteryDevicePath()
    readonly property var battery: findBatteryDevice(deviceNativePath)
    readonly property var bluetoothDevice: deviceNativePath ? findBluetoothDevice(deviceNativePath) : null
    readonly property bool hasBluetoothBattery: bluetoothDevice && bluetoothDevice.batteryAvailable && bluetoothDevice.battery !== undefined
    readonly property bool isBluetoothConnected: bluetoothDevice && bluetoothDevice.connected !== undefined ? bluetoothDevice.connected : false

    // Check if device is actually present/connected
    readonly property bool isDevicePresent: {
      if (deviceNativePath && deviceNativePath !== "") {
        if (bluetoothDevice) {
          return isBluetoothConnected;
        }
        if (battery && battery.nativePath === deviceNativePath) {
          if (battery.type === UPowerDeviceType.Battery && battery.isPresent !== undefined) {
            return battery.isPresent;
          }
          return battery.ready && battery.percentage !== undefined && (battery.percentage > 0 || battery.state === UPowerDeviceState.Charging);
        }
        return false;
      }
      if (battery) {
        if (battery.type === UPowerDeviceType.Battery && battery.isPresent !== undefined) {
          return battery.isPresent;
        }
        return battery.ready && battery.percentage !== undefined;
      }
      return false;
    }

    readonly property bool isReady: battery && battery.ready && isDevicePresent && (battery.percentage !== undefined || hasBluetoothBattery)
    readonly property int percent: isReady ? Math.round(hasBluetoothBattery ? (bluetoothDevice.battery * 100) : (battery.percentage * 100)) : -1
    readonly property bool charging: isReady ? battery.state === UPowerDeviceState.Charging : false
    readonly property bool healthAvailable: isReady && battery.healthSupported
    readonly property int healthPercent: healthAvailable ? Math.round(battery.healthPercentage) : -1

    function getDeviceName() {
      if (!isReady) {
        return "";
      }
      // Don't show name for laptop batteries
      if (battery && battery.isLaptopBattery) {
        return "";
      }
      if (bluetoothDevice && bluetoothDevice.name) {
        return bluetoothDevice.name;
      }
      if (battery && battery.model) {
        return battery.model;
      }
      return "";
    }

    readonly property string deviceName: getDeviceName()
    readonly property string panelTitle: deviceName ? `${I18n.tr("battery.panel-title")} - ${deviceName}` : I18n.tr("battery.panel-title")

    readonly property string timeText: {
      if (!isReady || !isDevicePresent)
        return I18n.tr("battery.no-battery-detected");
      if (charging && battery.timeToFull > 0) {
        return I18n.tr("battery.time-until-full", {
                         "time": Time.formatVagueHumanReadableDuration(battery.timeToFull)
                       });
      }
      if (!charging && battery.timeToEmpty > 0) {
        return I18n.tr("battery.time-left", {
                         "time": Time.formatVagueHumanReadableDuration(battery.timeToEmpty)
                       });
      }
      return I18n.tr("battery.idle");
    }
    readonly property string iconName: BatteryService.getIcon(percent, charging, isReady)

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
        implicitHeight: headerRow.implicitHeight + (Style.marginM * 2)

        RowLayout {
          id: headerRow
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          NIcon {
            pointSize: Style.fontSizeXXL
            color: charging ? Color.mPrimary : Color.mOnSurface
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
              text: timeText
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
              wrapMode: Text.Wrap
              Layout.fillWidth: true
            }
          }

          NIconButton {
            icon: "close"
            tooltipText: I18n.tr("tooltips.close")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: root.close()
          }
        }
      }

      // Charge level + health/time
      NBox {
        Layout.fillWidth: true
        height: chargeLayout.implicitHeight + Style.marginL * 2
        visible: isReady

        ColumnLayout {
          id: chargeLayout
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginS

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            ColumnLayout {
              NText {
                text: I18n.tr("battery.battery-level")
                color: Color.mOnSurface
                pointSize: Style.fontSizeS
              }

              Rectangle {
                Layout.fillWidth: true
                height: Math.round(8 * Style.uiScaleRatio)
                radius: Math.min(Style.radiusL, height / 2)
                color: Color.mSurfaceVariant

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  height: parent.height
                  radius: parent.radius
                  width: {
                    var ratio = Math.max(0, Math.min(1, percent / 100));
                    return parent.width * ratio;
                  }
                  color: Color.mPrimary
                }
              }
            }

            NText {
              text: percent >= 0 ? `${percent}%` : "--"
              color: Color.mOnSurface
              pointSize: Style.fontSizeS
              font.weight: Style.fontWeightBold
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginL
            visible: healthAvailable

            NText {
              text: I18n.tr("battery.health", {
                              "percent": healthPercent
                            })
              color: Color.mOnSurface
              pointSize: Style.fontSizeS
              font.weight: Style.fontWeightMedium
              Layout.fillWidth: true
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
            visible: showPowerProfiles && showNoctaliaPerformance
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
