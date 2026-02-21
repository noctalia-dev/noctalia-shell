import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Compositor
import qs.Services.Hardware
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  ColumnLayout {
    spacing: Style.marginL

    Repeater {
      model: Quickshell.screens || []
      delegate: NBox {
        Layout.fillWidth: true
        implicitHeight: Math.round(contentCol.implicitHeight + Style.margin2L)
        color: Color.mSurface

        property var brightnessMonitor: BrightnessService.getMonitorForScreen(modelData)
        property real localBrightness: 0.5
        property bool localBrightnessChanging: false

        onBrightnessMonitorChanged: {
          if (brightnessMonitor && !localBrightnessChanging)
            localBrightness = brightnessMonitor.brightness || 0.5;
        }

        Connections {
          target: BrightnessService
          function onMonitorBrightnessChanged(monitor, newBrightness) {
            if (monitor === brightnessMonitor && !localBrightnessChanging) {
              localBrightness = newBrightness;
            }
          }
        }
        Connections {
          target: brightnessMonitor
          ignoreUnknownSignals: true
          function onBrightnessUpdated() {
            if (brightnessMonitor && !localBrightnessChanging) {
              localBrightness = brightnessMonitor.brightness || 0;
            }
          }
        }
        Timer {
          id: debounceTimer
          interval: 120
          repeat: false
          onTriggered: {
            if (brightnessMonitor && brightnessMonitor.brightnessControlAvailable && Math.abs(localBrightness - brightnessMonitor.brightness) >= 0.005) {
              brightnessMonitor.setBrightness(localBrightness);
            }
          }
        }

        ColumnLayout {
          id: contentCol
          width: parent.width - 2 * Style.marginL
          x: Style.marginL
          y: Style.marginL
          spacing: Style.marginXXS

          RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignBottom

            NText {
              text: modelData.name || "Unknown"
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightSemiBold
              Layout.alignment: Qt.AlignBottom
            }

            NText {
              Layout.fillWidth: true
              text: {
                const compositorScale = CompositorService.getDisplayScale(modelData.name);
                I18n.tr("system.monitor-description", {
                          "model": modelData.model,
                          "width": modelData.width * compositorScale,
                          "height": modelData.height * compositorScale,
                          "scale": compositorScale
                        });
              }
              pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignRight
              Layout.alignment: Qt.AlignBottom
            }
          }

          ColumnLayout {
            spacing: Style.marginS
            Layout.fillWidth: true
            visible: brightnessMonitor !== undefined && brightnessMonitor !== null

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginL

              NText {
                text: I18n.tr("common.brightness")
                Layout.preferredWidth: 90
                Layout.alignment: Qt.AlignVCenter
              }

              NValueSlider {
                id: brightnessSlider
                from: 0
                to: 1
                value: localBrightness
                stepSize: 0.01
                enabled: brightnessMonitor ? brightnessMonitor.brightnessControlAvailable : false
                onMoved: value => {
                           if (brightnessMonitor && brightnessMonitor.brightnessControlAvailable) {
                             localBrightness = value;
                             debounceTimer.restart();
                           }
                         }
                onPressedChanged: (pressed, value) => {
                                    localBrightnessChanging = pressed;
                                    if (brightnessMonitor && brightnessMonitor.brightnessControlAvailable) {
                                      if (pressed) {
                                        localBrightness = value;
                                        debounceTimer.restart();
                                      } else {
                                        localBrightness = value;
                                        debounceTimer.restart();
                                      }
                                    }
                                  }
                Layout.fillWidth: true
              }

              NText {
                text: brightnessMonitor ? Math.round(localBrightness * 100) + "%" : "N/A"
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
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  opacity: brightnessMonitor && !brightnessMonitor.brightnessControlAvailable ? 0.5 : 1.0
                }
              }
            }

            NText {
              visible: brightnessMonitor && !brightnessMonitor.brightnessControlAvailable
              text: !Settings.data.brightness.enableDdcSupport ? I18n.tr("panels.display.monitors-brightness-unavailable-ddc-disabled") : I18n.tr("panels.display.monitors-brightness-unavailable-generic")
              pointSize: Style.fontSizeXS
              color: Color.mOnSurfaceVariant
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }

    NSpinBox {
      Layout.fillWidth: true
      label: I18n.tr("panels.display.monitors-brightness-step-label")
      description: I18n.tr("panels.display.monitors-brightness-step-description")
      minimum: 1
      maximum: 50
      value: Settings.data.brightness.brightnessStep
      stepSize: 1
      suffix: "%"
      onValueChanged: Settings.data.brightness.brightnessStep = value
      defaultValue: Settings.getDefaultValue("brightness.brightnessStep")
    }

    NToggle {
      Layout.fillWidth: true
      label: I18n.tr("panels.display.monitors-enforce-minimum-label")
      description: I18n.tr("panels.display.monitors-enforce-minimum-description")
      checked: Settings.data.brightness.enforceMinimum
      onToggled: checked => Settings.data.brightness.enforceMinimum = checked
      defaultValue: Settings.getDefaultValue("brightness.enforceMinimum")
    }

    NToggle {
      Layout.fillWidth: true
      label: I18n.tr("panels.display.monitors-external-brightness-label")
      description: I18n.tr("panels.display.monitors-external-brightness-description")
      checked: Settings.data.brightness.enableDdcSupport
      onToggled: checked => {
                   Settings.data.brightness.enableDdcSupport = checked;
                 }
      defaultValue: Settings.getDefaultValue("brightness.enableDdcSupport")
    }
  }
}
