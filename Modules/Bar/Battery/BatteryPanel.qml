import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

NPanel {
  id: root

  preferredWidth: 350 * Style.uiScaleRatio
  preferredHeight: 210 * Style.uiScaleRatio
  panelKeyboardFocus: true

  property var optionsModel: []

  function updateOptionsModel() {
    let newOptions = [{
                        "id": BatteryService.ChargingMode.Full,
                        "label": "battery.panel.full"
                      }, {
                        "id": BatteryService.ChargingMode.Balanced,
                        "label": "battery.panel.balanced"
                      }, {
                        "id": BatteryService.ChargingMode.Lifespan,
                        "label": "battery.panel.lifespan"
                      }]
    root.optionsModel = newOptions
  }

  onOpened: {
    updateOptionsModel()
  }

  panelContent: Item {
    anchors.fill: parent

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginM

      // HEADER
      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: header.implicitHeight + Style.marginM * 2

        RowLayout {
          id: header
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          NText {
            text: I18n.tr("battery.panel.title")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            Layout.fillWidth: true
          }

          NToggle {
            id: batteryManagerSwitch
            checked: BatteryService.chargingMode !== BatteryService.ChargingMode.Disabled
            onToggled: checked => BatteryService.toggleEnabled(checked)
            baseSize: Style.baseWidgetSize * 0.65
          }

          NIconButton {
            icon: "close"
            tooltipText: I18n.tr("tooltips.close")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              root.close()
            }
          }
        }
      }

      ButtonGroup {
        id: batteryGroup
      }

      NBox {
        Layout.fillWidth: true
        Layout.fillHeight: true

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          Repeater {
            model: optionsModel

            NRadioButton {
              visible: BatteryService.chargingMode !== BatteryService.ChargingMode.Disabled
              ButtonGroup.group: batteryGroup
              required property var modelData
              text: I18n.tr(modelData.label, {
                              "percent": BatteryService.getThresholdValue(modelData.id)
                            })
              checked: BatteryService.chargingMode === modelData.id
              onClicked: {
                BatteryService.setChargingMode(modelData.id)
              }
              Layout.fillWidth: true
            }
          }
        }

        ColumnLayout {
          visible: BatteryService.chargingMode === BatteryService.ChargingMode.Disabled
          anchors.fill: parent
          spacing: Style.marginM

          Item {
            Layout.fillHeight: true
          }

          NText {
            text: I18n.tr("battery.panel.disabled")
            pointSize: Style.fontSizeL
            color: Color.mOnSurfaceVariant
            Layout.alignment: Qt.AlignHCenter
          }

          Item {
            Layout.fillHeight: true
          }
        }
      }
    }
  }
}
