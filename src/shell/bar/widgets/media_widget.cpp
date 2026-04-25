#include "shell/bar/widgets/media_widget.h"

#include "core/log.h"
#include "dbus/mpris/mpris_art.h"
#include "dbus/mpris/mpris_service.h"
#include "net/http_client.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "ui/controls/glyph.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <filesystem>

using namespace mpris;

namespace {

  const Logger kLog{"media"};

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
  art->setRadius((m_artSize * m_contentScale) * 0.5f);
  art->setFill(roleColor(ColorRole::SurfaceVariant, 0.9f));
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

  auto emptyGlyph = std::make_unique<Glyph>();
  emptyGlyph->setGlyph("music-off");
  emptyGlyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  emptyGlyph->setColor(roleColor(ColorRole::OnSurfaceVariant));
  emptyGlyph->setVisible(false);
  m_emptyGlyph = emptyGlyph.get();
  area->addChild(std::move(emptyGlyph));

  setRoot(std::move(area));
}

void MediaWidget::doLayout(Renderer& renderer, float containerWidth, float containerHeight) {
  auto* rootNode = root();
  if (rootNode == nullptr || m_art == nullptr || m_label == nullptr || m_emptyGlyph == nullptr) {
    return;
  }
  syncState(renderer);

  const bool isVertical = containerHeight > containerWidth;

  m_label->setMaxWidth(m_maxWidth * m_contentScale);
  m_label->setColor(m_lastPlaybackStatus == "Playing" ? widgetForegroundOr(roleColor(ColorRole::OnSurface))
                                                      : roleColor(ColorRole::OnSurfaceVariant));
  m_label->measure(renderer);
  m_emptyGlyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  m_emptyGlyph->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_emptyGlyph->measure(renderer);

  const bool showArtSlot = isVertical ? m_art->hasImage() : (m_lastText != "Nothing playing");

  // Clamp art to the label's single-line height so oversized art_size cannot
  // distort the bar capsule. The bar uses a uniform cross-axis extent derived
  // from the same reference metrics.
  float artSize = 0.0f;
  if (showArtSlot) {
    artSize = std::min(m_artSize * m_contentScale, m_label->height());
    m_art->setVisible(true);
    m_art->setSize(artSize, artSize);
    m_art->setRadius(artSize * 0.5f);
  } else {
    m_art->setVisible(false);
    m_art->setSize(0.0f, 0.0f);
    m_art->setRadius(0.0f);
  }

  const float contentHeight = m_label->height();
  const float artY = showArtSlot ? std::round((contentHeight - artSize) * 0.5f) : 0.0f;

  const bool showEmptyGlyph = !showArtSlot;
  m_label->setVisible(!isVertical);
  m_emptyGlyph->setVisible(showEmptyGlyph);
  if (isVertical) {
    if (!showArtSlot) {
      m_art->setPosition(0.0f, 0.0f);
      m_emptyGlyph->setPosition(0.0f, 0.0f);
      rootNode->setSize(m_emptyGlyph->width(), m_emptyGlyph->height());
    } else {
      m_art->setPosition(0.0f, 0.0f);
      rootNode->setSize(artSize, artSize);
    }
  } else {
    const float emptyGlyphY = std::round((contentHeight - m_emptyGlyph->height()) * 0.5f);
    const bool showLabel = m_label->visible() && !m_label->text().empty();
    if (showArtSlot) {
      const float spacing = showLabel ? Style::spaceXs : 0.0f;
      m_art->setPosition(0.0f, artY);
      m_emptyGlyph->setPosition(0.0f, emptyGlyphY);
      m_label->setPosition(artSize + spacing, 0.0f);
    } else {
      const float spacing = showLabel ? Style::spaceXs : 0.0f;
      m_art->setPosition(0.0f, 0.0f);
      m_emptyGlyph->setPosition(0.0f, emptyGlyphY);
      m_label->setPosition(m_emptyGlyph->width() + spacing, 0.0f);
    }
    rootNode->setSize(m_label->x() + m_label->width(), contentHeight);
  }
}

void MediaWidget::doUpdate(Renderer& renderer) { syncState(renderer); }

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
  m_label->setColor(m_lastPlaybackStatus == "Playing" ? widgetForegroundOr(roleColor(ColorRole::OnSurface))
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
