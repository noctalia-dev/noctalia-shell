import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NIconButtonHot {
  property ShellScreen screen

  icon: Settings.data.notifications.doNotDisturb ? "bell-off" : "bell"
  hot: Settings.data.notifications.doNotDisturb
  tooltipText: I18n.tr("quickSettings.notifications.tooltip.action")
  onClicked: PanelService.getPanel("notificationHistoryPanel", screen)?.toggle(this)
  onRightClicked: Settings.data.notifications.doNotDisturb = !Settings.data.notifications.doNotDisturb
}
