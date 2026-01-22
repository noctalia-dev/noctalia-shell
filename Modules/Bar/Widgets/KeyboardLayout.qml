import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Keyboard
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
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property string displayMode: (widgetSettings.displayMode !== undefined) ? widgetSettings.displayMode : widgetMetadata.displayMode
  readonly property bool showIcon: (widgetSettings.showIcon !== undefined) ? widgetSettings.showIcon : widgetMetadata.showIcon

  // Use the shared service for keyboard layout
  property string currentLayout: KeyboardLayoutService.currentLayout

  readonly property string barPosition: Settings.getBarPositionForScreen(screen?.name)
  readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"

  implicitWidth: pill.width
  implicitHeight: pill.height

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.close();
                   }

                   if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  BarPill {
    id: pill
    anchors.verticalCenter: parent.verticalCenter
    screen: root.screen
    oppositeDirection: BarService.getPillDirection(root)
    icon: root.showIcon ? "keyboard" : ""
    autoHide: false // Important to be false so we can hover as long as we want
    text: { // Prevent text from exceeding the widget when bar is vertical
      let txt = currentLayout.toUpperCase();
      if (root.isBarVertical) {
        return txt.replace("(", "\n").replace(")", "");
      }
      return txt;
    }
    tooltipText: I18n.tr("tooltips.keyboard-layout", {
                           "layout": currentLayout.toUpperCase()
                         })
    // When icon is disabled, always show the layout text
    forceOpen: !root.showIcon || root.displayMode === "forceOpen"
    forceClose: root.showIcon && root.displayMode === "alwaysHide"
    onClicked: {}
    onRightClicked: {
      var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
      if (popupMenuWindow) {
        popupMenuWindow.showContextMenu(contextMenu);
        contextMenu.openAtItem(pill, screen);
      }
    }
  }
}
