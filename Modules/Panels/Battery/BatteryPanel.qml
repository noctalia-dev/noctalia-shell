import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets
import qs.Modules.MainScreen

SmartPanel {
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

  onOpened: {
    updateOptionsModel()
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

    ColumnLayout {
      anchors.centerIn: parent
      spacing: Style.marginM

      NIcon {
        icon: "recharging"
        pointSize: 48
        color: Color.mOnSurfaceVariant
        Layout.alignment: Qt.AlignHCenter
      }

      NText {
        text: I18n.tr("battery.panel.disabled")
        pointSize: Style.fontSizeL
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        Layout.alignment: Qt.AlignHCenter
      }
    }
  }

  panelContent: Item {
    anchors.fill: parent

    property real contentPreferredWidth: Math.round(340 * Style.uiScaleRatio)
    property real contentPreferredHeight: Math.round(mainLayout.implicitHeight + Style.marginM * 2)

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

          NIcon {
            icon: "battery-4"
            pointSize: Style.fontSizeXXL
            color: Color.mPrimary
          }

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
