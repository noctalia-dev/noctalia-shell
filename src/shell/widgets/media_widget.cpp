#include "shell/widgets/media_widget.h"

#include "core/log.h"
#include "dbus/mpris/mpris_service.h"
#include "net/http_client.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <filesystem>
#include <format>
#include <string_view>

namespace {

const Logger kLog{"media"};

bool isRemoteArtUrl(std::string_view artUrl) {
  return artUrl.starts_with("https://") || artUrl.starts_with("http://");
}

std::string extractQueryParam(std::string_view url, std::string_view key) {
  const auto queryPos = url.find('?');
  if (queryPos == std::string_view::npos) {
    return {};
  }

  std::string_view query = url.substr(queryPos + 1);
  while (!query.empty()) {
    const auto ampPos = query.find('&');
    const std::string_view pair = query.substr(0, ampPos);
    const auto eqPos = pair.find('=');
    const std::string_view pairKey = pair.substr(0, eqPos);
    if (pairKey == key) {
      return eqPos == std::string_view::npos ? std::string{} : std::string(pair.substr(eqPos + 1));
    }
    if (ampPos == std::string_view::npos) {
      break;
    }
    query.remove_prefix(ampPos + 1);
  }

  return {};
}

std::string deriveYouTubeThumbnailUrl(std::string_view sourceUrl) {
  if (sourceUrl.empty()) {
    return {};
  }

  std::string videoId;
  if (sourceUrl.find("youtube.com/watch") != std::string_view::npos) {
    videoId = extractQueryParam(sourceUrl, "v");
  } else if (sourceUrl.find("youtu.be/") != std::string_view::npos) {
    const auto marker = sourceUrl.find("youtu.be/");
    const auto start = marker + std::string_view("youtu.be/").size();
    const auto end = sourceUrl.find_first_of("?#&/", start);
    videoId = std::string(sourceUrl.substr(start, end == std::string_view::npos ? sourceUrl.size() - start : end - start));
  } else if (sourceUrl.find("youtube.com/shorts/") != std::string_view::npos) {
    const auto marker = sourceUrl.find("youtube.com/shorts/");
    const auto start = marker + std::string_view("youtube.com/shorts/").size();
    const auto end = sourceUrl.find_first_of("?#&/", start);
    videoId = std::string(sourceUrl.substr(start, end == std::string_view::npos ? sourceUrl.size() - start : end - start));
  }

  if (videoId.empty()) {
    return {};
  }

  return std::format("https://i.ytimg.com/vi/{}/hqdefault.jpg", videoId);
}

std::string effectiveArtUrl(const MprisPlayerInfo& player) {
  if (!player.artUrl.empty()) {
    return player.artUrl;
  }
  return deriveYouTubeThumbnailUrl(player.sourceUrl);
}

int hexValue(char ch) {
  if (ch >= '0' && ch <= '9') {
    return ch - '0';
  }
  ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
  if (ch >= 'a' && ch <= 'f') {
    return 10 + (ch - 'a');
  }
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

std::string joinArtists(const std::vector<std::string>& artists) {
  if (artists.empty()) {
    return {};
  }

  std::string joined = artists.front();
  for (std::size_t i = 1; i < artists.size(); ++i) {
    joined += ", ";
    joined += artists[i];
  }
  return joined;
}

std::string normalizeArtPath(std::string_view artUrl) {
  if (artUrl.empty()) {
    return {};
  }
  if (isRemoteArtUrl(artUrl)) {
    return {};
  }

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

} // namespace

MediaWidget::MediaWidget(MprisService* mpris, HttpClient* httpClient, float maxWidth, float artSize)
    : m_mpris(mpris), m_httpClient(httpClient), m_maxWidth(maxWidth), m_artSize(artSize) {}

void MediaWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnMotion([this](const InputArea::PointerData& /*data*/) { m_clickReady = true; });
  area->setOnLeave([this]() {
    m_clickReady = false;
    m_clickArmed = false;
  });
  area->setOnPress([this](const InputArea::PointerData& data) {
    if (!data.pressed) {
      return;
    }
    m_clickArmed = m_clickReady && data.button == BTN_LEFT;
  });
  area->setOnClick([this](const InputArea::PointerData& data) {
    if (!m_clickArmed || data.button != BTN_LEFT) {
      return;
    }
    m_clickArmed = false;
    if (m_mpris != nullptr) {
      m_mpris->playPauseActive();
    }
  });
  m_area = area.get();

  auto art = std::make_unique<Image>();
  art->setCornerRadius((m_artSize * m_contentScale) * 0.5f);
  art->setBackground(roleColor(ColorRole::SurfaceVariant, 0.9f));
  art->setFit(ImageFit::Cover);
  art->setSize(m_artSize * m_contentScale, m_artSize * m_contentScale);
  m_art = art.get();
  area->addChild(std::move(art));

  auto label = std::make_unique<Label>();
  label->setBold(true);
  label->setFontSize(Style::fontSizeBody * m_contentScale);
  label->setColor(widgetForegroundOr(roleColor(ColorRole::OnSurface)));
  label->setMaxWidth(m_maxWidth * m_contentScale);
  label->setMaxLines(1);
  label->setStableBaseline(true);
  m_label = label.get();
  area->addChild(std::move(label));

  setRoot(std::move(area));
}

void MediaWidget::doLayout(Renderer& renderer, float containerWidth, float containerHeight) {
  auto* rootNode = root();
  if (rootNode == nullptr || m_art == nullptr || m_label == nullptr) {
    return;
  }
  syncState(renderer);

  const bool isVertical = containerHeight > containerWidth;

  m_label->setMaxWidth(m_maxWidth * m_contentScale);
  m_label->setColor(m_lastPlaybackStatus == "Playing"
                         ? widgetForegroundOr(roleColor(ColorRole::OnSurface))
                         : roleColor(ColorRole::OnSurfaceVariant));
  m_label->measure(renderer);

  // Clamp art to the label's single-line height so oversized art_size cannot
  // distort the bar capsule. The bar uses a uniform cross-axis extent derived
  // from the same reference metrics.
  const float artSize = std::min(m_artSize * m_contentScale, m_label->height());
  m_art->setSize(artSize, artSize);
  m_art->setCornerRadius(artSize * 0.5f);

  const float contentHeight = m_label->height();
  const float artY = std::round((contentHeight - artSize) * 0.5f);

  m_label->setVisible(!isVertical);
  if (isVertical) {
    m_art->setPosition(0.0f, artY);
    rootNode->setSize(artSize, contentHeight);
  } else {
    const float spacing = m_label->text().empty() ? 0.0f : Style::spaceXs;
    m_art->setPosition(0.0f, artY);
    m_label->setPosition(artSize + spacing, 0.0f);
    rootNode->setSize(m_label->x() + m_label->width(), contentHeight);
  }
}

void MediaWidget::doUpdate(Renderer& renderer) {
  syncState(renderer);
}

void MediaWidget::syncState(Renderer& renderer) {
  if (m_art == nullptr || m_label == nullptr) {
    return;
  }

  const auto active = m_mpris != nullptr ? m_mpris->activePlayer() : std::nullopt;

  std::string playbackStatus;
  std::string displayText = "Nothing playing";
  std::string artUrl;

  if (active.has_value()) {
    playbackStatus = active->playbackStatus;
    displayText = buildDisplayText(*active);
    artUrl = effectiveArtUrl(*active);
  }

  const bool textChanged = displayText != m_lastText;
  const bool artChanged = artUrl != m_lastArtUrl;
  const bool playbackChanged = playbackStatus != m_lastPlaybackStatus;
  if (!textChanged && !artChanged && !playbackChanged) {
    return;
  }

  m_lastText = displayText;
  m_lastArtUrl = artUrl;
  m_lastPlaybackStatus = playbackStatus;

  m_label->setMaxWidth(m_maxWidth * m_contentScale);
  m_label->setText(m_lastText);
  m_label->setColor(m_lastPlaybackStatus == "Playing"
                        ? widgetForegroundOr(roleColor(ColorRole::OnSurface))
                        : roleColor(ColorRole::OnSurfaceVariant));
  m_label->measure(renderer);

  if (artChanged) {
    std::string artPath = resolveArtworkPath();
    if (artPath.empty() && isRemoteArtUrl(m_lastArtUrl)) {
      const auto cached = artCachePath(m_lastArtUrl);
      std::error_code ec;
      if (std::filesystem::exists(cached, ec) && std::filesystem::file_size(cached, ec) > 0) {
        artPath = cached.string();
      } else if (m_httpClient != nullptr && m_pendingArtDownloads.find(m_lastArtUrl) == m_pendingArtDownloads.end()) {
        std::filesystem::create_directories(cached.parent_path(), ec);
        m_pendingArtDownloads.insert(m_lastArtUrl);
        m_httpClient->download(m_lastArtUrl, cached, [this, url = m_lastArtUrl](bool success) {
          m_pendingArtDownloads.erase(url);
          if (success && url == m_lastArtUrl) {
            requestRedraw();
          }
        });
      }
    }

    if (!artPath.empty()) {
      if (!m_art->setSourceFile(renderer, artPath, static_cast<int>(std::round(64.0f * m_contentScale)), true)) {
        kLog.warn("artwork load failed url=\"{}\" path=\"{}\"", m_lastArtUrl, artPath);
        m_art->clear(renderer);
      } else {
        kLog.debug("artwork loaded url=\"{}\" path=\"{}\"", m_lastArtUrl, artPath);
      }
    } else {
      if (!m_lastArtUrl.empty()) {
        kLog.debug("artwork unresolved url=\"{}\"", m_lastArtUrl);
      }
      m_art->clear(renderer);
    }
  } else if (!m_lastArtUrl.empty() && !m_art->hasImage()) {
    std::string artPath = resolveArtworkPath();
    if (artPath.empty() && isRemoteArtUrl(m_lastArtUrl)) {
      const auto cached = artCachePath(m_lastArtUrl);
      std::error_code ec;
      if (std::filesystem::exists(cached, ec) && std::filesystem::file_size(cached, ec) > 0) {
        artPath = cached.string();
      }
    }
    if (!artPath.empty()) {
      if (m_art->setSourceFile(renderer, artPath, static_cast<int>(std::round(64.0f * m_contentScale)))) {
        requestRedraw();
      }
    }
  }

  requestRedraw();
}

std::string MediaWidget::buildDisplayText(const MprisPlayerInfo& player) {
  const std::string artists = joinArtists(player.artists);
  if (!player.title.empty() && !artists.empty()) {
    return player.title + " - " + artists;
  }
  if (!player.title.empty()) {
    return player.title;
  }
  if (!artists.empty()) {
    return artists;
  }
  if (!player.identity.empty()) {
    return player.identity;
  }
  if (!player.busName.empty()) {
    return player.busName;
  }
  if (player.playbackStatus == "Playing") {
    return "Playing";
  }
  return "Nothing playing";
}

std::string MediaWidget::resolveArtworkPath() const { return normalizeArtPath(m_lastArtUrl); }
