import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
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
  customRadius: Style.radiusL
  visible: PowerProfileService.available
  icon: PowerProfileService.getIcon()
  tooltipText: I18n.tr("tooltips.power-profile", {
                         "profile": PowerProfileService.getName()
                       })
  tooltipDirection: BarService.getTooltipDirection()
  colorBg: (PowerProfileService.profile === PowerProfile.Balanced) ? Style.capsuleColor : Color.mPrimary
  colorFg: (PowerProfileService.profile === PowerProfile.Balanced) ? Color.mOnSurface : Color.mOnPrimary
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent
  onClicked: PowerProfileService.cycleProfile()
}
