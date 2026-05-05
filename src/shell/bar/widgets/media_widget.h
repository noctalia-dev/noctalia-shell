#pragma once

#include "shell/bar/widget.h"

#include <filesystem>
#include <string>
#include <unordered_set>

class Image;
class InputArea;
class HttpClient;
class Glyph;
class Label;
class MprisService;
class Renderer;
struct MprisPlayerInfo;
struct wl_output;

class MediaWidget : public Widget {
public:
  MediaWidget(MprisService* mpris, HttpClient* httpClient, wl_output* output, float maxWidth, float minWidth,
              float artSize);

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  void syncState(Renderer& renderer);
  [[nodiscard]] static std::string buildDisplayText(const MprisPlayerInfo& player);
  [[nodiscard]] std::string resolveArtworkPath() const;

  MprisService* m_mpris = nullptr;
  HttpClient* m_httpClient = nullptr;
  wl_output* m_output = nullptr;
  float m_maxWidth = 220.0f;
  float m_minWidth = 80.0f;
  float m_artSize = 16.0f;
  InputArea* m_area = nullptr;
  Image* m_art = nullptr;
  Glyph* m_emptyGlyph = nullptr;
  Label* m_label = nullptr;

  std::string m_lastText;
  std::string m_lastArtUrl;
  std::string m_lastPlaybackStatus;
  std::unordered_set<std::string> m_pendingArtDownloads;
};
