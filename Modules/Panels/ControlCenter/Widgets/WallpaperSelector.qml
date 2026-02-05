import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

NIconButtonHot {
  property ShellScreen screen

  enabled: Settings.data.wallpaper.enabled
  icon: "wallpaper-selector"
  tooltipText: I18n.tr("wallpaper.panel.title")
  onClicked: PanelService.getPanel("wallpaperPanel", screen)?.toggle()
  onRightClicked: WallpaperService.setRandomWallpaper(null)
}
