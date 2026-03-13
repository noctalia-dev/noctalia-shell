import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Networking
import qs.Services.UI
import qs.Widgets

NIconButtonHot {
  property ShellScreen screen

  function getStatustxt() {
    if (NetworkService.connecting) {
      return NetworkService.connectingTo ? I18n.tr("common.connecting") + " " + NetworkService.connectingTo : I18n.tr("common.connecting"); // Im hoping for the best :P
    }

    let p = [];

    // Ethernet
    if (NetworkService.ethernetConnected) {
      const eth = NetworkService.activeEthernetDetails;
      const name = eth.connectionName || (NetworkService.ethernetInterfaces.length > 0 ? NetworkService.ethernetInterfaces[0].connectionName : "") || NetworkService.activeEthernetIf || "";
      const speed = eth.speed || "";
      const s = name ? (speed ? name + " - " + speed : name) : "";
      if (s) {
        p.push(s);
      }
    }

    // Wi-Fi
    if (NetworkService.activeWifiIf) {
      const wl = NetworkService.activeWifiDetails;
      const speed = wl.rateShort || wl.rate || "";
      const connectedNet = Object.values(NetworkService.networks).find(net => net.connected);
      const name = connectedNet ? connectedNet.ssid : (wl.connectionName || NetworkService.activeWifiIf || "");
      const s = name ? (speed ? name + " - " + speed : name) : "";
      if (s) {
        p.push(s);
      }
    }
    return p.join(" + ");
  }

  function getIcon() {
    if (NetworkService.ethernetConnected) {
      return NetworkService.internetConnectivity ? "ethernet" : "ethernet-off";
    }
    const connectedNet = Object.values(NetworkService.networks).find(net => net.connected);
    return connectedNet ? NetworkService.signalIcon(connectedNet.signal, true) : "wifi-off";
  }

  icon: getIcon()
  tooltipText: getStatustxt()
  onClicked: {
    var panel = PanelService.getPanel("networkPanel", screen);
    panel?.toggle(this);
  }
  onRightClicked: {
    if (!Settings.data.network.airplaneModeEnabled) {
      NetworkService.setWifiEnabled(!Settings.data.network.wifiEnabled);
    }
  }
}
