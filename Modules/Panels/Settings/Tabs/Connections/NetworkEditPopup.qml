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
  height: Math.min(contentLayout.implicitHeight + padding * 2, parent.height * 0.85)
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
        root.errorMsg = I18n.tr("wifi.edit.error-apply-failed");
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
    NetworkService.getConnectionSettings(connName);
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

    NetworkService.modifyConnection(connectionName, {
      ipv4Method: ipv4Method,
      ipv4Address: ipv4Method === "manual" ? ipv4Address : "",
      ipv4Gateway: ipv4Method === "manual" ? ipv4Gateway : "",
      ipv4Dns: v4dns,
      ipv6Method: ipv6Method,
      ipv6Address: ipv6Method === "manual" ? ipv6Address : "",
      ipv6Gateway: ipv6Method === "manual" ? ipv6Gateway : "",
      ipv6Dns: v6dns,
      mtu: mtu
    }, isActive);
  }

  onClosed: {
    try { NetworkService.connectionSettingsLoaded.disconnect(root._settingsSlot); } catch (e) {}
    try { NetworkService.connectionModified.disconnect(root._modifiedSlot); } catch (e) {}
  }

  contentItem: ColumnLayout {
    id: contentLayout
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

    // Form content
    NScrollView {
      visible: !root.loading
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.maximumHeight: root.height - 160 * Style.uiScaleRatio

      ColumnLayout {
        width: parent.width
        spacing: Style.marginM

        // === IPv4 Section ===
        NCollapsible {
          label: I18n.tr("wifi.edit.ipv4")
          expanded: true
          Layout.fillWidth: true

          NComboBox {
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
            Layout.fillWidth: true
            label: I18n.tr("wifi.edit.address")
            placeholderText: I18n.tr("wifi.edit.address-placeholder-v4")
            text: root.ipv4Address
            onTextChanged: root.ipv4Address = text
            enabled: root.ipv4Method === "manual"
            readOnly: root.ipv4Method !== "manual"
          }

          NTextInput {
            Layout.fillWidth: true
            label: I18n.tr("wifi.edit.gateway")
            placeholderText: I18n.tr("wifi.edit.gateway-placeholder-v4")
            text: root.ipv4Gateway
            onTextChanged: root.ipv4Gateway = text
            enabled: root.ipv4Method === "manual"
            readOnly: root.ipv4Method !== "manual"
          }

          NTextInput {
            Layout.fillWidth: true
            label: I18n.tr("wifi.edit.dns") + " (" + I18n.tr("wifi.edit.dns-hint") + ")"
            placeholderText: I18n.tr("wifi.edit.dns-placeholder-v4")
            text: root.ipv4Dns
            onTextChanged: root.ipv4Dns = text
            enabled: root.ipv4Method !== "disabled"
            readOnly: root.ipv4Method === "disabled"
          }
        }

        // === IPv6 Section ===
        NCollapsible {
          label: I18n.tr("wifi.edit.ipv6")
          expanded: false
          Layout.fillWidth: true

          NComboBox {
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
            Layout.fillWidth: true
            label: I18n.tr("wifi.edit.address")
            placeholderText: I18n.tr("wifi.edit.address-placeholder-v6")
            text: root.ipv6Address
            onTextChanged: root.ipv6Address = text
            enabled: root.ipv6Method === "manual"
            readOnly: root.ipv6Method !== "manual"
          }

          NTextInput {
            Layout.fillWidth: true
            label: I18n.tr("wifi.edit.gateway")
            placeholderText: I18n.tr("wifi.edit.gateway-placeholder-v6")
            text: root.ipv6Gateway
            onTextChanged: root.ipv6Gateway = text
            enabled: root.ipv6Method === "manual"
            readOnly: root.ipv6Method !== "manual"
          }

          NTextInput {
            Layout.fillWidth: true
            label: I18n.tr("wifi.edit.dns") + " (" + I18n.tr("wifi.edit.dns-hint") + ")"
            placeholderText: I18n.tr("wifi.edit.dns-placeholder-v6")
            text: root.ipv6Dns
            onTextChanged: root.ipv6Dns = text
            enabled: root.ipv6Method !== "disabled"
            readOnly: root.ipv6Method === "disabled"
          }
        }

        // === General Section ===
        NCollapsible {
          label: I18n.tr("wifi.edit.general")
          expanded: false
          Layout.fillWidth: true

          NSpinBox {
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
