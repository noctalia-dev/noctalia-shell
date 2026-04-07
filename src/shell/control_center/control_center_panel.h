#pragma once

#include "shell/panel/panel.h"
#include "shell/control_center/common.h"

#include <array>
#include <chrono>
#include <cstdint>
#include <string_view>

class Button;
class Flex;
class Image;
class Label;
class MprisService;
class NotificationManager;
class PipeWireService;
class ScrollView;
class Select;
class Slider;

class ControlCenterPanel : public Panel {
public:
  ControlCenterPanel(NotificationManager* notifications, PipeWireService* audio, MprisService* mpris);

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
    const char* icon;
  };

  static constexpr std::size_t kTabCount = static_cast<std::size_t>(TabId::Count);
  static constexpr std::array<TabMeta, kTabCount> kTabs{{
      {TabId::Overview, "overview", "Overview", "person"},
      {TabId::Media, "media", "Media", "disc"},
      {TabId::Calendar, "calendar", "Calendar", "settings-about"},
      {TabId::Notifications, "notifications", "Notifications", "bell"},
      {TabId::Network, "network", "Network", "wifi"},
  }};

  void buildOverviewTab();
  void buildMediaTab();
  void buildCalendarTab();
  void buildNotificationsTab();
  void buildNetworkTab();

  void selectTab(TabId tab);
  void rebuildNotifications(Renderer& renderer, float width);
  void refreshMediaState(Renderer& renderer);
  void rebuildCalendar(Renderer& renderer);
  void clearMediaArt(Renderer& renderer);
  [[nodiscard]] static TabId tabFromContext(std::string_view context);
  [[nodiscard]] static std::size_t tabIndex(TabId id);

  NotificationManager* m_notifications = nullptr;
  PipeWireService* m_audio = nullptr;
  MprisService* m_mpris = nullptr;

  Flex* m_rootLayout = nullptr;
  Flex* m_sidebar = nullptr;
  Flex* m_content = nullptr;
  Label* m_contentTitle = nullptr;
  Flex* m_tabBodies = nullptr;

  std::array<Button*, kTabCount> m_tabButtons{};
  std::array<Flex*, kTabCount> m_tabContainers{};
  TabId m_activeTab = TabId::Overview;

  ScrollView* m_notificationScroll = nullptr;
  Flex* m_notificationList = nullptr;
  std::uint64_t m_lastNotificationSerial = 0;
  float m_lastNotificationWidth = -1.0f;

  Slider* m_outputSlider = nullptr;
  Label* m_outputValue = nullptr;
  Slider* m_inputSlider = nullptr;
  Label* m_inputValue = nullptr;
  float m_lastSinkVolume = -1.0f;
  float m_lastSourceVolume = -1.0f;
  Image* m_mediaArtwork = nullptr;
  Flex* m_mediaColumn = nullptr;
  Flex* m_mediaNowCard = nullptr;
  Flex* m_mediaAudioColumn = nullptr;
  Flex* m_mediaOutputCard = nullptr;
  Flex* m_mediaInputCard = nullptr;
  Label* m_mediaTrackTitle = nullptr;
  Label* m_mediaTrackArtist = nullptr;
  Label* m_mediaTrackAlbum = nullptr;
  Slider* m_mediaProgressSlider = nullptr;
  Select* m_mediaPlayerSelect = nullptr;
  Select* m_outputDeviceSelect = nullptr;
  Select* m_inputDeviceSelect = nullptr;
  Button* m_mediaPrevButton = nullptr;
  Button* m_mediaPlayPauseButton = nullptr;
  Button* m_mediaNextButton = nullptr;
  Button* m_mediaRepeatButton = nullptr;
  Button* m_mediaShuffleButton = nullptr;
  std::string m_lastMediaArtPath;
  std::string m_lastMediaBusName;
  std::string m_lastMediaPlaybackStatus;
  std::string m_lastMediaLoopStatus;
  bool m_lastMediaShuffle = false;
  bool m_syncingMediaProgress = false;
  std::int64_t m_pendingMediaSeekUs = -1;
  std::string m_pendingMediaSeekBusName;
  std::chrono::steady_clock::time_point m_pendingMediaSeekUntil{};
  bool m_syncingPlayerSelect = false;
  bool m_syncingOutputSelect = false;
  bool m_syncingInputSelect = false;
  bool m_syncingOutputSlider = false;
  bool m_syncingInputSlider = false;
  std::vector<std::string> m_mediaPlayerBusNames;
  std::vector<std::uint32_t> m_outputDeviceIds;
  std::vector<std::uint32_t> m_inputDeviceIds;

  Flex* m_calendarCard = nullptr;
  Label* m_calendarMonthLabel = nullptr;
  Flex* m_calendarGrid = nullptr;
  int m_calendarMonthOffset = 0;
};
