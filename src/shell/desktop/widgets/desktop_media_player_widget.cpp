#include "shell/desktop/widgets/desktop_media_player_widget.h"

#include "dbus/mpris/mpris_service.h"
#include "net/http_client.h"
#include "render/core/renderer.h"
#include "render/scene/node.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <cctype>
#include <cmath>
#include <filesystem>
#include <format>

namespace {

  constexpr float kArtSize = 120.0f;
  constexpr float kControlSize = 32.0f;
  constexpr float kPlayPauseSize = 40.0f;
  constexpr float kSpacing = 6.0f;

  bool isRemoteArtUrl(std::string_view url) { return url.starts_with("https://") || url.starts_with("http://"); }

  std::string extractQueryParam(std::string_view url, std::string_view key) {
    const auto queryPos = url.find('?');
    if (queryPos == std::string_view::npos)
      return {};
    std::string_view query = url.substr(queryPos + 1);
    while (!query.empty()) {
      const auto ampPos = query.find('&');
      const std::string_view pair = query.substr(0, ampPos);
      const auto eqPos = pair.find('=');
      if (pair.substr(0, eqPos) == key)
        return eqPos == std::string_view::npos ? std::string{} : std::string(pair.substr(eqPos + 1));
      if (ampPos == std::string_view::npos)
        break;
      query.remove_prefix(ampPos + 1);
    }
    return {};
  }

  std::string deriveYouTubeThumbnailUrl(std::string_view sourceUrl) {
    if (sourceUrl.empty())
      return {};
    std::string videoId;
    if (sourceUrl.find("youtube.com/watch") != std::string_view::npos) {
      videoId = extractQueryParam(sourceUrl, "v");
    } else if (sourceUrl.find("youtu.be/") != std::string_view::npos) {
      const auto start = sourceUrl.find("youtu.be/") + 9;
      const auto end = sourceUrl.find_first_of("?#&/", start);
      videoId =
          std::string(sourceUrl.substr(start, end == std::string_view::npos ? sourceUrl.size() - start : end - start));
    } else if (sourceUrl.find("youtube.com/shorts/") != std::string_view::npos) {
      const auto start = sourceUrl.find("youtube.com/shorts/") + 19;
      const auto end = sourceUrl.find_first_of("?#&/", start);
      videoId =
          std::string(sourceUrl.substr(start, end == std::string_view::npos ? sourceUrl.size() - start : end - start));
    }
    if (videoId.empty())
      return {};
    return std::format("https://i.ytimg.com/vi/{}/hqdefault.jpg", videoId);
  }

  std::string effectiveArtUrl(const MprisPlayerInfo& player) {
    if (!player.artUrl.empty())
      return player.artUrl;
    return deriveYouTubeThumbnailUrl(player.sourceUrl);
  }

  int hexValue(char ch) {
    if (ch >= '0' && ch <= '9')
      return ch - '0';
    ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    if (ch >= 'a' && ch <= 'f')
      return 10 + (ch - 'a');
    return -1;
  }

  std::string decodeUriComponent(std::string_view text) {
    std::string decoded;
    decoded.reserve(text.size());
    for (std::size_t i = 0; i < text.size(); ++i) {
      if (text[i] == '%' && i + 2 < text.size()) {
        const int hi = hexValue(text[i + 1]);
        const int lo = hexValue(text[i + 2]);
        if (hi >= 0 && lo >= 0) {
          decoded.push_back(static_cast<char>((hi << 4) | lo));
          i += 2;
          continue;
        }
      }
      decoded.push_back(text[i]);
    }
    return decoded;
  }

  std::string normalizeArtPath(std::string_view artUrl) {
    if (artUrl.empty() || isRemoteArtUrl(artUrl))
      return {};
    std::string path(artUrl);
    constexpr std::string_view prefix = "file://";
    if (path.starts_with(prefix)) {
      path.erase(0, prefix.size());
      if (path.starts_with("localhost/")) {
        path.erase(0, std::string_view("localhost").size());
      } else if (!path.empty() && path.front() != '/') {
        const auto firstSlash = path.find('/');
        path = firstSlash == std::string::npos ? std::string{} : path.substr(firstSlash);
      }
    }
    return decodeUriComponent(path);
  }

  std::filesystem::path artCachePath(std::string_view artUrl) {
    const std::filesystem::path cacheDir = std::filesystem::path("/tmp") / "noctalia-media-art";
    const std::size_t hash = std::hash<std::string_view>{}(artUrl);
    return cacheDir / (std::to_string(hash) + ".img");
  }

  std::string joinArtists(const std::vector<std::string>& artists) {
    if (artists.empty())
      return {};
    std::string joined = artists.front();
    for (std::size_t i = 1; i < artists.size(); ++i) {
      joined += ", ";
      joined += artists[i];
    }
    return joined;
  }

} // namespace

DesktopMediaPlayerWidget::DesktopMediaPlayerWidget(MprisService* mpris, HttpClient* httpClient, bool vertical)
    : m_mpris(mpris), m_httpClient(httpClient), m_vertical(vertical) {}

void DesktopMediaPlayerWidget::create() {
  auto rootNode = std::make_unique<Node>();

  auto artwork = std::make_unique<Image>();
  artwork->setFit(ImageFit::Cover);
  artwork->setCornerRadius(Style::radiusMd * contentScale());
  artwork->setBackground(roleColor(ColorRole::SurfaceVariant, 0.5f));
  m_artwork = artwork.get();
  rootNode->addChild(std::move(artwork));

  auto title = std::make_unique<Label>();
  title->setBold(true);
  title->setMaxLines(1);
  title->setColor(roleColor(ColorRole::OnSurface));
  m_title = title.get();
  rootNode->addChild(std::move(title));

  auto artist = std::make_unique<Label>();
  artist->setMaxLines(1);
  artist->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_artist = artist.get();
  rootNode->addChild(std::move(artist));

  auto controls = std::make_unique<Flex>();
  controls->setDirection(FlexDirection::Horizontal);
  controls->setAlign(FlexAlign::Center);
  controls->setJustify(FlexJustify::Center);
  m_controls = controls.get();

  auto prev = std::make_unique<Button>();
  prev->setGlyph("media-prev");
  prev->setVariant(ButtonVariant::Ghost);
  prev->setOnClick([this]() {
    if (m_mpris != nullptr) {
      m_mpris->previousActive();
      requestRedraw();
    }
  });
  m_prev = prev.get();
  controls->addChild(std::move(prev));

  auto playPause = std::make_unique<Button>();
  playPause->setGlyph("media-play");
  playPause->setVariant(ButtonVariant::Accent);
  playPause->setOnClick([this]() {
    if (m_mpris != nullptr) {
      m_mpris->playPauseActive();
      requestRedraw();
    }
  });
  m_playPause = playPause.get();
  controls->addChild(std::move(playPause));

  auto next = std::make_unique<Button>();
  next->setGlyph("media-next");
  next->setVariant(ButtonVariant::Ghost);
  next->setOnClick([this]() {
    if (m_mpris != nullptr) {
      m_mpris->nextActive();
      requestRedraw();
    }
  });
  m_next = next.get();
  controls->addChild(std::move(next));

  rootNode->addChild(std::move(controls));
  setRoot(std::move(rootNode));
}

void DesktopMediaPlayerWidget::doLayout(Renderer& renderer) {
  if (root() == nullptr || m_artwork == nullptr || m_title == nullptr || m_artist == nullptr || m_controls == nullptr)
    return;

  sync(renderer);

  const float scale = contentScale();
  if (m_vertical) {
    layoutVertical(renderer, scale);
  } else {
    layoutHorizontal(renderer, scale);
  }
}

void DesktopMediaPlayerWidget::layoutVertical(Renderer& renderer, float scale) {
  const float artW = kArtSize * scale;
  const float spacing = kSpacing * scale;
  const float fontSize = Style::fontSizeBody * scale;

  m_artwork->setSize(artW, artW);
  m_artwork->setCornerRadius(Style::radiusMd * scale);
  m_artwork->setPosition(0.0f, 0.0f);

  m_title->setFontSize(fontSize);
  m_title->setMaxWidth(artW);
  m_title->measure(renderer);
  m_title->setPosition(0.0f, artW + spacing);

  m_artist->setFontSize(fontSize * 0.9f);
  m_artist->setMaxWidth(artW);
  m_artist->measure(renderer);
  const float artistY = m_title->y() + m_title->height() + spacing * 0.5f;
  m_artist->setPosition(0.0f, artistY);

  layoutButtons(renderer, scale);

  const float controlsY =
      (m_artist->visible() ? m_artist->y() + m_artist->height() : m_title->y() + m_title->height()) + spacing;
  const float controlsX = std::round((artW - m_controls->width()) * 0.5f);
  m_controls->setPosition(controlsX, controlsY);

  root()->setSize(artW, controlsY + m_controls->height());
}

void DesktopMediaPlayerWidget::layoutHorizontal(Renderer& renderer, float scale) {
  const float artH = kArtSize * scale;
  const float spacing = kSpacing * scale;
  const float fontSize = Style::fontSizeBody * scale;
  const float textWidth = artH * 1.5f;

  m_artwork->setSize(artH, artH);
  m_artwork->setCornerRadius(Style::radiusMd * scale);
  m_artwork->setPosition(0.0f, 0.0f);

  const float textX = artH + spacing;

  m_title->setFontSize(fontSize);
  m_title->setMaxWidth(textWidth);
  m_title->measure(renderer);

  m_artist->setFontSize(fontSize * 0.9f);
  m_artist->setMaxWidth(textWidth);
  m_artist->measure(renderer);

  layoutButtons(renderer, scale);

  const float titleH = m_title->height();
  const float artistH = m_artist->visible() ? m_artist->height() + spacing * 0.5f : 0.0f;
  const float controlsH = m_controls->height();
  const float textBlockH = titleH + artistH + spacing * 0.5f + controlsH;
  const float textY = std::round((artH - textBlockH) * 0.5f);

  m_title->setPosition(textX, textY);
  m_artist->setPosition(textX, textY + titleH + spacing * 0.5f);

  const float controlsY = textY + titleH + artistH + spacing * 0.5f;
  m_controls->setPosition(textX, controlsY);

  const float totalWidth =
      textX + std::max({m_title->width(), m_artist->visible() ? m_artist->width() : 0.0f, m_controls->width()});
  root()->setSize(totalWidth, artH);
}

void DesktopMediaPlayerWidget::layoutButtons(Renderer& renderer, float scale) {
  const float controlBtnSize = kControlSize * scale;
  const float playPauseBtnSize = kPlayPauseSize * scale;
  const float glyphSize = Style::fontSizeBody * scale;
  const float playPauseGlyphSize = Style::fontSizeBody * 1.2f * scale;

  m_controls->setGap(Style::spaceXs * scale);

  m_prev->setMinWidth(controlBtnSize);
  m_prev->setMinHeight(controlBtnSize);
  m_prev->setGlyphSize(glyphSize);
  m_prev->setPadding(Style::spaceXs * scale, Style::spaceXs * scale);
  m_prev->setRadius(Style::radiusMd * scale);

  m_playPause->setMinWidth(playPauseBtnSize);
  m_playPause->setMinHeight(playPauseBtnSize);
  m_playPause->setGlyphSize(playPauseGlyphSize);
  m_playPause->setPadding(Style::spaceSm * scale, Style::spaceSm * scale);
  m_playPause->setRadius(Style::radiusLg * scale);

  m_next->setMinWidth(controlBtnSize);
  m_next->setMinHeight(controlBtnSize);
  m_next->setGlyphSize(glyphSize);
  m_next->setPadding(Style::spaceXs * scale, Style::spaceXs * scale);
  m_next->setRadius(Style::radiusMd * scale);

  m_controls->layout(renderer);
  m_prev->updateInputArea();
  m_playPause->updateInputArea();
  m_next->updateInputArea();
}

void DesktopMediaPlayerWidget::doUpdate(Renderer& renderer) { sync(renderer); }

void DesktopMediaPlayerWidget::sync(Renderer& renderer) {
  if (m_title == nullptr || m_artist == nullptr || m_playPause == nullptr)
    return;

  const auto active = m_mpris != nullptr ? m_mpris->activePlayer() : std::nullopt;

  std::string title;
  std::string artist;
  std::string artUrl;
  std::string playbackStatus;

  if (active.has_value()) {
    title = active->title;
    artist = joinArtists(active->artists);
    artUrl = effectiveArtUrl(*active);
    playbackStatus = active->playbackStatus;
  }

  const bool titleChanged = title != m_lastTitle;
  const bool artistChanged = artist != m_lastArtist;
  const bool artChanged = artUrl != m_lastArtUrl;
  const bool statusChanged = playbackStatus != m_lastPlaybackStatus;
  if (!titleChanged && !artistChanged && !artChanged && !statusChanged)
    return;

  m_lastTitle = title;
  m_lastArtist = artist;
  m_lastArtUrl = artUrl;
  m_lastPlaybackStatus = playbackStatus;

  m_title->setText(m_lastTitle.empty() ? "Nothing playing" : m_lastTitle);
  m_artist->setText(m_lastArtist);
  m_artist->setVisible(!m_lastArtist.empty());

  m_playPause->setGlyph(m_lastPlaybackStatus == "Playing" ? "media-pause" : "media-play");

  if (artChanged && m_artwork != nullptr) {
    std::string artPath = resolveArtworkPath();
    if (artPath.empty() && isRemoteArtUrl(m_lastArtUrl)) {
      const auto cached = artCachePath(m_lastArtUrl);
      std::error_code ec;
      if (std::filesystem::exists(cached, ec) && std::filesystem::file_size(cached, ec) > 0) {
        artPath = cached.string();
      } else if (m_httpClient != nullptr && !m_pendingArtDownloads.contains(m_lastArtUrl)) {
        std::filesystem::create_directories(cached.parent_path(), ec);
        m_pendingArtDownloads.insert(m_lastArtUrl);
        m_httpClient->download(m_lastArtUrl, cached, [this, url = m_lastArtUrl](bool success) {
          m_pendingArtDownloads.erase(url);
          if (success && url == m_lastArtUrl)
            requestRedraw();
        });
      }
    }

    if (!artPath.empty()) {
      const int targetPx = static_cast<int>(std::round(kArtSize * contentScale()));
      if (!m_artwork->setSourceFile(renderer, artPath, targetPx, true))
        m_artwork->clear(renderer);
    } else {
      m_artwork->clear(renderer);
    }
  } else if (!m_lastArtUrl.empty() && m_artwork != nullptr && !m_artwork->hasImage()) {
    std::string artPath = resolveArtworkPath();
    if (artPath.empty() && isRemoteArtUrl(m_lastArtUrl)) {
      const auto cached = artCachePath(m_lastArtUrl);
      std::error_code ec;
      if (std::filesystem::exists(cached, ec) && std::filesystem::file_size(cached, ec) > 0)
        artPath = cached.string();
    }
    if (!artPath.empty()) {
      const int targetPx = static_cast<int>(std::round(kArtSize * contentScale()));
      if (m_artwork->setSourceFile(renderer, artPath, targetPx, true))
        requestRedraw();
    }
  }

  requestRedraw();
}

std::string DesktopMediaPlayerWidget::resolveArtworkPath() const { return normalizeArtPath(m_lastArtUrl); }
