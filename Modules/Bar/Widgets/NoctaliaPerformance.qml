import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Modules.Panels.Settings
import qs.Services.Power
import qs.Services.UI
import qs.Widgets

NIconButton {
  id: root

  property ShellScreen screen

  density: Settings.data.bar.density
  baseSize: Style.capsuleHeight
  applyUiScale: false
  customRadius: Style.radiusL
  colorBg: PowerProfileService.noctaliaPerformanceMode ? Color.mPrimary : Style.capsuleColor
  colorFg: PowerProfileService.noctaliaPerformanceMode ? Color.mOnPrimary : Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent

  icon: PowerProfileService.noctaliaPerformanceMode ? "rocket" : "rocket-off"
  tooltipText: PowerProfileService.noctaliaPerformanceMode ? I18n.tr("tooltips.noctalia-performance-enabled") : I18n.tr("tooltips.noctalia-performance-disabled")
  tooltipDirection: BarService.getTooltipDirection()
  onClicked: {
    PowerProfileService.toggleNoctaliaPerformance();
  }
}
