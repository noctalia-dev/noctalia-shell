#include "shell/desktop/widgets/desktop_media_player_widget.h"

#include "dbus/mpris/mpris_art.h"
#include "dbus/mpris/mpris_service.h"
#include "i18n/i18n.h"
#include "net/http_client.h"
#include "render/core/renderer.h"
#include "render/scene/node.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <cmath>
#include <filesystem>

using namespace mpris;

namespace {

  constexpr float kArtSize = 120.0f;
  constexpr float kControlSize = 32.0f;
  constexpr float kPlayPauseSize = 40.0f;
  constexpr float kSpacing = 6.0f;

} // namespace

namespace {

  constexpr float kShadowAlpha = 0.6f;
  constexpr float kShadowOffset = 1.5f;

} // namespace

DesktopMediaPlayerWidget::DesktopMediaPlayerWidget(MprisService* mpris, HttpClient* httpClient, bool vertical,
                                                   ThemeColor color, bool shadow)
    : m_mpris(mpris), m_httpClient(httpClient), m_vertical(vertical), m_color(std::move(color)), m_shadow(shadow) {}

void DesktopMediaPlayerWidget::create() {
  auto rootNode = std::make_unique<Node>();

  auto artwork = std::make_unique<Image>();
  artwork->setFit(ImageFit::Cover);
  artwork->setRadius(Style::radiusMd * contentScale());
  m_artwork = artwork.get();
  rootNode->addChild(std::move(artwork));

  auto title = std::make_unique<Label>();
  title->setBold(true);
  title->setMaxLines(1);
  title->setColor(m_color);
  m_title = title.get();
  rootNode->addChild(std::move(title));

  auto artist = std::make_unique<Label>();
  artist->setMaxLines(1);
  artist->setColor(m_color);
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
  applyShadow();
}

void DesktopMediaPlayerWidget::doLayout(Renderer& renderer) {
  if (root() == nullptr || m_artwork == nullptr || m_title == nullptr || m_artist == nullptr || m_controls == nullptr)
    return;

  sync(renderer);
  applyShadow();

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
  m_artwork->setRadius(Style::radiusMd * scale);
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
  m_artwork->setRadius(Style::radiusMd * scale);
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

  m_title->setText(m_lastTitle.empty() ? i18n::tr("desktop-widgets.media.nothing-playing") : m_lastTitle);
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

void DesktopMediaPlayerWidget::applyShadow() {
  if (m_title == nullptr || m_artist == nullptr) {
    return;
  }
  if (m_shadow) {
    const float offset = kShadowOffset * contentScale();
    const Color shadow(0.0f, 0.0f, 0.0f, kShadowAlpha);
    m_title->setShadow(shadow, offset, offset);
    m_artist->setShadow(shadow, offset, offset);
  } else {
    m_title->clearShadow();
    m_artist->clearShadow();
  }
}
