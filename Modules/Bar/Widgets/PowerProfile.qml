import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import qs.Commons
import qs.Services
import qs.Widgets

NIconButton {
  id: root

  property ShellScreen screen
  property real scaling: ScalingService.scale(screen)
  property var powerProfiles: PowerProfiles
  readonly property bool hasPP: powerProfiles.hasPerformanceProfile

  sizeMultiplier: 0.8
  visible: hasPP

  function profileIcon() {
    if (!hasPP)
      return "balance"
    if (powerProfiles.profile === PowerProfile.Performance)
      return "speed"
    if (powerProfiles.profile === PowerProfile.Balanced)
      return "balance"
    if (powerProfiles.profile === PowerProfile.PowerSaver)
      return "eco"
  }

  function profileName() {
    if (!hasPP)
      return "Unknown"
    if (powerProfiles.profile === PowerProfile.Performance)
      return "Performance"
    if (powerProfiles.profile === PowerProfile.Balanced)
      return "Balanced"
    if (powerProfiles.profile === PowerProfile.PowerSaver)
      return "Power Saver"
  }

  function changeProfile() {
    if (!hasPP)
      return
    if (powerProfiles.profile === PowerProfile.Performance)
      powerProfiles.profile = PowerProfile.PowerSaver
    else if (powerProfiles.profile === PowerProfile.Balanced)
      powerProfiles.profile = PowerProfile.Performance
    else if (powerProfiles.profile === PowerProfile.PowerSaver)
      powerProfiles.profile = PowerProfile.Balanced
  }

  icon: root.profileIcon()
  tooltipText: root.profileName()
  colorBg: Color.mSurfaceVariant
  colorFg: Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent
  onClicked: root.changeProfile()
}
