import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

NIconButton {
  id: root

  property ShellScreen screen

  density: Settings.data.bar.density
  baseSize: Style.capsuleHeight
  applyUiScale: false
  icon: "power"
  tooltipText: I18n.tr("tooltips.session-menu")
  tooltipDirection: BarService.getTooltipDirection()
  colorBg: (Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent)
  colorFg: Color.mError
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent
  onClicked: PanelService.getPanel("sessionMenuPanel", screen)?.toggle()
}
