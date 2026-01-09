import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Networking
import qs.Services.UI
import qs.Widgets

NIconButtonHot {
  property ShellScreen screen

  icon: {
    try {
      if (NetworkService.ethernetConnected) {
        return NetworkService.internetConnectivity ? "ethernet" : "ethernet-off";
      }
      let connected = false;
      let signalStrength = 0;
      for (const net in NetworkService.networks) {
        if (NetworkService.networks[net].connected) {
          connected = true;
          signalStrength = NetworkService.networks[net].signal;
          break;
        }
      }
      return connected ? NetworkService.signalIcon(signalStrength, true) : "wifi-off";
    } catch (error) {
      Logger.e("Wi-Fi", "Error getting icon:", error);
      return "wifi-off";
    }
  }

  tooltipText: {
    try {
      if (NetworkService.ethernetConnected) {
        // Match design: fixed label when on Ethernet
        return I18n.tr("control-center.wifi.label-ethernet");
      }
      // Wi‑Fi: SSID — link speed (if available)
      for (const net in NetworkService.networks) {
        if (NetworkService.networks[net].connected) {
          const w = NetworkService.activeWifiDetails || ({});
          const rate = (w.rateShort && w.rateShort.length > 0) ? w.rateShort : (w.rate || "");
          return rate && rate.length > 0 ? (net + " — " + rate) : net;
        }
      }
    } catch (e) {
      // noop
    }
    return I18n.tr("tooltips.manage-wifi");
  }
  onClicked: {
    var panel = PanelService.getPanel("networkPanel", screen);
    panel?.toggle(this);
  }
  onRightClicked: NetworkService.setWifiEnabled(!Settings.data.network.wifiEnabled)
}
