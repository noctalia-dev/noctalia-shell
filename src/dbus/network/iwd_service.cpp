#include "dbus/network/iwd_service.h"

#include "core/log.h"
#include "dbus/system_bus.h"

#include <algorithm>
#include <map>
#include <sdbus-c++/IProxy.h>
#include <sdbus-c++/Types.h>
#include <string>
#include <vector>

namespace {

  constexpr Logger kLog("iwd");

  const sdbus::ServiceName k_iwdBusName{"net.connman.iwd"};
  const sdbus::ObjectPath k_iwdRootPath{"/"};
  constexpr auto k_objectManagerInterface = "org.freedesktop.DBus.ObjectManager";
  constexpr auto k_propertiesInterface = "org.freedesktop.DBus.Properties";
  constexpr auto k_stationInterface = "net.connman.iwd.Station";
  constexpr auto k_networkInterface = "net.connman.iwd.Network";
  constexpr auto k_knownNetworkInterface = "net.connman.iwd.KnownNetwork";
  constexpr auto k_deviceInterface = "net.connman.iwd.Device";

  template <typename T>
  T getPropertyOr(sdbus::IProxy& proxy, std::string_view iface, std::string_view prop, T fallback) {
    try {
      return proxy.getProperty(prop).onInterface(std::string(iface)).template get<T>();
    } catch (const sdbus::Error&) {
      return fallback;
    }
  }

  // IWD signal strength is in 100 * dBm (range 0 to -10000).
  // Convert to 0..100 percent using the same -50..-100 dBm window.
  std::uint8_t signalToPercent(std::int16_t iwdSignal) {
    const int dBm = iwdSignal / 100;
    if (dBm <= -100)
      return 0;
    if (dBm >= -50)
      return 100;
    return static_cast<std::uint8_t>(2 * (dBm + 100));
  }

  using ManagedObjects =
      std::map<sdbus::ObjectPath, std::map<std::string, std::map<std::string, sdbus::Variant>>>;

} // namespace

IwdService::IwdService(SystemBus& bus) : m_bus(bus) {
  if (!bus.nameHasOwner("net.connman.iwd")) {
    throw sdbus::Error(sdbus::Error::Name{"org.freedesktop.DBus.Error.ServiceUnknown"},
                       "The name net.connman.iwd was not provided by any .service files");
  }

  m_objectManager = sdbus::createProxy(m_bus.connection(), k_iwdBusName, k_iwdRootPath);

  m_objectManager->uponSignal("InterfacesAdded")
      .onInterface(k_objectManagerInterface)
      .call([this](const sdbus::ObjectPath& path,
                   const std::map<std::string, std::map<std::string, sdbus::Variant>>& ifaces) {
        if (ifaces.count(k_stationInterface))
          subscribeStation(std::string(path));
        if (ifaces.count(k_networkInterface))
          subscribeNetwork(std::string(path));
        rebuildState();
      });

  m_objectManager->uponSignal("InterfacesRemoved")
      .onInterface(k_objectManagerInterface)
      .call([this](const sdbus::ObjectPath& path, const std::vector<std::string>&) {
        const std::string key{path};
        m_stations.erase(key);
        m_networks.erase(key);
        rebuildState();
      });

  enumerateObjects();
  rebuildState();
}

IwdService::~IwdService() = default;

void IwdService::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

void IwdService::enumerateObjects() {
  try {
    ManagedObjects objects;
    m_objectManager->callMethod("GetManagedObjects")
        .onInterface(k_objectManagerInterface)
        .storeResultsTo(objects);

    for (const auto& [path, ifaces] : objects) {
      if (ifaces.count(k_stationInterface))
        subscribeStation(std::string(path));
      if (ifaces.count(k_networkInterface))
        subscribeNetwork(std::string(path));
    }
  } catch (const sdbus::Error& e) {
    kLog.warn("GetManagedObjects failed: {}", e.what());
  }
}

void IwdService::subscribeStation(const std::string& stationPath) {
  if (m_stations.count(stationPath))
    return;
  try {
    auto proxy = sdbus::createProxy(m_bus.connection(), k_iwdBusName, sdbus::ObjectPath{stationPath});

    proxy->uponSignal("PropertiesChanged")
        .onInterface(k_propertiesInterface)
        .call([this](const std::string&, const std::map<std::string, sdbus::Variant>&,
                     const std::vector<std::string>&) { rebuildState(); });

    m_stations.emplace(stationPath, std::move(proxy));
  } catch (const sdbus::Error& e) {
    kLog.warn("failed to subscribe station {}: {}", stationPath, e.what());
  }
}

void IwdService::subscribeNetwork(const std::string& netPath) {
  if (m_networks.count(netPath))
    return;
  try {
    auto proxy = sdbus::createProxy(m_bus.connection(), k_iwdBusName, sdbus::ObjectPath{netPath});
    m_networks.emplace(netPath, std::move(proxy));
  } catch (const sdbus::Error& e) {
    kLog.warn("failed to subscribe network {}: {}", netPath, e.what());
  }
}

sdbus::IProxy* IwdService::firstStation() const {
  return m_stations.empty() ? nullptr : m_stations.begin()->second.get();
}

bool IwdService::hasSavedConnection(const std::string& ssid) const { return m_knownNetworks.count(ssid) > 0; }

void IwdService::requestScan() {
  for (const auto& [path, proxy] : m_stations) {
    try {
      proxy->callMethod("Scan").onInterface(k_stationInterface);
    } catch (const sdbus::Error& e) {
      kLog.debug("Scan failed on {}: {}", path, e.what());
    }
  }
}

bool IwdService::activateAccessPoint(const AccessPointInfo& ap) {
  // ap.path is the network object path set during GetOrderedNetworks enumeration.
  const auto it = m_networks.find(ap.path);
  if (it == m_networks.end()) {
    kLog.warn("activateAccessPoint: no network object found for ssid '{}'", ap.ssid);
    return false;
  }
  try {
    it->second->callMethod("Connect").onInterface(k_networkInterface);
    return true;
  } catch (const sdbus::Error& e) {
    kLog.warn("Connect failed for {}: {}", ap.ssid, e.what());
    return false;
  }
}

bool IwdService::activateAccessPoint(const AccessPointInfo& ap, const std::string& /*psk*/) {
  // IWD handles PSK via its own agent mechanism; just call Connect and IWD will
  // prompt the registered agent if a passphrase is needed.
  return activateAccessPoint(ap);
}

void IwdService::disconnect() {
  for (const auto& [path, proxy] : m_stations) {
    try {
      proxy->callMethod("Disconnect").onInterface(k_stationInterface);
    } catch (const sdbus::Error& e) {
      kLog.warn("Disconnect failed on {}: {}", path, e.what());
    }
  }
}

void IwdService::setWirelessEnabled(bool enabled) {
  // IWD exposes Powered on the net.connman.iwd.Device interface.
  for (const auto& [stationPath, stationProxy] : m_stations) {
    // The device object shares the same path prefix; try setting Powered on Device.
    try {
      auto devProxy = sdbus::createProxy(m_bus.connection(), k_iwdBusName, sdbus::ObjectPath{stationPath});
      devProxy->setProperty("Powered").onInterface(k_deviceInterface).toValue(enabled);
    } catch (const sdbus::Error& e) {
      kLog.warn("setWirelessEnabled({}) failed on {}: {}", enabled, stationPath, e.what());
    }
  }
  rebuildState();
}

void IwdService::forgetSsid(const std::string& ssid) {
  const auto it = m_knownNetworks.find(ssid);
  if (it == m_knownNetworks.end())
    return;
  try {
    auto proxy = sdbus::createProxy(m_bus.connection(), k_iwdBusName, sdbus::ObjectPath{it->second});
    proxy->callMethod("Forget").onInterface(k_knownNetworkInterface);
    m_knownNetworks.erase(it);
  } catch (const sdbus::Error& e) {
    kLog.warn("forgetSsid failed for '{}': {}", ssid, e.what());
  }
}

void IwdService::rebuildState() {
  NetworkState next;
  next.wirelessEnabled = !m_stations.empty();

  std::vector<AccessPointInfo> aps;
  m_knownNetworks.clear();

  // Collect known networks from all network objects.
  for (const auto& [netPath, proxy] : m_networks) {
    const std::string name = getPropertyOr<std::string>(*proxy, k_networkInterface, "Name", "");
    if (name.empty())
      continue;
    // KnownNetwork property is an object path; non-empty means it's saved.
    try {
      const auto knownPath =
          proxy->getProperty("KnownNetwork").onInterface(k_networkInterface).get<sdbus::ObjectPath>();
      if (!std::string(knownPath).empty() && std::string(knownPath) != "/") {
        m_knownNetworks[name] = std::string(knownPath);
      }
    } catch (const sdbus::Error&) {
    }
  }

  for (const auto& [stationPath, stationProxy] : m_stations) {
    const std::string stateStr = getPropertyOr<std::string>(*stationProxy, k_stationInterface, "State", "disconnected");
    next.scanning = next.scanning || getPropertyOr(*stationProxy, k_stationInterface, "Scanning", false);

    const bool connected = (stateStr == "connected");
    const bool connecting = (stateStr == "connecting");

    if (connected || connecting) {
      next.kind = NetworkConnectivity::Wireless;
      next.connected = connected;

      // Device name from Device interface on the same object path.
      next.interfaceName = getPropertyOr<std::string>(*stationProxy, k_deviceInterface, "Name", "");

      // Connected network SSID.
      try {
        const auto connNetPath =
            stationProxy->getProperty("ConnectedNetwork").onInterface(k_stationInterface).get<sdbus::ObjectPath>();
        const std::string connNetKey{connNetPath};
        if (const auto it = m_networks.find(connNetKey); it != m_networks.end()) {
          next.ssid = getPropertyOr<std::string>(*it->second, k_networkInterface, "Name", "");
        }
      } catch (const sdbus::Error&) {
      }
    }

    // Enumerate visible networks with signal strength via OrderedNetworks().
    try {
      // Returns array of (object_path, int16 signal_strength).
      using OrderedEntry = sdbus::Struct<sdbus::ObjectPath, std::int16_t>;
      std::vector<OrderedEntry> ordered;
      stationProxy->callMethod("GetOrderedNetworks")
          .onInterface(k_stationInterface)
          .storeResultsTo(ordered);

      for (const auto& entry : ordered) {
        const std::string netPath{std::get<0>(entry)};
        const std::int16_t dBm = std::get<1>(entry);

        auto netIt = m_networks.find(netPath);
        if (netIt == m_networks.end())
          continue;

        const std::string ssid = getPropertyOr<std::string>(*netIt->second, k_networkInterface, "Name", "");
        if (ssid.empty())
          continue;

        const std::string type = getPropertyOr<std::string>(*netIt->second, k_networkInterface, "Type", "");
        const bool secured = (type == "psk" || type == "8021x");
        const bool isActive = getPropertyOr(*netIt->second, k_networkInterface, "Connected", false);
        const std::uint8_t strength = signalToPercent(dBm);

        if (isActive && connected) {
          next.signalStrength = strength;
        }

        auto existing = std::find_if(aps.begin(), aps.end(), [&](const AccessPointInfo& a) { return a.ssid == ssid; });
        if (existing != aps.end()) {
          if (strength > existing->strength)
            existing->strength = strength;
          if (isActive)
            existing->active = true;
        } else {
          AccessPointInfo ap;
          ap.path = netPath;
          ap.devicePath = stationPath;
          ap.ssid = ssid;
          ap.strength = strength;
          ap.secured = secured;
          ap.active = isActive;
          aps.push_back(std::move(ap));
        }
      }
    } catch (const sdbus::Error& e) {
      kLog.debug("GetOrderedNetworks failed on {}: {}", stationPath, e.what());
    }
  }

  std::sort(aps.begin(), aps.end(), [](const AccessPointInfo& a, const AccessPointInfo& b) {
    if (a.active != b.active)
      return a.active > b.active;
    return a.strength > b.strength;
  });

  m_accessPoints = std::move(aps);
  emitChangedIfNeeded(std::move(next));
}

void IwdService::refresh() { rebuildState(); }

void IwdService::emitChangedIfNeeded(NetworkState next) {
  const bool firstSnapshot = !m_hasStateSnapshot;
  const bool stateChanged = next != m_state;
  m_state = std::move(next);
  m_hasStateSnapshot = true;
  if ((firstSnapshot || stateChanged) && m_changeCallback) {
    m_changeCallback(m_state, NetworkChangeOrigin::External);
  }
}
