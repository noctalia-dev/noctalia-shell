#include "dbus/tray/tray_service.h"

#include "core/log.h"
#include "dbus/session_bus.h"

#include <algorithm>
#include <cstdint>
#include <string_view>

namespace {

static const sdbus::ServiceName k_watcher_bus_name{"org.kde.StatusNotifierWatcher"};
static const sdbus::ObjectPath k_watcher_object_path{"/StatusNotifierWatcher"};
static constexpr auto k_watcher_interface = "org.kde.StatusNotifierWatcher";

static const sdbus::ServiceName k_dbus_name{"org.freedesktop.DBus"};
static const sdbus::ObjectPath k_dbus_path{"/org/freedesktop/DBus"};
static constexpr auto k_dbus_interface = "org.freedesktop.DBus";
static constexpr auto k_item_interface = "org.kde.StatusNotifierItem";
static constexpr auto k_menu_interface = "com.canonical.dbusmenu";
static constexpr auto k_default_item_path = "/StatusNotifierItem";

bool starts_with_slash(std::string_view value) { return !value.empty() && value.front() == '/'; }

bool looks_like_dbus_name(std::string_view value) {
  return !value.empty() && value != "__path_only__";
}

std::string lower_copy(std::string_view value) {
  std::string out(value);
  std::ranges::transform(out, out.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return out;
}

std::vector<std::string> path_name_hints(std::string_view objectPath) {
  std::vector<std::string> hints;
  if (objectPath.empty()) {
    return hints;
  }

  auto push = [&hints](std::string value) {
    if (value.empty()) {
      return;
    }
    value = lower_copy(value);
    if (std::ranges::find(hints, value) == hints.end()) {
      hints.push_back(std::move(value));
    }
  };

  std::string tail(objectPath);
  if (const auto slash = tail.find_last_of('/'); slash != std::string::npos && slash + 1 < tail.size()) {
    tail = tail.substr(slash + 1);
  }

  push(tail);

  std::string dashed = tail;
  std::replace(dashed.begin(), dashed.end(), '_', '-');
  push(dashed);

  std::string underscored = tail;
  std::replace(underscored.begin(), underscored.end(), '-', '_');
  push(underscored);

  for (const auto& suffix : {"_client", "-client", ".desktop"}) {
    for (const auto& candidate : std::vector<std::string>{tail, dashed, underscored}) {
      if (candidate.size() > std::char_traits<char>::length(suffix) && candidate.ends_with(suffix)) {
        push(candidate.substr(0, candidate.size() - std::char_traits<char>::length(suffix)));
      }
    }
  }

  return hints;
}

std::string stripMnemonicUnderscores(std::string label) {
  std::string out;
  out.reserve(label.size());
  for (std::size_t i = 0; i < label.size(); ++i) {
    if (label[i] == '_') {
      if (i + 1 < label.size() && label[i + 1] == '_') {
        out.push_back('_');
        ++i;
      }
      continue;
    }
    out.push_back(label[i]);
  }
  return out;
}

template <typename T>
T get_property_or(sdbus::IProxy& proxy, std::string_view property_name, T fallback) {
  try {
    const sdbus::Variant value = proxy.getProperty(property_name).onInterface(k_item_interface);
    return value.get<T>();
  } catch (const sdbus::Error&) {
    return fallback;
  }
}

std::string get_item_property_string_or(sdbus::IProxy& proxy, std::string_view propertyName, std::string fallback) {
  try {
    const sdbus::Variant value = proxy.getProperty(propertyName).onInterface(k_item_interface);
    try {
      return value.get<std::string>();
    } catch (const sdbus::Error&) {
    }
    try {
      return value.get<sdbus::ObjectPath>();
    } catch (const sdbus::Error&) {
    }
  } catch (const sdbus::Error&) {
  }
  return fallback;
}

using IconPixmapTuple = std::tuple<std::int32_t, std::int32_t, std::vector<std::uint8_t>>;
using IconPixmapStruct = sdbus::Struct<std::int32_t, std::int32_t, std::vector<std::uint8_t>>;
using DbusMenuLayout = sdbus::Struct<std::int32_t, std::map<std::string, sdbus::Variant>, std::vector<sdbus::Variant>>;

TrayMenuEntry decodeMenuEntry(const DbusMenuLayout& entryLayout) {
  TrayMenuEntry out;
  out.id = std::get<0>(entryLayout);
  const auto& props = std::get<1>(entryLayout);

  if (const auto it = props.find("label"); it != props.end()) {
    try {
      out.label = stripMnemonicUnderscores(it->second.get<std::string>());
    } catch (const sdbus::Error&) {
    }
  }
  if (const auto it = props.find("enabled"); it != props.end()) {
    try {
      out.enabled = it->second.get<bool>();
    } catch (const sdbus::Error&) {
    }
  }
  if (const auto it = props.find("visible"); it != props.end()) {
    try {
      out.visible = it->second.get<bool>();
    } catch (const sdbus::Error&) {
    }
  }
  if (const auto it = props.find("type"); it != props.end()) {
    try {
      out.separator = (it->second.get<std::string>() == "separator");
    } catch (const sdbus::Error&) {
    }
  }
  if (const auto it = props.find("children-display"); it != props.end()) {
    try {
      out.hasSubmenu = (it->second.get<std::string>() == "submenu");
    } catch (const sdbus::Error&) {
    }
  }

  return out;
}

std::vector<IconPixmapTuple> iconPixmapsFromVariant(const sdbus::Variant& value) {
  try {
    return value.get<std::vector<IconPixmapTuple>>();
  } catch (const sdbus::Error&) {
  }

  try {
    const auto structs = value.get<std::vector<IconPixmapStruct>>();
    std::vector<IconPixmapTuple> out;
    out.reserve(structs.size());
    for (const auto& entry : structs) {
      out.emplace_back(std::get<0>(entry), std::get<1>(entry), std::get<2>(entry));
    }
    return out;
  } catch (const sdbus::Error&) {
  }

  return {};
}

std::vector<IconPixmapTuple> get_icon_pixmaps_or(sdbus::IProxy& proxy, std::string_view property_name,
                                                  const std::vector<IconPixmapTuple>& fallback) {
  try {
    const sdbus::Variant value = proxy.getProperty(property_name).onInterface(k_item_interface);
    const auto decoded = iconPixmapsFromVariant(value);
    if (!decoded.empty()) {
      return decoded;
    }
  } catch (const sdbus::Error&) {
  }

  try {
    std::map<std::string, sdbus::Variant> all;
    proxy.callMethod("GetAll").onInterface("org.freedesktop.DBus.Properties").withArguments(k_item_interface).storeResultsTo(all);
    const auto it = all.find(std::string(property_name));
    if (it != all.end()) {
      const auto decoded = iconPixmapsFromVariant(it->second);
      if (!decoded.empty()) {
        return decoded;
      }
    }
  } catch (const sdbus::Error&) {
  }

  return fallback;
}

bool pickBestPixmap(const std::vector<IconPixmapTuple>& pixmaps, std::vector<std::uint8_t>& outArgb, std::int32_t& outW,
                    std::int32_t& outH) {
  std::size_t bestIndex = static_cast<std::size_t>(-1);
  std::int64_t bestArea = -1;

  for (std::size_t i = 0; i < pixmaps.size(); ++i) {
    const auto& [w, h, data] = pixmaps[i];
    if (w <= 0 || h <= 0 || data.empty()) {
      continue;
    }
    if (static_cast<std::size_t>(w * h * 4) > data.size()) {
      continue;
    }

    const std::int64_t area = static_cast<std::int64_t>(w) * static_cast<std::int64_t>(h);
    if (area > bestArea) {
      bestArea = area;
      bestIndex = i;
    }
  }

  if (bestIndex == static_cast<std::size_t>(-1)) {
    outArgb.clear();
    outW = 0;
    outH = 0;
    return false;
  }

  const auto& [w, h, data] = pixmaps[bestIndex];
  outW = w;
  outH = h;
  outArgb = data;
  return true;
}

constexpr Logger kLog("tray");

} // namespace

TrayService::TrayService(SessionBus& bus) : m_bus(bus) {
  m_watcherObject = sdbus::createObject(m_bus.connection(), k_watcher_object_path);

  // RegisterStatusNotifierItem needs raw MethodCall access to capture the sender's unique
  // bus name, which lets us skip the O(n) bus-name probe for path-only registrations.
  auto regItem = sdbus::registerMethod("RegisterStatusNotifierItem").withInputParamNames("service");
  regItem.inputSignature = "s"; // must be set explicitly when bypassing implementedAs
  regItem.callbackHandler = [this](sdbus::MethodCall msg) {
    std::string serviceOrPath;
    msg >> serviceOrPath;
    const char* sender = msg.getSender();
    onRegisterStatusNotifierItem(serviceOrPath, sender != nullptr ? sender : "");
  };

  m_watcherObject
      ->addVTable(
          std::move(regItem),

          sdbus::registerMethod("RegisterStatusNotifierHost")
              .withInputParamNames("service")
              .implementedAs([this](const std::string& host) { onRegisterStatusNotifierHost(host); }),

          sdbus::registerMethod("GetRegisteredItems").withOutputParamNames("items").implementedAs([this]() {
            return registeredItems();
          }),

          sdbus::registerProperty("RegisteredStatusNotifierItems").withGetter([this]() { return registeredItems(); }),
          sdbus::registerProperty("IsStatusNotifierHostRegistered").withGetter([this]() { return m_hostRegistered; }),
          sdbus::registerProperty("ProtocolVersion").withGetter([]() { return static_cast<std::int32_t>(0); }),

          sdbus::registerSignal("StatusNotifierItemRegistered").withParameters<std::string>("service"),
          sdbus::registerSignal("StatusNotifierItemUnregistered").withParameters<std::string>("service"),
          sdbus::registerSignal("StatusNotifierHostRegistered").withParameters<>())
      .forInterface(k_watcher_interface);

  // Claim the watcher name only after the vtable is fully registered, so any app
  // that reacts to NameOwnerChanged and immediately calls RegisterStatusNotifierItem
  // will find our methods already in place.
  m_bus.connection().requestName(k_watcher_bus_name);

  m_dbusProxy = sdbus::createProxy(m_bus.connection(), k_dbus_name, k_dbus_path);
  m_dbusProxy->uponSignal("NameOwnerChanged")
      .onInterface(k_dbus_interface)
      .call([this](const std::string& name, const std::string& old_owner, const std::string& new_owner) {
        if (!old_owner.empty() && new_owner.empty()) {
          removeItemsForBusName(name);
        }
      });

  kLog.info("watcher active on {}", std::string(k_watcher_bus_name));

  // Tell apps that started before us to re-register. Compliant implementations
  // (libayatana-appindicator, libappindicator) watch for StatusNotifierHostRegistered
  // and call RegisterStatusNotifierItem again when they see it.
  m_watcherObject->emitSignal("StatusNotifierHostRegistered").onInterface(k_watcher_interface);
}

void TrayService::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

void TrayService::setMenuToggleCallback(MenuToggleCallback callback) { m_menuToggleCallback = std::move(callback); }

void TrayService::requestMenuToggle(const std::string& itemId) const {
  if (m_menuToggleCallback) {
    m_menuToggleCallback(itemId);
  }
}

std::size_t TrayService::itemCount() const noexcept { return m_items.size(); }

std::vector<TrayItemInfo> TrayService::items() const {
  std::vector<TrayItemInfo> out;
  out.reserve(m_items.size());
  for (const auto& [_, item] : m_items) {
    out.push_back(item);
  }
  std::ranges::sort(out, [](const TrayItemInfo& a, const TrayItemInfo& b) { return a.id < b.id; });
  return out;
}

std::vector<TrayMenuEntry> TrayService::menuEntries(const std::string& itemId) {
  if (!ensureItemProxy(itemId)) {
    kLog.warn("menuEntries: no proxy for id={}", itemId);
    return {};
  }
  const auto itemIt = m_items.find(itemId);
  if (itemIt == m_items.end()) {
    kLog.warn("menuEntries: item not found id={}", itemId);
    return {};
  }
  if (itemIt->second.busName.empty() || itemIt->second.menuObjectPath.empty()) {
    kLog.warn("menuEntries: missing bus/menu path id={} bus='{}' menu='{}'",
              itemId, itemIt->second.busName, itemIt->second.menuObjectPath);
    return {};
  }

  try {
    auto menuProxy = sdbus::createProxy(m_bus.connection(), sdbus::ServiceName{itemIt->second.busName},
                                        sdbus::ObjectPath{itemIt->second.menuObjectPath});

    // Signal the app to prepare its menu. Some apps (Electron-based) only populate
    // GetLayout after receiving AboutToShow(0). Ignore errors — not all apps implement it.
    try {
      bool needsUpdate = false;
      menuProxy->callMethod("AboutToShow")
          .onInterface(k_menu_interface)
          .withTimeout(std::chrono::milliseconds(500))
          .withArguments(static_cast<std::int32_t>(0))
          .storeResultsTo(needsUpdate);
      (void)needsUpdate;
    } catch (const sdbus::Error& e) {
      kLog.warn("menuEntries: AboutToShow failed id={} err={}", itemId, e.what());
    }

    std::uint32_t revision = 0;
    DbusMenuLayout root{};
    menuProxy->callMethod("GetLayout")
        .onInterface(k_menu_interface)
        .withTimeout(std::chrono::milliseconds(2000))
        .withArguments(static_cast<std::int32_t>(0), static_cast<std::int32_t>(1), std::vector<std::string>{})
        .storeResultsTo(revision, root);
    (void)revision;

    std::vector<TrayMenuEntry> out;
    const auto& children = std::get<2>(root);
    out.reserve(children.size());
    for (const auto& childValue : children) {
      try {
        const auto child = childValue.get<DbusMenuLayout>();
        auto entry = decodeMenuEntry(child);
        if (entry.id <= 0 || !entry.visible) {
          continue;
        }
        if (entry.label.empty() && !entry.separator) {
          continue;
        }
        out.push_back(std::move(entry));
      } catch (const sdbus::Error&) {
      }
    }
    kLog.debug("menuEntries: id={} got {} entries (raw children={})", itemId, out.size(), children.size());
    return out;
  } catch (const sdbus::Error& e) {
    kLog.warn("menuEntries: GetLayout failed id={} menu={} err={}", itemId, itemIt->second.menuObjectPath, e.what());
    // Recreate the LayoutUpdated subscription in case the proxy went stale.
    refreshMenuWatch(itemId);
    return {};
  }
}

std::vector<TrayMenuEntry> TrayService::menuEntriesForParent(const std::string& itemId, std::int32_t parentId) {
  if (!ensureItemProxy(itemId)) {
    return {};
  }
  const auto itemIt = m_items.find(itemId);
  if (itemIt == m_items.end()) {
    return {};
  }
  if (itemIt->second.busName.empty() || itemIt->second.menuObjectPath.empty()) {
    return {};
  }

  try {
    auto menuProxy = sdbus::createProxy(m_bus.connection(), sdbus::ServiceName{itemIt->second.busName},
                                        sdbus::ObjectPath{itemIt->second.menuObjectPath});

    std::uint32_t revision = 0;
    DbusMenuLayout root{};
    menuProxy->callMethod("GetLayout")
        .onInterface(k_menu_interface)
        .withTimeout(std::chrono::milliseconds(2000))
        .withArguments(parentId, static_cast<std::int32_t>(1), std::vector<std::string>{})
        .storeResultsTo(revision, root);
    (void)revision;

    std::vector<TrayMenuEntry> out;
    const auto& children = std::get<2>(root);
    out.reserve(children.size());
    for (const auto& childValue : children) {
      try {
        const auto child = childValue.get<DbusMenuLayout>();
        auto entry = decodeMenuEntry(child);
        if (entry.id <= 0 || !entry.visible) {
          continue;
        }
        if (entry.label.empty() && !entry.separator) {
          continue;
        }
        out.push_back(std::move(entry));
      } catch (const sdbus::Error&) {
      }
    }
    return out;
  } catch (const sdbus::Error& e) {
    kLog.debug("dbusmenu submenu load failed id={} parentId={} err={}", itemId, parentId, e.what());
    return {};
  }
}

void TrayService::subscribeMenuLayoutUpdated(const std::string& itemId, const std::string& busName,
                                              const std::string& menuPath) {
  if (busName.empty() || menuPath.empty()) {
    return;
  }
  // Check if we already have a subscription for the same endpoint — don't recreate it.
  const auto existing = m_menuWatchProxies.find(itemId);
  if (existing != m_menuWatchProxies.end()) {
    return;
  }

  try {
    auto proxy = sdbus::createProxy(m_bus.connection(), sdbus::ServiceName{busName},
                                    sdbus::ObjectPath{menuPath});
    proxy->uponSignal("LayoutUpdated")
        .onInterface(k_menu_interface)
        .call([this, itemId](std::uint32_t /*revision*/, std::int32_t /*parent*/) {
          kLog.info("LayoutUpdated for id={}", itemId);
          emitChanged();
        });
    m_menuWatchProxies[itemId] = std::move(proxy);
    kLog.debug("menuWatch: permanent LayoutUpdated subscription for id={}", itemId);
  } catch (const sdbus::Error& e) {
    kLog.warn("menuWatch: failed to subscribe LayoutUpdated for id={} err={}", itemId, e.what());
  }
}

void TrayService::refreshMenuWatch(const std::string& itemId) {
  m_menuWatchProxies.erase(itemId);
  const auto itemIt = m_items.find(itemId);
  if (itemIt != m_items.end()) {
    subscribeMenuLayoutUpdated(itemId, itemIt->second.busName, itemIt->second.menuObjectPath);
  }
}

bool TrayService::activateMenuEntry(const std::string& itemId, std::int32_t entryId) {
  if (!ensureItemProxy(itemId)) {
    return false;
  }
  const auto itemIt = m_items.find(itemId);
  if (itemIt == m_items.end()) {
    return false;
  }
  if (itemIt->second.busName.empty() || itemIt->second.menuObjectPath.empty()) {
    return false;
  }

  try {
    auto menuProxy = sdbus::createProxy(m_bus.connection(), sdbus::ServiceName{itemIt->second.busName},
                                        sdbus::ObjectPath{itemIt->second.menuObjectPath});
    menuProxy->callMethod("Event")
        .onInterface(k_menu_interface)
        .withArguments(entryId, std::string("clicked"), sdbus::Variant{std::int32_t{0}}, static_cast<std::uint32_t>(0));
    return true;
  } catch (const sdbus::Error& e) {
    kLog.debug("dbusmenu event failed id={} entryId={} err={}", itemId, entryId, e.what());
    return false;
  }
}

std::vector<std::string> TrayService::registeredItems() const {
  std::vector<std::string> items;
  items.reserve(m_items.size());
  for (const auto& [id, _] : m_items) {
    items.push_back(id);
  }
  std::ranges::sort(items);
  return items;
}

bool TrayService::activateItem(const std::string& itemId, std::int32_t x, std::int32_t y) {
  if (!ensureItemProxy(itemId)) {
    return false;
  }
  const auto it = m_itemProxies.find(itemId);
  if (it == m_itemProxies.end()) {
    return false;
  }

  try {
    it->second->callMethod("Activate").onInterface(k_item_interface).withArguments(x, y);
    return true;
  } catch (const sdbus::Error& e) {
    kLog.info("activate failed id={} err={}", itemId, e.what());
    return false;
  }
}

bool TrayService::openContextMenu(const std::string& itemId, std::int32_t x, std::int32_t y) {
  if (!ensureItemProxy(itemId)) {
    return false;
  }
  const auto it = m_itemProxies.find(itemId);
  if (it == m_itemProxies.end()) {
    return false;
  }

  try {
    it->second->callMethod("ContextMenu").onInterface(k_item_interface).withArguments(x, y);
    return true;
  } catch (const sdbus::Error& e) {
    kLog.info("context menu failed id={} err={}", itemId, e.what());
    return false;
  }
}

void TrayService::onRegisterStatusNotifierItem(const std::string& serviceOrPath,
                                               const std::string& senderBusName) {
  kLog.info("RegisterStatusNotifierItem: service/path='{}' sender='{}'", serviceOrPath, senderBusName);
  if (serviceOrPath.empty()) {
    kLog.warn("register item ignored: empty service/path");
    return;
  }

  std::string busName;
  std::string objectPath;

  if (starts_with_slash(serviceOrPath)) {
    // Path-only registration: use the sender's unique bus name directly instead of
    // deferring to lazy probing. The sender is the process that registered the item,
    // so its unique name (:1.xxx) is always correct.
    objectPath = serviceOrPath;
    busName = looks_like_dbus_name(senderBusName) ? senderBusName : "__path_only__";
  } else {
    busName = serviceOrPath;
    objectPath = k_default_item_path;
    if (const auto slash = serviceOrPath.find('/'); slash != std::string::npos && slash > 0) {
      busName = serviceOrPath.substr(0, slash);
      objectPath = serviceOrPath.substr(slash);
    }
  }

  if (busName.empty() || objectPath.empty()) {
    kLog.warn("register item ignored: invalid id ({})", serviceOrPath);
    return;
  }

  registerOrRefreshItem(busName, objectPath);
}

void TrayService::onRegisterStatusNotifierHost(const std::string& host) {
  if (m_hostRegistered) {
    return;
  }
  m_hostRegistered = true;

  kLog.info("host registered: {}", host);
  m_watcherObject->emitSignal("StatusNotifierHostRegistered").onInterface(k_watcher_interface);
  m_watcherObject->emitPropertiesChangedSignal(
      k_watcher_interface, std::vector<sdbus::PropertyName>{sdbus::PropertyName{"IsStatusNotifierHostRegistered"}});
  emitChanged();
}

std::string TrayService::busNameFromItemId(const std::string& itemId) {
  if (itemId.empty()) {
    return {};
  }

  if (starts_with_slash(itemId)) {
    return {};
  }

  const auto slash = itemId.find('/');
  if (slash == std::string::npos) {
    return itemId;
  }
  if (slash == 0) {
    return {};
  }
  return itemId.substr(0, slash);
}

std::string TrayService::canonicalItemId(const std::string& busName, const std::string& objectPath) {
  return busName + objectPath;
}

void TrayService::registerOrRefreshItem(const std::string& busName, const std::string& objectPath) {
  const std::string itemId = canonicalItemId(busName, objectPath);
  if (itemId.empty()) {
    return;
  }

  const bool inserted = !m_items.contains(itemId);
  if (inserted) {
    m_items.emplace(itemId, TrayItemInfo{
        .id = itemId,
        .busName = busName,
        .objectPath = objectPath,
        .iconName = {},
        .iconThemePath = {},
        .attentionIconName = {},
        .menuObjectPath = {},
        .itemName = {},
        .title = {},
        .status = {},
        .iconArgb32 = {},
        .iconWidth = 0,
        .iconHeight = 0,
        .attentionArgb32 = {},
        .attentionWidth = 0,
        .attentionHeight = 0,
        .needsAttention = false,
    });

    if (looks_like_dbus_name(busName)) {
      auto [proxyIt, _] = m_itemProxies.emplace(
          itemId, sdbus::createProxy(m_bus.connection(), sdbus::ServiceName{busName}, sdbus::ObjectPath{objectPath}));

      proxyIt->second->uponSignal("NewIcon").onInterface(k_item_interface).call([this, itemId]() {
        refreshItemMetadata(itemId);
      });
      proxyIt->second->uponSignal("NewAttentionIcon").onInterface(k_item_interface).call([this, itemId]() {
        refreshItemMetadata(itemId);
      });
      proxyIt->second->uponSignal("NewStatus")
          .onInterface(k_item_interface)
          .call([this, itemId](const std::string& /*status*/) { refreshItemMetadata(itemId); });
      proxyIt->second->uponSignal("NewTitle")
          .onInterface(k_item_interface)
          .call([this, itemId](const std::string& /*title*/) { refreshItemMetadata(itemId); });
    }

    kLog.debug("item registered: {}", itemId);
    m_watcherObject->emitSignal("StatusNotifierItemRegistered").onInterface(k_watcher_interface).withArguments(itemId);
    m_watcherObject->emitPropertiesChangedSignal(
      k_watcher_interface,
      std::vector<sdbus::PropertyName>{sdbus::PropertyName{"RegisteredStatusNotifierItems"}});
  }

  if (looks_like_dbus_name(busName)) {
    refreshItemMetadata(itemId);
  }
}

bool TrayService::ensureItemProxy(const std::string& itemId) {
  const auto itemIt = m_items.find(itemId);
  if (itemIt == m_items.end()) {
    return false;
  }

  if (itemIt->second.busName != "__path_only__") {
    return m_itemProxies.contains(itemId);
  }

  std::vector<std::string> names;
  try {
    m_dbusProxy->callMethod("ListNames").onInterface(k_dbus_interface).storeResultsTo(names);
  } catch (const sdbus::Error& e) {
    kLog.warn("lazy path-only resolve failed to list dbus names path={} err={}", itemIt->second.objectPath, e.what());
    return false;
  }

  const auto hints = path_name_hints(itemIt->second.objectPath);

  auto tryCandidate = [&](const std::string& candidate) -> bool {
    if (!looks_like_dbus_name(candidate)) {
      return false;
    }
    try {
      auto probe = sdbus::createProxy(m_bus.connection(), sdbus::ServiceName{candidate},
                                      sdbus::ObjectPath{itemIt->second.objectPath});
      std::map<std::string, sdbus::Variant> props;
      probe->callMethod("GetAll")
          .onInterface("org.freedesktop.DBus.Properties")
          .withTimeout(std::chrono::milliseconds(500))
          .withArguments(k_item_interface)
          .storeResultsTo(props);

      auto& item = m_items[itemId];
      item.busName = candidate;
      auto [proxyIt, _] = m_itemProxies.emplace(
          itemId, sdbus::createProxy(m_bus.connection(), sdbus::ServiceName{candidate},
                                     sdbus::ObjectPath{item.objectPath}));

      proxyIt->second->uponSignal("NewIcon").onInterface(k_item_interface).call([this, itemId]() {
        refreshItemMetadata(itemId);
      });
      proxyIt->second->uponSignal("NewAttentionIcon").onInterface(k_item_interface).call([this, itemId]() {
        refreshItemMetadata(itemId);
      });
      proxyIt->second->uponSignal("NewStatus")
          .onInterface(k_item_interface)
          .call([this, itemId](const std::string& /*status*/) { refreshItemMetadata(itemId); });
      proxyIt->second->uponSignal("NewTitle")
          .onInterface(k_item_interface)
          .call([this, itemId](const std::string& /*title*/) { refreshItemMetadata(itemId); });

      kLog.info("resolved path-only tray item lazily path={} bus={}", item.objectPath, candidate);
      refreshItemMetadata(itemId);
      return true;
    } catch (const sdbus::Error&) {
      return false;
    }
  };

  for (const auto& hint : hints) {
    for (const auto& candidate : names) {
      if (lower_copy(candidate).find(hint) != std::string::npos && tryCandidate(candidate)) {
        return true;
      }
    }
  }

  // Fallback: only probe unique names (":1.xxx"). Well-known names may trigger
  // D-Bus service auto-activation which blocks for hundreds of ms per candidate.
  // Unique names represent currently-running processes and respond immediately.
  for (const auto& candidate : names) {
    if (!candidate.empty() && candidate[0] == ':' && tryCandidate(candidate)) {
      return true;
    }
  }

  kLog.warn("could not resolve bus name for path-only tray item path={}", itemIt->second.objectPath);
  return false;
}

void TrayService::refreshItemMetadata(const std::string& itemId) {
  const auto itemIt = m_items.find(itemId);
  const auto proxyIt = m_itemProxies.find(itemId);
  if (itemIt == m_items.end() || proxyIt == m_itemProxies.end()) {
    return;
  }

  const auto& cur = itemIt->second;
  auto next = cur;
  // Use the existing value as the fallback so a transient D-Bus failure doesn't
  // wipe out data that was successfully fetched earlier (e.g. menuObjectPath).
  next.iconName         = get_item_property_string_or(*proxyIt->second, "IconName",         cur.iconName);
  next.iconThemePath    = get_item_property_string_or(*proxyIt->second, "IconThemePath",    cur.iconThemePath);
  next.attentionIconName= get_item_property_string_or(*proxyIt->second, "AttentionIconName",cur.attentionIconName);
  next.menuObjectPath   = get_item_property_string_or(*proxyIt->second, "Menu",             cur.menuObjectPath);
  next.itemName         = get_item_property_string_or(*proxyIt->second, "Id",               cur.itemName);
  next.title            = get_item_property_string_or(*proxyIt->second, "Title",            cur.title);
  next.status           = get_item_property_string_or(*proxyIt->second, "Status",           cur.status);
  next.needsAttention = (next.status == "NeedsAttention");

  const auto iconPixmaps = get_icon_pixmaps_or(*proxyIt->second, "IconPixmap", {});
  pickBestPixmap(iconPixmaps, next.iconArgb32, next.iconWidth, next.iconHeight);

  const auto attentionPixmaps = get_icon_pixmaps_or(*proxyIt->second, "AttentionIconPixmap", {});
  pickBestPixmap(attentionPixmaps, next.attentionArgb32, next.attentionWidth, next.attentionHeight);

  kLog.debug(
      "item metadata id={} itemName='{}' status={} iconName='{}' attentionIconName='{}' menu='{}' "
      "iconThemePath='{}' iconPixmap={}x{} (bytes={}) attentionPixmap={}x{} (bytes={})",
      itemId, next.itemName, next.status, next.iconName, next.attentionIconName, next.menuObjectPath,
      next.iconThemePath, next.iconWidth, next.iconHeight, next.iconArgb32.size(), next.attentionWidth,
      next.attentionHeight, next.attentionArgb32.size());

  if (next == itemIt->second) {
    // Menu path unchanged — make sure subscription exists (may not have been set up yet
    // if it was empty on first registration and only available now).
    subscribeMenuLayoutUpdated(itemId, next.busName, next.menuObjectPath);
    return;
  }

  // If the menu path changed, tear down the old subscription so the new one gets created.
  if (next.menuObjectPath != itemIt->second.menuObjectPath) {
    m_menuWatchProxies.erase(itemId);
  }

  itemIt->second = std::move(next);
  subscribeMenuLayoutUpdated(itemId, itemIt->second.busName, itemIt->second.menuObjectPath);
  emitChanged();
}

void TrayService::removeItemsForBusName(const std::string& busName) {
  std::vector<std::string> removedIds;
  for (const auto& [id, item] : m_items) {
    if (item.busName == busName || busNameFromItemId(id) == busName) {
      removedIds.push_back(id);
    }
  }

  if (removedIds.empty()) {
    return;
  }

  for (const auto& itemId : removedIds) {
    m_items.erase(itemId);
    m_itemProxies.erase(itemId);
    m_menuWatchProxies.erase(itemId);
    kLog.debug("item unregistered: {}", itemId);
    m_watcherObject->emitSignal("StatusNotifierItemUnregistered").onInterface(k_watcher_interface).withArguments(
        itemId);
  }
  m_watcherObject->emitPropertiesChangedSignal(
      k_watcher_interface, std::vector<sdbus::PropertyName>{sdbus::PropertyName{"RegisteredStatusNotifierItems"}});
  emitChanged();
}

void TrayService::emitChanged() {
  if (m_changeCallback) {
    m_changeCallback();
  }
}
