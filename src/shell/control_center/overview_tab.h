#pragma once

#include "shell/control_center/shortcut_services.h"
#include "shell/control_center/tab.h"

#include <memory>
#include <optional>
#include <string>
#include <vector>

class Button;
class ConfigService;
class Glyph;
class GridView;
class Image;
class Label;
class RectNode;
class Shortcut;
class Wallpaper;
class WaylandConnection;

struct ShortcutPad {
  std::unique_ptr<Shortcut> shortcut;
  Button* button = nullptr;
  Glyph* glyph = nullptr;
  Label* label = nullptr;
  std::optional<std::string> labelOverride;
};

class OverviewTab : public Tab {
public:
  OverviewTab(MprisService* mpris, WeatherService* weather, PipeWireService* audio, PowerProfilesService* powerProfiles,
              ConfigService* config, NetworkService* network, BluetoothService* bluetooth,
              NightLightManager* nightLight, noctalia::theme::ThemeService* theme, NotificationManager* notifications,
              IdleInhibitor* idleInhibitor, WaylandConnection* wayland, Wallpaper* wallpaper = nullptr);
  ~OverviewTab() override;

  std::unique_ptr<Flex> create() override;
  std::unique_ptr<Flex> createHeaderActions() override;
  void setActive(bool active) override;
  void onClose() override;

private:
  void doLayout(Renderer& renderer, float contentWidth, float bodyHeight) override;
  void doUpdate(Renderer& renderer) override;
  void layoutWallpaperBackground(Renderer& renderer);
  void syncWallpaperBackground(Renderer& renderer);
  void sync(Renderer& renderer);
  void syncShortcuts();

  MprisService* m_mpris = nullptr;
  WeatherService* m_weather = nullptr;
  ConfigService* m_config = nullptr;
  Wallpaper* m_wallpaper = nullptr;
  ShortcutServices m_services;
  bool m_active = false;

  Flex* m_rootLayout = nullptr;
  Flex* m_dateTimeCard = nullptr;
  Flex* m_mediaCard = nullptr;
  Flex* m_mediaText = nullptr;
  Flex* m_userCard = nullptr;
  Flex* m_userMain = nullptr;
  Image* m_userAvatar = nullptr;

  Label* m_timeLabel = nullptr;
  Label* m_dateLabel = nullptr;
  Glyph* m_weatherGlyph = nullptr;
  Label* m_weatherLine = nullptr;
  Label* m_userFacts = nullptr;
  Button* m_settingsButton = nullptr;
  std::string m_loadedAvatarPath;

  Image* m_wallpaperBg = nullptr;
  RectNode* m_wallpaperGradient = nullptr;

  Label* m_mediaTrack = nullptr;
  Label* m_mediaArtist = nullptr;
  Label* m_mediaStatus = nullptr;
  Label* m_mediaProgress = nullptr;
  Image* m_mediaArt = nullptr;
  std::string m_loadedMediaArtUrl;

  GridView* m_shortcutsGrid = nullptr;
  std::vector<ShortcutPad> m_shortcutPads;
};
