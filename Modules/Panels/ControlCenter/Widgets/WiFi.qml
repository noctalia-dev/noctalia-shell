import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

NIconButtonHot {
  property ShellScreen screen

  icon: {
    try {
      if (NetworkService.ethernetConnected) {
        return "ethernet"
      }
      let connected = false
      let signalStrength = 0
      for (const net in NetworkService.networks) {
        if (NetworkService.networks[net].connected) {
          connected = true
          signalStrength = NetworkService.networks[net].signal
          break
        }
      }
      return connected ? NetworkService.signalIcon(signalStrength, true) : "wifi-off"
    } catch (error) {
      Logger.e("Wi-Fi", "Error getting icon:", error)
      return "signal_wifi_bad"
    }
  }

  tooltipText: I18n.tr("quickSettings.wifi.tooltip.action")
  onClicked: PanelService.getPanel("wifiPanel", screen)?.toggle(this)
}
