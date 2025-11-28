import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Hardware
import qs.Services.Power
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(360 * Style.uiScaleRatio)
  preferredHeight: Math.round(460 * Style.uiScaleRatio)

  readonly property var battery: UPower.displayDevice
  readonly property bool isReady: battery && battery.ready && battery.isLaptopBattery && battery.isPresent
  readonly property int percent: isReady ? Math.round(battery.percentage * 100) : -1
  readonly property bool charging: isReady ? battery.state === UPowerDeviceState.Charging : false
  readonly property bool healthAvailable: isReady && battery.healthSupported
  readonly property int healthPercent: healthAvailable ? Math.round(battery.healthPercentage) : -1
  readonly property bool powerProfileAvailable: PowerProfileService.available
  readonly property var powerProfiles: [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
  readonly property string timeText: {
    if (!isReady)
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
  readonly property bool profilesAvailable: PowerProfileService.available
  property int profileIndex: profileToIndex(PowerProfileService.profile)
  property bool manualInhibitActive: manualInhibitorEnabled()
  property var batteryWidgetInstance: BarService.lookupWidget("Battery", screen ? screen.name : null)
  readonly property var batteryWidgetSettings: batteryWidgetInstance ? batteryWidgetInstance.widgetSettings : null
  readonly property var batteryWidgetMetadata: BarWidgetRegistry.widgetMetadata["Battery"]
  readonly property bool showPowerProfileControls: resolveWidgetSetting("showPowerProfiles", true)
  readonly property bool showManualInhibitControl: resolveWidgetSetting("showKeepAwake", true)
  readonly property bool showPerformanceModeControl: resolveWidgetSetting("showNoctaliaPerformance", true)
  readonly property bool showBrightnessControls: resolveWidgetSetting("showBrightnessControls", true)

  panelContent: Item {
    property real contentPreferredHeight: mainLayout.implicitHeight + Style.marginL * 2

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
            color: root.charging ? Color.mPrimary : Color.mOnSurface
            icon: iconName
          }

          ColumnLayout {
            spacing: Style.marginXXS
            Layout.fillWidth: true

            NText {
              text: I18n.tr("battery.panel-title")
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
              Layout.fillWidth: true
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
                radius: height / 2
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

      // Power profile and idle inhibit controls
      NBox {
        Layout.fillWidth: true
        height: controlsLayout.implicitHeight + Style.marginM * 2
        visible: (root.showPowerProfileControls && root.powerProfileAvailable) || root.showPerformanceModeControl || root.showManualInhibitControl

        ColumnLayout {
          id: controlsLayout
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          ColumnLayout {
            id: ppd
            visible: root.powerProfileAvailable && root.showPowerProfileControls

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS
              NIcon {
                icon: PowerProfileService.getIcon()
                pointSize: Style.fontSizeM
                color: Color.mPrimary
              }
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
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            visible: root.showPerformanceModeControl

            NIcon {
              icon: PowerProfileService.noctaliaPerformanceMode ? "rocket" : "rocket-off"
              pointSize: Style.fontSizeL
              color: PowerProfileService.noctaliaPerformanceMode ? Color.mPrimary : Color.mOnSurfaceVariant
              Layout.alignment: Qt.AlignVCenter
            }

            NToggle {
              Layout.fillWidth: true
              checked: PowerProfileService.noctaliaPerformanceMode
              label: I18n.tr("toast.noctalia-performance.label")
              description: PowerProfileService.noctaliaPerformanceMode ? I18n.tr("toast.noctalia-performance.enabled") : I18n.tr("toast.noctalia-performance.disabled")
              onToggled: function (checked) {
                PowerProfileService.setNoctaliaPerformance(checked);
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS
            visible: root.showManualInhibitControl

            NIcon {
              icon: manualInhibitActive ? "keep-awake-on" : "keep-awake-off"
              pointSize: Style.fontSizeL
              color: manualInhibitActive ? Color.mPrimary : Color.mOnSurfaceVariant
              Layout.alignment: Qt.AlignVCenter
            }

            NToggle {
              Layout.fillWidth: true
              checked: manualInhibitActive
              label: I18n.tr("battery.inhibit-idle-label")
              description: I18n.tr("battery.inhibit-idle-description")
              onToggled: function (checked) {
                if (checked) {
                  IdleInhibitorService.addManualInhibitor(null);
                } else {
                  IdleInhibitorService.removeManualInhibitor();
                }
                manualInhibitActive = checked;
              }
            }
          }
        }
      }

      // Brightness controls
      NBox {
        Layout.fillWidth: true
        height: brightnessLayout.implicitHeight + Style.marginM * 2
        visible: root.showBrightnessControls && (Quickshell.screens && Quickshell.screens.length > 0)

        ColumnLayout {
          id: brightnessLayout
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginS

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NIcon {
              icon: "sun"
              pointSize: Style.fontSizeL
              color: Color.mOnSurface
              Layout.alignment: Qt.AlignVCenter
            }

            NText {
              text: I18n.tr("settings.display.monitors.brightness")
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
              Layout.fillWidth: true
            }
          }

          Repeater {
            id: brightnessRepeater
            model: Quickshell.screens || []
            delegate: RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS
              property var brightnessMonitor: BrightnessService.getMonitorForScreen(modelData)
              visible: brightnessMonitor !== undefined && brightnessMonitor !== null

              NIcon {
                icon: brightnessIconForMonitor(brightnessMonitor)
                pointSize: Style.fontSizeM
                color: Color.mOnSurface
                Layout.alignment: Qt.AlignVCenter
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.marginXXS

                NText {
                  text: modelData.name || I18n.tr("system.unknown")
                  pointSize: Style.fontSizeS
                  color: Color.mOnSurfaceVariant
                  Layout.fillWidth: true
                  wrapMode: Text.Wrap
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS

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
                    text: brightnessMonitor ? Math.round(brightnessSlider.value * 100) + "%" : "N/A"
                  }
                }
              }
            }
          }

          NText {
            visible: brightnessRepeater.count === 0
            text: I18n.tr("settings.display.monitors.brightness-unavailable.generic")
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            wrapMode: Text.Wrap
            Layout.fillWidth: true
          }
        }
      }
    }
  }

  function resolveWidgetSetting(key, defaultValue) {
    if (batteryWidgetSettings && batteryWidgetSettings[key] !== undefined)
      return batteryWidgetSettings[key];
    if (batteryWidgetMetadata && batteryWidgetMetadata[key] !== undefined)
      return batteryWidgetMetadata[key];
    return defaultValue;
  }

  function profileToIndex(p) {
    return powerProfiles.indexOf(p) ?? 1;
  }

  function brightnessIconForMonitor(monitor) {
    const brightness = monitor ? monitor.brightness : 0;
    if (brightness <= 0.001)
      return "sun-off";
    return brightness <= 0.5 ? "brightness-low" : "brightness-high";
  }

  function indexToProfile(idx) {
    return powerProfiles[idx] ?? PowerProfile.Balanced;
  }

  function setProfileByIndex(idx) {
    var prof = indexToProfile(idx);
    profileIndex = idx;
    PowerProfileService.setProfile(prof);
  }

  function manualInhibitorEnabled() {
    return IdleInhibitorService.activeInhibitors && IdleInhibitorService.activeInhibitors.indexOf("manual") >= 0;
  }

  Connections {
    target: BarService

    function onActiveWidgetsChanged() {
      batteryWidgetInstance = BarService.lookupWidget("Battery", screen ? screen.name : null);
    }
  }

  Connections {
    target: IdleInhibitorService

    function onIsInhibitedChanged() {
      manualInhibitActive = manualInhibitorEnabled();
    }
  }

  Timer {
    id: inhibitorPoll
    interval: 1000
    repeat: true
    running: true
    onTriggered: manualInhibitActive = manualInhibitorEnabled()
  }

  Connections {
    target: PowerProfileService

    function onProfileChanged() {
      profileIndex = profileToIndex(PowerProfileService.profile);
    }
  }
}
