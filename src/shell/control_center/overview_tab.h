#pragma once

#include "shell/control_center/tab.h"

#include <string>

class Glyph;
class Image;
class Label;
class MprisService;
class PipeWireService;
class PowerProfilesService;
class UPowerService;
class WeatherService;
class Button;
class ConfigService;

class OverviewTab : public Tab {
public:
  OverviewTab(MprisService* mpris, WeatherService* weather, PipeWireService* audio, UPowerService* upower,
              PowerProfilesService* powerProfiles, ConfigService* config);

  std::unique_ptr<Flex> create() override;
  void setActive(bool active) override;
  void onClose() override;

private:
  void doLayout(Renderer& renderer, float contentWidth, float bodyHeight) override;
  void doUpdate(Renderer& renderer) override;
  void sync(Renderer& renderer);

  MprisService* m_mpris = nullptr;
  WeatherService* m_weather = nullptr;
  PipeWireService* m_audio = nullptr;
  UPowerService* m_upower = nullptr;
  PowerProfilesService* m_powerProfiles = nullptr;
  ConfigService* m_config = nullptr;
  bool m_active = false;

  Flex* m_rootLayout = nullptr;
  Flex* m_weatherCard = nullptr;
  Flex* m_mediaCard = nullptr;
  Flex* m_mediaText = nullptr;
  Flex* m_userCard = nullptr;
  Flex* m_userMain = nullptr;
  Flex* m_powerCard = nullptr;
  Flex* m_audioCard = nullptr;
  Image* m_userAvatar = nullptr;

  Glyph* m_weatherGlyph = nullptr;
  Label* m_weatherDate = nullptr;
  Label* m_weatherTemp = nullptr;
  Label* m_weatherSub = nullptr;

  Label* m_userFacts = nullptr;
  Button* m_sessionMenuButton = nullptr;
  Button* m_settingsButton = nullptr;
  std::string m_loadedAvatarPath;

  Label* m_mediaKicker = nullptr;
  Label* m_mediaTrack = nullptr;
  Label* m_mediaArtist = nullptr;
  Label* m_mediaStatus = nullptr;
  Label* m_mediaProgress = nullptr;
  Image* m_mediaArt = nullptr;
  std::string m_loadedMediaArtUrl;

  Label* m_powerLine = nullptr;
  Label* m_powerSub = nullptr;
  Label* m_audioLine = nullptr;
  Label* m_audioSub = nullptr;
};
