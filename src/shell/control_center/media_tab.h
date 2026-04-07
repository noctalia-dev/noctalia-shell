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
class PipeWireService;
class Select;
class Slider;

class MediaTab : public Tab {
public:
  MediaTab(MprisService* mpris, PipeWireService* audio, HttpClient* httpClient);

  std::unique_ptr<Flex> build(Renderer& renderer) override;
  void layout(Renderer& renderer, float contentWidth, float bodyHeight) override;
  void update(Renderer& renderer) override;
  void onClose() override;

private:
  void refresh(Renderer& renderer);
  void clearArt(Renderer& renderer);

  MprisService* m_mpris = nullptr;
  PipeWireService* m_audio = nullptr;
  HttpClient* m_httpClient = nullptr;

  Image* m_artwork = nullptr;
  Flex* m_column = nullptr;
  Flex* m_nowCard = nullptr;
  Flex* m_audioColumn = nullptr;
  Flex* m_outputCard = nullptr;
  Flex* m_inputCard = nullptr;
  Label* m_trackTitle = nullptr;
  Label* m_trackArtist = nullptr;
  Label* m_trackAlbum = nullptr;
  Slider* m_progressSlider = nullptr;
  Select* m_playerSelect = nullptr;
  Select* m_outputDeviceSelect = nullptr;
  Select* m_inputDeviceSelect = nullptr;
  Button* m_prevButton = nullptr;
  Button* m_playPauseButton = nullptr;
  Button* m_nextButton = nullptr;
  Button* m_repeatButton = nullptr;
  Button* m_shuffleButton = nullptr;
  Slider* m_outputSlider = nullptr;
  Label* m_outputValue = nullptr;
  Slider* m_inputSlider = nullptr;
  Label* m_inputValue = nullptr;

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
  bool m_syncingOutputSelect = false;
  bool m_syncingInputSelect = false;
  bool m_syncingOutputSlider = false;
  bool m_syncingInputSlider = false;
  std::vector<std::string> m_playerBusNames;
  std::vector<std::uint32_t> m_outputDeviceIds;
  std::vector<std::uint32_t> m_inputDeviceIds;
  float m_lastSinkVolume = -1.0f;
  float m_lastSourceVolume = -1.0f;
  std::unordered_set<std::string> m_pendingArtDownloads;
};
