import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

NIconButton {
  id: root

  property ShellScreen screen

  icon: "dark-mode"
  tooltipText: Settings.data.colorSchemes.darkMode ? I18n.tr("tooltips.switch-to-light-mode") : I18n.tr("tooltips.switch-to-dark-mode")
  tooltipDirection: BarService.getTooltipDirection()
  density: Settings.data.bar.density
  baseSize: Style.capsuleHeight
  applyUiScale: false
  colorBg: Settings.data.colorSchemes.darkMode ? (Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent) : Color.mPrimary
  colorFg: Settings.data.colorSchemes.darkMode ? Color.mOnSurface : Color.mOnPrimary
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent
  onClicked: Settings.data.colorSchemes.darkMode = !Settings.data.colorSchemes.darkMode
}
