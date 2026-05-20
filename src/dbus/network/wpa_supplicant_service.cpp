#include "dbus/network/wpa_supplicant_service.h"

#include "core/log.h"
#include "dbus/system_bus.h"

#include <algorithm>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <linux/rfkill.h>
#include <map>
#include <sdbus-c++/IProxy.h>
#include <sdbus-c++/Types.h>
#include <string>
#include <unistd.h>
#include <vector>

namespace {

  constexpr Logger kLog("wpa_supplicant");

  const sdbus::ServiceName k_wpaBusName{"fi.w1.wpa_supplicant1"};
  const sdbus::ObjectPath k_wpaObjectPath{"/fi/w1/wpa_supplicant1"};
  constexpr auto k_wpaInterface = "fi.w1.wpa_supplicant1";
  constexpr auto k_wpaIfaceInterface = "fi.w1.wpa_supplicant1.Interface";
  constexpr auto k_wpaBssInterface = "fi.w1.wpa_supplicant1.BSS";
  constexpr auto k_propertiesInterface = "org.freedesktop.DBus.Properties";

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

  std::uint8_t signalToPercent(std::int16_t dBm) {
    if (dBm <= -100)
      return 0;
    if (dBm >= -50)
      return 100;
    return static_cast<std::uint8_t>(2 * (dBm + 100));
  }

  // Read all BSS properties in one GetAll round-trip.
  struct BssInfo {
    std::string ssid;
    std::int16_t signal = -100;
    bool secured = false;
  };

  std::optional<BssInfo> readBssInfo(sdbus::IProxy& proxy) {
    try {
      using VariantMap = std::map<std::string, sdbus::Variant>;
      VariantMap all;
      proxy.callMethod("GetAll")
          .onInterface(k_propertiesInterface)
          .withArguments(std::string{k_wpaBssInterface})
          .storeResultsTo(all);

      const auto ssidIt = all.find("SSID");
      if (ssidIt == all.end())
        return std::nullopt;
      const auto ssidBytes = ssidIt->second.get<std::vector<std::uint8_t>>();
      if (ssidBytes.empty())
        return std::nullopt;

      BssInfo info;
      info.ssid = {reinterpret_cast<const char*>(ssidBytes.data()), ssidBytes.size()};

      if (const auto it = all.find("Signal"); it != all.end()) {
        info.signal = it->second.get<std::int16_t>();
      }

      // Secured if RSN or WPA map is non-empty.
      for (const auto* key : {"RSN", "WPA"}) {
        if (const auto it = all.find(key); it != all.end()) {
          try {
            VariantMap vm;
            vm = it->second.get<VariantMap>();
            if (!vm.empty()) {
              info.secured = true;
              break;
            }
          } catch (const sdbus::Error&) {
          }
        }
      }

      return info;
    } catch (const sdbus::Error&) {
      return std::nullopt;
    }
  }

} // namespace

WpaSupplicantService::WpaSupplicantService(SystemBus& bus) : m_bus(bus) {
  if (!bus.nameHasOwner("fi.w1.wpa_supplicant1")) {
    throw sdbus::Error(sdbus::Error::Name{"org.freedesktop.DBus.Error.ServiceUnknown"},
                       "The name fi.w1.wpa_supplicant1 was not provided by any .service files");
  }

  m_wpa = sdbus::createProxy(m_bus.connection(), k_wpaBusName, k_wpaObjectPath);

  m_wpa->uponSignal("InterfaceAdded")
      .onInterface(k_wpaInterface)
      .call([this](const sdbus::ObjectPath& path, const std::map<std::string, sdbus::Variant>&) {
        subscribeInterface(std::string(path));
        scheduleRebuild();
      });

  m_wpa->uponSignal("InterfaceRemoved").onInterface(k_wpaInterface).call([this](const sdbus::ObjectPath& path) {
    m_interfaces.erase(std::string(path));
    scheduleRebuild();
  });

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
  if (m_interfaces.count(ifacePath))
    return;
  try {
    auto proxy = sdbus::createProxy(m_bus.connection(), k_wpaBusName, sdbus::ObjectPath{ifacePath});

    proxy->uponSignal("PropertiesChanged")
        .onInterface(k_propertiesInterface)
        .call([this](const std::string&, const std::map<std::string, sdbus::Variant>&,
                     const std::vector<std::string>&) { scheduleRebuild(); });

    proxy->uponSignal("ScanDone").onInterface(k_wpaIfaceInterface).call([this](bool) { scheduleRebuild(); });

    // Maintain BSS proxy cache via signals — avoids createProxy in rebuildState.
    proxy->uponSignal("BSSAdded")
        .onInterface(k_wpaIfaceInterface)
        .call([this](const sdbus::ObjectPath& bssPath, const std::map<std::string, sdbus::Variant>&) {
          const std::string key{bssPath};
          if (!m_bssProxies.count(key)) {
            try {
              m_bssProxies.emplace(key, sdbus::createProxy(m_bus.connection(), k_wpaBusName, bssPath));
            } catch (const sdbus::Error&) {
            }
          }
          scheduleRebuild();
        });

    proxy->uponSignal("BSSRemoved").onInterface(k_wpaIfaceInterface).call([this](const sdbus::ObjectPath& bssPath) {
      m_bssProxies.erase(std::string(bssPath));
      scheduleRebuild();
    });

    // Pre-populate BSS cache for already-visible BSSes.
    try {
      const auto bssPaths =
          proxy->getProperty("BSSs").onInterface(k_wpaIfaceInterface).get<std::vector<sdbus::ObjectPath>>();
      for (const auto& bssPath : bssPaths) {
        const std::string key{bssPath};
        if (!m_bssProxies.count(key)) {
          try {
            m_bssProxies.emplace(key, sdbus::createProxy(m_bus.connection(), k_wpaBusName, bssPath));
          } catch (const sdbus::Error&) {
          }
        }
      }
    } catch (const sdbus::Error&) {
    }

    auto& ref = *proxy;
    m_interfaces.emplace(ifacePath, std::move(proxy));
    loadSavedNetworks(ifacePath, ref);
  } catch (const sdbus::Error& e) {
    kLog.warn("failed to subscribe interface {}: {}", ifacePath, e.what());
  }
}

void WpaSupplicantService::scheduleRebuild() {
  if (m_rebuildPending)
    return;
  m_rebuildPending = true;
  // Rebuild is deferred to the next poll-loop dispatch via refresh().
  // For immediate correctness on the first call we also rebuild now,
  // but subsequent rapid signals within the same dispatch batch are coalesced.
  rebuildState();
  m_rebuildPending = false;
}

void WpaSupplicantService::loadSavedNetworks(const std::string& /*ifacePath*/, sdbus::IProxy& proxy) {
  if (&proxy != firstInterface())
    return;
  m_savedNetworks.clear();
  try {
    const auto paths =
        proxy.getProperty("Networks").onInterface(k_wpaIfaceInterface).get<std::vector<sdbus::ObjectPath>>();
    for (const auto& netPath : paths) {
      try {
        auto netProxy = sdbus::createProxy(m_bus.connection(), k_wpaBusName, netPath);
        using VariantMap = std::map<std::string, sdbus::Variant>;
        const auto props =
            netProxy->getProperty("Properties").onInterface("fi.w1.wpa_supplicant1.Network").get<VariantMap>();
        if (const auto it = props.find("ssid"); it != props.end()) {
          std::string ssid = it->second.get<std::string>();
          if (ssid.size() >= 2 && ssid.front() == '"' && ssid.back() == '"') {
            ssid = ssid.substr(1, ssid.size() - 2);
          }
          if (!ssid.empty()) {
            m_savedNetworks[ssid] = std::string(netPath);
          }
        }
      } catch (const sdbus::Error&) {
      }
    }
  } catch (const sdbus::Error& e) {
    kLog.debug("loadSavedNetworks failed: {}", e.what());
  }
}

sdbus::IProxy* WpaSupplicantService::firstInterface() const {
  return m_interfaces.empty() ? nullptr : m_interfaces.begin()->second.get();
}

bool WpaSupplicantService::hasSavedConnection(const std::string& ssid) const { return m_savedNetworks.count(ssid) > 0; }

bool WpaSupplicantService::activateAccessPoint(const AccessPointInfo& ap) {
  auto* iface = firstInterface();
  if (iface == nullptr)
    return false;
  if (const auto it = m_savedNetworks.find(ap.ssid); it != m_savedNetworks.end()) {
    try {
      iface->callMethod("SelectNetwork").onInterface(k_wpaIfaceInterface).withArguments(sdbus::ObjectPath{it->second});
      return true;
    } catch (const sdbus::Error& e) {
      kLog.warn("SelectNetwork failed: {}", e.what());
      return false;
    }
  }
  try {
    using VariantMap = std::map<std::string, sdbus::Variant>;
    VariantMap args;
    args["ssid"] = sdbus::Variant{'"' + ap.ssid + '"'};
    args["key_mgmt"] = sdbus::Variant{std::string{"NONE"}};
    sdbus::ObjectPath netPath;
    iface->callMethod("AddNetwork").onInterface(k_wpaIfaceInterface).withArguments(args).storeResultsTo(netPath);
    iface->callMethod("SelectNetwork").onInterface(k_wpaIfaceInterface).withArguments(netPath);
    iface->callMethod("SaveConfig").onInterface(k_wpaIfaceInterface);
    return true;
  } catch (const sdbus::Error& e) {
    kLog.warn("activateAccessPoint (open) failed: {}", e.what());
    return false;
  }
}

bool WpaSupplicantService::activateAccessPoint(const AccessPointInfo& ap, const std::string& psk) {
  auto* iface = firstInterface();
  if (iface == nullptr)
    return false;
  try {
    using VariantMap = std::map<std::string, sdbus::Variant>;
    VariantMap args;
    args["ssid"] = sdbus::Variant{'"' + ap.ssid + '"'};
    args["psk"] = sdbus::Variant{psk}; // raw passphrase, no quotes
    sdbus::ObjectPath netPath;
    iface->callMethod("AddNetwork").onInterface(k_wpaIfaceInterface).withArguments(args).storeResultsTo(netPath);
    iface->callMethod("SelectNetwork").onInterface(k_wpaIfaceInterface).withArguments(netPath);
    iface->callMethod("SaveConfig").onInterface(k_wpaIfaceInterface);
    return true;
  } catch (const sdbus::Error& e) {
    kLog.warn("activateAccessPoint (psk) failed: {}", e.what());
    return false;
  }
}

void WpaSupplicantService::disconnect() {
  auto* iface = firstInterface();
  if (iface == nullptr)
    return;
  try {
    iface->callMethod("Disconnect").onInterface(k_wpaIfaceInterface);
  } catch (const sdbus::Error& e) {
    kLog.warn("Disconnect failed: {}", e.what());
  }
}

void WpaSupplicantService::setWirelessEnabled(bool enabled) {
  m_wirelessEnabledOverride = enabled;

  bool rfkillDone = false;
  for (const auto& [ifacePath, proxy] : m_interfaces) {
    const std::string ifname = getPropertyOr<std::string>(*proxy, k_wpaIfaceInterface, "Ifname", "");
    if (ifname.empty())
      continue;

    const std::string phyPath = "/sys/class/net/" + ifname + "/phy80211/";
    DIR* dir = opendir(phyPath.c_str());
    if (dir == nullptr)
      continue;
    struct dirent* ent = nullptr;
    while ((ent = readdir(dir)) != nullptr) {
      const std::string name = ent->d_name;
      if (name.rfind("rfkill", 0) != 0)
        continue;
      FILE* f = fopen((phyPath + name + "/index").c_str(), "r");
      if (f == nullptr)
        continue;
      std::uint32_t idx = 0;
      const int scanned = fscanf(f, "%u", &idx);
      fclose(f);
      if (scanned != 1) {
        kLog.warn("setWirelessEnabled: cannot read rfkill index");
        continue;
      }
      const int fd = open("/dev/rfkill", O_WRONLY | O_CLOEXEC);
      if (fd < 0) {
        kLog.warn("setWirelessEnabled: cannot open /dev/rfkill: {}", std::strerror(errno));
        break;
      }
      struct rfkill_event ev{};
      ev.idx = idx;
      ev.type = RFKILL_TYPE_WLAN;
      ev.op = RFKILL_OP_CHANGE;
      ev.soft = enabled ? 0 : 1;
      ssize_t written = 0;
      do {
        written = write(fd, &ev, sizeof(ev));
      } while (written < 0 && errno == EINTR);
      const int writeErrno = errno;
      close(fd);
      if (written != static_cast<ssize_t>(sizeof(ev))) {
        kLog.warn("setWirelessEnabled: /dev/rfkill write failed: {}",
                  written < 0 ? std::strerror(writeErrno) : "short write");
        break;
      }
      rfkillDone = true;
      break;
    }
    closedir(dir);
    if (rfkillDone)
      break;
  }

  if (!rfkillDone) {
    auto* iface = firstInterface();
    if (iface != nullptr) {
      try {
        if (enabled)
          iface->callMethod("Reconnect").onInterface(k_wpaIfaceInterface);
        else
          iface->callMethod("Disconnect").onInterface(k_wpaIfaceInterface);
      } catch (const sdbus::Error& e) {
        kLog.warn("setWirelessEnabled({}) fallback failed: {}", enabled, e.what());
      }
    }
  }

  rebuildState();
}

void WpaSupplicantService::forgetSsid(const std::string& ssid) {
  auto* iface = firstInterface();
  if (iface == nullptr)
    return;
  const auto it = m_savedNetworks.find(ssid);
  if (it == m_savedNetworks.end())
    return;
  try {
    iface->callMethod("RemoveNetwork").onInterface(k_wpaIfaceInterface).withArguments(sdbus::ObjectPath{it->second});
    iface->callMethod("SaveConfig").onInterface(k_wpaIfaceInterface);
    m_savedNetworks.erase(it);
  } catch (const sdbus::Error& e) {
    kLog.warn("forgetSsid failed: {}", e.what());
  }
}

void WpaSupplicantService::rebuildState() {
  NetworkState next;
  next.wirelessEnabled = m_wirelessEnabledOverride.value_or(!m_interfaces.empty());

  std::vector<AccessPointInfo> aps;
  std::string activeBssPath;

  for (const auto& [ifacePath, proxy] : m_interfaces) {
    const std::string state = getPropertyOr<std::string>(*proxy, k_wpaIfaceInterface, "State", "inactive");
    const std::string ifname = getPropertyOr<std::string>(*proxy, k_wpaIfaceInterface, "Ifname", "");
    next.scanning = next.scanning || getPropertyOr(*proxy, k_wpaIfaceInterface, "Scanning", false);

    const bool connected = (state == k_stateCompleted || state == k_stateAssociated || state == k_stateGroupHandshake ||
                            state == k_state4wayHandshake);
    const bool associating = (state == k_stateAssociating);

    if (connected || associating) {
      next.kind = NetworkConnectivity::Wireless;
      next.connected = connected;
      next.interfaceName = ifname;

      try {
        const auto currentBss =
            proxy->getProperty("CurrentBSS").onInterface(k_wpaIfaceInterface).get<sdbus::ObjectPath>();
        activeBssPath = std::string(currentBss);
      } catch (const sdbus::Error&) {
      }

      try {
        const auto currentNetwork =
            proxy->getProperty("CurrentNetwork").onInterface(k_wpaIfaceInterface).get<sdbus::ObjectPath>();
        if (std::string(currentNetwork) != "/") {
          auto netProxy = sdbus::createProxy(m_bus.connection(), k_wpaBusName, currentNetwork);
          using VariantMap = std::map<std::string, sdbus::Variant>;
          const auto props =
              netProxy->getProperty("Properties").onInterface("fi.w1.wpa_supplicant1.Network").get<VariantMap>();
          if (const auto it = props.find("ssid"); it != props.end()) {
            try {
              next.ssid = it->second.get<std::string>();
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

    // Enumerate BSSes using cached proxies — one GetAll per BSS, no createProxy.
    try {
      const auto bssPaths =
          proxy->getProperty("BSSs").onInterface(k_wpaIfaceInterface).get<std::vector<sdbus::ObjectPath>>();
      for (const auto& bssPath : bssPaths) {
        const std::string key{bssPath};
        auto cacheIt = m_bssProxies.find(key);
        if (cacheIt == m_bssProxies.end()) {
          // Not yet in cache (race between BSSAdded signal and this rebuild) — create and cache now.
          try {
            auto p = sdbus::createProxy(m_bus.connection(), k_wpaBusName, bssPath);
            cacheIt = m_bssProxies.emplace(key, std::move(p)).first;
          } catch (const sdbus::Error&) {
            continue;
          }
        }

        const auto info = readBssInfo(*cacheIt->second);
        if (!info)
          continue;

        const bool active = (key == activeBssPath);
        const std::uint8_t pct = signalToPercent(info->signal);

        auto existing =
            std::find_if(aps.begin(), aps.end(), [&](const AccessPointInfo& a) { return a.ssid == info->ssid; });
        if (existing != aps.end()) {
          if (pct > existing->strength)
            existing->strength = pct;
          if (active)
            existing->active = true;
        } else {
          AccessPointInfo ap;
          ap.path = key;
          ap.devicePath = ifacePath;
          ap.ssid = info->ssid;
          ap.strength = pct;
          ap.secured = info->secured;
          ap.active = active;
          aps.push_back(std::move(ap));
        }
      }
    } catch (const sdbus::Error&) {
    }

    if ((connected || associating) && !activeBssPath.empty()) {
      if (const auto it = m_bssProxies.find(activeBssPath); it != m_bssProxies.end()) {
        const auto signal = getPropertyOr<std::int16_t>(*it->second, k_wpaBssInterface, "Signal", std::int16_t{-100});
        next.signalStrength = signalToPercent(signal);
      }
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
