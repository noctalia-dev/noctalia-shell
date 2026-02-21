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

    property var batteryWidgetInstance: BarService.lookupWidget("Battery", screen ? screen.name : null)
    readonly property var batteryWidgetSettings: batteryWidgetInstance ? batteryWidgetInstance.widgetSettings : null
    readonly property var batteryWidgetMetadata: BarWidgetRegistry.widgetMetadata["Battery"]
    readonly property bool powerProfileAvailable: PowerProfileService.available
    readonly property var powerProfiles: [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
    readonly property bool profilesAvailable: PowerProfileService.available
    property int profileIndex: profileToIndex(PowerProfileService.profile)
    readonly property bool showPowerProfiles: panelID ? panelID.showPowerProfiles : resolveWidgetSetting("showPowerProfiles", false)
    readonly property bool showNoctaliaPerformance: panelID ? panelID.showNoctaliaPerformance : resolveWidgetSetting("showNoctaliaPerformance", false)
    readonly property bool isLowBattery: BatteryService.isLowBattery
    readonly property bool isCriticalBattery: BatteryService.isCriticalBattery
    readonly property var primaryDevice: BatteryService.primaryDevice

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
        implicitHeight: headerRow.implicitHeight + Style.margin2M

        RowLayout {
          id: headerRow
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          NIcon {
            pointSize: Style.fontSizeXXL
            color: (BatteryService.isCharging(primaryDevice) || BatteryService.isPluggedIn(primaryDevice)) ? Color.mPrimary : (BatteryService.isCriticalBattery(primaryDevice) || BatteryService.isLowBattery(primaryDevice)) ? Color.mError : Color.mOnSurface
            icon: BatteryService.getIcon(BatteryService.getPercentage(primaryDevice), BatteryService.isCharging(primaryDevice), BatteryService.isPluggedIn(primaryDevice), BatteryService.isDeviceReady(primaryDevice))
          }

          ColumnLayout {
            spacing: Style.marginXXS
            Layout.fillWidth: true

            NText {
              text: I18n.tr("common.battery")
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
              Layout.fillWidth: true
              elide: Text.ElideRight
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
        visible: BatteryService.laptopBatteries.length > 0 || BatteryService.bluetoothBatteries.length > 0

        ColumnLayout {
          id: chargeLayout
          anchors.fill: parent
          anchors.margins: Style.marginL
          spacing: Style.marginL

          // Laptop batteries section
          Repeater {
            model: BatteryService.laptopBatteries
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
                    Item {
                      id: batteryInfoItem
                      implicitWidth: batteryInfoRow.implicitWidth
                      implicitHeight: batteryInfoRow.implicitHeight

                      RowLayout {
                        id: batteryInfoRow
                        anchors.fill: parent

                        NIcon {
                          icon: BatteryService.getIcon(BatteryService.getPercentage(modelData), BatteryService.isCharging(modelData), BatteryService.isPluggedIn(modelData), BatteryService.isDeviceReady(modelData))
                          color: (BatteryService.isCharging(modelData) || BatteryService.isPluggedIn(modelData)) ? Color.mPrimary : (BatteryService.isCriticalBattery(modelData) || BatteryService.isLowBattery(modelData)) ? Color.mError : Color.mOnSurface
                        }

                        NText {
                          readonly property string dName: BatteryService.getDeviceName(modelData)
                          text: dName ? dName : I18n.tr("common.battery")
                          color: (BatteryService.isCharging(modelData) || BatteryService.isPluggedIn(modelData)) ? Color.mPrimary : (BatteryService.isCriticalBattery(modelData) || BatteryService.isLowBattery(modelData)) ? Color.mError : Color.mOnSurface
                          pointSize: Style.fontSizeS
                        }
                      }

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: {
                          if (modelData.healthSupported) {
                            TooltipService.show(batteryInfoItem, `${I18n.tr("battery.battery-health")}: ${Math.round(modelData.healthPercentage)}%`);
                          }
                        }
                        onExited: TooltipService.hide(batteryInfoItem)
                      }
                    }

                    Item {
                      Layout.fillWidth: true
                    }

                    NText {
                      text: BatteryService.getTimeRemainingText(modelData)
                      pointSize: Style.fontSizeS
                      color: Color.mOnSurfaceVariant
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
                      text: `${BatteryService.getPercentage(modelData)}%`
                      color: (BatteryService.isCharging(modelData) || BatteryService.isPluggedIn(modelData)) ? Color.mPrimary : (BatteryService.isCriticalBattery(modelData) || BatteryService.isLowBattery(modelData)) ? Color.mError : Color.mOnSurface
                      pointSize: Style.fontSizeS
                      font.weight: Style.fontWeightBold
                    }
                  }
                }
              }
            }
          }

          NDivider {
            Layout.fillWidth: true
            visible: BatteryService.laptopBatteries.length > 0 && BatteryService.bluetoothBatteries.length > 0
          }

          // Other devices (Bluetooth) section
          Repeater {
            model: BatteryService.bluetoothBatteries
            delegate: ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.marginS
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                NIcon {
                  icon: BluetoothService.getDeviceIcon(modelData)
                  color: (BatteryService.isCharging(modelData) || BatteryService.isPluggedIn(modelData)) ? Color.mPrimary : (BatteryService.isCriticalBattery(modelData) || BatteryService.isLowBattery(modelData)) ? Color.mError : Color.mOnSurface
                }

                NText {
                  readonly property string dName: BatteryService.getDeviceName(modelData)
                  text: dName ? dName : I18n.tr("common.bluetooth")
                  color: (BatteryService.isCharging(modelData) || BatteryService.isPluggedIn(modelData)) ? Color.mPrimary : (BatteryService.isCriticalBattery(modelData) || BatteryService.isLowBattery(modelData)) ? Color.mError : Color.mOnSurface
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
                  text: `${BatteryService.getPercentage(modelData)}%`
                  color: (BatteryService.isCharging(modelData) || BatteryService.isPluggedIn(modelData)) ? Color.mPrimary : (BatteryService.isCriticalBattery(modelData) || BatteryService.isLowBattery(modelData)) ? Color.mError : Color.mOnSurface
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
