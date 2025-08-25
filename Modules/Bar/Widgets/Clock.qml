import QtQuick
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

Rectangle {
  id: root

  property ShellScreen screen
  property real scaling: ScalingService.scale(screen)

  implicitWidth: clock.width + Style.marginM * 2 * scaling
  implicitHeight: Math.round(Style.capsuleHeight * scaling)
  radius: Math.round(Style.radiusM * scaling)
  color: Color.mSurfaceVariant

  // Clock Icon with attached calendar
  NClock {
    id: clock
    anchors.verticalCenter: parent.verticalCenter
    anchors.horizontalCenter: parent.horizontalCenter

    NTooltip {
      id: tooltip
      text: Time.dateString
      target: clock
      positionAbove: Settings.data.bar.position === "bottom"
    }

    onEntered: {
      if (!PanelService.getPanel("calendarPanel")?.active) {
        tooltip.show()
      }
    }
    onExited: {
      tooltip.hide()
    }
    onClicked: {
      tooltip.hide()
      PanelService.getPanel("calendarPanel")?.toggle(screen)
    }
  }
}
