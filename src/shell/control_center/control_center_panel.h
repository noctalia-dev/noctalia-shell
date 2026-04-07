#pragma once

#include "shell/control_center/tab.h"
#include "shell/control_center/overview_tab.h"
#include "shell/control_center/media_tab.h"
#include "shell/control_center/calendar_tab.h"
#include "shell/control_center/notifications_tab.h"
#include "shell/control_center/network_tab.h"
#include "shell/panel/panel.h"
#include "shell/control_center/common.h"

#include <array>
#include <cstdint>
#include <memory>
#include <string_view>

class Button;
class Flex;
class HttpClient;
class Label;
class MprisService;
class NotificationManager;
class PipeWireService;

class ControlCenterPanel : public Panel {
public:
  ControlCenterPanel(NotificationManager* notifications, PipeWireService* audio, MprisService* mpris,
                     HttpClient* httpClient = nullptr);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float width, float height) override;
  void update(Renderer& renderer) override;
  void onOpen(std::string_view context) override;
  void onClose() override;

  [[nodiscard]] float preferredWidth() const override { return control_center::kPreferredPanelWidth; }
  [[nodiscard]] float preferredHeight() const override { return control_center::kPreferredPanelHeight; }
  [[nodiscard]] bool centeredHorizontally() const override { return true; }
  [[nodiscard]] bool centeredVertically() const override { return true; }

private:
  enum class TabId : std::uint8_t {
    Overview = 0,
    Media = 1,
    Calendar = 2,
    Notifications = 3,
    Network = 4,
    Count = 5,
  };

  struct TabMeta {
    TabId id;
    const char* key;
    const char* title;
    const char* glyph;
  };

  static constexpr std::size_t kTabCount = static_cast<std::size_t>(TabId::Count);
  static constexpr std::array<TabMeta, kTabCount> kTabs{{
      {TabId::Overview, "overview", "Overview", "person"},
      {TabId::Media, "media", "Media", "disc"},
      {TabId::Calendar, "calendar", "Calendar", "settings-about"},
      {TabId::Notifications, "notifications", "Notifications", "bell"},
      {TabId::Network, "network", "Network", "wifi"},
  }};

  void selectTab(TabId tab);
  [[nodiscard]] static TabId tabFromContext(std::string_view context);
  [[nodiscard]] static std::size_t tabIndex(TabId id);

  // Tab instances (long-lived, survive panel open/close cycles)
  std::array<std::unique_ptr<Tab>, kTabCount> m_tabs;

  // Panel chrome (rebuilt each create(), nulled in onClose())
  Flex* m_rootLayout = nullptr;
  Flex* m_sidebar = nullptr;
  Flex* m_content = nullptr;
  Label* m_contentTitle = nullptr;
  Flex* m_tabBodies = nullptr;
  std::array<Button*, kTabCount> m_tabButtons{};
  std::array<Flex*, kTabCount> m_tabContainers{};
  TabId m_activeTab = TabId::Overview;
};
