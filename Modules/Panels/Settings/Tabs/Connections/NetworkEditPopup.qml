import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Networking
import qs.Services.UI
import qs.Widgets

Popup {
  id: root
  modal: true
  closePolicy: Popup.NoAutoClose
  dim: true
  anchors.centerIn: parent

  width: Math.min(550 * Style.uiScaleRatio, parent.width * 0.9)
  padding: Style.marginL

  // Input properties
  property string connectionName: ""
  property bool isActive: false
  property bool isWifi: true

  // Internal state
  property bool loading: true
  property string errorMsg: ""

  // IPv4 fields
  property string ipv4Method: "auto"
  property string ipv4Address: ""
  property string ipv4Gateway: ""
  property string ipv4Dns: ""

  // IPv6 fields
  property string ipv6Method: "auto"
  property string ipv6Address: ""
  property string ipv6Gateway: ""
  property string ipv6Dns: ""

  // General fields
  property int mtu: 0

  signal applied()

  property var _settingsSlot: null
  property var _modifiedSlot: null

  background: Rectangle {
    color: Color.mSurface
    radius: Style.radiusL
    border.color: Color.mOutline
    border.width: Style.borderS
  }

  function openEdit(connName, active, wifi) {
    connectionName = connName;
    isActive = active;
    isWifi = wifi;
    loading = true;
    errorMsg = "";

    // Clean up old signal connections
    try { NetworkService.connectionSettingsLoaded.disconnect(root._settingsSlot); } catch (e) {}
    try { NetworkService.connectionModified.disconnect(root._modifiedSlot); } catch (e) {}

    // Connect settings loaded handler
    root._settingsSlot = function(settings) {
      try { NetworkService.connectionSettingsLoaded.disconnect(root._settingsSlot); } catch (e) {}
      if (!settings) {
        root.errorMsg = I18n.tr("wifi.edit.error-load-failed");
        root.loading = false;
        return;
      }
      root.ipv4Method = settings.ipv4Method || "auto";
      root.ipv4Address = settings.ipv4Address || "";
      root.ipv4Gateway = settings.ipv4Gateway || "";
      root.ipv4Dns = settings.ipv4Dns || "";
      root.ipv6Method = settings.ipv6Method || "auto";
      root.ipv6Address = settings.ipv6Address || "";
      root.ipv6Gateway = settings.ipv6Gateway || "";
      root.ipv6Dns = settings.ipv6Dns || "";
      root.mtu = settings.mtu || 0;
      root.loading = false;
    };
    NetworkService.connectionSettingsLoaded.connect(root._settingsSlot);

    // Connect modify result handler
    root._modifiedSlot = function(success, err) {
      try { NetworkService.connectionModified.disconnect(root._modifiedSlot); } catch (e) {}
      if (success) {
        root.close();
        root.applied();
      } else {
        root.errorMsg = err || I18n.tr("wifi.edit.error-apply-failed");
      }
    };
    NetworkService.connectionModified.connect(root._modifiedSlot);

    root.open();
    NetworkService.getConnectionSettings(connName, wifi);
  }

  // Validation helpers
  function isValidIpv4(ip) {
    if (!ip) return true;
    var re = /^(\d{1,3}\.){3}\d{1,3}(\/\d{1,2})?$/;
    if (!re.test(ip)) return false;
    var parts = ip.split("/")[0].split(".");
    for (var i = 0; i < parts.length; i++) {
      if (parseInt(parts[i]) > 255) return false;
    }
    return true;
  }

  function isValidIpv6(ip) {
    if (!ip) return true;
    var addr = ip.split("/")[0];
    return /^[0-9a-fA-F:]+$/.test(addr) && addr.indexOf(":") !== -1;
  }

  function isValidDnsList(dns, isV6) {
    if (!dns) return true;
    var servers = dns.split(",");
    for (var i = 0; i < servers.length; i++) {
      var s = servers[i].trim();
      if (!s) continue;
      if (isV6 ? !isValidIpv6(s) : !isValidIpv4(s)) return false;
    }
    return true;
  }

  function canApply() {
    if (loading || NetworkService.modifyingConnection) return false;
    if (ipv4Method === "manual") {
      if (!ipv4Address || !isValidIpv4(ipv4Address)) return false;
      if (ipv4Gateway && !isValidIpv4(ipv4Gateway)) return false;
    }
    if (!isValidDnsList(ipv4Dns, false)) return false;
    if (ipv6Method === "manual") {
      if (!ipv6Address || !isValidIpv6(ipv6Address)) return false;
      if (ipv6Gateway && !isValidIpv6(ipv6Gateway)) return false;
    }
    if (!isValidDnsList(ipv6Dns, true)) return false;
    return true;
  }

  function applySettings() {
    if (!canApply()) return;
    errorMsg = "";

    var v4dns = ipv4Dns.split(",").map(function(s) { return s.trim(); }).filter(function(s) { return s; }).join(" ");
    var v6dns = ipv6Dns.split(",").map(function(s) { return s.trim(); }).filter(function(s) { return s; }).join(" ");

    // Default prefix if user omits it: /24 for IPv4, /64 for IPv6
    var v4addr = ipv4Address;
    if (v4addr && v4addr.indexOf("/") === -1) v4addr += "/24";
    var v6addr = ipv6Address;
    if (v6addr && v6addr.indexOf("/") === -1) v6addr += "/64";

    NetworkService.modifyConnection(connectionName, {
      ipv4Method: ipv4Method,
      ipv4Address: ipv4Method === "manual" ? v4addr : "",
      ipv4Gateway: ipv4Method === "manual" ? ipv4Gateway : "",
      ipv4Dns: v4dns,
      ipv6Method: ipv6Method,
      ipv6Address: ipv6Method === "manual" ? v6addr : "",
      ipv6Gateway: ipv6Method === "manual" ? ipv6Gateway : "",
      ipv6Dns: v6dns,
      mtu: mtu
    }, isActive, isWifi);
  }

  onClosed: {
    try { NetworkService.connectionSettingsLoaded.disconnect(root._settingsSlot); } catch (e) {}
    try { NetworkService.connectionModified.disconnect(root._modifiedSlot); } catch (e) {}
  }

  contentItem: Flickable {
    id: flickable
    implicitHeight: Math.min(contentColumn.implicitHeight, root.parent ? root.parent.height * 0.8 : 600)
    contentHeight: contentColumn.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
      id: contentColumn
      width: flickable.width
      spacing: Style.marginL

      // Header
      RowLayout {
        Layout.fillWidth: true
        NText {
          text: I18n.tr("wifi.edit.title") + " — " + root.connectionName
          font.weight: Style.fontWeightBold
          pointSize: Style.fontSizeL
          Layout.fillWidth: true
          elide: Text.ElideRight
        }
        NIconButton {
          icon: "close"
          onClicked: root.close()
        }
      }

      // Loading indicator
      NText {
        visible: root.loading
        text: "..."
        color: Color.mOnSurfaceVariant
        Layout.alignment: Qt.AlignHCenter
      }

      // === IPv4 Section ===
      ColumnLayout {
        visible: !root.loading
        Layout.fillWidth: true
        spacing: Style.marginM

        NText {
          text: I18n.tr("wifi.edit.ipv4")
          pointSize: Style.fontSizeM
          font.weight: Style.fontWeightSemiBold
          color: Color.mPrimary
        }

        NComboBox {
          id: ipv4MethodCombo
          Layout.fillWidth: true
          label: I18n.tr("wifi.edit.method")
          model: [
            { key: "auto", name: I18n.tr("wifi.edit.method-auto") },
            { key: "manual", name: I18n.tr("wifi.edit.method-manual") },
            { key: "disabled", name: I18n.tr("wifi.edit.method-disabled") }
          ]
          currentKey: root.ipv4Method
          onSelected: key => root.ipv4Method = key
        }

        NTextInput {
          id: ipv4AddressInput
          Layout.fillWidth: true
          label: I18n.tr("wifi.edit.address")
          placeholderText: I18n.tr("wifi.edit.address-placeholder-v4")
          text: root.ipv4Address
          onTextChanged: root.ipv4Address = text
          visible: root.ipv4Method === "manual"
        }
        NText {
          visible: ipv4AddressInput.visible && root.ipv4Address && !root.isValidIpv4(root.ipv4Address)
          text: I18n.tr("wifi.edit.error-invalid-ip")
          pointSize: Style.fontSizeXS
          color: Color.mError
        }

        NTextInput {
          id: ipv4GatewayInput
          Layout.fillWidth: true
          label: I18n.tr("wifi.edit.gateway")
          placeholderText: I18n.tr("wifi.edit.gateway-placeholder-v4")
          text: root.ipv4Gateway
          onTextChanged: root.ipv4Gateway = text
          visible: root.ipv4Method === "manual"
        }
        NText {
          visible: ipv4GatewayInput.visible && root.ipv4Gateway && !root.isValidIpv4(root.ipv4Gateway)
          text: I18n.tr("wifi.edit.error-invalid-gateway")
          pointSize: Style.fontSizeXS
          color: Color.mError
        }

        NTextInput {
          id: ipv4DnsInput
          Layout.fillWidth: true
          label: I18n.tr("wifi.edit.dns") + " (" + I18n.tr("wifi.edit.dns-hint") + ")"
          placeholderText: I18n.tr("wifi.edit.dns-placeholder-v4")
          text: root.ipv4Dns
          onTextChanged: root.ipv4Dns = text
          visible: root.ipv4Method !== "disabled"
        }
        NText {
          visible: ipv4DnsInput.visible && root.ipv4Dns && !root.isValidDnsList(root.ipv4Dns, false)
          text: I18n.tr("wifi.edit.error-invalid-dns")
          pointSize: Style.fontSizeXS
          color: Color.mError
        }
      }

      // Separator
      Rectangle {
        visible: !root.loading
        Layout.fillWidth: true
        height: Style.borderS
        color: Color.mOutline
      }

      // === IPv6 Section ===
      ColumnLayout {
        visible: !root.loading
        Layout.fillWidth: true
        spacing: Style.marginM

        NText {
          text: I18n.tr("wifi.edit.ipv6")
          pointSize: Style.fontSizeM
          font.weight: Style.fontWeightSemiBold
          color: Color.mPrimary
        }

        NComboBox {
          id: ipv6MethodCombo
          Layout.fillWidth: true
          label: I18n.tr("wifi.edit.method")
          model: [
            { key: "auto", name: I18n.tr("wifi.edit.method-auto") },
            { key: "manual", name: I18n.tr("wifi.edit.method-manual") },
            { key: "link-local", name: I18n.tr("wifi.edit.method-link-local") },
            { key: "disabled", name: I18n.tr("wifi.edit.method-disabled") }
          ]
          currentKey: root.ipv6Method
          onSelected: key => root.ipv6Method = key
        }

        NTextInput {
          id: ipv6AddressInput
          Layout.fillWidth: true
          label: I18n.tr("wifi.edit.address")
          placeholderText: I18n.tr("wifi.edit.address-placeholder-v6")
          text: root.ipv6Address
          onTextChanged: root.ipv6Address = text
          visible: root.ipv6Method === "manual"
        }
        NText {
          visible: ipv6AddressInput.visible && root.ipv6Address && !root.isValidIpv6(root.ipv6Address)
          text: I18n.tr("wifi.edit.error-invalid-ip")
          pointSize: Style.fontSizeXS
          color: Color.mError
        }

        NTextInput {
          id: ipv6GatewayInput
          Layout.fillWidth: true
          label: I18n.tr("wifi.edit.gateway")
          placeholderText: I18n.tr("wifi.edit.gateway-placeholder-v6")
          text: root.ipv6Gateway
          onTextChanged: root.ipv6Gateway = text
          visible: root.ipv6Method === "manual"
        }
        NText {
          visible: ipv6GatewayInput.visible && root.ipv6Gateway && !root.isValidIpv6(root.ipv6Gateway)
          text: I18n.tr("wifi.edit.error-invalid-gateway")
          pointSize: Style.fontSizeXS
          color: Color.mError
        }

        NTextInput {
          id: ipv6DnsInput
          Layout.fillWidth: true
          label: I18n.tr("wifi.edit.dns") + " (" + I18n.tr("wifi.edit.dns-hint") + ")"
          placeholderText: I18n.tr("wifi.edit.dns-placeholder-v6")
          text: root.ipv6Dns
          onTextChanged: root.ipv6Dns = text
          visible: root.ipv6Method !== "disabled"
        }
        NText {
          visible: ipv6DnsInput.visible && root.ipv6Dns && !root.isValidDnsList(root.ipv6Dns, true)
          text: I18n.tr("wifi.edit.error-invalid-dns")
          pointSize: Style.fontSizeXS
          color: Color.mError
        }
      }

      // Separator
      Rectangle {
        visible: !root.loading
        Layout.fillWidth: true
        height: Style.borderS
        color: Color.mOutline
      }

      // === General Section ===
      ColumnLayout {
        visible: !root.loading
        Layout.fillWidth: true
        spacing: Style.marginM

        NText {
          text: I18n.tr("wifi.edit.general")
          pointSize: Style.fontSizeM
          font.weight: Style.fontWeightSemiBold
          color: Color.mPrimary
        }

        NSpinBox {
          id: mtuSpinBox
          Layout.fillWidth: true
          label: I18n.tr("wifi.edit.mtu")
          description: I18n.tr("wifi.edit.mtu-description")
          value: root.mtu
          from: 0
          to: 9000
          stepSize: 1
          onValueChanged: root.mtu = value
        }
      }

      // Error message
      NText {
        visible: root.errorMsg.length > 0
        text: root.errorMsg
        color: Color.mError
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }

      // Footer buttons
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        Item { Layout.fillWidth: true }

        NButton {
          text: I18n.tr("wifi.edit.cancel")
          outlined: true
          onClicked: root.close()
        }

        NButton {
          text: NetworkService.modifyingConnection ? I18n.tr("wifi.edit.applying") : I18n.tr("wifi.edit.apply")
          icon: "check"
          backgroundColor: Color.mPrimary
          textColor: Color.mOnPrimary
          enabled: root.canApply()
          onClicked: root.applySettings()
        }
      }
    }
  }
}
