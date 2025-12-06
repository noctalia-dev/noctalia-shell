import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

NIconButton {
  id: root

  property ShellScreen screen

  icon: "dark-mode"
  tooltipText: Settings.data.colorSchemes.darkMode ? I18n.tr("tooltips.switch-to-light-mode") : I18n.tr("tooltips.switch-to-dark-mode")
  tooltipDirection: BarService.getTooltipDirection()
  density: Settings.data.bar.density
  baseSize: Style.capsuleHeight
  applyUiScale: false
  customRadius: Style.radiusL
  colorBg: Style.capsuleColor
  colorFg: Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent
  onClicked: Settings.data.colorSchemes.darkMode = !Settings.data.colorSchemes.darkMode
}
