import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Power
import qs.Widgets

NIconButtonHot {
  property ShellScreen screen

  icon: IdleInhibitorService.isInhibited ? "keep-awake-on" : "keep-awake-off"
  hot: IdleInhibitorService.isInhibited
  tooltipText: I18n.tr("quickSettings.keepAwake.tooltip.action")
  onClicked: IdleInhibitorService.manualToggle()
}
