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
  
  function updateOptionsModel2() {
    let newOptions = [{
                        "id": BatteryService.ChargingMode.Full,
                        "label": "battery.panel.full"
                      }, {
                        "id": BatteryService.ChargingMode.Balanced,
                        "label": "battery.panel.balanced"
                      }]
    root.optionsModel = newOptions
  }

  onOpened: {
    !BatteryService.conservationModeEnabled ? updateOptionsModel() : updateOptionsModel2()
  }

  ButtonGroup {
    id: batteryGroup
  }

  Component {
    id: optionsComponent
    ColumnLayout {
      spacing: Style.marginM
      Repeater {
        model: root.optionsModel
        delegate: NRadioButton {
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

  Component {
    id: disabledComponent
    NText {
      text: I18n.tr("battery.panel.disabled")
      pointSize: Style.fontSizeL
      color: Color.mOnSurfaceVariant
      wrapMode: Text.WordWrap
      horizontalAlignment: Text.AlignHCenter
    }
  }

  panelContent: Item {
    anchors.fill: parent
    property real contentPreferredHeight: mainLayout.implicitHeight + Style.marginM * 2
    property real contentPreferredWidth: 350 * Style.uiScaleRatio

    ColumnLayout {
      id: mainLayout
      anchors.centerIn: parent
      width: parent.contentPreferredWidth - Style.marginM * 2
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

      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: loader.implicitHeight + Style.marginM * 2

        Loader {
          id: loader
          anchors.centerIn: parent
          width: parent.width - Style.marginM * 2
          sourceComponent: BatteryService.chargingMode === BatteryService.ChargingMode.Disabled ? disabledComponent : optionsComponent
        }
      }
    }
  }
}