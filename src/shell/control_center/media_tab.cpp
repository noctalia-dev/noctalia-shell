#include "shell/control_center/media_tab.h"

#include "dbus/mpris/mpris_service.h"
#include "net/http_client.h"
#include "pipewire/pipewire_service.h"
#include "render/core/renderer.h"
#include "shell/panel/panel_manager.h"
#include "shell/control_center/common.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/controls/select.h"
#include "ui/controls/slider.h"

#include <algorithm>
#include <filesystem>
#include <cmath>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

using namespace control_center;

namespace {

constexpr float kArtworkSize = Style::controlHeightLg * 6;
constexpr float kMediaColumnWidth = Style::controlHeightLg * 11;
constexpr float kAudioColumnWidth = Style::controlHeightLg * 11;

bool isRemoteArtUrl(std::string_view artUrl) {
  return artUrl.starts_with("https://") || artUrl.starts_with("http://");
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
  }
  return path;
}

std::filesystem::path artCachePath(std::string_view artUrl) {
  const std::filesystem::path cacheDir = std::filesystem::path("/tmp") / "noctalia-media-art";
  const std::size_t hash = std::hash<std::string_view>{}(artUrl);
  return cacheDir / (std::to_string(hash) + ".img");
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

std::string playPauseGlyph(const std::string& playbackStatus) {
  return playbackStatus == "Playing" ? "media-pause" : "media-play";
}

std::string repeatGlyph(const std::string& loopStatus) {
  return loopStatus == "Track" ? "repeat-once" : "repeat";
}

ButtonVariant toggleVariant(bool active) { return active ? ButtonVariant::Accent : ButtonVariant::Ghost; }

std::vector<AudioNode> sortedAudioDevices(const std::vector<AudioNode>& devices) {
  std::vector<AudioNode> sorted = devices;
  std::ranges::sort(sorted, [](const AudioNode& a, const AudioNode& b) {
    const std::string& left = !a.description.empty() ? a.description : a.name;
    const std::string& right = !b.description.empty() ? b.description : b.name;
    if (left != right) {
      return left < right;
    }
    return a.id < b.id;
  });
  return sorted;
}

const AudioNode* findAudioNodeById(const std::vector<AudioNode>& devices, std::uint32_t id) {
  const auto it = std::ranges::find(devices, id, &AudioNode::id);
  return it != devices.end() ? &(*it) : nullptr;
}

} // namespace

MediaTab::MediaTab(MprisService* mpris, PipeWireService* audio, HttpClient* httpClient)
    : m_mpris(mpris), m_audio(audio), m_httpClient(httpClient) {}

std::unique_ptr<Flex> MediaTab::build(Renderer& /*renderer*/) {
  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Horizontal);
  tab->setAlign(FlexAlign::Start);
  tab->setGap(Style::spaceMd);

  auto mediaColumn = std::make_unique<Flex>();
  mediaColumn->setDirection(FlexDirection::Vertical);
  mediaColumn->setAlign(FlexAlign::Start);
  mediaColumn->setGap(0.0f);
  mediaColumn->setMinWidth(kMediaColumnWidth);
  m_column = mediaColumn.get();

  auto nowCard = std::make_unique<Flex>();
  applyCard(*nowCard);
  nowCard->setAlign(FlexAlign::Center);
  nowCard->setGap(Style::spaceMd);
  nowCard->setMinWidth(kMediaColumnWidth);
  nowCard->setMinHeight(kMediaNowCardMinHeight);
  m_nowCard = nowCard.get();

  auto artwork = std::make_unique<Image>();
  artwork->setCornerRadius(Style::radiusLg);
  artwork->setBackground(alphaSurfaceVariant(0.95f));
  artwork->setFit(ImageFit::Contain);
  artwork->setSize(kArtworkSize, kArtworkSize);
  m_artwork = artwork.get();
  nowCard->addChild(std::move(artwork));

  auto title = std::make_unique<Label>();
  title->setText("Nothing playing");
  title->setBold(true);
  title->setFontSize(Style::fontSizeTitle);
  title->setColor(palette.onSurface);
  title->setMaxWidth(kMediaColumnWidth - Style::spaceMd * 2);
  m_trackTitle = title.get();
  nowCard->addChild(std::move(title));

  auto artist = std::make_unique<Label>();
  artist->setText("Start playback in an MPRIS app");
  artist->setColor(palette.onSurfaceVariant);
  artist->setMaxWidth(kMediaColumnWidth - Style::spaceMd * 2);
  m_trackArtist = artist.get();
  nowCard->addChild(std::move(artist));

  auto album = std::make_unique<Label>();
  album->setText(" ");
  album->setCaptionStyle();
  album->setColor(palette.onSurfaceVariant);
  album->setMaxWidth(kMediaColumnWidth - Style::spaceMd * 2);
  m_trackAlbum = album.get();
  nowCard->addChild(std::move(album));

  auto progress = std::make_unique<Slider>();
  progress->setRange(0.0f, 100.0f);
  progress->setStep(1.0f);
  progress->setSize(kMediaColumnWidth - Style::spaceMd * 2, 0.0f);
  progress->setOnValueChanged([this](float value) {
    if (m_syncingProgress || m_mpris == nullptr) {
      return;
    }
    const auto active = m_mpris->activePlayer();
    const std::int64_t targetUs = static_cast<std::int64_t>(std::llround(value * 1000000.0f));
    if (active.has_value()) {
      m_pendingSeekBusName = active->busName;
      m_pendingSeekUs = targetUs;
      m_pendingSeekUntil = std::chrono::steady_clock::now() + std::chrono::milliseconds(1500);
    }
    m_mpris->setPositionActive(targetUs);
  });
  m_progressSlider = progress.get();
  nowCard->addChild(std::move(progress));

  auto controls = std::make_unique<Flex>();
  controls->setDirection(FlexDirection::Horizontal);
  controls->setAlign(FlexAlign::Center);
  controls->setGap(Style::spaceSm);

  auto repeat = std::make_unique<Button>();
  repeat->setGlyph("repeat");
  repeat->setVariant(ButtonVariant::Ghost);
  repeat->setMinimalChrome(true);
  repeat->setMinWidth(kMediaControlsHeight);
  repeat->setMinHeight(kMediaControlsHeight);
  repeat->setOnClick([this]() {
    if (m_mpris == nullptr) {
      return;
    }
    const auto current = m_mpris->loopStatusActive().value_or("None");
    const std::string next = current == "None" ? "Playlist" : (current == "Playlist" ? "Track" : "None");
    m_mpris->setLoopStatusActive(next);
    PanelManager::instance().refresh();
  });
  m_repeatButton = repeat.get();
  controls->addChild(std::move(repeat));

  auto previous = std::make_unique<Button>();
  previous->setGlyph("media-prev");
  previous->setVariant(ButtonVariant::Ghost);
  previous->setMinimalChrome(true);
  previous->setMinWidth(kMediaControlsHeight);
  previous->setMinHeight(kMediaControlsHeight);
  previous->setOnClick([this]() {
    if (m_mpris != nullptr) {
      m_mpris->previousActive();
      PanelManager::instance().refresh();
    }
  });
  m_prevButton = previous.get();
  controls->addChild(std::move(previous));

  auto playPause = std::make_unique<Button>();
  playPause->setGlyph("media-play");
  playPause->setVariant(ButtonVariant::Accent);
  playPause->setMinimalChrome(true);
  playPause->setMinWidth(kMediaPlayPauseHeight);
  playPause->setMinHeight(kMediaPlayPauseHeight);
  playPause->setOnClick([this]() {
    if (m_mpris != nullptr) {
      m_mpris->playPauseActive();
      PanelManager::instance().refresh();
    }
  });
  m_playPauseButton = playPause.get();
  controls->addChild(std::move(playPause));

  auto next = std::make_unique<Button>();
  next->setGlyph("media-next");
  next->setVariant(ButtonVariant::Ghost);
  next->setMinimalChrome(true);
  next->setMinWidth(kMediaControlsHeight);
  next->setMinHeight(kMediaControlsHeight);
  next->setOnClick([this]() {
    if (m_mpris != nullptr) {
      m_mpris->nextActive();
      PanelManager::instance().refresh();
    }
  });
  m_nextButton = next.get();
  controls->addChild(std::move(next));

  auto shuffle = std::make_unique<Button>();
  shuffle->setGlyph("shuffle");
  shuffle->setVariant(ButtonVariant::Ghost);
  shuffle->setMinimalChrome(true);
  shuffle->setMinWidth(kMediaControlsHeight);
  shuffle->setMinHeight(kMediaControlsHeight);
  shuffle->setOnClick([this]() {
    if (m_mpris != nullptr) {
      const bool enabled = m_mpris->shuffleActive().value_or(false);
      m_mpris->setShuffleActive(!enabled);
      PanelManager::instance().refresh();
    }
  });
  m_shuffleButton = shuffle.get();
  controls->addChild(std::move(shuffle));

  nowCard->addChild(std::move(controls));

  auto playerSelect = std::make_unique<Select>();
  playerSelect->setPlaceholder("Active player");
  playerSelect->setSize(kMediaColumnWidth - Style::spaceMd * 2, 0.0f);
  playerSelect->setOnSelectionChanged([this](std::size_t index, std::string_view /*text*/) {
    if (m_syncingPlayerSelect || m_mpris == nullptr) {
      return;
    }
    if (index == 0) {
      m_mpris->clearPinnedPlayerPreference();
    } else if (index - 1 < m_playerBusNames.size()) {
      m_mpris->setPinnedPlayerPreference(m_playerBusNames[index - 1]);
    }
    PanelManager::instance().refresh();
  });
  m_playerSelect = playerSelect.get();
  nowCard->addChild(std::move(playerSelect));

  mediaColumn->addChild(std::move(nowCard));

  auto audioColumn = std::make_unique<Flex>();
  audioColumn->setDirection(FlexDirection::Vertical);
  audioColumn->setAlign(FlexAlign::Start);
  audioColumn->setGap(Style::spaceSm);
  audioColumn->setMinWidth(kAudioColumnWidth);
  m_audioColumn = audioColumn.get();

  auto outputCard = std::make_unique<Flex>();
  applyCard(*outputCard);
  outputCard->setMinWidth(kAudioColumnWidth);
  outputCard->setMinHeight(kMediaAudioCardMinHeight);
  m_outputCard = outputCard.get();
  addTitle(*outputCard, "Output");

  auto outputDeviceSelect = std::make_unique<Select>();
  outputDeviceSelect->setPlaceholder("Select output device");
  outputDeviceSelect->setSize(kAudioColumnWidth - Style::spaceMd * 2, 0.0f);
  outputDeviceSelect->setOnSelectionChanged([this](std::size_t index, std::string_view /*text*/) {
    if (m_syncingOutputSelect || m_audio == nullptr || index >= m_outputDeviceIds.size()) {
      return;
    }
    m_audio->setDefaultSink(m_outputDeviceIds[index]);
    PanelManager::instance().refresh();
  });
  m_outputDeviceSelect = outputDeviceSelect.get();
  outputCard->addChild(std::move(outputDeviceSelect));

  auto outputRow = std::make_unique<Flex>();
  outputRow->setDirection(FlexDirection::Horizontal);
  outputRow->setAlign(FlexAlign::Center);
  outputRow->setGap(Style::spaceSm);

  auto outputSlider = std::make_unique<Slider>();
  outputSlider->setRange(0.0f, 150.0f);
  outputSlider->setStep(1.0f);
  outputSlider->setSize(kMediaSliderWidth, 0.0f);
  outputSlider->setOnValueChanged([this](float value) {
    if (m_syncingOutputSlider) {
      return;
    }
    if (m_audio != nullptr) {
      std::uint32_t sinkId = m_audio->state().defaultSinkId;
      if (m_outputDeviceSelect != nullptr && m_outputDeviceSelect->selectedIndex() < m_outputDeviceIds.size()) {
        sinkId = m_outputDeviceIds[m_outputDeviceSelect->selectedIndex()];
      }
      if (sinkId != 0) {
        m_audio->setSinkVolume(sinkId, value / 100.0f);
      }
    }
    if (m_outputValue != nullptr) {
      m_outputValue->setText(std::to_string(static_cast<int>(std::round(value))) + "%");
    }
  });
  m_outputSlider = outputSlider.get();
  outputRow->addChild(std::move(outputSlider));

  auto outputLabel = std::make_unique<Label>();
  outputLabel->setText("0%");
  outputLabel->setBold(true);
  outputLabel->setMinWidth(kValueLabelWidth);
  m_outputValue = outputLabel.get();
  outputRow->addChild(std::move(outputLabel));
  outputCard->addChild(std::move(outputRow));
  audioColumn->addChild(std::move(outputCard));

  auto inputCard = std::make_unique<Flex>();
  applyCard(*inputCard);
  inputCard->setMinWidth(kAudioColumnWidth);
  inputCard->setMinHeight(kMediaAudioCardMinHeight);
  m_inputCard = inputCard.get();
  addTitle(*inputCard, "Input");

  auto inputDeviceSelect = std::make_unique<Select>();
  inputDeviceSelect->setPlaceholder("Select input device");
  inputDeviceSelect->setSize(kAudioColumnWidth - Style::spaceMd * 2, 0.0f);
  inputDeviceSelect->setOnSelectionChanged([this](std::size_t index, std::string_view /*text*/) {
    if (m_syncingInputSelect || m_audio == nullptr || index >= m_inputDeviceIds.size()) {
      return;
    }
    m_audio->setDefaultSource(m_inputDeviceIds[index]);
    PanelManager::instance().refresh();
  });
  m_inputDeviceSelect = inputDeviceSelect.get();
  inputCard->addChild(std::move(inputDeviceSelect));

  auto inputRow = std::make_unique<Flex>();
  inputRow->setDirection(FlexDirection::Horizontal);
  inputRow->setAlign(FlexAlign::Center);
  inputRow->setGap(Style::spaceSm);

  auto inputSlider = std::make_unique<Slider>();
  inputSlider->setRange(0.0f, 150.0f);
  inputSlider->setStep(1.0f);
  inputSlider->setSize(kMediaSliderWidth, 0.0f);
  inputSlider->setOnValueChanged([this](float value) {
    if (m_syncingInputSlider) {
      return;
    }
    if (m_audio != nullptr) {
      std::uint32_t sourceId = m_audio->state().defaultSourceId;
      if (m_inputDeviceSelect != nullptr && m_inputDeviceSelect->selectedIndex() < m_inputDeviceIds.size()) {
        sourceId = m_inputDeviceIds[m_inputDeviceSelect->selectedIndex()];
      }
      if (sourceId != 0) {
        m_audio->setSourceVolume(sourceId, value / 100.0f);
      }
    }
    if (m_inputValue != nullptr) {
      m_inputValue->setText(std::to_string(static_cast<int>(std::round(value))) + "%");
    }
  });
  m_inputSlider = inputSlider.get();
  inputRow->addChild(std::move(inputSlider));

  auto inputLabel = std::make_unique<Label>();
  inputLabel->setText("0%");
  inputLabel->setBold(true);
  inputLabel->setMinWidth(kValueLabelWidth);
  m_inputValue = inputLabel.get();
  inputRow->addChild(std::move(inputLabel));
  inputCard->addChild(std::move(inputRow));
  audioColumn->addChild(std::move(inputCard));

  tab->addChild(std::move(mediaColumn));
  tab->addChild(std::move(audioColumn));

  return tab;
}

void MediaTab::layout(Renderer& renderer, float contentWidth, float bodyHeight) {
  const float mediaGap = Style::spaceMd;
  const float leftPreferred = std::clamp(contentWidth * 0.48f, 260.0f, 360.0f);
  const float rightWidth = std::max(220.0f, contentWidth - leftPreferred - mediaGap);
  const float leftWidth = std::max(220.0f, contentWidth - rightWidth - mediaGap);
  const float leftInnerWidth = std::max(0.0f, leftWidth - Style::spaceMd * 2);
  const float rightInnerWidth = std::max(0.0f, rightWidth - Style::spaceMd * 2);

  if (m_column != nullptr) {
    m_column->setMinWidth(leftWidth);
    m_column->setSize(leftWidth, bodyHeight);
  }
  if (m_nowCard != nullptr) {
    m_nowCard->setMinWidth(leftWidth);
    m_nowCard->setMinHeight(std::max(kMediaNowCardMinHeight, bodyHeight));
  }
  if (m_audioColumn != nullptr) {
    m_audioColumn->setMinWidth(rightWidth);
    m_audioColumn->setSize(rightWidth, bodyHeight);
  }
  if (m_outputCard != nullptr) {
    m_outputCard->setMinWidth(rightWidth);
    m_outputCard->setMinHeight(kMediaAudioCardMinHeight);
  }
  if (m_inputCard != nullptr) {
    m_inputCard->setMinWidth(rightWidth);
    m_inputCard->setMinHeight(kMediaAudioCardMinHeight);
  }
  if (m_playerSelect != nullptr) {
    m_playerSelect->setSize(leftInnerWidth, 0.0f);
  }
  if (m_outputDeviceSelect != nullptr) {
    m_outputDeviceSelect->setSize(rightInnerWidth, 0.0f);
  }
  if (m_inputDeviceSelect != nullptr) {
    m_inputDeviceSelect->setSize(rightInnerWidth, 0.0f);
  }

  if (m_artwork != nullptr) {
    const float mediaArtworkSize = std::min(leftInnerWidth, Style::controlHeightLg * 6);
    const float mediaMetaHeight = Style::fontSizeTitle + Style::fontSizeBody +
                                 Style::fontSizeCaption + Style::spaceMd * 2;
    const float aspectRatio = m_artwork->hasImage() ? m_artwork->aspectRatio() : 1.0f;
    const bool wideArtwork = aspectRatio > 1.15f;
    const float mediaReservedHeight =
        kMediaPlayerSelectHeight + kMediaPlayPauseHeight + Style::controlHeight +
        mediaMetaHeight + Style::spaceMd * 5;
    const float artworkMaxHeight = std::max(kMediaArtworkMinHeight, bodyHeight - mediaReservedHeight);

    float artworkWidth = mediaArtworkSize;
    float artworkHeight = mediaArtworkSize;
    if (wideArtwork) {
      artworkWidth = leftInnerWidth;
      artworkHeight = std::min(artworkMaxHeight, artworkWidth / aspectRatio);
    } else if (aspectRatio < 0.9f) {
      artworkHeight = std::min(artworkMaxHeight, leftInnerWidth);
      artworkWidth = std::min(leftInnerWidth, artworkHeight * aspectRatio);
    } else {
      const float squareSize = std::min(leftInnerWidth, artworkMaxHeight);
      artworkWidth = squareSize;
      artworkHeight = squareSize;
    }

    m_artwork->setSize(std::max(0.0f, artworkWidth), std::max(0.0f, artworkHeight));

    const float sideButtonSize = kMediaControlsHeight;
    const float playPauseButtonSize = kMediaPlayPauseHeight;
    const float sideGlyphSize = Style::fontSizeTitle;
    const float playPauseGlyphSize = Style::fontSizeTitle + Style::spaceXs;

    for (auto* button : {m_repeatButton, m_prevButton, m_nextButton, m_shuffleButton}) {
      if (button != nullptr) {
        button->setMinWidth(sideButtonSize);
        button->setMinHeight(sideButtonSize);
        button->setGlyphSize(sideGlyphSize);
        button->layout(renderer);
        button->updateInputArea();
      }
    }
    if (m_playPauseButton != nullptr) {
      m_playPauseButton->setMinWidth(playPauseButtonSize);
      m_playPauseButton->setMinHeight(playPauseButtonSize);
      m_playPauseButton->setGlyphSize(playPauseGlyphSize);
      m_playPauseButton->layout(renderer);
      m_playPauseButton->updateInputArea();
    }
  }

  if (m_trackTitle != nullptr) {
    m_trackTitle->setMaxWidth(leftInnerWidth);
    m_trackTitle->measure(renderer);
  }
  if (m_trackArtist != nullptr) {
    m_trackArtist->setMaxWidth(leftInnerWidth);
    m_trackArtist->measure(renderer);
  }
  if (m_trackAlbum != nullptr) {
    m_trackAlbum->setMaxWidth(leftInnerWidth);
    m_trackAlbum->measure(renderer);
  }
  if (m_progressSlider != nullptr) {
    m_progressSlider->setSize(leftInnerWidth, 0.0f);
    m_progressSlider->layout(renderer);
  }
  if (m_outputSlider != nullptr) {
    m_outputSlider->setSize(std::max(120.0f, rightInnerWidth - kValueLabelWidth - Style::spaceSm), 0.0f);
    m_outputSlider->layout(renderer);
  }
  if (m_inputSlider != nullptr) {
    m_inputSlider->setSize(std::max(120.0f, rightInnerWidth - kValueLabelWidth - Style::spaceSm), 0.0f);
    m_inputSlider->layout(renderer);
  }
  if (m_outputValue != nullptr) {
    m_outputValue->measure(renderer);
  }
  if (m_inputValue != nullptr) {
    m_inputValue->measure(renderer);
  }
}

void MediaTab::update(Renderer& renderer) {
  refresh(renderer);
}

void MediaTab::onClose() {
  m_artwork = nullptr;
  m_column = nullptr;
  m_nowCard = nullptr;
  m_audioColumn = nullptr;
  m_outputCard = nullptr;
  m_inputCard = nullptr;
  m_trackTitle = nullptr;
  m_trackArtist = nullptr;
  m_trackAlbum = nullptr;
  m_progressSlider = nullptr;
  m_playerSelect = nullptr;
  m_outputDeviceSelect = nullptr;
  m_inputDeviceSelect = nullptr;
  m_prevButton = nullptr;
  m_playPauseButton = nullptr;
  m_nextButton = nullptr;
  m_repeatButton = nullptr;
  m_shuffleButton = nullptr;
  m_outputSlider = nullptr;
  m_outputValue = nullptr;
  m_inputSlider = nullptr;
  m_inputValue = nullptr;
  m_lastArtPath.clear();
  m_lastBusName.clear();
  m_lastPlaybackStatus.clear();
  m_lastLoopStatus.clear();
  m_playerBusNames.clear();
  m_outputDeviceIds.clear();
  m_inputDeviceIds.clear();
  m_pendingSeekBusName.clear();
  m_pendingSeekUs = -1;
  m_lastSinkVolume = -1.0f;
  m_lastSourceVolume = -1.0f;
}

void MediaTab::clearArt(Renderer& renderer) {
  if (m_artwork != nullptr) {
    m_artwork->clear(renderer);
  }
}

void MediaTab::refresh(Renderer& renderer) {
  if (m_mpris != nullptr && m_playerSelect != nullptr) {
    const auto players = m_mpris->listPlayers();
    std::vector<std::string> playerLabels;
    std::vector<std::string> playerBusNames;
    playerLabels.reserve(players.size() + 1);
    playerBusNames.reserve(players.size());
    std::size_t selectedPlayerIndex = 0;

    const auto active = m_mpris->activePlayer();
    const std::string activeBusName = active.has_value() ? active->busName : std::string{};
    const auto pinnedBusName = m_mpris->pinnedPlayerPreference();

    playerLabels.push_back("Active player");

    for (std::size_t i = 0; i < players.size(); ++i) {
      const auto& player = players[i];
      playerBusNames.push_back(player.busName);
      playerLabels.push_back(player.identity.empty() ? player.busName : player.identity);
      if (pinnedBusName.has_value() && player.busName == *pinnedBusName) {
        selectedPlayerIndex = i + 1;
      }
    }

    m_playerBusNames = std::move(playerBusNames);
    m_syncingPlayerSelect = true;
    m_playerSelect->setOptions(std::move(playerLabels));
    m_playerSelect->setEnabled(!m_playerBusNames.empty());
    if (!m_playerBusNames.empty()) {
      m_playerSelect->setSelectedIndex(selectedPlayerIndex);
    }
    m_syncingPlayerSelect = false;
  }

  if (m_trackTitle != nullptr && m_trackArtist != nullptr && m_progressSlider != nullptr &&
      m_playPauseButton != nullptr && m_repeatButton != nullptr && m_shuffleButton != nullptr) {
    const auto active = m_mpris != nullptr ? m_mpris->activePlayer() : std::nullopt;
    if (active.has_value()) {
      const auto& player = *active;
      const auto now = std::chrono::steady_clock::now();
      const bool seekPending =
          !m_pendingSeekBusName.empty() && m_pendingSeekBusName == player.busName &&
          now < m_pendingSeekUntil && m_pendingSeekUs >= 0;
      const bool seekReached =
          seekPending && std::llabs(player.positionUs - m_pendingSeekUs) <= 1500000;
      const std::int64_t displayPositionUs = seekPending && !seekReached ? m_pendingSeekUs : player.positionUs;
      if (!seekPending || seekReached) {
        m_pendingSeekBusName.clear();
        m_pendingSeekUs = -1;
      }

      m_trackTitle->setText(player.title.empty() ? player.identity : player.title);
      m_trackTitle->measure(renderer);
      m_trackArtist->setText(joinArtists(player.artists).empty() ? player.identity : joinArtists(player.artists));
      m_trackArtist->measure(renderer);
      if (m_trackAlbum != nullptr) {
        m_trackAlbum->setText(player.album.empty() ? " " : player.album);
        m_trackAlbum->measure(renderer);
      }

      std::string artPath = normalizeArtPath(player.artUrl);
      if (artPath.empty() && isRemoteArtUrl(player.artUrl)) {
        const auto cached = artCachePath(player.artUrl);
        std::error_code ec;
        if (std::filesystem::exists(cached, ec) && std::filesystem::file_size(cached, ec) > 0) {
          artPath = cached.string();
        } else if (m_httpClient != nullptr &&
                   m_pendingArtDownloads.find(player.artUrl) == m_pendingArtDownloads.end()) {
          std::filesystem::create_directories(cached.parent_path(), ec);
          m_pendingArtDownloads.insert(player.artUrl);
          m_httpClient->download(player.artUrl, cached,
              [this, url = player.artUrl](bool success) {
                m_pendingArtDownloads.erase(url);
                if (success) {
                  m_lastArtPath.clear();
                  PanelManager::instance().refresh();
                }
              });
        }
      }

      if (m_artwork != nullptr && player.artUrl != m_lastArtPath) {
        if (artPath.empty()) {
          clearArt(renderer);
        } else if (!m_artwork->setSourceFile(renderer, artPath, static_cast<int>(kArtworkSize))) {
          clearArt(renderer);
        }
        m_lastArtPath = player.artUrl;
      }

      m_syncingProgress = true;
      m_progressSlider->setEnabled(player.canSeek && player.lengthUs > 0);
      m_progressSlider->setRange(0.0f, std::max(1.0f, static_cast<float>(player.lengthUs) / 1000000.0f));
      m_progressSlider->setValue(static_cast<float>(displayPositionUs) / 1000000.0f);
      m_syncingProgress = false;

      m_playPauseButton->setGlyph(playPauseGlyph(player.playbackStatus));
      m_playPauseButton->setVariant(ButtonVariant::Accent);
      if (m_prevButton != nullptr) { m_prevButton->setEnabled(player.canGoPrevious); }
      if (m_nextButton != nullptr) { m_nextButton->setEnabled(player.canGoNext); }
      m_repeatButton->setGlyph(repeatGlyph(player.loopStatus));
      m_repeatButton->setVariant(toggleVariant(player.loopStatus != "None"));
      m_shuffleButton->setVariant(toggleVariant(player.shuffle));

      m_lastBusName = player.busName;
      m_lastPlaybackStatus = player.playbackStatus;
      m_lastLoopStatus = player.loopStatus;
      m_lastShuffle = player.shuffle;
    } else {
      m_pendingSeekBusName.clear();
      m_pendingSeekUs = -1;
      m_trackTitle->setText("Nothing playing");
      m_trackTitle->measure(renderer);
      m_trackArtist->setText("Start playback in an MPRIS app");
      m_trackArtist->measure(renderer);
      if (m_trackAlbum != nullptr) {
        m_trackAlbum->setText(" ");
        m_trackAlbum->measure(renderer);
      }
      clearArt(renderer);
      m_lastArtPath.clear();
      m_syncingProgress = true;
      m_progressSlider->setEnabled(false);
      m_progressSlider->setRange(0.0f, 100.0f);
      m_progressSlider->setValue(0.0f);
      m_syncingProgress = false;
      m_playPauseButton->setGlyph("media-play");
      if (m_prevButton != nullptr) { m_prevButton->setEnabled(false); }
      if (m_nextButton != nullptr) { m_nextButton->setEnabled(false); }
      m_repeatButton->setGlyph("repeat");
      m_repeatButton->setVariant(ButtonVariant::Ghost);
      m_shuffleButton->setVariant(ButtonVariant::Ghost);
      m_lastBusName.clear();
      m_lastPlaybackStatus.clear();
      m_lastLoopStatus.clear();
      m_lastShuffle = false;
    }
  }

  if (m_audio != nullptr) {
    // Output devices
    if (m_outputDeviceSelect != nullptr) {
      const auto sortedSinks = sortedAudioDevices(m_audio->state().sinks);
      std::vector<std::string> outputLabels;
      std::vector<std::uint32_t> outputIds;
      outputLabels.reserve(sortedSinks.size());
      outputIds.reserve(sortedSinks.size());
      std::size_t selectedOutputIndex = 0;
      for (std::size_t i = 0; i < sortedSinks.size(); ++i) {
        const auto& device = sortedSinks[i];
        outputLabels.push_back(!device.description.empty() ? device.description : device.name);
        outputIds.push_back(device.id);
        if (device.isDefault) {
          selectedOutputIndex = i;
        }
      }
      m_outputDeviceIds = std::move(outputIds);
      m_syncingOutputSelect = true;
      m_outputDeviceSelect->setOptions(std::move(outputLabels));
      m_outputDeviceSelect->setEnabled(!m_outputDeviceIds.empty());
      if (!m_outputDeviceIds.empty()) {
        m_outputDeviceSelect->setSelectedIndex(selectedOutputIndex);
      }
      m_syncingOutputSelect = false;
    }

    // Input devices
    if (m_inputDeviceSelect != nullptr) {
      const auto sortedSources = sortedAudioDevices(m_audio->state().sources);
      std::vector<std::string> inputLabels;
      std::vector<std::uint32_t> inputIds;
      inputLabels.reserve(sortedSources.size());
      inputIds.reserve(sortedSources.size());
      std::size_t selectedInputIndex = 0;
      for (std::size_t i = 0; i < sortedSources.size(); ++i) {
        const auto& device = sortedSources[i];
        inputLabels.push_back(!device.description.empty() ? device.description : device.name);
        inputIds.push_back(device.id);
        if (device.isDefault) {
          selectedInputIndex = i;
        }
      }
      m_inputDeviceIds = std::move(inputIds);
      m_syncingInputSelect = true;
      m_inputDeviceSelect->setOptions(std::move(inputLabels));
      m_inputDeviceSelect->setEnabled(!m_inputDeviceIds.empty());
      if (!m_inputDeviceIds.empty()) {
        m_inputDeviceSelect->setSelectedIndex(selectedInputIndex);
      }
      m_syncingInputSelect = false;
    }

    // Volume sliders
    constexpr std::size_t kInvalidIndex = static_cast<std::size_t>(-1);
    const auto outputIndex =
        (m_outputDeviceSelect != nullptr && m_outputDeviceSelect->selectedIndex() < m_outputDeviceIds.size())
            ? m_outputDeviceSelect->selectedIndex()
            : kInvalidIndex;
    const auto inputIndex =
        (m_inputDeviceSelect != nullptr && m_inputDeviceSelect->selectedIndex() < m_inputDeviceIds.size())
            ? m_inputDeviceSelect->selectedIndex()
            : kInvalidIndex;

    const std::uint32_t sinkId =
        outputIndex != kInvalidIndex ? m_outputDeviceIds[outputIndex] : m_audio->state().defaultSinkId;
    const std::uint32_t sourceId =
        inputIndex != kInvalidIndex ? m_inputDeviceIds[inputIndex] : m_audio->state().defaultSourceId;

    const auto* sink = findAudioNodeById(m_audio->state().sinks, sinkId);
    const auto* source = findAudioNodeById(m_audio->state().sources, sourceId);
    const float sinkVolume = sink != nullptr ? sink->volume * 100.0f : 0.0f;
    const float sourceVolume = source != nullptr ? source->volume * 100.0f : 0.0f;

    if (m_outputSlider != nullptr) {
      m_outputSlider->setEnabled(sink != nullptr);
      if (!m_outputSlider->dragging() && std::abs(sinkVolume - m_lastSinkVolume) >= 0.5f) {
        m_syncingOutputSlider = true;
        m_outputSlider->setValue(sinkVolume);
        m_syncingOutputSlider = false;
        if (m_outputValue != nullptr) {
          m_outputValue->setText(std::to_string(static_cast<int>(std::round(sinkVolume))) + "%");
          m_outputValue->measure(renderer);
        }
        m_lastSinkVolume = sinkVolume;
      }
    }

    if (m_inputSlider != nullptr) {
      m_inputSlider->setEnabled(source != nullptr);
      if (!m_inputSlider->dragging() && std::abs(sourceVolume - m_lastSourceVolume) >= 0.5f) {
        m_syncingInputSlider = true;
        m_inputSlider->setValue(sourceVolume);
        m_syncingInputSlider = false;
        if (m_inputValue != nullptr) {
          m_inputValue->setText(std::to_string(static_cast<int>(std::round(sourceVolume))) + "%");
          m_inputValue->measure(renderer);
        }
        m_lastSourceVolume = sourceVolume;
      }
    }
  } else {
    if (m_outputSlider != nullptr) {
      m_outputSlider->setEnabled(false);
    }
    if (m_inputSlider != nullptr) {
      m_inputSlider->setEnabled(false);
    }
  }
}
