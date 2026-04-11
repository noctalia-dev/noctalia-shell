#pragma once

#include "shell/widget/widget.h"

#include <filesystem>
#include <string>
#include <unordered_set>

class Image;
class InputArea;
class HttpClient;
class Label;
class MprisService;
class Renderer;
struct MprisPlayerInfo;

class MediaWidget : public Widget {
public:
  MediaWidget(MprisService* mpris, HttpClient* httpClient, float maxWidth, float artSize);

  void create() override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void update(Renderer& renderer) override;

private:
  void syncState(Renderer& renderer);
  [[nodiscard]] static std::string buildDisplayText(const MprisPlayerInfo& player);
  [[nodiscard]] std::string resolveArtworkPath() const;

  MprisService* m_mpris = nullptr;
  HttpClient* m_httpClient = nullptr;
  float m_maxWidth = 220.0f;
  float m_artSize = 24.0f;
  InputArea* m_area = nullptr;
  Image* m_art = nullptr;
  Label* m_label = nullptr;

  std::string m_lastText;
  std::string m_lastArtUrl;
  std::string m_lastPlaybackStatus;
  std::unordered_set<std::string> m_pendingArtDownloads;
  bool m_clickReady = false;
  bool m_clickArmed = false;
};
