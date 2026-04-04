#include "dbus/tray/TrayService.h"

#include "core/Log.h"
#include "dbus/SessionBus.h"

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

  m_watcher_object = sdbus::createObject(m_bus.connection(), k_watcher_object_path);
  m_watcher_object
      ->addVTable(
          sdbus::registerMethod("RegisterStatusNotifierItem")
              .withInputParamNames("service")
              .implementedAs([this](const std::string& service_or_path) {
                onRegisterStatusNotifierItem(service_or_path);
              }),

          sdbus::registerMethod("RegisterStatusNotifierHost")
              .withInputParamNames("service")
              .implementedAs([this](const std::string& host) { onRegisterStatusNotifierHost(host); }),

          sdbus::registerMethod("GetRegisteredItems").withOutputParamNames("items").implementedAs([this]() {
            return registeredItems();
          }),

          sdbus::registerProperty("RegisteredStatusNotifierItems").withGetter([this]() { return registeredItems(); }),
          sdbus::registerProperty("IsStatusNotifierHostRegistered").withGetter([this]() { return m_host_registered; }),
          sdbus::registerProperty("ProtocolVersion").withGetter([]() { return static_cast<std::int32_t>(0); }),

          sdbus::registerSignal("StatusNotifierItemRegistered").withParameters<std::string>("service"),
          sdbus::registerSignal("StatusNotifierItemUnregistered").withParameters<std::string>("service"),
          sdbus::registerSignal("StatusNotifierHostRegistered").withParameters<>())
      .forInterface(k_watcher_interface);

  m_dbus_proxy = sdbus::createProxy(m_bus.connection(), k_dbus_name, k_dbus_path);
  m_dbus_proxy->uponSignal("NameOwnerChanged")
      .onInterface(k_dbus_interface)
      .call([this](const std::string& name, const std::string& old_owner, const std::string& new_owner) {
        if (!old_owner.empty() && new_owner.empty()) {
          removeItemsForBusName(name);
        }
      });

  logInfo("tray watcher active on {}", std::string(k_watcher_bus_name));
}

void TrayService::setChangeCallback(ChangeCallback callback) { m_change_callback = std::move(callback); }

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
  const auto it = m_item_proxies.find(itemId);
  if (it == m_item_proxies.end()) {
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
  const auto it = m_item_proxies.find(itemId);
  if (it == m_item_proxies.end()) {
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

void TrayService::onRegisterStatusNotifierItem(const std::string& service_or_path) {
  if (service_or_path.empty()) {
    logWarn("tray register item ignored: empty service/path");
    return;
  }

  std::string bus_name;
  std::string object_path;

  if (starts_with_slash(service_or_path)) {
    // Fallback for implementations that register with object path only.
    // Without sender info in this sdbus callback API, track as a synthetic item.
    bus_name = "__path_only__";
    object_path = service_or_path;
  } else {
    bus_name = service_or_path;
    object_path = k_default_item_path;
    if (const auto slash = service_or_path.find('/'); slash != std::string::npos && slash > 0) {
      bus_name = service_or_path.substr(0, slash);
      object_path = service_or_path.substr(slash);
    }
  }

  if (bus_name.empty() || object_path.empty()) {
    logWarn("tray register item ignored: invalid id ({})", service_or_path);
    return;
  }

  registerOrRefreshItem(bus_name, object_path);
}

void TrayService::onRegisterStatusNotifierHost(const std::string& host) {
  if (m_host_registered) {
    return;
  }
  m_host_registered = true;

  logInfo("tray host registered: {}", host);
  m_watcher_object->emitSignal("StatusNotifierHostRegistered").onInterface(k_watcher_interface);
  m_watcher_object->emitPropertiesChangedSignal(
      k_watcher_interface, std::vector<sdbus::PropertyName>{sdbus::PropertyName{"IsStatusNotifierHostRegistered"}});
  emitChanged();
}

std::string TrayService::busNameFromItemId(const std::string& item_id) {
  if (item_id.empty()) {
    return {};
  }

  if (starts_with_slash(item_id)) {
    return {};
  }

  const auto slash = item_id.find('/');
  if (slash == std::string::npos) {
    return item_id;
  }
  if (slash == 0) {
    return {};
  }
  return item_id.substr(0, slash);
}

std::string TrayService::canonicalItemId(const std::string& bus_name, const std::string& object_path) {
  return bus_name + object_path;
}

void TrayService::registerOrRefreshItem(const std::string& bus_name, const std::string& object_path) {
  const std::string item_id = canonicalItemId(bus_name, object_path);
  if (item_id.empty()) {
    return;
  }

  const bool inserted = !m_items.contains(item_id);
  if (inserted) {
    m_items.emplace(item_id, TrayItemInfo{
        .id = item_id,
        .busName = bus_name,
        .objectPath = object_path,
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

    auto [proxy_it, _] = m_item_proxies.emplace(
        item_id, sdbus::createProxy(m_bus.connection(), sdbus::ServiceName{bus_name}, sdbus::ObjectPath{object_path}));

    proxy_it->second->uponSignal("NewIcon").onInterface(k_item_interface).call([this, item_id]() {
      refreshItemMetadata(item_id);
    });
    proxy_it->second->uponSignal("NewAttentionIcon").onInterface(k_item_interface).call([this, item_id]() {
      refreshItemMetadata(item_id);
    });
    proxy_it->second->uponSignal("NewStatus")
        .onInterface(k_item_interface)
        .call([this, item_id](const std::string& /*status*/) { refreshItemMetadata(item_id); });
    proxy_it->second->uponSignal("NewTitle")
        .onInterface(k_item_interface)
        .call([this, item_id](const std::string& /*title*/) { refreshItemMetadata(item_id); });

    logInfo("tray item registered: {}", item_id);
    m_watcher_object->emitSignal("StatusNotifierItemRegistered").onInterface(k_watcher_interface).withArguments(item_id);
    m_watcher_object->emitPropertiesChangedSignal(
      k_watcher_interface,
      std::vector<sdbus::PropertyName>{sdbus::PropertyName{"RegisteredStatusNotifierItems"}});
  }

  refreshItemMetadata(item_id);
}

void TrayService::refreshItemMetadata(const std::string& item_id) {
  const auto item_it = m_items.find(item_id);
  const auto proxy_it = m_item_proxies.find(item_id);
  if (item_it == m_items.end() || proxy_it == m_item_proxies.end()) {
    return;
  }

  auto next = item_it->second;
  next.iconName = get_property_or<std::string>(*proxy_it->second, "IconName", "");
  next.iconThemePath = get_property_or<std::string>(*proxy_it->second, "IconThemePath", "");
  next.attentionIconName = get_property_or<std::string>(*proxy_it->second, "AttentionIconName", "");
  next.title = get_property_or<std::string>(*proxy_it->second, "Title", "");
  next.status = get_property_or<std::string>(*proxy_it->second, "Status", "");
  next.needsAttention = (next.status == "NeedsAttention");

  const auto iconPixmaps = get_icon_pixmaps_or(*proxy_it->second, "IconPixmap", {});
  pickBestPixmap(iconPixmaps, next.iconArgb32, next.iconWidth, next.iconHeight);

  const auto attentionPixmaps = get_icon_pixmaps_or(*proxy_it->second, "AttentionIconPixmap", {});
  pickBestPixmap(attentionPixmaps, next.attentionArgb32, next.attentionWidth, next.attentionHeight);

    logInfo(
      "tray item metadata id={} status={} iconName='{}' attentionIconName='{}' iconThemePath='{}' iconPixmap={}x{} "
      "(bytes={}) attentionPixmap={}x{} (bytes={})",
      item_id, next.status, next.iconName, next.attentionIconName, next.iconThemePath, next.iconWidth,
      next.iconHeight, next.iconArgb32.size(), next.attentionWidth, next.attentionHeight, next.attentionArgb32.size());

  if (next == item_it->second) {
    return;
  }

  item_it->second = std::move(next);
  emitChanged();
}

void TrayService::removeItemsForBusName(const std::string& bus_name) {
  std::vector<std::string> removed_ids;
  for (const auto& [id, item] : m_items) {
    if (item.busName == bus_name || busNameFromItemId(id) == bus_name) {
      removed_ids.push_back(id);
    }
  }

  if (removed_ids.empty()) {
    return;
  }

  for (const auto& item_id : removed_ids) {
    m_items.erase(item_id);
    m_item_proxies.erase(item_id);
    logInfo("tray item unregistered: {}", item_id);
    m_watcher_object->emitSignal("StatusNotifierItemUnregistered").onInterface(k_watcher_interface).withArguments(
        item_id);
  }
  m_watcher_object->emitPropertiesChangedSignal(
      k_watcher_interface, std::vector<sdbus::PropertyName>{sdbus::PropertyName{"RegisteredStatusNotifierItems"}});
  emitChanged();
}

void TrayService::emitChanged() {
  if (m_change_callback) {
    m_change_callback();
  }
}
