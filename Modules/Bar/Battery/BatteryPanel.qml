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

  preferredWidth: 300
  preferredHeight: 210
  panelKeyboardFocus: true

  property var optionsModel: []

  function updateOptionsModel() {
    let newOptions = [{
                        "id": BatteryService.ChargingMode.Full,
                        "label": "battery.panel.full",
                        "icon": "battery-4"
                      }, {
                        "id": BatteryService.ChargingMode.Balanced,
                        "label": "battery.panel.balanced",
                        "icon": "battery-3"
                      }, {
                        "id": BatteryService.ChargingMode.Lifespan,
                        "label": "battery.panel.lifespan",
                        "icon": "battery-2"
                      }]
    root.optionsModel = newOptions
  }

  onOpened: {
    updateOptionsModel()
  }

  panelContent: Rectangle {
    color: Color.transparent

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginL * scaling
      spacing: Style.marginM * scaling

      // HEADER
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM * scaling

        NText {
          text: I18n.tr("battery.panel.title")
          pointSize: Style.fontSizeL * scaling
          font.weight: Style.fontWeightBold
          color: Color.mOnSurface
          Layout.fillWidth: true
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

      NDivider {
        Layout.fillWidth: true
      }

      ButtonGroup {
        id: batteryGroup
      }

      Repeater {
        model: optionsModel

        NRadioButton {
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
  }
}
