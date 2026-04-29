#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <sdbus-c++/sdbus-c++.h>
#include <string>
#include <unordered_map>
#include <vector>

class SessionBus;

struct TrayItemInfo {
  std::string id;
  std::string busName;
  std::string objectPath;
  std::string iconName;
  std::string iconThemePath;
  std::string overlayIconName;
  std::string attentionIconName;
  std::string menuObjectPath;
  std::string itemName;
  std::string title;
  std::string status;
  std::vector<std::uint8_t> iconArgb32;
  std::int32_t iconWidth = 0;
  std::int32_t iconHeight = 0;
  std::vector<std::uint8_t> overlayArgb32;
  std::int32_t overlayWidth = 0;
  std::int32_t overlayHeight = 0;
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
  ~TrayService();
  TrayService(const TrayService&) = delete;
  TrayService& operator=(const TrayService&) = delete;

  void setChangeCallback(ChangeCallback callback);
  void setMenuToggleCallback(MenuToggleCallback callback);
  void requestMenuToggle(const std::string& itemId) const;
  [[nodiscard]] std::size_t itemCount() const noexcept;
  [[nodiscard]] std::vector<TrayItemInfo> items() const;
  [[nodiscard]] std::vector<TrayMenuEntry> menuEntries(const std::string& itemId);
  [[nodiscard]] std::vector<TrayMenuEntry> menuEntriesForParent(const std::string& itemId, std::int32_t parentId);
  [[nodiscard]] bool activateMenuEntry(const std::string& itemId, std::int32_t entryId);
  // Notify the dbusmenu server that a (sub)menu is being opened/closed. `entryId`
  // is the menu item id: 0 for the root menu, or a submenu parent id otherwise.
  // Well-behaved dbusmenu servers (including Electron) rely on paired opened/closed
  // events to reset internal state — skipping these causes state drift after many
  // open/close cycles.
  void notifyMenuOpened(const std::string& itemId, std::int32_t entryId = 0);
  void notifyMenuClosed(const std::string& itemId, std::int32_t entryId = 0);
  [[nodiscard]] std::vector<std::string> registeredItems() const;
  [[nodiscard]] bool activateItem(const std::string& itemId, std::int32_t x = 0, std::int32_t y = 0);
  [[nodiscard]] bool openContextMenu(const std::string& itemId, std::int32_t x = 0, std::int32_t y = 0);

private:
  struct MenuCache {
    std::unique_ptr<sdbus::IProxy> proxy;
    // Decoded children per parent-id. parentId=0 is the root menu.
    std::unordered_map<std::int32_t, std::vector<TrayMenuEntry>> entriesByParent;
    std::uint32_t revision = 0;
    bool rootLoaded = false;
  };

  void onRegisterStatusNotifierItem(const std::string& serviceOrPath, const std::string& senderBusName);
  void onRegisterStatusNotifierHost(const std::string& host);
  void discoverExistingItems();
  [[nodiscard]] bool tryRegisterItemForBusName(const std::string& busName);
  void scheduleBusOnlyRegistrationProbe(const std::string& busName, int retriesRemaining);
  void scheduleMetadataRefreshRetry(const std::string& itemId, int retriesRemaining);
  [[nodiscard]] bool isMetadataReady(const TrayItemInfo& item) const;
  void registerOrRefreshItem(const std::string& busName, const std::string& objectPath);
  void refreshItemMetadata(const std::string& itemId);
  void ensureMenuCache(const std::string& itemId, const std::string& busName, const std::string& menuPath);
  void dropMenuCache(const std::string& itemId);
  bool fetchMenuSubtree(const std::string& itemId, std::int32_t parentId);
  void sendMenuEvent(const std::string& itemId, std::int32_t entryId, const std::string& eventName);
  [[nodiscard]] bool ensureItemProxy(const std::string& itemId);
  [[nodiscard]] bool hasServiceOwner(const std::string& serviceName) const;
  void removeItemsForBusName(const std::string& busName);
  void emitChanged();

  [[nodiscard]] static std::string busNameFromItemId(const std::string& itemId);
  [[nodiscard]] static std::string canonicalItemId(const std::string& busName, const std::string& objectPath);

  SessionBus& m_bus;
  std::unique_ptr<sdbus::IObject> m_watcherObject;
  std::unique_ptr<sdbus::IProxy> m_dbusProxy;
  std::unordered_map<std::string, TrayItemInfo> m_items;
  std::unordered_map<std::string, std::unique_ptr<sdbus::IProxy>> m_itemProxies;
  std::unordered_map<std::string, MenuCache> m_menuCache;
  bool m_hostRegistered = true;
  ChangeCallback m_changeCallback;
  MenuToggleCallback m_menuToggleCallback;
};
