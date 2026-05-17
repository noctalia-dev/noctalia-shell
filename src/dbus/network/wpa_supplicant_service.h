#pragma once

#include "dbus/network/inetwork_service.h"
#include "dbus/network/network_service.h" // for static glyph helpers and shared types

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

class SystemBus;

namespace sdbus {
  class IProxy;
}

// Read-only network backend for systems running wpa_supplicant without NetworkManager.
// Exposes the same INetworkService interface as NetworkService so the UI works with
// either backend transparently.
//
// Limitations compared to the NM backend:
//   - No VPN support (wpa_supplicant has no VPN concept).
//   - activateAccessPoint / disconnect / forgetSsid are no-ops.
//   - setWirelessEnabled is a no-op (rfkill is a separate interface).
class WpaSupplicantService : public INetworkService {
public:
  explicit WpaSupplicantService(SystemBus& bus);
  ~WpaSupplicantService() override;

  WpaSupplicantService(const WpaSupplicantService&) = delete;
  WpaSupplicantService& operator=(const WpaSupplicantService&) = delete;

  void setChangeCallback(ChangeCallback callback) override;
  void refresh() override;

  [[nodiscard]] const NetworkState& state() const noexcept override { return m_state; }
  [[nodiscard]] bool hasStateSnapshot() const noexcept override { return m_hasStateSnapshot; }
  [[nodiscard]] const std::vector<AccessPointInfo>& accessPoints() const noexcept override { return m_accessPoints; }
  [[nodiscard]] const std::vector<VpnConnectionInfo>& vpnConnections() const noexcept override {
    return m_vpnConnections;
  }

  void requestScan() override;

  // No-ops — wpa_supplicant connection management is not implemented.
  bool activateAccessPoint(const AccessPointInfo& /*ap*/) override { return false; }
  bool activateAccessPoint(const AccessPointInfo& /*ap*/, const std::string& /*psk*/) override { return false; }
  bool activateVpnConnection(const VpnConnectionInfo& /*vpn*/) override { return false; }
  bool deactivateVpnConnection(const VpnConnectionInfo& /*vpn*/) override { return false; }
  void setWirelessEnabled(bool /*enabled*/) override {}
  void disconnect() override {}
  void forgetSsid(const std::string& /*ssid*/) override {}
  [[nodiscard]] bool hasSavedConnection(const std::string& /*ssid*/) const override { return false; }

private:
  void subscribeInterface(const std::string& ifacePath);
  void rebuildState();
  void emitChangedIfNeeded(NetworkState next);

  SystemBus& m_bus;
  std::unique_ptr<sdbus::IProxy> m_wpa;
  std::unordered_map<std::string, std::unique_ptr<sdbus::IProxy>> m_interfaces;
  NetworkState m_state;
  std::vector<AccessPointInfo> m_accessPoints;
  const std::vector<VpnConnectionInfo> m_vpnConnections; // always empty
  bool m_hasStateSnapshot = false;
  ChangeCallback m_changeCallback;
};
