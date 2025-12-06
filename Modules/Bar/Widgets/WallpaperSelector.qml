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

  baseSize: Style.capsuleHeight
  applyUiScale: false
  density: Settings.data.bar.density
  customRadius: Style.radiusL
  icon: "wallpaper-selector"
  tooltipText: I18n.tr("tooltips.open-wallpaper-selector")
  tooltipDirection: BarService.getTooltipDirection()
  colorBg: Style.capsuleColor
  colorFg: Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("context-menu.random-wallpaper"),
        "action": "random-wallpaper",
        "icon": "dice"
      },
    ]

    onTriggered: action => {
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.close();
                   }

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
    var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
    if (popupMenuWindow) {
      popupMenuWindow.showContextMenu(contextMenu);
      const pos = BarService.getContextMenuPosition(root, contextMenu.implicitWidth, contextMenu.implicitHeight);
      contextMenu.openAtItem(root, pos.x, pos.y);
    }
  }
}
