#pragma once

#include "shell/control_center/tab.h"

#include <chrono>
#include <cstdint>
#include <string>
#include <unordered_set>
#include <vector>

class Button;
class HttpClient;
class Image;
class Label;
class MprisService;
class PipeWireSpectrum;
class Select;
class Slider;

class MediaTab : public Tab {
public:
  MediaTab(MprisService* mpris, HttpClient* httpClient, PipeWireSpectrum* spectrum);

  std::unique_ptr<Flex> build(Renderer& renderer) override;
  void layout(Renderer& renderer, float contentWidth, float bodyHeight) override;
  void update(Renderer& renderer) override;
  void setActive(bool active) override;
  void onClose() override;

private:
  void refresh(Renderer& renderer);
  void clearArt(Renderer& renderer);

  MprisService* m_mpris = nullptr;
  HttpClient* m_httpClient = nullptr;
  PipeWireSpectrum* m_spectrum = nullptr;
  bool m_active = false;

  Flex* m_rootLayout = nullptr;
  Flex* m_mediaColumn = nullptr;
  Flex* m_visualizerColumn = nullptr;
  Image* m_artwork = nullptr;
  Flex* m_nowCard = nullptr;
  Flex* m_mediaStack = nullptr;
  Flex* m_visualizerCard = nullptr;
  Label* m_trackTitle = nullptr;
  Label* m_trackArtist = nullptr;
  Label* m_trackAlbum = nullptr;
  Slider* m_progressSlider = nullptr;
  Select* m_playerSelect = nullptr;
  Button* m_prevButton = nullptr;
  Button* m_playPauseButton = nullptr;
  Button* m_nextButton = nullptr;
  Button* m_repeatButton = nullptr;
  Button* m_shuffleButton = nullptr;

  std::string m_lastArtPath;
  std::string m_lastBusName;
  std::string m_lastPlaybackStatus;
  std::string m_lastLoopStatus;
  bool m_lastShuffle = false;
  bool m_syncingProgress = false;
  std::int64_t m_pendingSeekUs = -1;
  std::string m_pendingSeekBusName;
  std::chrono::steady_clock::time_point m_pendingSeekUntil{};
  bool m_syncingPlayerSelect = false;
  std::vector<std::string> m_playerBusNames;
  std::chrono::steady_clock::time_point m_lastMprisRefreshAttempt{};
  std::unordered_set<std::string> m_pendingArtDownloads;
};
