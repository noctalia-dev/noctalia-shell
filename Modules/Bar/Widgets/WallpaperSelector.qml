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

  enabled: Settings.data.wallpaper.enabled
  baseSize: Style.getCapsuleHeightForScreen(screen?.name)
  applyUiScale: false
  customRadius: Style.radiusL
  icon: "wallpaper-selector"
  tooltipText: I18n.tr("tooltips.wallpaper-selector")
  tooltipDirection: BarService.getTooltipDirection(screen?.name)
  colorBg: Style.capsuleColor
  colorFg: Color.mOnSurface
  colorBorder: "transparent"
  colorBorderHover: "transparent"
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
    ]

    onTriggered: action => {
                   contextMenu.close();
                   PanelService.closeContextMenu(screen);

                   if (action === "random-wallpaper") {
                     WallpaperService.setRandomWallpaper();
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
