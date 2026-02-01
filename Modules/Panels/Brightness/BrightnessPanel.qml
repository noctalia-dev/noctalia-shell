import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Compositor
import qs.Services.Hardware
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(440 * Style.uiScaleRatio)
  preferredHeight: Math.round(420 * Style.uiScaleRatio)

  onOpened: {
    // Refresh DDC brightness from monitors (one-time on panel open)
    BrightnessService.monitors.forEach(m => {
                                         if (m.isDdc) {
                                           m.refreshBrightnessFromSystem();
                                         }
                                       });
  }

  panelContent: Item {
    id: panelContent
    property real contentPreferredHeight: mainColumn.implicitHeight + Style.marginL * 2

    function getIcon(brightness) {
      return brightness <= 0.5 ? "brightness-low" : "brightness-high";
    }

    ColumnLayout {
      id: mainColumn
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
            icon: "settings-display"
            pointSize: Style.fontSizeXXL
            color: Color.mPrimary
          }

          NText {
            text: I18n.tr("panels.display.title")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            Layout.fillWidth: true
          }

          NIconButton {
            icon: "close"
            tooltipText: I18n.tr("common.close")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              root.close();
            }
          }
        }
      }

      NScrollView {
        id: brightnessScrollView
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        verticalPolicy: ScrollBar.AsNeeded
        contentWidth: availableWidth
        reserveScrollbarSpace: false
        gradientColor: Color.mSurface

        // AudioService Devices
        ColumnLayout {
          spacing: Style.marginM
          width: brightnessScrollView.availableWidth

          Repeater {
            model: Quickshell.screens || []
            delegate: NBox {
              Layout.fillWidth: true
              Layout.preferredHeight: outputColumn.implicitHeight + (Style.marginXL)

              property var brightnessMonitor: BrightnessService.getMonitorForScreen(modelData)

              ColumnLayout {
                id: outputColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.marginM
                spacing: Style.marginS

                NLabel {
                  label: modelData.name || "Unknown"
                  labelColor: Color.mPrimary
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

                RowLayout {

                  Layout.fillWidth: true
                  spacing: Style.marginS
                  NIcon {
                    icon: getIcon(brightnessMonitor ? brightnessMonitor.brightness : 0)
                    pointSize: Style.fontSizeXL
                    color: Color.mOnSurface
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
                    text: brightnessMonitor ? Math.round(brightnessSlider.value * 100) + "%" : "N/A"
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
