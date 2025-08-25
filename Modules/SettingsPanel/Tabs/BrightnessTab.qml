import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

Item {
  readonly property real scaling: ScalingService.scale(screen)
  readonly property string tabIcon: "brightness_6"
  readonly property string tabLabel: "Brightness"
  Layout.fillWidth: true
  Layout.fillHeight: true

  ScrollView {
    anchors.fill: parent
    clip: true
    ScrollBar.vertical.policy: ScrollBar.AsNeeded
    ScrollBar.horizontal.policy: ScrollBar.AsNeeded
    contentWidth: parent.width

    ColumnLayout {
      width: parent.width
      ColumnLayout {
        spacing: Style.marginL * scaling
        Layout.margins: Style.marginL * scaling
        Layout.fillWidth: true

        NText {
          text: "Brightness Settings"
          font.pointSize: Style.fontSizeXXL * scaling
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
        }

        // Bar Visibility Section
        NToggle {
          label: "Show Bar Icon"
          description: "Display the brightness control icon in the bar."
          checked: Settings.data.bar.showBrightness
          onToggled: checked => {
                       Settings.data.bar.showBrightness = checked
                     }
        }

        // Brightness Step Section
        ColumnLayout {
          spacing: Style.marginS * scaling
          Layout.fillWidth: true

          NSpinBox {
            Layout.fillWidth: true
            label: "Brightness Step Size"
            description: "Adjust the step size for brightness changes (scroll wheel, keyboard shortcuts)."
            minimum: 1
            maximum: 50
            value: Settings.data.brightness.brightnessStep
            stepSize: 1
            suffix: "%"
            onValueChanged: {
              Settings.data.brightness.brightnessStep = value
            }
          }
        }

        NDivider {
          Layout.fillWidth: true
          Layout.topMargin: Style.marginL * scaling
          Layout.bottomMargin: Style.marginL * scaling
        }

        // Monitor Overview Section
        ColumnLayout {
          spacing: Style.marginS * scaling
          Layout.fillWidth: true

          NLabel {
            label: "Monitors Brightness Control"
            description: "Current brightness levels for all detected monitors."
          }

          // Single monitor display using the same data source as the bar icon
          Repeater {
            model: BrightnessService.monitors
            Rectangle {
              Layout.fillWidth: true
              radius: Style.radiusM * scaling
              color: Color.mSurface
              border.color: Color.mOutline
              border.width: Math.max(1, Style.borderS * scaling)
              implicitHeight: contentCol.implicitHeight + Style.marginXL * 2 * scaling

              ColumnLayout {
                id: contentCol
                anchors.fill: parent
                anchors.margins: Style.marginL * scaling
                spacing: Style.marginM * scaling

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginM * scaling

                  NText {
                    text: `${model.modelData.name} [${model.modelData.model}]`
                    font.pointSize: Style.fontSizeL * scaling
                    font.weight: Style.fontWeightBold
                    color: Color.mSecondary
                  }

                  Item {
                    Layout.fillWidth: true
                  }

                  NText {
                    text: model.method
                    font.pointSize: Style.fontSizeXS * scaling
                    color: Color.mOnSurfaceVariant
                    Layout.alignment: Qt.AlignRight
                  }
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginM * scaling

                  NText {
                    text: "Brightness:"
                    font.pointSize: Style.fontSizeM * scaling
                    color: Color.mOnSurface
                  }

                  NSlider {
                    Layout.fillWidth: true
                    from: 0
                    to: 1
                    value: model.brightness
                    stepSize: 0.05
                    onPressedChanged: {
                      if (!pressed) {
                        var monitor = BrightnessService.getMonitorForScreen(model.modelData)
                        monitor.setBrightness(value)
                      }
                    }
                  }

                  NText {
                    text: Math.round(model.brightness * 100) + "%"
                    font.pointSize: Style.fontSizeM * scaling
                    font.weight: Style.fontWeightBold
                    color: Color.mPrimary
                    Layout.alignment: Qt.AlignRight
                  }
                }
              }
            }
          }
        }

        Item {
          Layout.fillHeight: true
        }
      }
    }
  }
}
