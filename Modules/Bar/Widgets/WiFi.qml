import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

NIconButton {
  id: root

  property ShellScreen screen
  property real scaling: ScalingService.scale(screen)

  visible: Settings.data.network.wifiEnabled

  sizeMultiplier: 0.8

  Component.onCompleted: {
    Logger.log("WiFi", "Widget component completed")
    Logger.log("WiFi", "NetworkService available:", !!NetworkService)
    if (NetworkService) {
      Logger.log("WiFi", "NetworkService.networks available:", !!NetworkService.networks)
    }
  }

  colorBg: Color.mSurfaceVariant
  colorFg: Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent

  icon: {
    try {
      if (NetworkService.ethernet)
        return "lan"
      let connected = false
      let signalStrength = 0
      for (const net in NetworkService.networks) {
        if (NetworkService.networks[net].connected) {
          connected = true
          signalStrength = NetworkService.networks[net].signal
          break
        }
      }
      return connected ? NetworkService.signalIcon(signalStrength) : "wifi_find"
    } catch (error) {
      Logger.error("WiFi", "Error getting icon:", error)
      return "signal_wifi_bad"
    }
  }
  tooltipText: "Network / WiFi"
  onClicked: {
    try {
      Logger.log("WiFi", "Button clicked, toggling panel")
      PanelService.getPanel("wifiPanel")?.toggle(screen)
    } catch (error) {
      Logger.error("WiFi", "Error toggling panel:", error)
    }
  }
}
