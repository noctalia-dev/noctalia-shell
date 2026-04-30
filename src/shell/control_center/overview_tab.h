#pragma once

#include "shell/control_center/shortcut_services.h"
#include "shell/control_center/tab.h"

#include <memory>
#include <string>
#include <vector>

class Button;
class ConfigService;
class Glyph;
class GridView;
class Image;
class Label;
class Shortcut;

struct ShortcutPad {
  std::unique_ptr<Shortcut> shortcut;
  Button* button = nullptr;
  Glyph* glyph = nullptr;
  Label* label = nullptr;
  Label* description = nullptr;
};

class OverviewTab : public Tab {
public:
  OverviewTab(MprisService* mpris, WeatherService* weather, PipeWireService* audio, PowerProfilesService* powerProfiles,
              ConfigService* config, NetworkService* network, BluetoothService* bluetooth,
              NightLightManager* nightLight, noctalia::theme::ThemeService* theme, NotificationManager* notifications,
              IdleInhibitor* idleInhibitor);
  ~OverviewTab() override;

  std::unique_ptr<Flex> create() override;
  std::unique_ptr<Flex> createHeaderActions() override;
  void setActive(bool active) override;
  void onClose() override;

private:
  void doLayout(Renderer& renderer, float contentWidth, float bodyHeight) override;
  void doUpdate(Renderer& renderer) override;
  void sync(Renderer& renderer);
  void syncShortcuts();

  ConfigService* m_config = nullptr;
  ShortcutServices m_services;
  bool m_active = false;

  Flex* m_rootLayout = nullptr;
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

  GridView* m_shortcutsGrid = nullptr;
  std::vector<ShortcutPad> m_shortcutPads;
};
