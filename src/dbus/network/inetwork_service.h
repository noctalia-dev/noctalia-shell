#pragma once

#include "dbus/network/network_types.h"

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

// Abstract interface shared by NetworkManagerService (NetworkManager backend) and
// WpaSupplicantService (wpa_supplicant backend).  UI code should use this type
// so it works with either backend.
class IpcService;

class INetworkService {
public:
  using ChangeCallback = std::function<void(const NetworkState&, NetworkChangeOrigin)>;
  using WirelessFeedbackCallback = std::function<void(bool enabled)>;

  virtual ~INetworkService() = default;

  virtual void setChangeCallback(ChangeCallback callback) = 0;
  virtual void refresh() = 0;

  [[nodiscard]] virtual const NetworkState& state() const noexcept = 0;
  [[nodiscard]] virtual bool hasStateSnapshot() const noexcept = 0;
  [[nodiscard]] virtual const std::vector<AccessPointInfo>& accessPoints() const noexcept = 0;
  [[nodiscard]] virtual const std::vector<VpnConnectionInfo>& vpnConnections() const noexcept = 0;

  virtual void requestScan() = 0;
  virtual bool activateAccessPoint(const AccessPointInfo& ap) = 0;
  virtual bool activateAccessPoint(const AccessPointInfo& ap, const std::string& psk) = 0;
  virtual bool activateVpnConnection(const VpnConnectionInfo& vpn) = 0;
  virtual bool deactivateVpnConnection(const VpnConnectionInfo& vpn) = 0;
  [[nodiscard]] virtual bool canActivateWiredConnection() const noexcept { return false; }
  virtual bool activateWiredConnection() { return false; }
  virtual void setWirelessEnabled(bool enabled) = 0;
  virtual void disconnect() = 0;
  virtual void forgetSsid(const std::string& ssid) = 0;
  [[nodiscard]] virtual bool hasSavedConnection(const std::string& ssid) const = 0;
  [[nodiscard]] virtual bool supportsSecretAgent() const noexcept { return false; }
  void registerIpc(IpcService& ipc, WirelessFeedbackCallback wirelessFeedback = {});
};
