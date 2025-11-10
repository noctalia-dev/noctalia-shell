import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Networking
import qs.Services.UI

Item {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  readonly property bool isBarVertical: Settings.data.bar.position === "left" || Settings.data.bar.position === "right"
  readonly property string displayMode: widgetSettings.displayMode !== undefined ? widgetSettings.displayMode : widgetMetadata.displayMode

  implicitWidth: pill.width
  implicitHeight: pill.height

  BarPill {
    id: pill

    density: Settings.data.bar.density
    oppositeDirection: BarService.getPillDirection(root)
    icon: BluetoothService.enabled ? "bluetooth" : "bluetooth-off"
    text: {
      if (BluetoothService.connectedDevices && BluetoothService.connectedDevices.length > 0) {
        const firstDevice = BluetoothService.connectedDevices[0]
        return firstDevice.name || firstDevice.deviceName
      }
      return ""
    }
    suffix: {
      if (BluetoothService.connectedDevices && BluetoothService.connectedDevices.length > 1) {
        return ` + ${BluetoothService.connectedDevices.length - 1}`
      }
      return ""
    }
    autoHide: false
    forceOpen: !isBarVertical && root.displayMode === "alwaysShow"
    forceClose: isBarVertical || root.displayMode === "alwaysHide" || BluetoothService.connectedDevices.length === 0
    onClicked: PanelService.getPanel("bluetoothPanel", screen)?.toggle(this)
    onRightClicked: PanelService.getPanel("bluetoothPanel", screen)?.toggle(this)
    tooltipText: {
      if (pill.text !== "") {
        return pill.text
      }
      return I18n.tr("tooltips.bluetooth-devices")
    }
  }
}
