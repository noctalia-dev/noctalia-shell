import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Networking
import qs.Services.UI
import qs.Widgets

NIconButtonHot {
  property ShellScreen screen
  icon: NetworkService.getIcon()
  tooltipText: NetworkService.getStatusText(true)
  onClicked: {
    var panel = PanelService.getPanel("networkPanel", screen);
    panel?.toggle(this);
  }
  onRightClicked: {
    if (!NetworkService.airplaneModeEnabled) {
      NetworkService.setWifiEnabled(!NetworkService.wifiEnabled);
    }
  }
}
