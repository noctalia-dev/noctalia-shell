#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

class SystemBus;

namespace sdbus {
class IProxy;
}

struct AccessPointInfo {
  std::string path;       // NM AP object path
  std::string devicePath; // NM device object path this AP belongs to
  std::string ssid;
  std::uint8_t strength = 0; // 0..100
  bool secured = false;
  bool active = false; // currently the device's ActiveAccessPoint

  bool operator==(const AccessPointInfo&) const = default;
};

enum class NetworkConnectivity {
  Unknown = 0,
  None = 1,
  Wired = 2,
  Wireless = 3,
};

struct NetworkState {
  NetworkConnectivity kind = NetworkConnectivity::Unknown;
  bool connected = false;
  bool wirelessEnabled = false;
  bool scanning = false;
  std::string ssid;                // Wi-Fi only
  std::string ipv4;                // dotted-quad of first address; empty if none
  std::string interfaceName;       // e.g. "wlan0", "eth0"
  std::uint8_t signalStrength = 0; // 0..100, Wi-Fi only

  bool operator==(const NetworkState&) const = default;
};

class NetworkService {
public:
  using ChangeCallback = std::function<void(const NetworkState&)>;

  explicit NetworkService(SystemBus& bus);
  ~NetworkService();

  NetworkService(const NetworkService&) = delete;
  NetworkService& operator=(const NetworkService&) = delete;

  void setChangeCallback(ChangeCallback callback);
  void refresh();

  [[nodiscard]] const NetworkState& state() const noexcept { return m_state; }
  [[nodiscard]] const std::vector<AccessPointInfo>& accessPoints() const noexcept { return m_accessPoints; }

  // Trigger a Wi-Fi scan on every wifi device. Results arrive via PropertiesChanged.
  void requestScan();

  // Activate a known saved connection for the given access point. NM picks the
  // matching saved connection automatically when the first argument is "/".
  // Returns false only on an immediate D-Bus error. For secured networks that
  // have no saved secrets, the activation will fail asynchronously (slice 3
  // handles that via a SecretAgent).
  bool activateAccessPoint(const AccessPointInfo& ap);

  // Enable / disable the Wi-Fi radio.
  void setWirelessEnabled(bool enabled);

  // Deactivate the current primary connection.
  void disconnect();

  // Delete every saved connection whose 802-11-wireless SSID matches.
  void forgetSsid(const std::string& ssid);

  // Whether any saved connection matches the SSID (uses cached snapshot refreshed on every refresh()).
  [[nodiscard]] bool hasSavedConnection(const std::string& ssid) const;

private:
  void refreshAccessPoints();
  void refreshSavedConnections();
  void rebindActiveConnection();
  void rebindActiveDevice(const std::string& devicePath);
  void rebindActiveAccessPoint(const std::string& apPath);
  void ensureWifiDeviceSubscribed(const std::string& devicePath);
  [[nodiscard]] NetworkState readState();
  void emitChangedIfNeeded(NetworkState next);

  SystemBus& m_bus;
  std::unique_ptr<sdbus::IProxy> m_nm;
  std::unique_ptr<sdbus::IProxy> m_activeConnection;
  std::unique_ptr<sdbus::IProxy> m_activeDevice;
  std::unique_ptr<sdbus::IProxy> m_activeAp;
  std::unordered_map<std::string, std::unique_ptr<sdbus::IProxy>> m_wifiDevices;
  std::string m_activeConnectionPath;
  std::string m_activeDevicePath;
  std::string m_activeApPath;
  NetworkState m_state;
  std::vector<AccessPointInfo> m_accessPoints;
  std::vector<std::string> m_savedSsids;
  bool m_scanning = false;
  std::int64_t m_scanBaselineLastScan = 0;
  ChangeCallback m_changeCallback;
};
