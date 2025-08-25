import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NIconButton {
  id: root

  property ShellScreen screen
  property real scaling: ScalingService.scale(screen)

  sizeMultiplier: 0.8
  colorBg: Color.mSurfaceVariant
  colorFg: Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent

  // Enhanced icon states with better visual feedback
  icon: {
    if (ArchUpdaterService.busy)
      return "sync"
    if (ArchUpdaterService.updatePackages.length > 0) {
      // Show different icons based on update count
      const count = ArchUpdaterService.updatePackages.length
      if (count > 50)
        return "system_update_alt" // Many updates
      if (count > 10)
        return "system_update" // Moderate updates
      return "system_update" // Few updates
    }
    return "task_alt"
  }

  // Enhanced tooltip with more information
  tooltipText: {
    if (ArchUpdaterService.busy)
      return "Checking for updates…"

    var count = ArchUpdaterService.updatePackages.length
    if (count === 0)
      return "System is up to date ✓"

    var header = count === 1 ? "One package can be upgraded:" : (count + " packages can be upgraded:")

    var list = ArchUpdaterService.updatePackages || []
    var s = ""
    var limit = Math.min(list.length, 8)
    // Reduced to 8 for better readability
    for (var i = 0; i < limit; ++i) {
      var p = list[i]
      s += (i ? "\n" : "") + (p.name + ": " + p.oldVersion + " → " + p.newVersion)
    }
    if (list.length > 8)
      s += "\n… and " + (list.length - 8) + " more"

    return header + "\n\n" + s + "\n\nClick to update system"
  }

  // Enhanced click behavior with confirmation
  onClicked: {
    if (ArchUpdaterService.busy)
      return

    if (ArchUpdaterService.updatePackages.length > 0) {
      // Show confirmation dialog for updates
      PanelService.getPanel("archUpdaterPanel").toggle(screen)
    } else {
      // Just refresh if no updates available
      ArchUpdaterService.doPoll()
    }
  }
}
