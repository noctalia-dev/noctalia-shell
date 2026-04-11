#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#include <sdbus-c++/sdbus-c++.h>

class SessionBus;

struct TrayItemInfo {
  std::string id;
  std::string busName;
  std::string objectPath;
  std::string iconName;
  std::string iconThemePath;
  std::string attentionIconName;
  std::string menuObjectPath;
  std::string itemName;
  std::string title;
  std::string status;
  std::vector<std::uint8_t> iconArgb32;
  std::int32_t iconWidth = 0;
  std::int32_t iconHeight = 0;
  std::vector<std::uint8_t> attentionArgb32;
  std::int32_t attentionWidth = 0;
  std::int32_t attentionHeight = 0;
  bool needsAttention = false;

  bool operator==(const TrayItemInfo&) const = default;
};

struct TrayMenuEntry {
  std::int32_t id = 0;
  std::string label;
  bool enabled = true;
  bool visible = true;
  bool separator = false;
  bool hasSubmenu = false;

  bool operator==(const TrayMenuEntry&) const = default;
};

class TrayService {
public:
  using ChangeCallback = std::function<void()>;
  using MenuToggleCallback = std::function<void(const std::string&)>;

  explicit TrayService(SessionBus& bus);

  void setChangeCallback(ChangeCallback callback);
  void setMenuToggleCallback(MenuToggleCallback callback);
  void requestMenuToggle(const std::string& itemId) const;
  [[nodiscard]] std::size_t itemCount() const noexcept;
  [[nodiscard]] std::vector<TrayItemInfo> items() const;
  [[nodiscard]] std::vector<TrayMenuEntry> menuEntries(const std::string& itemId);
  [[nodiscard]] std::vector<TrayMenuEntry> menuEntriesForParent(const std::string& itemId, std::int32_t parentId);
  [[nodiscard]] bool activateMenuEntry(const std::string& itemId, std::int32_t entryId);
  [[nodiscard]] std::vector<std::string> registeredItems() const;
  [[nodiscard]] bool activateItem(const std::string& itemId, std::int32_t x = 0, std::int32_t y = 0);
  [[nodiscard]] bool openContextMenu(const std::string& itemId, std::int32_t x = 0, std::int32_t y = 0);

private:
  void onRegisterStatusNotifierItem(const std::string& serviceOrPath, const std::string& senderBusName);
  void onRegisterStatusNotifierHost(const std::string& host);
  void registerOrRefreshItem(const std::string& busName, const std::string& objectPath);
  void refreshItemMetadata(const std::string& itemId);
  void subscribeMenuLayoutUpdated(const std::string& itemId, const std::string& busName,
                                   const std::string& menuPath);
  void refreshMenuWatch(const std::string& itemId);
  [[nodiscard]] bool ensureItemProxy(const std::string& itemId);
  void removeItemsForBusName(const std::string& busName);
  void emitChanged();

  [[nodiscard]] static std::string busNameFromItemId(const std::string& itemId);
  [[nodiscard]] static std::string canonicalItemId(const std::string& busName, const std::string& objectPath);

  SessionBus& m_bus;
  std::unique_ptr<sdbus::IObject> m_watcherObject;
  std::unique_ptr<sdbus::IProxy> m_dbusProxy;
  std::unordered_map<std::string, TrayItemInfo> m_items;
  std::unordered_map<std::string, std::unique_ptr<sdbus::IProxy>> m_itemProxies;
  std::unordered_map<std::string, std::unique_ptr<sdbus::IProxy>> m_menuWatchProxies;
  bool m_hostRegistered = true;
  ChangeCallback m_changeCallback;
  MenuToggleCallback m_menuToggleCallback;
};
