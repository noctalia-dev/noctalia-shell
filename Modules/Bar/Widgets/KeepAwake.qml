import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Power
import qs.Services.UI
import qs.Widgets

NIconButton {
  id: root

  property ShellScreen screen

  baseSize: Style.capsuleHeight
  applyUiScale: false
  density: Settings.data.bar.density
  icon: IdleInhibitorService.isInhibited ? "keep-awake-on" : "keep-awake-off"
  tooltipText: IdleInhibitorService.isInhibited ? I18n.tr("tooltips.disable-keep-awake") : I18n.tr("tooltips.enable-keep-awake")
  tooltipDirection: BarService.getTooltipDirection()
  colorBg: IdleInhibitorService.isInhibited ? Color.mPrimary : (Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent)
  colorFg: IdleInhibitorService.isInhibited ? Color.mOnPrimary : Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent
  onClicked: IdleInhibitorService.manualToggle()
}
