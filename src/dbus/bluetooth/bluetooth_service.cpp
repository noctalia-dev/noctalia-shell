#include "dbus/bluetooth/bluetooth_service.h"

#include "core/log.h"
#include "dbus/system_bus.h"
#include "i18n/i18n.h"

#include <algorithm>
#include <map>
#include <optional>
#include <sdbus-c++/IConnection.h>
#include <sdbus-c++/IProxy.h>
#include <sdbus-c++/Types.h>
#include <string_view>
#include <utility>
#include <vector>

namespace {

  constexpr Logger kLog("bluetooth");

  const sdbus::ServiceName k_bluezBusName{"org.bluez"};
  const sdbus::ObjectPath k_rootPath{"/"};
  constexpr auto k_adapterInterface = "org.bluez.Adapter1";
  constexpr auto k_deviceInterface = "org.bluez.Device1";
  constexpr auto k_batteryInterface = "org.bluez.Battery1";
  constexpr auto k_objectManagerInterface = "org.freedesktop.DBus.ObjectManager";
  constexpr auto k_propertiesInterface = "org.freedesktop.DBus.Properties";

  using InterfaceProps = std::map<std::string, sdbus::Variant>;
  using ObjectInterfaces = std::map<std::string, InterfaceProps>;
  using ManagedObjects = std::map<sdbus::ObjectPath, ObjectInterfaces>;

  template <typename T> std::optional<T> variantGet(const sdbus::Variant& value) {
    try {
      return value.get<T>();
    } catch (const sdbus::Error&) {
      return std::nullopt;
    }
  }

  BluetoothDeviceKind classifyIcon(std::string_view icon) {
    // See https://specifications.freedesktop.org/icon-naming-spec/latest/
    // BlueZ uses names like "audio-headset", "input-mouse", "phone", "computer".
    if (icon == "audio-headset") {
      return BluetoothDeviceKind::Headset;
    }
    if (icon == "audio-headphones") {
      return BluetoothDeviceKind::Headphones;
    }
    if (icon == "audio-card" || icon == "audio-speakers") {
      return BluetoothDeviceKind::Speaker;
    }
    if (icon == "input-mouse") {
      return BluetoothDeviceKind::Mouse;
    }
    if (icon == "input-keyboard") {
      return BluetoothDeviceKind::Keyboard;
    }
    if (icon == "input-gaming") {
      return BluetoothDeviceKind::Gamepad;
    }
    if (icon == "phone") {
      return BluetoothDeviceKind::Phone;
    }
    if (icon == "computer") {
      return BluetoothDeviceKind::Computer;
    }
    if (icon == "video-display") {
      return BluetoothDeviceKind::Tv;
    }
    return BluetoothDeviceKind::Unknown;
  }

  BluetoothDeviceKind classifyClass(std::uint32_t cod) {
    // Bluetooth Class of Device: bits 8-12 are Major Device Class.
    const std::uint32_t major = (cod >> 8) & 0x1FU;
    const std::uint32_t minor = (cod >> 2) & 0x3FU;
    switch (major) {
    case 0x01: // Computer
      return BluetoothDeviceKind::Computer;
    case 0x02: // Phone
      return BluetoothDeviceKind::Phone;
    case 0x04: // Audio/Video
      switch (minor) {
      case 0x01: // Wearable headset
      case 0x02: // Hands-free
        return BluetoothDeviceKind::Headset;
      case 0x06:
        return BluetoothDeviceKind::Headphones;
      case 0x05: // Loudspeaker
      case 0x07: // Portable audio
        return BluetoothDeviceKind::Speaker;
      case 0x04:
        return BluetoothDeviceKind::Microphone;
      case 0x0A: // Video display/loudspeaker
      case 0x0B: // Video display/conferencing
        return BluetoothDeviceKind::Tv;
      default:
        return BluetoothDeviceKind::Headphones;
      }
    case 0x05: // Peripheral
      switch (minor & 0x0FU) {
      case 0x01:
        return BluetoothDeviceKind::Keyboard;
      case 0x02:
        return BluetoothDeviceKind::Mouse;
      default:
        return BluetoothDeviceKind::Unknown;
      }
    case 0x07: // Wearable
      return BluetoothDeviceKind::Watch;
    case 0x08: // Toy / Gamepad
      return BluetoothDeviceKind::Gamepad;
    default:
      return BluetoothDeviceKind::Unknown;
    }
  }

  void readAdapterProps(const InterfaceProps& props, BluetoothState& out) {
    out.adapterPresent = true;
    if (auto it = props.find("Powered"); it != props.end()) {
      if (auto v = variantGet<bool>(it->second)) {
        out.powered = *v;
      }
    }
    if (auto it = props.find("Discoverable"); it != props.end()) {
      if (auto v = variantGet<bool>(it->second)) {
        out.discoverable = *v;
      }
    }
    if (auto it = props.find("Pairable"); it != props.end()) {
      if (auto v = variantGet<bool>(it->second)) {
        out.pairable = *v;
      }
    }
    if (auto it = props.find("Discovering"); it != props.end()) {
      if (auto v = variantGet<bool>(it->second)) {
        out.discovering = *v;
      }
    }
    if (auto it = props.find("Alias"); it != props.end()) {
      if (auto v = variantGet<std::string>(it->second)) {
        out.adapterName = std::move(*v);
      }
    } else if (auto nameIt = props.find("Name"); nameIt != props.end()) {
      if (auto v = variantGet<std::string>(nameIt->second)) {
        out.adapterName = std::move(*v);
      }
    }
  }

  void mergeDeviceProps(const InterfaceProps& props, BluetoothDeviceInfo& out) {
    if (auto it = props.find("Address"); it != props.end()) {
      if (auto v = variantGet<std::string>(it->second)) {
        out.address = std::move(*v);
      }
    }
    if (auto it = props.find("Alias"); it != props.end()) {
      if (auto v = variantGet<std::string>(it->second)) {
        out.alias = std::move(*v);
      }
    }
    if (out.alias.empty()) {
      if (auto it = props.find("Name"); it != props.end()) {
        if (auto v = variantGet<std::string>(it->second)) {
          out.alias = std::move(*v);
        }
      }
    }
    if (auto it = props.find("Paired"); it != props.end()) {
      if (auto v = variantGet<bool>(it->second)) {
        out.paired = *v;
      }
    }
    if (auto it = props.find("Trusted"); it != props.end()) {
      if (auto v = variantGet<bool>(it->second)) {
        out.trusted = *v;
      }
    }
    if (auto it = props.find("Connected"); it != props.end()) {
      if (auto v = variantGet<bool>(it->second)) {
        out.connected = *v;
        if (out.connected) {
          out.connecting = false;
        }
      }
    }
    if (auto it = props.find("RSSI"); it != props.end()) {
      if (auto v = variantGet<std::int16_t>(it->second)) {
        out.rssi = *v;
        out.hasRssi = true;
      }
    }
    BluetoothDeviceKind kindFromIcon = BluetoothDeviceKind::Unknown;
    if (auto it = props.find("Icon"); it != props.end()) {
      if (auto v = variantGet<std::string>(it->second)) {
        kindFromIcon = classifyIcon(*v);
      }
    }
    if (kindFromIcon != BluetoothDeviceKind::Unknown) {
      out.kind = kindFromIcon;
    } else if (auto it = props.find("Class"); it != props.end()) {
      if (auto v = variantGet<std::uint32_t>(it->second)) {
        const auto kindFromCod = classifyClass(*v);
        if (kindFromCod != BluetoothDeviceKind::Unknown) {
          out.kind = kindFromCod;
        }
      }
    }
    if (out.alias.empty()) {
      out.alias = out.address.empty() ? i18n::tr("control-center.bluetooth.unknown-device") : out.address;
    }
  }

  void mergeBatteryProps(const InterfaceProps& props, BluetoothDeviceInfo& out) {
    if (auto it = props.find("Percentage"); it != props.end()) {
      if (auto v = variantGet<std::uint8_t>(it->second)) {
        out.hasBattery = true;
        out.batteryPercent = *v;
      }
    }
  }

} // namespace

struct BluetoothService::Impl {
  BluetoothService& self;
  SystemBus& bus;
  std::unique_ptr<sdbus::IProxy> root; // ObjectManager on "/"
  std::unique_ptr<sdbus::IProxy> adapter;
  std::unordered_map<std::string, std::unique_ptr<sdbus::IProxy>> objectProxies;
  std::string adapterPath;

  Impl(BluetoothService& s, SystemBus& b) : self(s), bus(b) {}

  sdbus::IProxy* ensureObjectProxy(const std::string& path) {
    auto it = objectProxies.find(path);
    if (it != objectProxies.end()) {
      return it->second.get();
    }
    std::unique_ptr<sdbus::IProxy> proxy;
    try {
      proxy = sdbus::createProxy(bus.connection(), k_bluezBusName, sdbus::ObjectPath{path});
    } catch (const sdbus::Error& e) {
      kLog.debug("proxy create failed {}: {}", path, e.what());
      return nullptr;
    }
    proxy->uponSignal("PropertiesChanged")
        .onInterface(k_propertiesInterface)
        .call([this, objectPath = path](const std::string& interfaceName, const InterfaceProps& changed,
                                        const std::vector<std::string>& /*invalidated*/) {
          onPropertiesChanged(objectPath, interfaceName, changed);
        });
    auto* raw = proxy.get();
    objectProxies.emplace(path, std::move(proxy));
    return raw;
  }

  void dropObjectProxy(const std::string& path) { objectProxies.erase(path); }

  void onInterfacesAdded(const sdbus::ObjectPath& path, const ObjectInterfaces& interfaces) {
    bool stateDirty = false;
    bool devicesDirty = false;
    if (auto it = interfaces.find(k_adapterInterface); it != interfaces.end()) {
      if (adapterPath.empty()) {
        adoptAdapter(path, it->second);
        stateDirty = true;
      }
    }
    if (auto it = interfaces.find(k_deviceInterface); it != interfaces.end()) {
      adoptDevice(path, it->second);
      ensureObjectProxy(path);
      devicesDirty = true;
    }
    if (auto it = interfaces.find(k_batteryInterface); it != interfaces.end()) {
      if (auto* dev = self.findDevice(path)) {
        mergeBatteryProps(it->second, *dev);
        devicesDirty = true;
      }
      ensureObjectProxy(path);
    }
    if (stateDirty) {
      self.emitState();
    }
    if (devicesDirty) {
      self.emitDevices();
    }
  }

  void onInterfacesRemoved(const sdbus::ObjectPath& path, const std::vector<std::string>& interfaces) {
    bool stateDirty = false;
    bool devicesDirty = false;
    for (const auto& iface : interfaces) {
      if (iface == k_adapterInterface && std::string(path) == adapterPath) {
        adapter.reset();
        adapterPath.clear();
        self.m_state = BluetoothState{};
        stateDirty = true;
        dropObjectProxy(path);
      } else if (iface == k_deviceInterface) {
        auto& vec = self.m_devices;
        vec.erase(std::remove_if(vec.begin(), vec.end(),
                                 [&](const BluetoothDeviceInfo& d) { return d.path == std::string(path); }),
                  vec.end());
        devicesDirty = true;
        dropObjectProxy(path);
      } else if (iface == k_batteryInterface) {
        if (auto* dev = self.findDevice(path)) {
          dev->hasBattery = false;
          dev->batteryPercent = 0;
          devicesDirty = true;
        }
      }
    }
    if (stateDirty) {
      self.emitState();
    }
    if (devicesDirty) {
      self.emitDevices();
    }
  }

  void onPropertiesChanged(const std::string& objectPath, const std::string& interfaceName,
                           const InterfaceProps& changed) {
    if (interfaceName == k_adapterInterface && objectPath == adapterPath) {
      BluetoothState next = self.m_state;
      readAdapterProps(changed, next);
      next.adapterPresent = true;
      const bool poweredChanged = next.powered != self.m_state.powered;
      BluetoothStateChangeOrigin origin = BluetoothStateChangeOrigin::External;
      if (poweredChanged) {
        kLog.debug("adapter Powered -> {}", next.powered);
        origin = self.consumePoweredChangeOrigin(next.powered);
      }
      if (next != self.m_state) {
        self.m_state = std::move(next);
        self.emitState(origin);
      }
      return;
    }
    if (interfaceName == k_deviceInterface) {
      if (auto* dev = self.findDevice(objectPath)) {
        BluetoothDeviceInfo updated = *dev;
        mergeDeviceProps(changed, updated);
        if (updated != *dev) {
          *dev = std::move(updated);
          self.emitDevices();
        }
      }
      return;
    }
    if (interfaceName == k_batteryInterface) {
      if (auto* dev = self.findDevice(objectPath)) {
        BluetoothDeviceInfo updated = *dev;
        mergeBatteryProps(changed, updated);
        if (updated != *dev) {
          *dev = std::move(updated);
          self.emitDevices();
        }
      }
    }
  }

  void adoptAdapter(const sdbus::ObjectPath& path, const InterfaceProps& props) {
    adapterPath = path;
    try {
      adapter = sdbus::createProxy(bus.connection(), k_bluezBusName, path);
    } catch (const sdbus::Error& e) {
      kLog.warn("adapter proxy failed: {}", e.what());
      adapter.reset();
    }
    ensureObjectProxy(path);
    BluetoothState next{};
    readAdapterProps(props, next);
    self.m_state = std::move(next);
  }

  void adoptDevice(const sdbus::ObjectPath& path, const InterfaceProps& props) {
    if (auto* existing = self.findDevice(path)) {
      mergeDeviceProps(props, *existing);
      return;
    }
    BluetoothDeviceInfo info;
    info.path = path;
    mergeDeviceProps(props, info);
    self.m_devices.push_back(std::move(info));
  }

  void seedFromManagedObjects(const ManagedObjects& objects) {
    for (const auto& [path, interfaces] : objects) {
      if (auto it = interfaces.find(k_adapterInterface); it != interfaces.end()) {
        if (adapterPath.empty()) {
          adoptAdapter(path, it->second);
        }
      }
    }
    for (const auto& [path, interfaces] : objects) {
      if (auto it = interfaces.find(k_deviceInterface); it != interfaces.end()) {
        adoptDevice(path, it->second);
        ensureObjectProxy(path);
        if (auto battIt = interfaces.find(k_batteryInterface); battIt != interfaces.end()) {
          if (auto* dev = self.findDevice(path)) {
            mergeBatteryProps(battIt->second, *dev);
          }
        }
      }
    }
  }

  sdbus::IProxy* deviceProxy(const std::string& path) {
    auto it = objectProxies.find(path);
    if (it != objectProxies.end()) {
      return it->second.get();
    }
    return ensureObjectProxy(path);
  }
};

BluetoothService::BluetoothService(SystemBus& bus) : m_impl(std::make_unique<Impl>(*this, bus)) {
  m_impl->root = sdbus::createProxy(bus.connection(), k_bluezBusName, k_rootPath);

  m_impl->root->uponSignal("InterfacesAdded")
      .onInterface(k_objectManagerInterface)
      .call([this](const sdbus::ObjectPath& path, const ObjectInterfaces& interfaces) {
        m_impl->onInterfacesAdded(path, interfaces);
      });
  m_impl->root->uponSignal("InterfacesRemoved")
      .onInterface(k_objectManagerInterface)
      .call([this](const sdbus::ObjectPath& path, const std::vector<std::string>& interfaces) {
        m_impl->onInterfacesRemoved(path, interfaces);
      });

  refresh();
}

BluetoothService::~BluetoothService() = default;

void BluetoothService::setStateCallback(StateCallback callback) { m_stateCallback = std::move(callback); }
void BluetoothService::setDevicesCallback(DevicesCallback callback) { m_devicesCallback = std::move(callback); }

void BluetoothService::refresh() {
  if (m_impl == nullptr || m_impl->root == nullptr) {
    return;
  }
  try {
    ManagedObjects objects;
    m_impl->root->callMethod("GetManagedObjects").onInterface(k_objectManagerInterface).storeResultsTo(objects);
    const BluetoothState previous = m_state;
    m_devices.clear();
    m_state = BluetoothState{};
    m_impl->adapterPath.clear();
    m_impl->adapter.reset();
    m_impl->seedFromManagedObjects(objects);
    const BluetoothStateChangeOrigin origin = previous.powered != m_state.powered
                                                  ? consumePoweredChangeOrigin(m_state.powered)
                                                  : BluetoothStateChangeOrigin::External;
    emitState(origin);
    emitDevices();
  } catch (const sdbus::Error& e) {
    kLog.debug("GetManagedObjects failed: {}", e.what());
  }
}

void BluetoothService::setPowered(bool enabled) {
  if (m_impl->adapter == nullptr) {
    return;
  }
  if (enabled != m_state.powered) {
    m_pendingLocalPowered = enabled;
  }
  try {
    if (!enabled && m_state.discovering) {
      try {
        m_impl->adapter->callMethod("StopDiscovery").onInterface(k_adapterInterface);
      } catch (const sdbus::Error&) {
      }
    }
    m_impl->adapter->setProperty("Powered").onInterface(k_adapterInterface).toValue(enabled);
  } catch (const sdbus::Error& e) {
    if (m_pendingLocalPowered == enabled) {
      m_pendingLocalPowered.reset();
    }
    kLog.warn("setPowered failed: {}", e.what());
  }
}

void BluetoothService::setDiscoverable(bool enabled) {
  if (m_impl->adapter == nullptr) {
    return;
  }
  try {
    m_impl->adapter->setProperty("Discoverable").onInterface(k_adapterInterface).toValue(enabled);
  } catch (const sdbus::Error& e) {
    kLog.warn("setDiscoverable failed: {}", e.what());
  }
}

void BluetoothService::setPairable(bool enabled) {
  if (m_impl->adapter == nullptr) {
    return;
  }
  try {
    m_impl->adapter->setProperty("Pairable").onInterface(k_adapterInterface).toValue(enabled);
  } catch (const sdbus::Error& e) {
    kLog.warn("setPairable failed: {}", e.what());
  }
}

void BluetoothService::startDiscovery() {
  if (m_impl->adapter == nullptr) {
    return;
  }
  try {
    m_impl->adapter->callMethod("StartDiscovery").onInterface(k_adapterInterface);
  } catch (const sdbus::Error& e) {
    kLog.warn("StartDiscovery failed: {}", e.what());
  }
}

void BluetoothService::stopDiscovery() {
  if (m_impl->adapter == nullptr) {
    return;
  }
  try {
    m_impl->adapter->callMethod("StopDiscovery").onInterface(k_adapterInterface);
  } catch (const sdbus::Error& e) {
    kLog.debug("StopDiscovery failed: {}", e.what());
  }
}

bool BluetoothService::connect(const std::string& devicePath) {
  auto* proxy = m_impl->deviceProxy(devicePath);
  if (proxy == nullptr) {
    return false;
  }
  if (auto* dev = findDevice(devicePath)) {
    dev->connecting = true;
    emitDevices();
  }
  try {
    proxy->callMethod("Connect").onInterface(k_deviceInterface);
    return true;
  } catch (const sdbus::Error& e) {
    kLog.warn("Device.Connect failed {}: {}", devicePath, e.what());
    if (auto* dev = findDevice(devicePath)) {
      dev->connecting = false;
      emitDevices();
    }
    return false;
  }
}

bool BluetoothService::disconnectDevice(const std::string& devicePath) {
  auto* proxy = m_impl->deviceProxy(devicePath);
  if (proxy == nullptr) {
    return false;
  }
  try {
    proxy->callMethod("Disconnect").onInterface(k_deviceInterface);
    return true;
  } catch (const sdbus::Error& e) {
    kLog.warn("Device.Disconnect failed {}: {}", devicePath, e.what());
    return false;
  }
}

bool BluetoothService::pair(const std::string& devicePath) {
  auto* proxy = m_impl->deviceProxy(devicePath);
  if (proxy == nullptr) {
    return false;
  }
  if (auto* dev = findDevice(devicePath)) {
    dev->connecting = true;
    emitDevices();
  }
  try {
    proxy->callMethod("Pair").onInterface(k_deviceInterface);
    return true;
  } catch (const sdbus::Error& e) {
    kLog.warn("Device.Pair failed {}: {}", devicePath, e.what());
    if (auto* dev = findDevice(devicePath)) {
      dev->connecting = false;
      emitDevices();
    }
    return false;
  }
}

bool BluetoothService::cancelPair(const std::string& devicePath) {
  auto* proxy = m_impl->deviceProxy(devicePath);
  if (proxy == nullptr) {
    return false;
  }
  try {
    proxy->callMethod("CancelPairing").onInterface(k_deviceInterface);
    return true;
  } catch (const sdbus::Error& e) {
    kLog.debug("CancelPairing failed {}: {}", devicePath, e.what());
    return false;
  }
}

void BluetoothService::setTrusted(const std::string& devicePath, bool trusted) {
  auto* proxy = m_impl->deviceProxy(devicePath);
  if (proxy == nullptr) {
    return;
  }
  try {
    proxy->setProperty("Trusted").onInterface(k_deviceInterface).toValue(trusted);
  } catch (const sdbus::Error& e) {
    kLog.warn("setTrusted failed {}: {}", devicePath, e.what());
  }
}

void BluetoothService::forget(const std::string& devicePath) {
  if (m_impl->adapter == nullptr) {
    return;
  }
  try {
    m_impl->adapter->callMethod("RemoveDevice")
        .onInterface(k_adapterInterface)
        .withArguments(sdbus::ObjectPath{devicePath});
  } catch (const sdbus::Error& e) {
    kLog.warn("RemoveDevice failed {}: {}", devicePath, e.what());
  }
}

BluetoothDeviceInfo* BluetoothService::findDevice(const std::string& path) {
  auto it =
      std::find_if(m_devices.begin(), m_devices.end(), [&](const BluetoothDeviceInfo& d) { return d.path == path; });
  return it == m_devices.end() ? nullptr : &*it;
}

BluetoothStateChangeOrigin BluetoothService::consumePoweredChangeOrigin(bool powered) {
  if (!m_pendingLocalPowered.has_value()) {
    return BluetoothStateChangeOrigin::External;
  }
  const bool matchesLocalRequest = *m_pendingLocalPowered == powered;
  m_pendingLocalPowered.reset();
  return matchesLocalRequest ? BluetoothStateChangeOrigin::Noctalia : BluetoothStateChangeOrigin::External;
}

void BluetoothService::emitState(BluetoothStateChangeOrigin origin) {
  if (m_stateCallback) {
    m_stateCallback(m_state, origin);
  }
}

void BluetoothService::emitDevices() {
  if (m_devicesCallback) {
    m_devicesCallback(m_devices);
  }
}
