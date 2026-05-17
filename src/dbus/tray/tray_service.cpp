#include "dbus/tray/tray_service.h"

#include "core/deferred_call.h"
#include "core/log.h"
#include "dbus/session_bus.h"
#include "util/string_utils.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <optional>
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
  static constexpr auto k_ayatana_item_path = "/org/ayatana/NotificationItem";

  bool isStatusNotifierItemBusName(std::string_view value) {
    // Different implementations use different bus-name prefixes for SNI items.
    return value.starts_with("org.kde.StatusNotifierItem-") ||
           value.starts_with("org.freedesktop.StatusNotifierItem-") ||
           value.starts_with("org.ayatana.StatusNotifierItem-");
  }

  bool starts_with_slash(std::string_view value) { return !value.empty() && value.front() == '/'; }

  bool looks_like_dbus_name(std::string_view value) { return !value.empty() && value != "__path_only__"; }

  bool isGenericProcessName(std::string_view value) {
    if (value.empty()) {
      return true;
    }
    const auto lower = StringUtils::toLower(value);
    return lower == "electron" || lower == "xdg-dbus-proxy";
  }

  std::string basenameFromPath(std::string value) {
    if (value.empty()) {
      return {};
    }
    if (const auto slash = value.find_last_of('/'); slash != std::string::npos && slash + 1 < value.size()) {
      value = value.substr(slash + 1);
    }
    return value;
  }

  std::string processNameForPid(std::uint32_t pid) {
    if (pid == 0) {
      return {};
    }

    const std::filesystem::path procDir = std::filesystem::path("/proc") / std::to_string(pid);
    std::string argv0;
    {
      std::ifstream cmdline(procDir / "cmdline", std::ios::binary);
      std::getline(cmdline, argv0, '\0');
      argv0 = basenameFromPath(StringUtils::trim(argv0));
    }

    std::error_code ec;
    const auto exe = std::filesystem::read_symlink(procDir / "exe", ec);
    if (!ec && !exe.empty()) {
      auto exeName = exe.filename().string();
      if (!isGenericProcessName(exeName) || argv0.empty()) {
        return exeName;
      }
      return argv0;
    }

    std::ifstream comm(procDir / "comm");
    std::string name;
    if (std::getline(comm, name)) {
      return StringUtils::trim(name);
    }
    return {};
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
      value = StringUtils::toLower(value);
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

  template <typename T> T get_property_or(sdbus::IProxy& proxy, std::string_view property_name, T fallback) {
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
  using StatusNotifierTextTuple = std::tuple<std::string, std::vector<IconPixmapTuple>, std::string, std::string>;
  using StatusNotifierTextStruct = sdbus::Struct<std::string, std::vector<IconPixmapStruct>, std::string, std::string>;
  using DbusMenuLayout =
      sdbus::Struct<std::int32_t, std::map<std::string, sdbus::Variant>, std::vector<sdbus::Variant>>;
  using DbusMenuItemProperties = sdbus::Struct<std::int32_t, std::map<std::string, sdbus::Variant>>;

  std::optional<std::string> stringFromVariant(const sdbus::Variant& value) {
    try {
      return value.get<std::string>();
    } catch (const sdbus::Error&) {
    }
    return std::nullopt;
  }

  std::optional<bool> boolFromVariant(const sdbus::Variant& value) {
    try {
      return value.get<bool>();
    } catch (const sdbus::Error&) {
    }
    return std::nullopt;
  }

  std::optional<std::int32_t> int32FromVariant(const sdbus::Variant& value) {
    try {
      return value.get<std::int32_t>();
    } catch (const sdbus::Error&) {
    }
    try {
      return static_cast<std::int32_t>(value.get<std::uint32_t>());
    } catch (const sdbus::Error&) {
    }
    return std::nullopt;
  }

  bool hasInt32ChildrenInVariant(const sdbus::Variant& value) {
    if (value.containsValueOfType<std::vector<std::int32_t>>()) {
      return !value.get<std::vector<std::int32_t>>().empty();
    }
    if (value.containsValueOfType<std::vector<std::uint32_t>>()) {
      return !value.get<std::vector<std::uint32_t>>().empty();
    }
    if (value.containsValueOfType<std::vector<sdbus::Variant>>()) {
      return !value.get<std::vector<sdbus::Variant>>().empty();
    }
    return false;
  }

  std::vector<std::uint8_t> bytesFromVariant(const sdbus::Variant& value) {
    try {
      return value.get<std::vector<std::uint8_t>>();
    } catch (const sdbus::Error&) {
    }
    return {};
  }

  void resetMenuEntryProperty(TrayMenuEntry& out, std::string_view property) {
    if (property == "label") {
      out.label.clear();
    } else if (property == "icon-name") {
      out.iconName.clear();
    } else if (property == "icon-data") {
      out.iconData.clear();
    } else if (property == "enabled") {
      out.enabled = true;
    } else if (property == "visible") {
      out.visible = true;
    } else if (property == "type") {
      out.separator = false;
    } else if (property == "children-display") {
      out.hasSubmenu = false;
    } else if (property == "toggle-type") {
      out.checkmark = false;
      out.radio = false;
    } else if (property == "toggle-state") {
      out.toggleState = -1;
    }
  }

  bool propertyRemoved(const std::vector<std::string>& removed, std::string_view property) {
    return std::ranges::any_of(removed, [property](const std::string& value) { return value == property; });
  }

  void applyMenuEntryProperties(TrayMenuEntry& out, const std::map<std::string, sdbus::Variant>& props,
                                bool resetMissing = false, const std::vector<std::string>& removed = {}) {
    if (const auto it = props.find("label"); it != props.end()) {
      if (const auto value = stringFromVariant(it->second); value.has_value()) {
        out.label = stripMnemonicUnderscores(*value);
      }
    } else if (resetMissing || propertyRemoved(removed, "label")) {
      resetMenuEntryProperty(out, "label");
    }

    if (const auto it = props.find("icon-name"); it != props.end()) {
      if (const auto value = stringFromVariant(it->second); value.has_value()) {
        out.iconName = *value;
      }
    } else if (resetMissing || propertyRemoved(removed, "icon-name")) {
      resetMenuEntryProperty(out, "icon-name");
    }

    if (const auto it = props.find("icon-data"); it != props.end()) {
      out.iconData = bytesFromVariant(it->second);
    } else if (resetMissing || propertyRemoved(removed, "icon-data")) {
      resetMenuEntryProperty(out, "icon-data");
    }

    if (const auto it = props.find("enabled"); it != props.end()) {
      if (const auto value = boolFromVariant(it->second); value.has_value()) {
        out.enabled = *value;
      }
    } else if (resetMissing || propertyRemoved(removed, "enabled")) {
      resetMenuEntryProperty(out, "enabled");
    }

    if (const auto it = props.find("visible"); it != props.end()) {
      if (const auto value = boolFromVariant(it->second); value.has_value()) {
        out.visible = *value;
      }
    } else if (resetMissing || propertyRemoved(removed, "visible")) {
      resetMenuEntryProperty(out, "visible");
    }

    if (const auto it = props.find("type"); it != props.end()) {
      if (const auto value = stringFromVariant(it->second); value.has_value()) {
        out.separator = (*value == "separator");
      }
    } else if (resetMissing || propertyRemoved(removed, "type")) {
      resetMenuEntryProperty(out, "type");
    }

    if (const auto it = props.find("children-display"); it != props.end()) {
      if (const auto value = stringFromVariant(it->second); value.has_value()) {
        out.hasSubmenu = (*value == "submenu");
      }
    } else if (resetMissing || propertyRemoved(removed, "children-display")) {
      resetMenuEntryProperty(out, "children-display");
    }

    // Some providers omit children-display but still populate children ids.
    // Treat a non-empty children vector as submenu-capable to match qs behavior.
    if (const auto it = props.find("children"); it != props.end()) {
      if (hasInt32ChildrenInVariant(it->second)) {
        out.hasSubmenu = true;
      }
    }

    if (const auto it = props.find("toggle-type"); it != props.end()) {
      if (const auto value = stringFromVariant(it->second); value.has_value()) {
        out.checkmark = (*value == "checkmark");
        out.radio = (*value == "radio");
      }
    } else if (resetMissing || propertyRemoved(removed, "toggle-type")) {
      resetMenuEntryProperty(out, "toggle-type");
    }

    if (const auto it = props.find("toggle-state"); it != props.end()) {
      if (const auto value = int32FromVariant(it->second); value.has_value()) {
        out.toggleState = *value;
      }
    } else if (resetMissing || propertyRemoved(removed, "toggle-state")) {
      resetMenuEntryProperty(out, "toggle-state");
    }
  }

  TrayMenuEntry decodeMenuEntry(const DbusMenuLayout& entryLayout) {
    TrayMenuEntry out;
    out.id = std::get<0>(entryLayout);
    const auto& props = std::get<1>(entryLayout);
    applyMenuEntryProperties(out, props, true);

    return out;
  }

  bool displayableMenuEntry(const TrayMenuEntry& entry) {
    if (entry.id <= 0 || !entry.visible) {
      return false;
    }
    if (entry.label.empty() && !entry.separator && !entry.hasSubmenu && entry.iconName.empty() &&
        entry.iconData.empty()) {
      return false;
    }
    return true;
  }

  const std::vector<std::string>& requestedMenuProperties() {
    // Per dbusmenu protocol, an empty property list means "all available properties".
    static const std::vector<std::string> kRequestedMenuProperties = {};
    return kRequestedMenuProperties;
  }

  std::vector<std::int32_t> int32ListFromVariant(const sdbus::Variant& value) {
    try {
      return value.get<std::vector<std::int32_t>>();
    } catch (const sdbus::Error&) {
    }

    try {
      const auto unsignedValues = value.get<std::vector<std::uint32_t>>();
      std::vector<std::int32_t> out;
      out.reserve(unsignedValues.size());
      for (const auto entry : unsignedValues) {
        out.push_back(static_cast<std::int32_t>(entry));
      }
      return out;
    } catch (const sdbus::Error&) {
    }

    try {
      const auto variants = value.get<std::vector<sdbus::Variant>>();
      std::vector<std::int32_t> out;
      out.reserve(variants.size());
      for (const auto& variant : variants) {
        try {
          out.push_back(variant.get<std::int32_t>());
          continue;
        } catch (const sdbus::Error&) {
        }
        try {
          out.push_back(static_cast<std::int32_t>(variant.get<std::uint32_t>()));
        } catch (const sdbus::Error&) {
        }
      }
      return out;
    } catch (const sdbus::Error&) {
    }

    return {};
  }

  std::vector<std::int32_t> childIdsFromLayoutProperties(const DbusMenuLayout& layout) {
    const auto& props = std::get<1>(layout);
    const auto it = props.find("children");
    if (it == props.end()) {
      return {};
    }
    return int32ListFromVariant(it->second);
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

    try {
      const auto single = value.get<IconPixmapTuple>();
      return {single};
    } catch (const sdbus::Error&) {
    }

    try {
      const auto single = value.get<IconPixmapStruct>();
      return {IconPixmapTuple{std::get<0>(single), std::get<1>(single), std::get<2>(single)}};
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
      proxy.callMethod("GetAll")
          .onInterface("org.freedesktop.DBus.Properties")
          .withArguments(k_item_interface)
          .storeResultsTo(all);
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

  std::pair<std::string, std::string> get_status_notifier_text_or(sdbus::IProxy& proxy, std::string fallbackTitle,
                                                                  std::string fallbackDescription) {
    try {
      const sdbus::Variant value = proxy.getProperty("ToolTip").onInterface(k_item_interface);
      try {
        const auto text = value.get<StatusNotifierTextTuple>();
        return {std::get<2>(text), std::get<3>(text)};
      } catch (const sdbus::Error&) {
      }
      try {
        const auto text = value.get<StatusNotifierTextStruct>();
        return {std::get<2>(text), std::get<3>(text)};
      } catch (const sdbus::Error&) {
      }
    } catch (const sdbus::Error&) {
    }

    return {std::move(fallbackTitle), std::move(fallbackDescription)};
  }

  bool pickBestPixmap(const std::vector<IconPixmapTuple>& pixmaps, std::vector<std::uint8_t>& outArgb,
                      std::int32_t& outW, std::int32_t& outH) {
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

TrayService::TrayService(SessionBus& bus) : m_bus(bus) {}

void TrayService::start() {
  if (m_started) {
    return;
  }

  m_watcherObject = sdbus::createObject(m_bus.connection(), k_watcher_object_path);

  // RegisterStatusNotifierItem needs raw MethodCall access to capture the sender's unique
  // bus name, which lets us skip the O(n) bus-name probe for path-only registrations.
  auto regItem = sdbus::registerMethod("RegisterStatusNotifierItem").withInputParamNames("service");
  regItem.inputSignature = "s"; // must be set explicitly when bypassing implementedAs
  regItem.callbackHandler = [this](sdbus::MethodCall msg) {
    std::string serviceOrPath;
    msg >> serviceOrPath;
    const char* sender = msg.getSender();
    msg.createReply().send();
    DeferredCall::callLater([this, serviceOrPath = std::move(serviceOrPath),
                             senderBusName = std::string(sender != nullptr ? sender : "")]() {
      onRegisterStatusNotifierItem(serviceOrPath, senderBusName);
    });
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
        if (old_owner.empty() && !new_owner.empty() && isStatusNotifierItemBusName(name)) {
          // Some apps miss the re-registration signal race at startup; probing
          // newly-owned SNI bus names keeps tray entries self-healing.
          DeferredCall::callLater([this, name]() { (void)tryRegisterItemForBusName(name); });
        }
        if (!old_owner.empty() && new_owner.empty()) {
          removeItemsForBusName(name);
        }
      });

  kLog.debug("watcher active on {}", std::string(k_watcher_bus_name));
  m_started = true;

  // Tell apps that started before us to re-register. Compliant implementations
  // (libayatana-appindicator, libappindicator) watch for StatusNotifierHostRegistered
  // and call RegisterStatusNotifierItem again when they see it.
  m_watcherObject->emitSignal("StatusNotifierHostRegistered").onInterface(k_watcher_interface);
  DeferredCall::callLater([this]() { discoverExistingItems(); });
  DeferredCall::callLater([this]() { discoverExistingItems(); });
}

TrayService::~TrayService() = default;

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

namespace {

  // Recursively decode a DbusMenuLayout into retained item + child-id maps.
  // Visibility is applied when entries are read for display, not while storing,
  // so later ItemsPropertiesUpdated patches can reveal previously hidden rows.
  void ingestLayoutNode(const DbusMenuLayout& node, std::unordered_map<std::int32_t, TrayMenuEntry>& entriesById,
                        std::unordered_map<std::int32_t, std::vector<std::int32_t>>& childrenByParent) {
    const auto nodeId = std::get<0>(node);
    const auto& children = std::get<2>(node);

    std::vector<std::int32_t> childIds;
    childIds.reserve(children.size());
    for (const auto& childValue : children) {
      try {
        const auto child = childValue.get<DbusMenuLayout>();
        auto entry = decodeMenuEntry(child);
        const auto entryId = entry.id;
        if (entryId > 0) {
          entriesById[entryId] = std::move(entry);
          childIds.push_back(entryId);
        }
        ingestLayoutNode(child, entriesById, childrenByParent);
      } catch (const sdbus::Error&) {
      }
    }
    childrenByParent[nodeId] = std::move(childIds);
  }

  std::vector<TrayMenuEntry>
  entriesForParent(const std::unordered_map<std::int32_t, TrayMenuEntry>& entriesById,
                   const std::unordered_map<std::int32_t, std::vector<std::int32_t>>& childrenByParent,
                   std::int32_t parentId) {
    std::vector<TrayMenuEntry> out;
    const auto childrenIt = childrenByParent.find(parentId);
    if (childrenIt == childrenByParent.end()) {
      return out;
    }

    out.reserve(childrenIt->second.size());
    for (const auto childId : childrenIt->second) {
      const auto entryIt = entriesById.find(childId);
      if (entryIt == entriesById.end() || !displayableMenuEntry(entryIt->second)) {
        continue;
      }
      out.push_back(entryIt->second);
    }
    return out;
  }

} // namespace

bool TrayService::fetchMenuProperties(const std::string& itemId, const std::vector<std::int32_t>& entryIds,
                                      std::vector<TrayMenuEntry>& outEntries) {
  if (entryIds.empty()) {
    return false;
  }

  auto cacheIt = m_menuCache.find(itemId);
  if (cacheIt == m_menuCache.end() || cacheIt->second.proxy == nullptr) {
    return false;
  }
  auto& cache = cacheIt->second;

  try {
    std::vector<DbusMenuItemProperties> properties;
    cache.proxy->callMethod("GetGroupProperties")
        .onInterface(k_menu_interface)
        .withTimeout(std::chrono::milliseconds(1000))
        .withArguments(entryIds, requestedMenuProperties())
        .storeResultsTo(properties);

    std::unordered_map<std::int32_t, std::map<std::string, sdbus::Variant>> propertiesById;
    propertiesById.reserve(properties.size());
    for (const auto& itemProperties : properties) {
      propertiesById.emplace(std::get<0>(itemProperties), std::get<1>(itemProperties));
    }

    outEntries.clear();
    outEntries.reserve(entryIds.size());
    for (const auto entryId : entryIds) {
      TrayMenuEntry entry;
      entry.id = entryId;
      if (const auto propsIt = propertiesById.find(entryId); propsIt != propertiesById.end()) {
        applyMenuEntryProperties(entry, propsIt->second, true);
      }
      cache.entriesById[entryId] = entry;
      if (displayableMenuEntry(entry)) {
        outEntries.push_back(std::move(entry));
      }
    }
    return !outEntries.empty();
  } catch (const sdbus::Error& e) {
    kLog.debug("GetGroupProperties failed id={} entries={} err={}", itemId, entryIds.size(), e.what());
    return false;
  }
}

void TrayService::requestMenuSubtree(const std::string& itemId, std::int32_t parentId, bool force) {
  auto cacheIt = m_menuCache.find(itemId);
  if (cacheIt == m_menuCache.end() || cacheIt->second.proxy == nullptr) {
    return;
  }
  auto& cache = cacheIt->second;

  if (!force && cache.loadedParents.contains(parentId)) {
    return;
  }
  if (cache.loadingParents.contains(parentId)) {
    return;
  }

  const auto now = std::chrono::steady_clock::now();
  if (const auto retryIt = cache.nextRetryAt.find(parentId);
      retryIt != cache.nextRetryAt.end() && now < retryIt->second) {
    return;
  }

  cache.loadingParents.insert(parentId);
  const auto generation = cache.generation;

  // Root menus for some indicators never reply to AboutToShow but still serve GetLayout.
  // Skip AboutToShow at root to avoid NoReply stalls and request storms.
  if (parentId == 0) {
    requestMenuLayoutAfterAboutToShow(itemId, parentId, generation);

    // Run root AboutToShow only once per cache lifetime. Some providers emit
    // repeated LayoutUpdated storms when this is called every open.
    if (!cache.rootAboutToShowPrimed) {
      cache.rootAboutToShowPrimed = true;
      try {
        cache.proxy->callMethodAsync("AboutToShow")
            .onInterface(k_menu_interface)
            .withTimeout(std::chrono::milliseconds(500))
            .withArguments(parentId)
            .uponReplyInvoke(
                [this, itemId, parentId, generation](std::optional<sdbus::Error> error, bool /*needsUpdate*/) {
                  if (error.has_value()) {
                    kLog.debug("root AboutToShow failed id={} parent={} err={}", itemId, parentId, error->what());
                  } else {
                    requestMenuLayoutAfterAboutToShow(itemId, parentId, generation);
                  }
                });
      } catch (const sdbus::Error& e) {
        kLog.debug("root AboutToShow async setup failed id={} parentId={} err={}", itemId, parentId, e.what());
      }
    }
    return;
  }

  try {
    cache.proxy->callMethodAsync("AboutToShow")
        .onInterface(k_menu_interface)
        .withTimeout(std::chrono::milliseconds(500))
        .withArguments(parentId)
        .uponReplyInvoke([this, itemId, parentId, generation](std::optional<sdbus::Error> error, bool /*needsUpdate*/) {
          if (error.has_value()) {
            kLog.debug("AboutToShow failed id={} parent={} err={}", itemId, parentId, error->what());
          }
          requestMenuLayoutAfterAboutToShow(itemId, parentId, generation);
        });
  } catch (const sdbus::Error& e) {
    cache.loadingParents.erase(parentId);
    kLog.debug("AboutToShow async setup failed id={} parentId={} err={}", itemId, parentId, e.what());
  }
}

void TrayService::requestMenuLayoutAfterAboutToShow(const std::string& itemId, std::int32_t parentId,
                                                    std::uint64_t generation) {
  auto cacheIt = m_menuCache.find(itemId);
  if (cacheIt == m_menuCache.end() || cacheIt->second.proxy == nullptr) {
    return;
  }
  auto& cache = cacheIt->second;
  if (cache.generation != generation) {
    return;
  }

  try {
    cache.proxy->callMethodAsync("GetLayout")
        .onInterface(k_menu_interface)
        .withTimeout(std::chrono::milliseconds(2000))
        .withArguments(parentId, static_cast<std::int32_t>(-1), requestedMenuProperties())
        .uponReplyInvoke([this, itemId, parentId, generation](std::optional<sdbus::Error> error, std::uint32_t revision,
                                                              DbusMenuLayout layout) {
          auto replyCacheIt = m_menuCache.find(itemId);
          if (replyCacheIt == m_menuCache.end() || replyCacheIt->second.proxy == nullptr) {
            return;
          }
          auto& replyCache = replyCacheIt->second;
          if (replyCache.generation != generation) {
            return;
          }

          const auto before = entriesForParent(replyCache.entriesById, replyCache.childrenByParent, parentId);
          replyCache.loadingParents.erase(parentId);

          if (error.has_value()) {
            std::uint8_t& streak = replyCache.failureStreak[parentId];
            streak = static_cast<std::uint8_t>(std::min<int>(4, static_cast<int>(streak) + 1));
            const int exponent = std::min<int>(4, static_cast<int>(streak));
            const auto backoff = std::chrono::milliseconds(250 * (1 << exponent));
            replyCache.nextRetryAt[parentId] = std::chrono::steady_clock::now() + backoff;
            kLog.debug("GetLayout failed id={} parent={} err={} streak={} backoffMs={}", itemId, parentId,
                       error->what(), streak, backoff.count());
            return;
          }

          replyCache.failureStreak.erase(parentId);
          replyCache.nextRetryAt.erase(parentId);

          replyCache.revision = revision;
          ingestLayoutNode(layout, replyCache.entriesById, replyCache.childrenByParent);

          const auto layoutRootId = std::get<0>(layout);
          if (layoutRootId != parentId) {
            if (const auto rootChildrenIt = replyCache.childrenByParent.find(layoutRootId);
                rootChildrenIt != replyCache.childrenByParent.end()) {
              replyCache.childrenByParent[parentId] = rootChildrenIt->second;
            }
          }

          auto after = entriesForParent(replyCache.entriesById, replyCache.childrenByParent, parentId);
          if (after.empty()) {
            const auto layoutChildIds = childIdsFromLayoutProperties(layout);
            if (!layoutChildIds.empty()) {
              replyCache.childrenByParent[parentId] = layoutChildIds;
              std::vector<TrayMenuEntry> propertyEntries;
              if (fetchMenuProperties(itemId, layoutChildIds, propertyEntries)) {
                kLog.debug("dbusmenu children-property fallback id={} parentId={} children={} entries={}", itemId,
                           parentId, layoutChildIds.size(), propertyEntries.size());
                after = entriesForParent(replyCache.entriesById, replyCache.childrenByParent, parentId);
              }
            }
          }

          replyCache.loadedParents.insert(parentId);
          if (parentId == 0) {
            replyCache.rootLoaded = true;
          }

          if (before != after) {
            emitChanged();
          }
        });
  } catch (const sdbus::Error& e) {
    cache.loadingParents.erase(parentId);
    kLog.debug("GetLayout async setup failed id={} parentId={} err={}", itemId, parentId, e.what());
  }
}

std::vector<TrayMenuEntry> TrayService::menuEntries(const std::string& itemId) {
  if (!ensureItemProxy(itemId)) {
    kLog.debug("menuEntries: no proxy for id={}", itemId);
    return {};
  }
  const auto itemIt = m_items.find(itemId);
  if (itemIt == m_items.end()) {
    kLog.debug("menuEntries: item not found id={}", itemId);
    return {};
  }
  if (itemIt->second.busName.empty() || itemIt->second.menuObjectPath.empty()) {
    kLog.debug("menuEntries: missing bus/menu path id={} bus='{}' menu='{}'", itemId, itemIt->second.busName,
               itemIt->second.menuObjectPath);
    return {};
  }

  ensureMenuCache(itemId, itemIt->second.busName, itemIt->second.menuObjectPath);
  auto cacheIt = m_menuCache.find(itemId);
  if (cacheIt == m_menuCache.end() || cacheIt->second.proxy == nullptr) {
    return {};
  }

  auto entries = entriesForParent(cacheIt->second.entriesById, cacheIt->second.childrenByParent, 0);

  // If we already have root entries, keep showing them even when a provider
  // emits noisy root invalidations.
  if (!cacheIt->second.rootLoaded && entries.empty()) {
    requestMenuSubtree(itemId, 0);
  }

  if (entries.empty() && !cacheIt->second.loadingParents.contains(0)) {
    requestMenuSubtree(itemId, 0, true);
  }
  return entries;
}

std::vector<TrayMenuEntry> TrayService::menuEntriesForParent(const std::string& itemId, std::int32_t parentId) {
  auto cacheIt = m_menuCache.find(itemId);
  if (cacheIt == m_menuCache.end() || cacheIt->second.proxy == nullptr) {
    // Fall back to opening the root cache path — if a caller asks for a submenu
    // before the root was fetched we have no idea if the parent is valid.
    (void)menuEntries(itemId);
    cacheIt = m_menuCache.find(itemId);
    if (cacheIt == m_menuCache.end() || cacheIt->second.proxy == nullptr) {
      return {};
    }
  }

  auto& cache = cacheIt->second;
  auto entries = entriesForParent(cache.entriesById, cache.childrenByParent, parentId);
  if (!entries.empty()) {
    return entries;
  }

  // Parent's children weren't populated by the recursive root fetch (some apps
  // populate submenus lazily on AboutToShow). Request the subtree and let the
  // tray menu refresh when the async reply arrives.
  if (!cache.loadingParents.contains(parentId)) {
    requestMenuSubtree(itemId, parentId, true);
  }
  return entries;
}

void TrayService::ensureMenuCache(const std::string& itemId, const std::string& busName, const std::string& menuPath) {
  if (busName.empty() || menuPath.empty()) {
    return;
  }
  const auto existing = m_menuCache.find(itemId);
  if (existing != m_menuCache.end() && existing->second.proxy != nullptr) {
    return;
  }

  try {
    auto proxy = sdbus::createProxy(m_bus.connection(), sdbus::ServiceName{busName}, sdbus::ObjectPath{menuPath});

    // LayoutUpdated(rev, parent): server is telling us the subtree rooted at
    // `parent` changed. Invalidate incrementally to avoid feedback loops where
    // providers emit many LayoutUpdated signals while we're already loading.
    proxy->uponSignal("LayoutUpdated")
        .onInterface(k_menu_interface)
        .call([this, itemId](std::uint32_t revision, std::int32_t parent) {
          if (auto it = m_menuCache.find(itemId); it != m_menuCache.end()) {
            auto& cache = it->second;

            if (parent <= 0 && cache.rootLoaded && cache.revision == revision) {
              return;
            }

            if (const auto revIt = cache.lastLayoutUpdatedRevisionByParent.find(parent);
                revIt != cache.lastLayoutUpdatedRevisionByParent.end() && revIt->second == revision) {
              return;
            }
            cache.lastLayoutUpdatedRevisionByParent[parent] = revision;
            cache.revision = revision;

            // While root is loading or not yet established, suppress all
            // layout-updated churn. The in-flight root fetch will converge us.
            if (cache.loadingParents.contains(0) || !cache.rootLoaded) {
              return;
            }

            if (parent <= 0) {
              const bool hadVisibleRootEntries =
                  !entriesForParent(cache.entriesById, cache.childrenByParent, 0).empty();

              // Soft-invalidate root: keep current snapshot visible and let the
              // next normal menu pull refresh it. Avoid force-refresh here,
              // which can cause redraw loops on noisy providers.
              cache.loadedParents.erase(0);
              cache.loadingParents.erase(0);
              cache.nextRetryAt.erase(0);
              cache.failureStreak.erase(0);
              cache.rootLoaded = false;
              // Allow a fresh root AboutToShow after provider-side resets.
              cache.rootAboutToShowPrimed = false;

              if (hadVisibleRootEntries) {
                return;
              }
            } else {
              // Invalidate only the changed subtree parent so we don't discard
              // an otherwise usable root snapshot.
              cache.loadedParents.erase(parent);
              cache.loadingParents.erase(parent);
              cache.nextRetryAt.erase(parent);
              cache.failureStreak.erase(parent);
            }
          }
          emitChanged();
        });

    // ItemsPropertiesUpdated(updated, removed): fine-grained property changes.
    // Patch retained rows in place. This keeps checked/radio/visible state in
    // sync without forcing another GetLayout round-trip for every state change.
    // Signature matches the dbusmenu spec (a(ia{sv}) + a(ias)).
    using PropertiesUpdate = std::vector<sdbus::Struct<std::int32_t, std::map<std::string, sdbus::Variant>>>;
    using PropertiesRemoved = std::vector<sdbus::Struct<std::int32_t, std::vector<std::string>>>;
    proxy->uponSignal("ItemsPropertiesUpdated")
        .onInterface(k_menu_interface)
        .call([this, itemId](const PropertiesUpdate& updated, const PropertiesRemoved& removed) {
          auto it = m_menuCache.find(itemId);
          if (it == m_menuCache.end()) {
            return;
          }

          bool changed = false;
          for (const auto& itemProperties : updated) {
            const auto entryId = std::get<0>(itemProperties);
            if (entryId <= 0) {
              continue;
            }
            auto& entry = it->second.entriesById[entryId];
            if (entry.id == 0) {
              entry.id = entryId;
            }
            const auto before = entry;
            applyMenuEntryProperties(entry, std::get<1>(itemProperties), false);
            changed = changed || before != entry;
          }

          for (const auto& removedProperties : removed) {
            const auto entryId = std::get<0>(removedProperties);
            auto entryIt = it->second.entriesById.find(entryId);
            if (entryIt == it->second.entriesById.end()) {
              continue;
            }
            const auto before = entryIt->second;
            applyMenuEntryProperties(entryIt->second, {}, false, std::get<1>(removedProperties));
            changed = changed || before != entryIt->second;
          }

          if (changed) {
            if (it->second.loadingParents.contains(0) && !it->second.rootLoaded) {
              // During initial root hydration, providers can emit many partial
              // property updates; emitting here causes redraw storms.
              return;
            }
            emitChanged();
          }
        });

    MenuCache cache;
    cache.proxy = std::move(proxy);
    cache.generation = 1;
    m_menuCache[itemId] = std::move(cache);
  } catch (const sdbus::Error& e) {
    kLog.debug("menuCache: failed to create proxy for id={} err={}", itemId, e.what());
  }
}

void TrayService::dropMenuCache(const std::string& itemId) { m_menuCache.erase(itemId); }

void TrayService::sendMenuEvent(const std::string& itemId, std::int32_t entryId, const std::string& eventName) {
  auto it = m_menuCache.find(itemId);
  if (it == m_menuCache.end() || it->second.proxy == nullptr) {
    return;
  }
  const auto timestamp = static_cast<std::uint32_t>(
      std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch()).count());
  try {
    it->second.proxy->callMethodAsync("Event")
        .onInterface(k_menu_interface)
        .withTimeout(std::chrono::milliseconds(500))
        .withArguments(entryId, eventName, sdbus::Variant{std::int32_t{0}}, timestamp)
        .uponReplyInvoke([itemId, entryId, eventName](std::optional<sdbus::Error> error) {
          if (error.has_value()) {
            kLog.debug("dbusmenu Event failed id={} entryId={} event={} err={}", itemId, entryId, eventName,
                       error->what());
          }
        });
  } catch (const sdbus::Error& e) {
    kLog.debug("dbusmenu Event dispatch failed id={} entryId={} event={} err={}", itemId, entryId, eventName, e.what());
  }
}

void TrayService::notifyMenuOpened(const std::string& itemId, std::int32_t entryId) {
  sendMenuEvent(itemId, entryId, "opened");

  // Some dbusmenu providers populate rows only after they observe "opened".
  // Refresh conditionally so right-click on already-hydrated roots does not
  // trigger repeated redraw loops.
  if (const auto itemIt = m_items.find(itemId); itemIt != m_items.end()) {
    ensureMenuCache(itemId, itemIt->second.busName, itemIt->second.menuObjectPath);
    if (entryId == 0) {
      const auto cacheIt = m_menuCache.find(itemId);
      if (cacheIt == m_menuCache.end() || cacheIt->second.proxy == nullptr || !cacheIt->second.rootLoaded ||
          !cacheIt->second.loadedParents.contains(0)) {
        requestMenuSubtree(itemId, 0, false);
      }
    } else {
      requestMenuSubtree(itemId, entryId, true);
    }
  }
}

void TrayService::notifyMenuClosed(const std::string& itemId, std::int32_t entryId) {
  sendMenuEvent(itemId, entryId, "closed");
}

bool TrayService::activateMenuEntry(const std::string& itemId, std::int32_t entryId) {
  auto it = m_menuCache.find(itemId);
  if (it == m_menuCache.end() || it->second.proxy == nullptr) {
    return false;
  }
  const auto timestamp = static_cast<std::uint32_t>(
      std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch()).count());
  try {
    it->second.proxy->callMethodAsync("Event")
        .onInterface(k_menu_interface)
        .withTimeout(std::chrono::milliseconds(1000))
        .withArguments(entryId, std::string("clicked"), sdbus::Variant{std::int32_t{0}}, timestamp)
        .uponReplyInvoke([itemId, entryId](std::optional<sdbus::Error> error) {
          if (error.has_value()) {
            kLog.debug("dbusmenu clicked failed id={} entryId={} err={}", itemId, entryId, error->what());
          }
        });
    // Async call: true means dispatch succeeded locally, not remote activation completion.
    return true;
  } catch (const sdbus::Error& e) {
    kLog.debug("dbusmenu clicked dispatch failed id={} entryId={} err={}", itemId, entryId, e.what());
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
    it->second->callMethodAsync("Activate")
        .onInterface(k_item_interface)
        .withTimeout(std::chrono::milliseconds(1000))
        .withArguments(x, y)
        .uponReplyInvoke([itemId](std::optional<sdbus::Error> error) {
          if (error.has_value()) {
            kLog.debug("activate failed id={} err={}", itemId, error->what());
          }
        });
    return true;
  } catch (const sdbus::Error& e) {
    kLog.debug("activate dispatch failed id={} err={}", itemId, e.what());
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
    it->second->callMethodAsync("ContextMenu")
        .onInterface(k_item_interface)
        .withTimeout(std::chrono::milliseconds(1000))
        .withArguments(x, y)
        .uponReplyInvoke([itemId](std::optional<sdbus::Error> error) {
          if (error.has_value()) {
            kLog.debug("context menu failed id={} err={}", itemId, error->what());
          }
        });
    return true;
  } catch (const sdbus::Error& e) {
    kLog.debug("context menu dispatch failed id={} err={}", itemId, e.what());
    return false;
  }
}

void TrayService::onRegisterStatusNotifierItem(const std::string& serviceOrPath, const std::string& senderBusName) {
  const auto t0 = std::chrono::steady_clock::now();
  if (serviceOrPath.empty()) {
    kLog.debug("register item ignored: empty service/path");
    return;
  }

  std::string busName;
  std::string objectPath;
  bool busOnlyRegistration = false;

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
    } else {
      busOnlyRegistration = true;
    }
  }

  if (busName.empty() || objectPath.empty()) {
    kLog.debug("register item ignored: invalid id ({})", serviceOrPath);
    return;
  }

  if (!hasServiceOwner(busName)) {
    kLog.debug("register item ignored: no DBus owner for bus='{}' service/path='{}'", busName, serviceOrPath);
    return;
  }

  if (busOnlyRegistration) {
    // Match watcher semantics for service-only registrations while tolerating
    // late object-path readiness by probing known paths for a few ticks.
    scheduleBusOnlyRegistrationProbe(busName, 5);
    return;
  }

  registerOrRefreshItem(busName, objectPath);
  const auto elapsedMs =
      std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count();
  kLog.debug("tray register service/path='{}' sender='{}' -> bus='{}' objectPath='{}' elapsed={}ms", serviceOrPath,
             senderBusName, busName, objectPath, elapsedMs);
}

void TrayService::onRegisterStatusNotifierHost(const std::string& host) {
  if (m_hostRegistered) {
    return;
  }
  m_hostRegistered = true;

  kLog.debug("host registered: {}", host);
  m_watcherObject->emitSignal("StatusNotifierHostRegistered").onInterface(k_watcher_interface);
  m_watcherObject->emitPropertiesChangedSignal(
      k_watcher_interface, std::vector<sdbus::PropertyName>{sdbus::PropertyName{"IsStatusNotifierHostRegistered"}});
  emitChanged();
}

void TrayService::discoverExistingItems() {
  std::vector<std::string> names;
  try {
    m_dbusProxy->callMethod("ListNames").onInterface(k_dbus_interface).storeResultsTo(names);
  } catch (const sdbus::Error& e) {
    kLog.debug("tray discover failed: {}", e.what());
    return;
  }

  for (const auto& name : names) {
    if (isStatusNotifierItemBusName(name)) {
      (void)tryRegisterItemForBusName(name);
    }
  }
}

bool TrayService::tryRegisterItemForBusName(const std::string& busName) {
  const auto t0 = std::chrono::steady_clock::now();
  if (!looks_like_dbus_name(busName)) {
    return false;
  }

  const std::array<std::string_view, 2> candidatePaths = {k_default_item_path, k_ayatana_item_path};
  bool registeredAny = false;
  for (const auto candidatePath : candidatePaths) {
    const auto probeStart = std::chrono::steady_clock::now();
    try {
      auto probe = sdbus::createProxy(m_bus.connection(), sdbus::ServiceName{busName},
                                      sdbus::ObjectPath{std::string(candidatePath)});
      std::map<std::string, sdbus::Variant> props;
      probe->callMethod("GetAll")
          .onInterface("org.freedesktop.DBus.Properties")
          .withTimeout(std::chrono::milliseconds(200))
          .withArguments(k_item_interface)
          .storeResultsTo(props);
      registerOrRefreshItem(busName, std::string(candidatePath));
      registeredAny = true;
    } catch (const sdbus::Error&) {
      const auto probeElapsed =
          std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - probeStart).count();
      kLog.debug("tray probe failed bus='{}' path='{}' elapsed={}ms", busName, candidatePath, probeElapsed);
    }
  }

  if (registeredAny) {
    emitChanged();
  } else {
    const auto elapsedMs =
        std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - t0).count();
    kLog.debug("tray probe exhausted bus='{}' elapsed={}ms", busName, elapsedMs);
  }
  return registeredAny;
}

void TrayService::scheduleBusOnlyRegistrationProbe(const std::string& busName, int retriesRemaining) {
  if (retriesRemaining <= 0 || busName.empty()) {
    return;
  }
  DeferredCall::callLater([this, busName, retriesRemaining]() {
    if (!tryRegisterItemForBusName(busName)) {
      scheduleBusOnlyRegistrationProbe(busName, retriesRemaining - 1);
    }
  });
}

void TrayService::scheduleMetadataRefreshRetry(const std::string& itemId, int retriesRemaining) {
  if (retriesRemaining <= 0 || itemId.empty()) {
    return;
  }

  DeferredCall::callLater([this, itemId, retriesRemaining]() {
    auto it = m_items.find(itemId);
    if (it == m_items.end()) {
      return;
    }
    refreshItemMetadata(itemId);
    it = m_items.find(itemId);
    if (it == m_items.end()) {
      return;
    }
    if (!isMetadataReady(it->second)) {
      scheduleMetadataRefreshRetry(itemId, retriesRemaining - 1);
    }
  });
}

bool TrayService::isMetadataReady(const TrayItemInfo& item) const {
  if (!item.iconName.empty() || !item.attentionIconName.empty() || !item.overlayIconName.empty()) {
    return true;
  }
  if (!item.iconArgb32.empty() || !item.attentionArgb32.empty() || !item.overlayArgb32.empty()) {
    return true;
  }
  if (!item.itemName.empty() || !item.title.empty() || !item.statusNotifierTitle.empty() ||
      !item.statusNotifierDescription.empty()) {
    return true;
  }
  return false;
}

bool TrayService::hasServiceOwner(const std::string& serviceName) const {
  if (serviceName.empty() || m_dbusProxy == nullptr) {
    return false;
  }
  try {
    std::string owner;
    m_dbusProxy->callMethod("GetNameOwner")
        .onInterface(k_dbus_interface)
        .withTimeout(std::chrono::milliseconds(200))
        .withArguments(serviceName)
        .storeResultsTo(owner);
    return !owner.empty();
  } catch (const sdbus::Error&) {
    return false;
  }
}

std::string TrayService::processNameForBusName(const std::string& busName) const {
  if (busName.empty() || m_dbusProxy == nullptr || !looks_like_dbus_name(busName)) {
    return {};
  }

  try {
    std::uint32_t pid = 0;
    m_dbusProxy->callMethod("GetConnectionUnixProcessID")
        .onInterface(k_dbus_interface)
        .withTimeout(std::chrono::milliseconds(200))
        .withArguments(busName)
        .storeResultsTo(pid);
    return processNameForPid(pid);
  } catch (const sdbus::Error&) {
    return {};
  }
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

  if (!m_items.contains(itemId)) {
    kLog.debug("tray item registered id={} bus='{}' path='{}'", itemId, busName, objectPath);
    m_items.emplace(itemId, TrayItemInfo{
                                .id = itemId,
                                .busName = busName,
                                .objectPath = objectPath,
                                .iconName = {},
                                .iconThemePath = {},
                                .overlayIconName = {},
                                .attentionIconName = {},
                                .menuObjectPath = {},
                                .itemName = {},
                                .processName = processNameForBusName(busName),
                                .title = {},
                                .statusNotifierTitle = {},
                                .statusNotifierDescription = {},
                                .status = {},
                                .iconArgb32 = {},
                                .iconWidth = 0,
                                .iconHeight = 0,
                                .overlayArgb32 = {},
                                .overlayWidth = 0,
                                .overlayHeight = 0,
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
      proxyIt->second->uponSignal("NewOverlayIcon").onInterface(k_item_interface).call([this, itemId]() {
        refreshItemMetadata(itemId);
      });
      proxyIt->second->uponSignal("NewToolTip").onInterface(k_item_interface).call([this, itemId]() {
        refreshItemMetadata(itemId);
      });
      proxyIt->second->uponSignal("NewStatus")
          .onInterface(k_item_interface)
          .call([this, itemId](const std::string& /*status*/) { refreshItemMetadata(itemId); });
      proxyIt->second->uponSignal("NewTitle")
          .onInterface(k_item_interface)
          .call([this, itemId](const std::string& /*title*/) { refreshItemMetadata(itemId); });
      proxyIt->second->uponSignal("PropertiesChanged")
          .onInterface("org.freedesktop.DBus.Properties")
          .call([this, itemId](const std::string& iface, const std::map<std::string, sdbus::Variant>& /*changed*/,
                               const std::vector<std::string>& /*invalidated*/) {
            if (iface == k_item_interface) {
              refreshItemMetadata(itemId);
            }
          });
    }

    m_watcherObject->emitSignal("StatusNotifierItemRegistered").onInterface(k_watcher_interface).withArguments(itemId);
    m_watcherObject->emitPropertiesChangedSignal(
        k_watcher_interface, std::vector<sdbus::PropertyName>{sdbus::PropertyName{"RegisteredStatusNotifierItems"}});
  }

  if (looks_like_dbus_name(busName)) {
    DeferredCall::callLater([this, itemId]() { refreshItemMetadata(itemId); });
    scheduleMetadataRefreshRetry(itemId, 4);
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
    kLog.debug("lazy path-only resolve failed to list dbus names path={} err={}", itemIt->second.objectPath, e.what());
    return false;
  }

  const auto hints = path_name_hints(itemIt->second.objectPath);

  // Path-only fallback probing is synchronous; keep it tightly bounded to avoid
  // long compositor stalls when many bus names are present.
  constexpr std::size_t kMaxProbeAttempts = 16;
  constexpr auto kProbeTimeout = std::chrono::milliseconds(80);
  std::size_t probeAttempts = 0;

  auto tryCandidate = [&](const std::string& candidate) -> bool {
    if (probeAttempts >= kMaxProbeAttempts) {
      return false;
    }
    ++probeAttempts;

    if (!looks_like_dbus_name(candidate)) {
      return false;
    }
    try {
      auto probe = sdbus::createProxy(m_bus.connection(), sdbus::ServiceName{candidate},
                                      sdbus::ObjectPath{itemIt->second.objectPath});
      std::map<std::string, sdbus::Variant> props;
      probe->callMethod("GetAll")
          .onInterface("org.freedesktop.DBus.Properties")
          .withTimeout(kProbeTimeout)
          .withArguments(k_item_interface)
          .storeResultsTo(props);

      auto& item = m_items[itemId];
      item.busName = candidate;
      auto [proxyIt, _] =
          m_itemProxies.emplace(itemId, sdbus::createProxy(m_bus.connection(), sdbus::ServiceName{candidate},
                                                           sdbus::ObjectPath{item.objectPath}));

      proxyIt->second->uponSignal("NewIcon").onInterface(k_item_interface).call([this, itemId]() {
        refreshItemMetadata(itemId);
      });
      proxyIt->second->uponSignal("NewAttentionIcon").onInterface(k_item_interface).call([this, itemId]() {
        refreshItemMetadata(itemId);
      });
      proxyIt->second->uponSignal("NewOverlayIcon").onInterface(k_item_interface).call([this, itemId]() {
        refreshItemMetadata(itemId);
      });
      proxyIt->second->uponSignal("NewToolTip").onInterface(k_item_interface).call([this, itemId]() {
        refreshItemMetadata(itemId);
      });
      proxyIt->second->uponSignal("NewStatus")
          .onInterface(k_item_interface)
          .call([this, itemId](const std::string& /*status*/) { refreshItemMetadata(itemId); });
      proxyIt->second->uponSignal("NewTitle")
          .onInterface(k_item_interface)
          .call([this, itemId](const std::string& /*title*/) { refreshItemMetadata(itemId); });
      proxyIt->second->uponSignal("PropertiesChanged")
          .onInterface("org.freedesktop.DBus.Properties")
          .call([this, itemId](const std::string& iface, const std::map<std::string, sdbus::Variant>& /*changed*/,
                               const std::vector<std::string>& /*invalidated*/) {
            if (iface == k_item_interface) {
              refreshItemMetadata(itemId);
            }
          });

      refreshItemMetadata(itemId);
      return true;
    } catch (const sdbus::Error&) {
      return false;
    }
  };

  for (const auto& hint : hints) {
    if (probeAttempts >= kMaxProbeAttempts) {
      break;
    }
    for (const auto& candidate : names) {
      if (probeAttempts >= kMaxProbeAttempts) {
        break;
      }
      if (StringUtils::toLower(candidate).find(hint) != std::string::npos && tryCandidate(candidate)) {
        return true;
      }
    }
  }

  // Fallback: only probe unique names (":1.xxx"). Well-known names may trigger
  // D-Bus service auto-activation which blocks for hundreds of ms per candidate.
  // Unique names represent currently-running processes and respond immediately.
  for (const auto& candidate : names) {
    if (probeAttempts >= kMaxProbeAttempts) {
      break;
    }
    if (!candidate.empty() && candidate[0] == ':' && tryCandidate(candidate)) {
      return true;
    }
  }

  kLog.debug("could not resolve bus name for path-only tray item path={} probes={}", itemIt->second.objectPath,
             probeAttempts);
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
  next.iconName = get_item_property_string_or(*proxyIt->second, "IconName", cur.iconName);
  next.iconThemePath = get_item_property_string_or(*proxyIt->second, "IconThemePath", cur.iconThemePath);
  next.overlayIconName = get_item_property_string_or(*proxyIt->second, "OverlayIconName", cur.overlayIconName);
  next.attentionIconName = get_item_property_string_or(*proxyIt->second, "AttentionIconName", cur.attentionIconName);
  next.menuObjectPath = get_item_property_string_or(*proxyIt->second, "Menu", cur.menuObjectPath);
  next.itemName = get_item_property_string_or(*proxyIt->second, "Id", cur.itemName);
  next.title = get_item_property_string_or(*proxyIt->second, "Title", cur.title);
  auto [statusNotifierTitle, statusNotifierDescription] =
      get_status_notifier_text_or(*proxyIt->second, cur.statusNotifierTitle, cur.statusNotifierDescription);
  next.statusNotifierTitle = std::move(statusNotifierTitle);
  next.statusNotifierDescription = std::move(statusNotifierDescription);
  next.status = get_item_property_string_or(*proxyIt->second, "Status", cur.status);
  next.needsAttention = (next.status == "NeedsAttention");

  const auto iconPixmaps = get_icon_pixmaps_or(*proxyIt->second, "IconPixmap", {});
  pickBestPixmap(iconPixmaps, next.iconArgb32, next.iconWidth, next.iconHeight);

  const auto overlayPixmaps = get_icon_pixmaps_or(*proxyIt->second, "OverlayIconPixmap", {});
  pickBestPixmap(overlayPixmaps, next.overlayArgb32, next.overlayWidth, next.overlayHeight);

  const auto attentionPixmaps = get_icon_pixmaps_or(*proxyIt->second, "AttentionIconPixmap", {});
  pickBestPixmap(attentionPixmaps, next.attentionArgb32, next.attentionWidth, next.attentionHeight);

  if (next == itemIt->second) {
    // Menu path unchanged — make sure the cache/subscription exists (may not have
    // been set up yet if the Menu property was empty on first registration).
    ensureMenuCache(itemId, next.busName, next.menuObjectPath);
    return;
  }

  // If the menu path changed, drop the cache so it gets recreated against the new endpoint.
  if (next.menuObjectPath != itemIt->second.menuObjectPath) {
    dropMenuCache(itemId);
  }

  itemIt->second = std::move(next);
  kLog.debug("tray metadata updated id={} status={} itemName='{}' title='{}' sniTitle='{}' icon='{}' overlay='{}' "
             "attention='{}' pixmap={}x{} overlay={}x{} attention={}x{}",
             itemId, itemIt->second.status, itemIt->second.itemName, itemIt->second.title,
             itemIt->second.statusNotifierTitle, itemIt->second.iconName, itemIt->second.overlayIconName,
             itemIt->second.attentionIconName, itemIt->second.iconWidth, itemIt->second.iconHeight,
             itemIt->second.overlayWidth, itemIt->second.overlayHeight, itemIt->second.attentionWidth,
             itemIt->second.attentionHeight);
  ensureMenuCache(itemId, itemIt->second.busName, itemIt->second.menuObjectPath);
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
    m_menuCache.erase(itemId);
    kLog.debug("item unregistered: {}", itemId);
    m_watcherObject->emitSignal("StatusNotifierItemUnregistered")
        .onInterface(k_watcher_interface)
        .withArguments(itemId);
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
