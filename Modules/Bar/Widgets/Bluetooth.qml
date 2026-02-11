import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Networking
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  // Explicit screenName property ensures reactive binding when screen changes
  readonly property string screenName: screen ? screen.name : ""
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0 && screenName) {
      var widgets = Settings.getBarWidgetsForScreen(screenName)[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
  readonly property string displayMode: widgetSettings.displayMode !== undefined ? widgetSettings.displayMode : widgetMetadata.displayMode
  readonly property string iconColorKey: widgetSettings.iconColor !== undefined ? widgetSettings.iconColor : widgetMetadata.iconColor
  readonly property string textColorKey: widgetSettings.textColor !== undefined ? widgetSettings.textColor : widgetMetadata.textColor

  implicitWidth: pill.width
  implicitHeight: pill.height

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": BluetoothService.enabled ? I18n.tr("actions.disable-bluetooth") : I18n.tr("actions.enable-bluetooth"),
        "action": "toggle-bluetooth",
        "icon": BluetoothService.enabled ? "bluetooth-off" : "bluetooth"
      },
      {
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
                   contextMenu.close();
                   PanelService.closeContextMenu(screen);

                   if (action === "toggle-bluetooth") {
                     BluetoothService.setBluetoothEnabled(!BluetoothService.enabled);
                   } else if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  BarPill {
    id: pill

    screen: root.screen
    oppositeDirection: BarService.getPillDirection(root)
    customIconColor: Color.resolveColorKeyOptional(root.iconColorKey)
    customTextColor: Color.resolveColorKeyOptional(root.textColorKey)
    icon: !BluetoothService.enabled ? "bluetooth-off" : ((BluetoothService.connectedDevices && BluetoothService.connectedDevices.length > 0) ? "bluetooth-connected" : "bluetooth")
    text: {
      if (BluetoothService.connectedDevices && BluetoothService.connectedDevices.length > 0) {
        const firstDevice = BluetoothService.connectedDevices[0];
        return firstDevice.name || firstDevice.deviceName;
      }
      return "";
    }
    suffix: {
      if (BluetoothService.connectedDevices && BluetoothService.connectedDevices.length > 1) {
        return ` + ${BluetoothService.connectedDevices.length - 1}`;
      }
      return "";
    }
    autoHide: false
    forceOpen: !isBarVertical && root.displayMode === "alwaysShow"
    forceClose: isBarVertical || root.displayMode === "alwaysHide" || text === ""
    onClicked: {
      var p = PanelService.getPanel("bluetoothPanel", screen);
      if (p)
        p.toggle(this);
    }
    onRightClicked: {
      PanelService.showContextMenu(contextMenu, pill, screen);
    }
    tooltipText: {
      if (pill.text !== "") {
        return pill.text;
      }
      return I18n.tr("tooltips.bluetooth-devices");
    }
  }
}
