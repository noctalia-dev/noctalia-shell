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
static constexpr auto k_default_item_path = "/StatusNotifierItem";

bool starts_with_slash(std::string_view value) { return !value.empty() && value.front() == '/'; }

template <typename T>
T get_property_or(sdbus::IProxy& proxy, std::string_view property_name, T fallback) {
  try {
    const sdbus::Variant value = proxy.getProperty(property_name).onInterface(k_item_interface);
    return value.get<T>();
  } catch (const sdbus::Error&) {
    return fallback;
  }
}

using IconPixmapTuple = std::tuple<std::int32_t, std::int32_t, std::vector<std::uint8_t>>;
using IconPixmapStruct = sdbus::Struct<std::int32_t, std::int32_t, std::vector<std::uint8_t>>;

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

} // namespace

TrayService::TrayService(SessionBus& bus) : m_bus(bus) {
  m_bus.connection().requestName(k_watcher_bus_name);

  m_watcherObject = sdbus::createObject(m_bus.connection(), k_watcher_object_path);
  m_watcherObject
      ->addVTable(
          sdbus::registerMethod("RegisterStatusNotifierItem")
              .withInputParamNames("service")
              .implementedAs([this](const std::string& serviceOrPath) {
                onRegisterStatusNotifierItem(serviceOrPath);
              }),

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

  m_dbusProxy = sdbus::createProxy(m_bus.connection(), k_dbus_name, k_dbus_path);
  m_dbusProxy->uponSignal("NameOwnerChanged")
      .onInterface(k_dbus_interface)
      .call([this](const std::string& name, const std::string& old_owner, const std::string& new_owner) {
        if (!old_owner.empty() && new_owner.empty()) {
          removeItemsForBusName(name);
        }
      });

  logInfo("tray watcher active on {}", std::string(k_watcher_bus_name));
}

void TrayService::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

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

std::vector<std::string> TrayService::registeredItems() const {
  std::vector<std::string> items;
  items.reserve(m_items.size());
  for (const auto& [id, _] : m_items) {
    items.push_back(id);
  }
  std::ranges::sort(items);
  return items;
}

bool TrayService::activateItem(const std::string& itemId, std::int32_t x, std::int32_t y) const {
  const auto it = m_itemProxies.find(itemId);
  if (it == m_itemProxies.end()) {
    return false;
  }

  try {
    it->second->callMethod("Activate").onInterface(k_item_interface).withArguments(x, y);
    return true;
  } catch (const sdbus::Error& e) {
    logInfo("tray activate failed id={} err={}", itemId, e.what());
    return false;
  }
}

bool TrayService::openContextMenu(const std::string& itemId, std::int32_t x, std::int32_t y) const {
  const auto it = m_itemProxies.find(itemId);
  if (it == m_itemProxies.end()) {
    return false;
  }

  try {
    it->second->callMethod("ContextMenu").onInterface(k_item_interface).withArguments(x, y);
    return true;
  } catch (const sdbus::Error& e) {
    logInfo("tray context menu failed id={} err={}", itemId, e.what());
    return false;
  }
}

void TrayService::onRegisterStatusNotifierItem(const std::string& serviceOrPath) {
  if (serviceOrPath.empty()) {
    logWarn("tray register item ignored: empty service/path");
    return;
  }

  std::string busName;
  std::string objectPath;

  if (starts_with_slash(serviceOrPath)) {
    // Fallback for implementations that register with object path only.
    // Without sender info in this sdbus callback API, track as a synthetic item.
    busName = "__path_only__";
    objectPath = serviceOrPath;
  } else {
    busName = serviceOrPath;
    objectPath = k_default_item_path;
    if (const auto slash = serviceOrPath.find('/'); slash != std::string::npos && slash > 0) {
      busName = serviceOrPath.substr(0, slash);
      objectPath = serviceOrPath.substr(slash);
    }
  }

  if (busName.empty() || objectPath.empty()) {
    logWarn("tray register item ignored: invalid id ({})", serviceOrPath);
    return;
  }

  registerOrRefreshItem(busName, objectPath);
}

void TrayService::onRegisterStatusNotifierHost(const std::string& host) {
  if (m_hostRegistered) {
    return;
  }
  m_hostRegistered = true;

  logInfo("tray host registered: {}", host);
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

    logDebug("tray item registered: {}", itemId);
    m_watcherObject->emitSignal("StatusNotifierItemRegistered").onInterface(k_watcher_interface).withArguments(itemId);
    m_watcherObject->emitPropertiesChangedSignal(
      k_watcher_interface,
      std::vector<sdbus::PropertyName>{sdbus::PropertyName{"RegisteredStatusNotifierItems"}});
  }

  refreshItemMetadata(itemId);
}

void TrayService::refreshItemMetadata(const std::string& itemId) {
  const auto itemIt = m_items.find(itemId);
  const auto proxyIt = m_itemProxies.find(itemId);
  if (itemIt == m_items.end() || proxyIt == m_itemProxies.end()) {
    return;
  }

  auto next = itemIt->second;
  next.iconName = get_property_or<std::string>(*proxyIt->second, "IconName", "");
  next.iconThemePath = get_property_or<std::string>(*proxyIt->second, "IconThemePath", "");
  next.attentionIconName = get_property_or<std::string>(*proxyIt->second, "AttentionIconName", "");
  next.title = get_property_or<std::string>(*proxyIt->second, "Title", "");
  next.status = get_property_or<std::string>(*proxyIt->second, "Status", "");
  next.needsAttention = (next.status == "NeedsAttention");

  const auto iconPixmaps = get_icon_pixmaps_or(*proxyIt->second, "IconPixmap", {});
  pickBestPixmap(iconPixmaps, next.iconArgb32, next.iconWidth, next.iconHeight);

  const auto attentionPixmaps = get_icon_pixmaps_or(*proxyIt->second, "AttentionIconPixmap", {});
  pickBestPixmap(attentionPixmaps, next.attentionArgb32, next.attentionWidth, next.attentionHeight);

    logDebug(
      "tray item metadata id={} status={} iconName='{}' attentionIconName='{}' iconThemePath='{}' iconPixmap={}x{} "
      "(bytes={}) attentionPixmap={}x{} (bytes={})",
      itemId, next.status, next.iconName, next.attentionIconName, next.iconThemePath, next.iconWidth,
      next.iconHeight, next.iconArgb32.size(), next.attentionWidth, next.attentionHeight, next.attentionArgb32.size());

  if (next == itemIt->second) {
    return;
  }

  itemIt->second = std::move(next);
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
    logDebug("tray item unregistered: {}", itemId);
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
