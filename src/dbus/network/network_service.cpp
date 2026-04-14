#include "dbus/network/network_service.h"

#include "core/log.h"
#include "dbus/system_bus.h"

#include <algorithm>
#include <array>
#include <cstdio>
#include <map>
#include <sdbus-c++/IProxy.h>
#include <sdbus-c++/Types.h>
#include <vector>

namespace {

constexpr Logger kLog("network");

const sdbus::ServiceName k_nmBusName{"org.freedesktop.NetworkManager"};
const sdbus::ObjectPath k_nmObjectPath{"/org/freedesktop/NetworkManager"};
constexpr auto k_nmInterface = "org.freedesktop.NetworkManager";
constexpr auto k_nmDeviceInterface = "org.freedesktop.NetworkManager.Device";
constexpr auto k_nmDeviceWirelessInterface = "org.freedesktop.NetworkManager.Device.Wireless";
constexpr auto k_nmSettingsInterface = "org.freedesktop.NetworkManager.Settings";
const sdbus::ObjectPath k_nmSettingsObjectPath{"/org/freedesktop/NetworkManager/Settings"};
constexpr auto k_nmSettingsConnectionInterface = "org.freedesktop.NetworkManager.Settings.Connection";

// NM80211ApSecurityFlags bits we care about.
constexpr std::uint32_t k_nm80211ApSecNone = 0x0;
constexpr auto k_nmActiveConnectionInterface = "org.freedesktop.NetworkManager.Connection.Active";
constexpr auto k_nmAccessPointInterface = "org.freedesktop.NetworkManager.AccessPoint";
constexpr auto k_nmIp4ConfigInterface = "org.freedesktop.NetworkManager.IP4Config";
constexpr auto k_propertiesInterface = "org.freedesktop.DBus.Properties";

// NMDeviceType values from NetworkManager.h
constexpr std::uint32_t k_nmDeviceTypeEthernet = 1;
constexpr std::uint32_t k_nmDeviceTypeWifi = 2;

// NMActiveConnectionState
constexpr std::uint32_t k_nmActiveConnectionStateActivated = 2;

template <typename T>
T getPropertyOr(sdbus::IProxy& proxy, std::string_view interfaceName, std::string_view propertyName, T fallback) {
  try {
    const sdbus::Variant value = proxy.getProperty(propertyName).onInterface(std::string(interfaceName));
    return value.get<T>();
  } catch (const sdbus::Error&) {
    return fallback;
  }
}

std::string ipv4FromUint(std::uint32_t addrLe) {
  // NM stores IPv4 addresses as native-byte-order uint32 in network order bytes.
  // I.e. the bytes a.b.c.d are laid out in memory low->high as a,b,c,d.
  std::array<std::uint8_t, 4> bytes{};
  bytes[0] = static_cast<std::uint8_t>(addrLe & 0xffU);
  bytes[1] = static_cast<std::uint8_t>((addrLe >> 8) & 0xffU);
  bytes[2] = static_cast<std::uint8_t>((addrLe >> 16) & 0xffU);
  bytes[3] = static_cast<std::uint8_t>((addrLe >> 24) & 0xffU);
  char buf[32];
  std::snprintf(buf, sizeof(buf), "%u.%u.%u.%u", bytes[0], bytes[1], bytes[2], bytes[3]);
  return std::string(buf);
}

std::string firstIpv4FromConfig(sdbus::IConnection& conn, const std::string& ip4ConfigPath) {
  if (ip4ConfigPath.empty() || ip4ConfigPath == "/") {
    return {};
  }
  try {
    auto proxy =
        sdbus::createProxy(conn, k_nmBusName, sdbus::ObjectPath{ip4ConfigPath});
    // Prefer "AddressData" (vector<dict<string,variant>>) since "Addresses" is deprecated.
    try {
      const sdbus::Variant value = proxy->getProperty("AddressData").onInterface(k_nmIp4ConfigInterface);
      const auto data = value.get<std::vector<std::map<std::string, sdbus::Variant>>>();
      for (const auto& entry : data) {
        auto it = entry.find("address");
        if (it != entry.end()) {
          try {
            return it->second.get<std::string>();
          } catch (const sdbus::Error&) {
          }
        }
      }
    } catch (const sdbus::Error&) {
    }
    // Fallback: legacy Addresses (vector<vector<uint32>> — addr, prefix, gateway).
    try {
      const sdbus::Variant value = proxy->getProperty("Addresses").onInterface(k_nmIp4ConfigInterface);
      const auto data = value.get<std::vector<std::vector<std::uint32_t>>>();
      if (!data.empty() && !data.front().empty()) {
        return ipv4FromUint(data.front().front());
      }
    } catch (const sdbus::Error&) {
    }
  } catch (const sdbus::Error&) {
  }
  return {};
}

} // namespace

NetworkService::NetworkService(SystemBus& bus) : m_bus(bus) {
  m_nm = sdbus::createProxy(m_bus.connection(), k_nmBusName, k_nmObjectPath);

  m_nm->uponSignal("PropertiesChanged")
      .onInterface(k_propertiesInterface)
      .call([this](const std::string& interfaceName, const std::map<std::string, sdbus::Variant>& changedProperties,
                   const std::vector<std::string>& /*invalidatedProperties*/) {
        if (interfaceName != k_nmInterface) {
          return;
        }
        bool wirelessNowOn = false;
        if (auto it = changedProperties.find("WirelessEnabled"); it != changedProperties.end()) {
          try {
            wirelessNowOn = it->second.get<bool>();
          } catch (const sdbus::Error&) {
          }
        }
        if (changedProperties.contains("PrimaryConnection") || changedProperties.contains("ActiveConnections") ||
            changedProperties.contains("WirelessEnabled") || changedProperties.contains("State") ||
            changedProperties.contains("Connectivity")) {
          rebindActiveConnection();
        }
        if (wirelessNowOn) {
          // NM powered the radio on but the wifi device is still transitioning
          // out of Unavailable, so calling RequestScan now would be rejected.
          // NM starts its own scan as soon as the device reaches Disconnected;
          // just mark ourselves scanning and snapshot LastScan so the device
          // PropertiesChanged watcher clears the flag when the scan finishes.
          std::int64_t baseline = 0;
          try {
            std::vector<sdbus::ObjectPath> devices;
            m_nm->callMethod("GetDevices").onInterface(k_nmInterface).storeResultsTo(devices);
            for (const auto& devicePath : devices) {
              try {
                auto device = sdbus::createProxy(m_bus.connection(), k_nmBusName, devicePath);
                const auto deviceType = getPropertyOr<std::uint32_t>(*device, k_nmDeviceInterface, "DeviceType", 0U);
                if (deviceType != k_nmDeviceTypeWifi) {
                  continue;
                }
                const auto lastScan = getPropertyOr<std::int64_t>(*device, k_nmDeviceWirelessInterface, "LastScan",
                                                                  std::int64_t{0});
                if (lastScan > baseline) {
                  baseline = lastScan;
                }
              } catch (const sdbus::Error&) {
              }
            }
          } catch (const sdbus::Error&) {
          }
          m_scanning = true;
          m_scanBaselineLastScan = baseline;
          refresh();
        }
      });

  rebindActiveConnection();
}

NetworkService::~NetworkService() = default;

void NetworkService::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

void NetworkService::refresh() {
  const auto previousAps = m_accessPoints;
  const auto previousSaved = m_savedSsids;
  refreshAccessPoints();
  refreshSavedConnections();
  NetworkState next = readState();
  const bool apsChanged = previousAps != m_accessPoints;
  const bool savedChanged = previousSaved != m_savedSsids;
  const bool stateChanged = next != m_state;
  m_state = std::move(next);
  if ((stateChanged || apsChanged || savedChanged) && m_changeCallback) {
    m_changeCallback(m_state);
  }
}

void NetworkService::requestScan() {
  std::int64_t baseline = 0;
  bool anyRequested = false;
  try {
    std::vector<sdbus::ObjectPath> devices;
    m_nm->callMethod("GetDevices").onInterface(k_nmInterface).storeResultsTo(devices);
    for (const auto& devicePath : devices) {
      try {
        auto device = sdbus::createProxy(m_bus.connection(), k_nmBusName, devicePath);
        const auto deviceType = getPropertyOr<std::uint32_t>(*device, k_nmDeviceInterface, "DeviceType", 0U);
        if (deviceType != k_nmDeviceTypeWifi) {
          continue;
        }
        const auto lastScan =
            getPropertyOr<std::int64_t>(*device, k_nmDeviceWirelessInterface, "LastScan", std::int64_t{0});
        if (lastScan > baseline) {
          baseline = lastScan;
        }
        const std::map<std::string, sdbus::Variant> options;
        device->callMethod("RequestScan").onInterface(k_nmDeviceWirelessInterface).withArguments(options);
        anyRequested = true;
      } catch (const sdbus::Error& e) {
        kLog.debug("RequestScan failed on {}: {}", std::string(devicePath), e.what());
      }
    }
  } catch (const sdbus::Error& e) {
    kLog.warn("GetDevices failed: {}", e.what());
  }
  if (anyRequested) {
    m_scanning = true;
    m_scanBaselineLastScan = baseline;
    refresh();
  }
}

bool NetworkService::activateAccessPoint(const AccessPointInfo& ap) {
  if (ap.devicePath.empty() || ap.path.empty()) {
    return false;
  }

  // First try ActivateConnection with "/" as the connection path — NM picks an
  // existing saved profile for the AP. Falls back to AddAndActivateConnection
  // when no saved profile exists, which creates a temporary profile and (for
  // secured networks) triggers GetSecrets against our agent.
  try {
    const sdbus::ObjectPath emptyConnectionPath{"/"};
    const sdbus::ObjectPath devicePath{ap.devicePath};
    const sdbus::ObjectPath apPath{ap.path};
    sdbus::ObjectPath activePath;
    m_nm->callMethod("ActivateConnection")
        .onInterface(k_nmInterface)
        .withArguments(emptyConnectionPath, devicePath, apPath)
        .storeResultsTo(activePath);
    kLog.info("activating ap ssid={} active={}", ap.ssid, std::string(activePath));
    return true;
  } catch (const sdbus::Error& e) {
    kLog.debug("ActivateConnection(/) failed for ssid={}: {}; trying AddAndActivate", ap.ssid, e.what());
  }

  try {
    using SettingsDict = std::map<std::string, std::map<std::string, sdbus::Variant>>;
    SettingsDict settings;
    if (ap.secured) {
      // Minimal secured-wifi settings — NM fills in ssid from the specific_object
      // and calls GetSecrets against us for the PSK.
      settings["802-11-wireless-security"]["key-mgmt"] = sdbus::Variant{std::string("wpa-psk")};
    }
    const sdbus::ObjectPath devicePath{ap.devicePath};
    const sdbus::ObjectPath apPath{ap.path};
    sdbus::ObjectPath connectionPath;
    sdbus::ObjectPath activePath;
    m_nm->callMethod("AddAndActivateConnection")
        .onInterface(k_nmInterface)
        .withArguments(settings, devicePath, apPath)
        .storeResultsTo(connectionPath, activePath);
    kLog.info("add+activate ap ssid={} conn={} active={}", ap.ssid, std::string(connectionPath),
              std::string(activePath));
    return true;
  } catch (const sdbus::Error& e) {
    kLog.warn("AddAndActivateConnection failed ssid={} err={}", ap.ssid, e.what());
    return false;
  }
}

void NetworkService::setWirelessEnabled(bool enabled) {
  try {
    m_nm->setProperty("WirelessEnabled").onInterface(k_nmInterface).toValue(enabled);
  } catch (const sdbus::Error& e) {
    kLog.warn("WirelessEnabled write failed: {}", e.what());
  }
}

void NetworkService::disconnect() {
  if (m_activeConnectionPath.empty() || m_activeConnectionPath == "/") {
    return;
  }
  try {
    m_nm->callMethod("DeactivateConnection")
        .onInterface(k_nmInterface)
        .withArguments(sdbus::ObjectPath{m_activeConnectionPath});
    kLog.info("deactivated connection path={}", m_activeConnectionPath);
  } catch (const sdbus::Error& e) {
    kLog.warn("DeactivateConnection failed: {}", e.what());
  }
}

void NetworkService::forgetSsid(const std::string& ssid) {
  if (ssid.empty()) {
    return;
  }
  try {
    auto settings = sdbus::createProxy(m_bus.connection(), k_nmBusName, k_nmSettingsObjectPath);
    std::vector<sdbus::ObjectPath> connectionPaths;
    settings->callMethod("ListConnections").onInterface(k_nmSettingsInterface).storeResultsTo(connectionPaths);
    int removed = 0;
    for (const auto& connectionPath : connectionPaths) {
      try {
        auto connection = sdbus::createProxy(m_bus.connection(), k_nmBusName, connectionPath);
        std::map<std::string, std::map<std::string, sdbus::Variant>> cfg;
        connection->callMethod("GetSettings").onInterface(k_nmSettingsConnectionInterface).storeResultsTo(cfg);
        auto wifiIt = cfg.find("802-11-wireless");
        if (wifiIt == cfg.end()) {
          continue;
        }
        auto ssidIt = wifiIt->second.find("ssid");
        if (ssidIt == wifiIt->second.end()) {
          continue;
        }
        std::string foundSsid;
        try {
          const auto bytes = ssidIt->second.get<std::vector<std::uint8_t>>();
          foundSsid.assign(bytes.begin(), bytes.end());
        } catch (const sdbus::Error&) {
          continue;
        }
        if (foundSsid != ssid) {
          continue;
        }
        connection->callMethod("Delete").onInterface(k_nmSettingsConnectionInterface);
        ++removed;
      } catch (const sdbus::Error& e) {
        kLog.debug("forgetSsid: failed to inspect {}: {}", std::string(connectionPath), e.what());
      }
    }
    kLog.info("forgetSsid ssid=\"{}\" removed={}", ssid, removed);
  } catch (const sdbus::Error& e) {
    kLog.warn("forgetSsid failed ssid=\"{}\": {}", ssid, e.what());
  }
  refreshSavedConnections();
}

bool NetworkService::hasSavedConnection(const std::string& ssid) const {
  if (ssid.empty()) {
    return false;
  }
  return std::find(m_savedSsids.begin(), m_savedSsids.end(), ssid) != m_savedSsids.end();
}

void NetworkService::refreshSavedConnections() {
  std::vector<std::string> next;
  try {
    auto settings = sdbus::createProxy(m_bus.connection(), k_nmBusName, k_nmSettingsObjectPath);
    std::vector<sdbus::ObjectPath> connectionPaths;
    settings->callMethod("ListConnections").onInterface(k_nmSettingsInterface).storeResultsTo(connectionPaths);
    for (const auto& connectionPath : connectionPaths) {
      try {
        auto connection = sdbus::createProxy(m_bus.connection(), k_nmBusName, connectionPath);
        std::map<std::string, std::map<std::string, sdbus::Variant>> cfg;
        connection->callMethod("GetSettings").onInterface(k_nmSettingsConnectionInterface).storeResultsTo(cfg);
        auto wifiIt = cfg.find("802-11-wireless");
        if (wifiIt == cfg.end()) {
          continue;
        }
        auto ssidIt = wifiIt->second.find("ssid");
        if (ssidIt == wifiIt->second.end()) {
          continue;
        }
        try {
          const auto bytes = ssidIt->second.get<std::vector<std::uint8_t>>();
          std::string ssid(bytes.begin(), bytes.end());
          if (!ssid.empty()) {
            next.push_back(std::move(ssid));
          }
        } catch (const sdbus::Error&) {
        }
      } catch (const sdbus::Error&) {
      }
    }
  } catch (const sdbus::Error& e) {
    kLog.debug("refreshSavedConnections: {}", e.what());
  }
  std::ranges::sort(next);
  next.erase(std::unique(next.begin(), next.end()), next.end());
  m_savedSsids = std::move(next);
}

void NetworkService::ensureWifiDeviceSubscribed(const std::string& devicePath) {
  if (m_wifiDevices.contains(devicePath)) {
    return;
  }
  try {
    auto proxy = sdbus::createProxy(m_bus.connection(), k_nmBusName, sdbus::ObjectPath{devicePath});
    proxy->uponSignal("PropertiesChanged")
        .onInterface(k_propertiesInterface)
        .call([this](const std::string& interfaceName, const std::map<std::string, sdbus::Variant>& changedProperties,
                     const std::vector<std::string>& /*invalidatedProperties*/) {
          if (interfaceName == k_nmDeviceWirelessInterface) {
            if (auto it = changedProperties.find("LastScan"); it != changedProperties.end()) {
              try {
                const auto lastScan = it->second.get<std::int64_t>();
                if (m_scanning && lastScan > m_scanBaselineLastScan) {
                  m_scanning = false;
                }
              } catch (const sdbus::Error&) {
              }
            }
            if (changedProperties.contains("AccessPoints") || changedProperties.contains("LastScan")) {
              refresh();
            }
          } else if (interfaceName == k_nmDeviceInterface) {
            if (changedProperties.contains("State")) {
              refresh();
            }
          }
        });
    m_wifiDevices.emplace(devicePath, std::move(proxy));
  } catch (const sdbus::Error& e) {
    kLog.debug("wifi device subscribe failed {}: {}", devicePath, e.what());
  }
}

void NetworkService::refreshAccessPoints() {
  std::vector<AccessPointInfo> next;
  try {
    std::vector<sdbus::ObjectPath> devices;
    m_nm->callMethod("GetDevices").onInterface(k_nmInterface).storeResultsTo(devices);
    for (const auto& devicePath : devices) {
      try {
        auto device = sdbus::createProxy(m_bus.connection(), k_nmBusName, devicePath);
        const auto deviceType = getPropertyOr<std::uint32_t>(*device, k_nmDeviceInterface, "DeviceType", 0U);
        if (deviceType != k_nmDeviceTypeWifi) {
          continue;
        }
        ensureWifiDeviceSubscribed(devicePath);
        std::string activeApPath;
        try {
          const sdbus::Variant value =
              device->getProperty("ActiveAccessPoint").onInterface(k_nmDeviceWirelessInterface);
          activeApPath = value.get<sdbus::ObjectPath>();
        } catch (const sdbus::Error&) {
        }

        const sdbus::Variant apListVar = device->getProperty("AccessPoints").onInterface(k_nmDeviceWirelessInterface);
        const auto apPaths = apListVar.get<std::vector<sdbus::ObjectPath>>();
        for (const auto& apPath : apPaths) {
          try {
            auto ap = sdbus::createProxy(m_bus.connection(), k_nmBusName, apPath);
            AccessPointInfo info;
            info.path = apPath;
            info.devicePath = devicePath;
            info.active = !activeApPath.empty() && apPath == activeApPath;
            try {
              const sdbus::Variant ssidVar = ap->getProperty("Ssid").onInterface(k_nmAccessPointInterface);
              const auto ssidBytes = ssidVar.get<std::vector<std::uint8_t>>();
              info.ssid.assign(ssidBytes.begin(), ssidBytes.end());
            } catch (const sdbus::Error&) {
            }
            info.strength =
                getPropertyOr<std::uint8_t>(*ap, k_nmAccessPointInterface, "Strength", std::uint8_t{0});
            const auto wpaFlags =
                getPropertyOr<std::uint32_t>(*ap, k_nmAccessPointInterface, "WpaFlags", 0U);
            const auto rsnFlags =
                getPropertyOr<std::uint32_t>(*ap, k_nmAccessPointInterface, "RsnFlags", 0U);
            info.secured = (wpaFlags != k_nm80211ApSecNone) || (rsnFlags != k_nm80211ApSecNone);
            if (info.ssid.empty()) {
              continue; // skip hidden networks for now
            }
            next.push_back(std::move(info));
          } catch (const sdbus::Error&) {
          }
        }
      } catch (const sdbus::Error&) {
      }
    }
  } catch (const sdbus::Error& e) {
    kLog.debug("refreshAccessPoints: {}", e.what());
  }

  // Deduplicate by SSID, keeping the strongest (and marking active if any entry is active).
  std::vector<AccessPointInfo> deduped;
  deduped.reserve(next.size());
  for (auto& ap : next) {
    auto it = std::find_if(deduped.begin(), deduped.end(),
                           [&](const AccessPointInfo& other) { return other.ssid == ap.ssid; });
    if (it == deduped.end()) {
      deduped.push_back(std::move(ap));
      continue;
    }
    if (ap.active) {
      it->active = true;
    }
    if (ap.strength > it->strength) {
      it->strength = ap.strength;
      it->path = ap.path;
      it->devicePath = ap.devicePath;
      it->secured = ap.secured;
    }
  }
  std::ranges::sort(deduped, [](const AccessPointInfo& a, const AccessPointInfo& b) {
    if (a.active != b.active) {
      return a.active;
    }
    return a.strength > b.strength;
  });

  m_accessPoints = std::move(deduped);
}

void NetworkService::rebindActiveConnection() {
  std::string newPath;
  try {
    const sdbus::Variant value = m_nm->getProperty("PrimaryConnection").onInterface(k_nmInterface);
    newPath = value.get<sdbus::ObjectPath>();
  } catch (const sdbus::Error& e) {
    kLog.debug("PrimaryConnection unavailable: {}", e.what());
  }

  if (newPath != m_activeConnectionPath) {
    m_activeConnectionPath = newPath;
    m_activeConnection.reset();
    if (!newPath.empty() && newPath != "/") {
      try {
        m_activeConnection = sdbus::createProxy(m_bus.connection(), k_nmBusName, sdbus::ObjectPath{newPath});
        m_activeConnection->uponSignal("PropertiesChanged")
            .onInterface(k_propertiesInterface)
            .call([this](const std::string& interfaceName,
                         const std::map<std::string, sdbus::Variant>& changedProperties,
                         const std::vector<std::string>& /*invalidatedProperties*/) {
              if (interfaceName != k_nmActiveConnectionInterface) {
                return;
              }
              if (changedProperties.contains("Devices") || changedProperties.contains("State") ||
                  changedProperties.contains("Ip4Config")) {
                rebindActiveConnection();
              }
            });
      } catch (const sdbus::Error& e) {
        kLog.debug("active connection proxy failed: {}", e.what());
        m_activeConnection.reset();
      }
    }
  }

  std::string newDevicePath;
  if (m_activeConnection != nullptr) {
    try {
      const sdbus::Variant value = m_activeConnection->getProperty("Devices").onInterface(k_nmActiveConnectionInterface);
      const auto devices = value.get<std::vector<sdbus::ObjectPath>>();
      if (!devices.empty()) {
        newDevicePath = devices.front();
      }
    } catch (const sdbus::Error&) {
    }
  }
  rebindActiveDevice(newDevicePath);

  refresh();
}

void NetworkService::rebindActiveDevice(const std::string& devicePath) {
  if (devicePath == m_activeDevicePath && m_activeDevice != nullptr) {
    return;
  }
  m_activeDevicePath = devicePath;
  m_activeDevice.reset();
  rebindActiveAccessPoint({});

  if (devicePath.empty() || devicePath == "/") {
    return;
  }

  try {
    m_activeDevice = sdbus::createProxy(m_bus.connection(), k_nmBusName, sdbus::ObjectPath{devicePath});
    m_activeDevice->uponSignal("PropertiesChanged")
        .onInterface(k_propertiesInterface)
        .call([this](const std::string& interfaceName, const std::map<std::string, sdbus::Variant>& changedProperties,
                     const std::vector<std::string>& /*invalidatedProperties*/) {
          if (interfaceName == k_nmDeviceInterface) {
            if (changedProperties.contains("Ip4Config") || changedProperties.contains("State") ||
                changedProperties.contains("Interface")) {
              refresh();
            }
          } else if (interfaceName == k_nmDeviceWirelessInterface) {
            if (changedProperties.contains("ActiveAccessPoint")) {
              std::string apPath;
              try {
                apPath = changedProperties.at("ActiveAccessPoint").get<sdbus::ObjectPath>();
              } catch (const sdbus::Error&) {
              }
              rebindActiveAccessPoint(apPath);
              refresh();
            }
          }
        });
  } catch (const sdbus::Error& e) {
    kLog.debug("device proxy failed: {}", e.what());
    m_activeDevice.reset();
    return;
  }

  // If this is a wireless device, also bind the current access point.
  const auto deviceType = getPropertyOr<std::uint32_t>(*m_activeDevice, k_nmDeviceInterface, "DeviceType", 0U);
  if (deviceType == k_nmDeviceTypeWifi) {
    std::string apPath;
    try {
      const sdbus::Variant value =
          m_activeDevice->getProperty("ActiveAccessPoint").onInterface(k_nmDeviceWirelessInterface);
      apPath = value.get<sdbus::ObjectPath>();
    } catch (const sdbus::Error&) {
    }
    rebindActiveAccessPoint(apPath);
  }
}

void NetworkService::rebindActiveAccessPoint(const std::string& apPath) {
  if (apPath == m_activeApPath && m_activeAp != nullptr) {
    return;
  }
  m_activeApPath = apPath;
  m_activeAp.reset();
  if (apPath.empty() || apPath == "/") {
    return;
  }
  try {
    m_activeAp = sdbus::createProxy(m_bus.connection(), k_nmBusName, sdbus::ObjectPath{apPath});
    m_activeAp->uponSignal("PropertiesChanged")
        .onInterface(k_propertiesInterface)
        .call([this](const std::string& interfaceName, const std::map<std::string, sdbus::Variant>& changedProperties,
                     const std::vector<std::string>& /*invalidatedProperties*/) {
          if (interfaceName != k_nmAccessPointInterface) {
            return;
          }
          if (changedProperties.contains("Strength") || changedProperties.contains("Ssid")) {
            refresh();
          }
        });
  } catch (const sdbus::Error& e) {
    kLog.debug("AP proxy failed: {}", e.what());
    m_activeAp.reset();
  }
}

NetworkState NetworkService::readState() {
  NetworkState next;

  next.wirelessEnabled = getPropertyOr<bool>(*m_nm, k_nmInterface, "WirelessEnabled", false);
  next.scanning = m_scanning;

  if (m_activeDevice == nullptr) {
    return next;
  }

  const auto deviceType = getPropertyOr<std::uint32_t>(*m_activeDevice, k_nmDeviceInterface, "DeviceType", 0U);
  next.interfaceName = getPropertyOr<std::string>(*m_activeDevice, k_nmDeviceInterface, "Interface", "");

  const auto ip4ConfigPath =
      getPropertyOr<sdbus::ObjectPath>(*m_activeDevice, k_nmDeviceInterface, "Ip4Config", sdbus::ObjectPath{});
  next.ipv4 = firstIpv4FromConfig(m_bus.connection(), ip4ConfigPath);

  if (m_activeConnection != nullptr) {
    const auto state = getPropertyOr<std::uint32_t>(*m_activeConnection, k_nmActiveConnectionInterface, "State", 0U);
    next.connected = state == k_nmActiveConnectionStateActivated;
  }

  if (deviceType == k_nmDeviceTypeWifi) {
    next.kind = NetworkConnectivity::Wireless;
    if (m_activeAp != nullptr) {
      try {
        const sdbus::Variant ssidVar = m_activeAp->getProperty("Ssid").onInterface(k_nmAccessPointInterface);
        const auto ssidBytes = ssidVar.get<std::vector<std::uint8_t>>();
        next.ssid.assign(ssidBytes.begin(), ssidBytes.end());
      } catch (const sdbus::Error&) {
      }
      next.signalStrength =
          getPropertyOr<std::uint8_t>(*m_activeAp, k_nmAccessPointInterface, "Strength", std::uint8_t{0});
    }
  } else if (deviceType == k_nmDeviceTypeEthernet) {
    next.kind = NetworkConnectivity::Wired;
  } else {
    next.kind = NetworkConnectivity::Unknown;
  }

  return next;
}

void NetworkService::emitChangedIfNeeded(NetworkState next) {
  if (next == m_state) {
    return;
  }
  m_state = std::move(next);
  if (m_changeCallback) {
    m_changeCallback(m_state);
  }
}
