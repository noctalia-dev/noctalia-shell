import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.Panels.Settings
import qs.Services.UI
import qs.Widgets

NIconButton {
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

  readonly property string iconName: widgetSettings.icon || (widgetMetadata ? widgetMetadata.icon : "search")
  readonly property string iconColorKey: widgetSettings.iconColor !== undefined ? widgetSettings.iconColor : widgetMetadata.iconColor

  icon: iconName
  tooltipText: I18n.tr("actions.open-launcher")
  tooltipDirection: BarService.getTooltipDirection(screenName)
  baseSize: Style.getCapsuleHeightForScreen(screenName)
  applyUiScale: false
  customRadius: Style.radiusL
  colorBg: Style.capsuleColor
  colorBgHover: Color.mHover
  colorFg: Color.resolveColorKey(iconColorKey)
  colorFgHover: Color.mOnHover
  colorBorder: Style.capsuleBorderColor
  colorBorderHover: Style.capsuleBorderColor

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("actions.launcher-settings"),
        "action": "launcher-settings",
        "icon": "adjustments"
      },
      {
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      }
    ]

    onTriggered: action => {
                   contextMenu.close();
                   PanelService.closeContextMenu(screen);

                   if (action === "launcher-settings") {
                     var panel = PanelService.getPanel("settingsPanel", screen);
                     panel.requestedTab = SettingsPanel.Tab.Launcher;
                     panel.toggle();
                   } else if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  onClicked: PanelService.toggleLauncher(screen)
  onMiddleClicked: PanelService.toggleLauncher(screen)
  onRightClicked: {
    PanelService.showContextMenu(contextMenu, root, screen);
  }
}
