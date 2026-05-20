#pragma once

#include "dbus/network/inetwork_service.h"

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

class SystemBus;

namespace sdbus {
  class IProxy;
}

// Network backend for systems running iwd (iNet Wireless Daemon) without NetworkManager.
// Exposes the same INetworkService interface as NetworkManagerService and WpaSupplicantService.
class IwdService : public INetworkService {
public:
  explicit IwdService(SystemBus& bus);
  ~IwdService() override;

  IwdService(const IwdService&) = delete;
  IwdService& operator=(const IwdService&) = delete;

  void setChangeCallback(ChangeCallback callback) override;
  void refresh() override;

  [[nodiscard]] const NetworkState& state() const noexcept override { return m_state; }
  [[nodiscard]] bool hasStateSnapshot() const noexcept override { return m_hasStateSnapshot; }
  [[nodiscard]] const std::vector<AccessPointInfo>& accessPoints() const noexcept override { return m_accessPoints; }
  [[nodiscard]] const std::vector<VpnConnectionInfo>& vpnConnections() const noexcept override {
    return m_vpnConnections;
  }

  void requestScan() override;
  bool activateAccessPoint(const AccessPointInfo& ap) override;
  bool activateAccessPoint(const AccessPointInfo& ap, const std::string& psk) override;
  bool activateVpnConnection(const VpnConnectionInfo& /*vpn*/) override { return false; }
  bool deactivateVpnConnection(const VpnConnectionInfo& /*vpn*/) override { return false; }
  void setWirelessEnabled(bool enabled) override;
  void disconnect() override;
  void forgetSsid(const std::string& ssid) override;
  [[nodiscard]] bool hasSavedConnection(const std::string& ssid) const override;

private:
  void subscribeStation(const std::string& stationPath);
  void subscribeNetwork(const std::string& netPath);
  void enumerateObjects();
  void rebuildState();
  void emitChangedIfNeeded(NetworkState next);

  // Returns the first station proxy, or nullptr if none.
  sdbus::IProxy* firstStation() const;

  SystemBus& m_bus;
  std::unique_ptr<sdbus::IProxy> m_objectManager;
  // Station object path -> proxy (one per wireless device).
  std::unordered_map<std::string, std::unique_ptr<sdbus::IProxy>> m_stations;
  // Network object path -> proxy.
  std::unordered_map<std::string, std::unique_ptr<sdbus::IProxy>> m_networks;
  // ssid -> network object path (known/saved networks).
  std::unordered_map<std::string, std::string> m_knownNetworks;
  NetworkState m_state;
  std::vector<AccessPointInfo> m_accessPoints;
  const std::vector<VpnConnectionInfo> m_vpnConnections; // always empty
  bool m_hasStateSnapshot = false;
  ChangeCallback m_changeCallback;
};
