import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.System
import qs.Services.UI
import qs.Widgets

NIconButtonHot {
  property ShellScreen screen

  icon: NotificationService.doNotDisturb ? "bell-off" : "bell"
  hot: NotificationService.doNotDisturb
  tooltipText: I18n.tr("common.notifications")
  onClicked: PanelService.getPanel("notificationHistoryPanel", screen)?.toggle(this)
  onRightClicked: NotificationService.doNotDisturb = !NotificationService.doNotDisturb
}
