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

  implicitWidth: pill.width
  implicitHeight: pill.height

  NPopupContextMenu {
    id: contextMenu

    model: {
      const items = [];
      const active = VPNService.activeConnections;
      for (let i = 0; i < active.length; ++i) {
        const conn = active[i];
        items.push({
                     "label": I18n.tr("actions.disconnect-vpn", {
                                        "name": conn.name
                                      }),
                     "action": "disconnect:" + conn.uuid,
                     "icon": "shield-off"
                   });
      }
      const inactive = VPNService.inactiveConnections;
      for (let i = 0; i < inactive.length; ++i) {
        const conn = inactive[i];
        items.push({
                     "label": I18n.tr("actions.connect-vpn", {
                                        "name": conn.name
                                      }),
                     "action": "connect:" + conn.uuid,
                     "icon": "shield-lock"
                   });
      }
      items.push({
                   "label": I18n.tr("actions.widget-settings"),
                   "action": "widget-settings",
                   "icon": "settings"
                 });
      return items;
    }

    onTriggered: action => {
                   contextMenu.close();
                   PanelService.closeContextMenu(screen);

                   if (!action) {
                     return;
                   }
                   if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                     return;
                   }
                   if (action.startsWith("connect:")) {
                     const uuid = action.substring("connect:".length);
                     VPNService.connect(uuid);
                     return;
                   }
                   if (action.startsWith("disconnect:")) {
                     const uuid = action.substring("disconnect:".length);
                     VPNService.disconnect(uuid);
                   }
                 }
  }

  BarPill {
    id: pill

    screen: root.screen
    oppositeDirection: BarService.getPillDirection(root)
    icon: VPNService.hasActiveConnection ? "shield-lock" : "shield"
    text: {
      if (VPNService.activeConnections.length > 0) {
        return VPNService.activeConnections[0].name;
      }
      if (VPNService.connectingUuid) {
        const pending = VPNService.connections[VPNService.connectingUuid];
        if (pending) {
          return pending.name;
        }
      }
      return "";
    }
    suffix: {
      if (VPNService.activeConnections.length > 1) {
        return ` + ${VPNService.activeConnections.length - 1}`;
      }
      return "";
    }
    autoHide: false
    forceOpen: !isBarVertical && root.displayMode === "alwaysShow"
    forceClose: isBarVertical || root.displayMode === "alwaysHide" || !pill.text
    onRightClicked: {
      PanelService.showContextMenu(contextMenu, pill, screen);
    }
    tooltipText: {
      if (pill.text !== "") {
        return pill.text;
      }
      return I18n.tr("tooltips.manage-vpn");
    }
  }
}
