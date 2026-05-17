#include "dbus/network/wpa_supplicant_service.h"

#include "core/log.h"
#include "dbus/system_bus.h"

#include <cstdint>
#include <map>
#include <string>
#include <vector>

#include <sdbus-c++/IProxy.h>
#include <sdbus-c++/Types.h>

namespace {

  constexpr Logger kLog("wpa_supplicant");

  const sdbus::ServiceName k_wpaBusName{"fi.w1.wpa_supplicant1"};
  const sdbus::ObjectPath k_wpaObjectPath{"/fi/w1/wpa_supplicant1"};
  constexpr auto k_wpaInterface = "fi.w1.wpa_supplicant1";
  constexpr auto k_wpaIfaceInterface = "fi.w1.wpa_supplicant1.Interface";
  constexpr auto k_wpaBssInterface = "fi.w1.wpa_supplicant1.BSS";
  constexpr auto k_propertiesInterface = "org.freedesktop.DBus.Properties";

  // wpa_supplicant interface states that mean "connected".
  // https://w1.fi/wpa_supplicant/devel/dbus.html
  constexpr auto k_stateCompleted = "completed";
  constexpr auto k_stateAssociated = "associated";
  constexpr auto k_stateAssociating = "associating";
  constexpr auto k_stateGroupHandshake = "group_handshake";
  constexpr auto k_state4wayHandshake = "4way_handshake";

  template <typename T>
  T getPropertyOr(sdbus::IProxy& proxy, std::string_view iface, std::string_view prop, T fallback) {
    try {
      return proxy.getProperty(prop).onInterface(std::string(iface)).template get<T>();
    } catch (const sdbus::Error&) {
      return fallback;
    }
  }

  // Convert a wpa_supplicant SSID (byte array) to a UTF-8 string.
  std::string ssidFromBytes(const std::vector<std::uint8_t>& bytes) {
    return std::string(reinterpret_cast<const char*>(bytes.data()), bytes.size());
  }

  // Convert wpa_supplicant signal level (dBm, typically -100..0) to 0..100.
  std::uint8_t signalToPercent(std::int16_t dBm) {
    if (dBm <= -100) {
      return 0;
    }
    if (dBm >= -50) {
      return 100;
    }
    return static_cast<std::uint8_t>(2 * (dBm + 100));
  }

  // A BSS is "secured" if it advertises any RSN/WPA key management.
  bool bssIsSecured(sdbus::IProxy& bss) {
    try {
      using VariantMap = std::map<std::string, sdbus::Variant>;
      const auto rsn = bss.getProperty("RSN").onInterface(k_wpaBssInterface).get<VariantMap>();
      if (!rsn.empty()) {
        return true;
      }
    } catch (const sdbus::Error&) {
    }
    try {
      using VariantMap = std::map<std::string, sdbus::Variant>;
      const auto wpa = bss.getProperty("WPA").onInterface(k_wpaBssInterface).get<VariantMap>();
      if (!wpa.empty()) {
        return true;
      }
    } catch (const sdbus::Error&) {
    }
    return false;
  }

} // namespace

WpaSupplicantService::WpaSupplicantService(SystemBus& bus) : m_bus(bus) {
  m_wpa = sdbus::createProxy(m_bus.connection(), k_wpaBusName, k_wpaObjectPath);

  // Subscribe to InterfaceAdded / InterfaceRemoved on the root object.
  m_wpa->uponSignal("InterfaceAdded")
      .onInterface(k_wpaInterface)
      .call([this](const sdbus::ObjectPath& path, const std::map<std::string, sdbus::Variant>& /*props*/) {
        subscribeInterface(std::string(path));
        rebuildState();
      });

  m_wpa->uponSignal("InterfaceRemoved")
      .onInterface(k_wpaInterface)
      .call([this](const sdbus::ObjectPath& path) {
        m_interfaces.erase(std::string(path));
        rebuildState();
      });

  // Subscribe to all currently-known interfaces.
  try {
    const auto ifaces =
        m_wpa->getProperty("Interfaces").onInterface(k_wpaInterface).get<std::vector<sdbus::ObjectPath>>();
    for (const auto& p : ifaces) {
      subscribeInterface(std::string(p));
    }
  } catch (const sdbus::Error& e) {
    kLog.warn("failed to enumerate interfaces: {}", e.what());
  }

  rebuildState();
}

WpaSupplicantService::~WpaSupplicantService() = default;

void WpaSupplicantService::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

void WpaSupplicantService::subscribeInterface(const std::string& ifacePath) {
  if (m_interfaces.count(ifacePath)) {
    return;
  }
  try {
    auto proxy = sdbus::createProxy(m_bus.connection(), k_wpaBusName, sdbus::ObjectPath{ifacePath});

    proxy->uponSignal("PropertiesChanged")
        .onInterface(k_propertiesInterface)
        .call([this](const std::string& /*iface*/, const std::map<std::string, sdbus::Variant>& /*changed*/,
                     const std::vector<std::string>& /*invalidated*/) { rebuildState(); });

    proxy->uponSignal("ScanDone")
        .onInterface(k_wpaIfaceInterface)
        .call([this](bool /*success*/) { rebuildState(); });

    m_interfaces.emplace(ifacePath, std::move(proxy));
  } catch (const sdbus::Error& e) {
    kLog.warn("failed to subscribe interface {}: {}", ifacePath, e.what());
  }
}

void WpaSupplicantService::rebuildState() {
  NetworkState next;
  next.wirelessEnabled = !m_interfaces.empty();

  std::vector<AccessPointInfo> aps;
  std::string activeBssPath;

  for (const auto& [ifacePath, proxy] : m_interfaces) {
    const std::string state = getPropertyOr<std::string>(*proxy, k_wpaIfaceInterface, "State", "inactive");
    const std::string ifname = getPropertyOr<std::string>(*proxy, k_wpaIfaceInterface, "Ifname", "");

    const bool connected = (state == k_stateCompleted || state == k_stateAssociated ||
                            state == k_stateGroupHandshake || state == k_state4wayHandshake);
    const bool associating = (state == k_stateAssociating);

    if (connected || associating) {
      next.kind = NetworkConnectivity::Wireless;
      next.connected = connected;
      next.interfaceName = ifname;

      // Current BSS.
      try {
        const auto currentBss =
            proxy->getProperty("CurrentBSS").onInterface(k_wpaIfaceInterface).get<sdbus::ObjectPath>();
        activeBssPath = std::string(currentBss);
      } catch (const sdbus::Error&) {
      }

      // Current network SSID.
      try {
        const auto currentNetwork =
            proxy->getProperty("CurrentNetwork").onInterface(k_wpaIfaceInterface).get<sdbus::ObjectPath>();
        if (std::string(currentNetwork) != "/") {
          auto netProxy = sdbus::createProxy(m_bus.connection(), k_wpaBusName, currentNetwork);
          using VariantMap = std::map<std::string, sdbus::Variant>;
          const auto props = netProxy->getProperty("Properties")
                                 .onInterface("fi.w1.wpa_supplicant1.Network")
                                 .get<VariantMap>();
          if (const auto it = props.find("ssid"); it != props.end()) {
            try {
              next.ssid = it->second.get<std::string>();
              // Strip surrounding quotes that wpa_supplicant sometimes adds.
              if (next.ssid.size() >= 2 && next.ssid.front() == '"' && next.ssid.back() == '"') {
                next.ssid = next.ssid.substr(1, next.ssid.size() - 2);
              }
            } catch (const sdbus::Error&) {
            }
          }
        }
      } catch (const sdbus::Error&) {
      }
    }

    // Enumerate visible BSSes.
    try {
      const auto bssPaths =
          proxy->getProperty("BSSs").onInterface(k_wpaIfaceInterface).get<std::vector<sdbus::ObjectPath>>();
      for (const auto& bssPath : bssPaths) {
        try {
          auto bssProxy = sdbus::createProxy(m_bus.connection(), k_wpaBusName, bssPath);
          const auto ssidBytes =
              getPropertyOr<std::vector<std::uint8_t>>(*bssProxy, k_wpaBssInterface, "SSID", {});
          if (ssidBytes.empty()) {
            continue;
          }
          const std::string ssid = ssidFromBytes(ssidBytes);
          const auto signal =
              getPropertyOr<std::int16_t>(*bssProxy, k_wpaBssInterface, "Signal", std::int16_t{-100});
          const bool secured = bssIsSecured(*bssProxy);
          const bool active = (std::string(bssPath) == activeBssPath);

          // Deduplicate by SSID: keep the strongest signal.
          auto existing = std::find_if(aps.begin(), aps.end(), [&ssid](const AccessPointInfo& a) {
            return a.ssid == ssid;
          });
          const std::uint8_t pct = signalToPercent(signal);
          if (existing != aps.end()) {
            if (pct > existing->strength) {
              existing->strength = pct;
            }
            if (active) {
              existing->active = true;
            }
          } else {
            AccessPointInfo ap;
            ap.path = std::string(bssPath);
            ap.devicePath = ifacePath;
            ap.ssid = ssid;
            ap.strength = pct;
            ap.secured = secured;
            ap.active = active;
            aps.push_back(std::move(ap));
          }
        } catch (const sdbus::Error&) {
        }
      }
    } catch (const sdbus::Error&) {
    }

    // Signal strength for the active connection.
    if ((connected || associating) && !activeBssPath.empty()) {
      try {
        auto bssProxy = sdbus::createProxy(m_bus.connection(), k_wpaBusName, sdbus::ObjectPath{activeBssPath});
        const auto signal =
            getPropertyOr<std::int16_t>(*bssProxy, k_wpaBssInterface, "Signal", std::int16_t{-100});
        next.signalStrength = signalToPercent(signal);
      } catch (const sdbus::Error&) {
      }
    }
  }

  // Sort: active first, then by signal strength descending.
  std::sort(aps.begin(), aps.end(), [](const AccessPointInfo& a, const AccessPointInfo& b) {
    if (a.active != b.active) {
      return a.active > b.active;
    }
    return a.strength > b.strength;
  });

  m_accessPoints = std::move(aps);
  emitChangedIfNeeded(std::move(next));
}

void WpaSupplicantService::refresh() { rebuildState(); }

void WpaSupplicantService::requestScan() {
  for (const auto& [ifacePath, proxy] : m_interfaces) {
    try {
      const std::map<std::string, sdbus::Variant> args{{"Type", sdbus::Variant{std::string{"passive"}}}};
      proxy->callMethod("Scan").onInterface(k_wpaIfaceInterface).withArguments(args);
    } catch (const sdbus::Error& e) {
      kLog.debug("Scan failed on {}: {}", ifacePath, e.what());
    }
  }
}

void WpaSupplicantService::emitChangedIfNeeded(NetworkState next) {
  const bool firstSnapshot = !m_hasStateSnapshot;
  const bool stateChanged = next != m_state;
  m_state = std::move(next);
  m_hasStateSnapshot = true;
  if ((firstSnapshot || stateChanged) && m_changeCallback) {
    m_changeCallback(m_state, NetworkChangeOrigin::External);
  }
}
