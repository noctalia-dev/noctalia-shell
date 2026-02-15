import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.Bar.Extras
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

  readonly property string iconColorKey: widgetSettings.iconColor !== undefined ? widgetSettings.iconColor : widgetMetadata.iconColor

  enabled: Settings.data.wallpaper.enabled
  baseSize: Style.getCapsuleHeightForScreen(screen?.name)
  applyUiScale: false
  customRadius: Style.radiusL
  icon: "wallpaper-selector"
  tooltipText: I18n.tr("tooltips.wallpaper-selector")
  tooltipDirection: BarService.getTooltipDirection(screen?.name)
  colorBg: Style.capsuleColor
  colorFg: Color.resolveColorKey(iconColorKey)
  border.color: Style.capsuleBorderColor
  border.width: Style.capsuleBorderWidth

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("actions.random-wallpaper"),
        "action": "random-wallpaper",
        "icon": "dice"
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

                   if (action === "random-wallpaper") {
                     WallpaperService.setRandomWallpaper();
                   } else if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  onClicked: {
    var wallpaperPanel = PanelService.getPanel("wallpaperPanel", screen);
    if (Settings.data.wallpaper.panelPosition === "follow_bar") {
      wallpaperPanel?.toggle(this);
    } else {
      wallpaperPanel?.toggle();
    }
  }
  onRightClicked: {
    PanelService.showContextMenu(contextMenu, root, screen);
  }
}
