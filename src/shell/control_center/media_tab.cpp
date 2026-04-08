#include "shell/control_center/media_tab.h"

#include "core/log.h"
#include "dbus/mpris/mpris_service.h"
#include "net/http_client.h"
#include "pipewire/pipewire_service.h"
#include "render/core/renderer.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/controls/select.h"
#include "ui/controls/slider.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <filesystem>
#include <format>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

using namespace control_center;

namespace {

  const Logger kLog{"media_tab"};

  constexpr float kArtworkSize = Style::controlHeightLg * 6;
  constexpr float kMediaColumnMinWidth = Style::controlHeightLg * 9;
  constexpr float kAudioColumnMinWidth = Style::controlHeightLg * 8;
  constexpr float kValueLabelWidth = Style::controlHeightLg + Style::spaceLg;
  constexpr float kMediaNowCardMinHeight = Style::controlHeightLg * 11 + Style::spaceSm * 2;
  constexpr float kMediaAudioCardMinHeight = Style::controlHeightLg * 3 + Style::spaceMd * 2;
  constexpr float kMediaControlsHeight = Style::controlHeightLg + Style::spaceXs;
  constexpr float kMediaPlayPauseHeight = Style::controlHeightLg + Style::spaceSm;
  constexpr float kMediaArtworkMinHeight = Style::controlHeightLg * 4;

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
      videoId =
          std::string(sourceUrl.substr(start, end == std::string_view::npos ? sourceUrl.size() - start : end - start));
    } else if (sourceUrl.find("youtube.com/shorts/") != std::string_view::npos) {
      const auto marker = sourceUrl.find("youtube.com/shorts/");
      const auto start = marker + std::string_view("youtube.com/shorts/").size();
      const auto end = sourceUrl.find_first_of("?#&/", start);
      videoId =
          std::string(sourceUrl.substr(start, end == std::string_view::npos ? sourceUrl.size() - start : end - start));
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

  std::string repeatGlyph(const std::string& loopStatus) { return loopStatus == "Track" ? "repeat-once" : "repeat"; }

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
  const float scale = contentScale();
  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Horizontal);
  tab->setAlign(FlexAlign::Stretch);
  tab->setGap(Style::spaceMd * scale);
  m_rootLayout = tab.get();

  auto mediaColumn = std::make_unique<Flex>();
  mediaColumn->setDirection(FlexDirection::Vertical);
  mediaColumn->setAlign(FlexAlign::Stretch);
  mediaColumn->setGap(Style::spaceSm * scale);
  mediaColumn->setFlexGrow(3.0f);
  mediaColumn->setMinWidth(kMediaColumnMinWidth * scale);
  m_column = mediaColumn.get();

  auto nowCard = std::make_unique<Flex>();
  applyCard(*nowCard, scale);
  nowCard->setAlign(FlexAlign::Stretch);
  nowCard->setGap(Style::spaceMd * scale);
  nowCard->setFlexGrow(1.0f);
  nowCard->setMinHeight(kMediaNowCardMinHeight * scale);
  m_nowCard = nowCard.get();

  auto mediaStack = std::make_unique<Flex>();
  mediaStack->setDirection(FlexDirection::Vertical);
  mediaStack->setAlign(FlexAlign::Stretch);
  mediaStack->setGap(Style::spaceMd * scale);
  mediaStack->setFlexGrow(1.0f);
  m_mediaStack = mediaStack.get();

  auto artworkRow = std::make_unique<Flex>();
  artworkRow->setDirection(FlexDirection::Horizontal);
  artworkRow->setAlign(FlexAlign::Center);
  artworkRow->setJustify(FlexJustify::Center);
  artworkRow->setGap(0.0f);

  auto artwork = std::make_unique<Image>();
  artwork->setCornerRadius(Style::radiusLg * scale);
  artwork->setFit(ImageFit::Contain);
  artwork->setSize(kArtworkSize * scale, kArtworkSize * scale);
  m_artwork = artwork.get();
  artworkRow->addChild(std::move(artwork));
  mediaStack->addChild(std::move(artworkRow));

  auto title = std::make_unique<Label>();
  title->setText("Nothing playing");
  title->setBold(true);
  title->setFontSize(Style::fontSizeTitle * scale);
  title->setColor(palette.onSurface);
  m_trackTitle = title.get();
  mediaStack->addChild(std::move(title));

  auto artist = std::make_unique<Label>();
  artist->setText("Start playback in an MPRIS app");
  artist->setFontSize(Style::fontSizeBody * scale);
  artist->setColor(palette.onSurfaceVariant);
  m_trackArtist = artist.get();
  mediaStack->addChild(std::move(artist));

  auto album = std::make_unique<Label>();
  album->setText(" ");
  album->setCaptionStyle();
  album->setFontSize(Style::fontSizeCaption * scale);
  album->setColor(palette.onSurfaceVariant);
  m_trackAlbum = album.get();
  mediaStack->addChild(std::move(album));

  auto progress = std::make_unique<Slider>();
  progress->setRange(0.0f, 100.0f);
  progress->setStep(1.0f);
  progress->setControlHeight(Style::controlHeight * scale);
  progress->setTrackHeight(6.0f * scale);
  progress->setThumbSize(16.0f * scale);
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
  mediaStack->addChild(std::move(progress));

  auto controlsRow = std::make_unique<Flex>();
  controlsRow->setDirection(FlexDirection::Horizontal);
  controlsRow->setAlign(FlexAlign::Center);
  controlsRow->setJustify(FlexJustify::Center);
  controlsRow->setGap(0.0f);

  auto controls = std::make_unique<Flex>();
  controls->setDirection(FlexDirection::Horizontal);
  controls->setAlign(FlexAlign::Center);
  controls->setGap(Style::spaceSm * scale);

  auto repeat = std::make_unique<Button>();
  repeat->setGlyph("repeat");
  repeat->setVariant(ButtonVariant::Ghost);
  repeat->setMinimalChrome(true);
  repeat->setMinWidth(kMediaControlsHeight * scale);
  repeat->setMinHeight(kMediaControlsHeight * scale);
  repeat->setPadding(Style::spaceSm * scale, Style::spaceSm * scale, Style::spaceSm * scale, Style::spaceSm * scale);
  repeat->setRadius(Style::radiusLg * scale);
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
  previous->setMinWidth(kMediaControlsHeight * scale);
  previous->setMinHeight(kMediaControlsHeight * scale);
  previous->setPadding(Style::spaceSm * scale, Style::spaceSm * scale, Style::spaceSm * scale, Style::spaceSm * scale);
  previous->setRadius(Style::radiusLg * scale);
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
  playPause->setMinWidth(kMediaPlayPauseHeight * scale);
  playPause->setMinHeight(kMediaPlayPauseHeight * scale);
  playPause->setPadding(Style::spaceSm * scale, Style::spaceSm * scale, Style::spaceSm * scale, Style::spaceSm * scale);
  playPause->setRadius(Style::radiusLg * scale);
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
  next->setMinWidth(kMediaControlsHeight * scale);
  next->setMinHeight(kMediaControlsHeight * scale);
  next->setPadding(Style::spaceSm * scale, Style::spaceSm * scale, Style::spaceSm * scale, Style::spaceSm * scale);
  next->setRadius(Style::radiusLg * scale);
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
  shuffle->setMinWidth(kMediaControlsHeight * scale);
  shuffle->setMinHeight(kMediaControlsHeight * scale);
  shuffle->setPadding(Style::spaceSm * scale, Style::spaceSm * scale, Style::spaceSm * scale, Style::spaceSm * scale);
  shuffle->setRadius(Style::radiusLg * scale);
  shuffle->setOnClick([this]() {
    if (m_mpris != nullptr) {
      const bool enabled = m_mpris->shuffleActive().value_or(false);
      m_mpris->setShuffleActive(!enabled);
      PanelManager::instance().refresh();
    }
  });
  m_shuffleButton = shuffle.get();
  controls->addChild(std::move(shuffle));

  controlsRow->addChild(std::move(controls));
  mediaStack->addChild(std::move(controlsRow));

  auto playerSelect = std::make_unique<Select>();
  playerSelect->setPlaceholder("Active player");
  playerSelect->setFontSize(Style::fontSizeBody * scale);
  playerSelect->setControlHeight(Style::controlHeight * scale);
  playerSelect->setHorizontalPadding(Style::spaceMd * scale);
  playerSelect->setGlyphSize(14.0f * scale);
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
  mediaStack->addChild(std::move(playerSelect));

  nowCard->addChild(std::move(mediaStack));
  mediaColumn->addChild(std::move(nowCard));

  auto audioColumn = std::make_unique<Flex>();
  audioColumn->setDirection(FlexDirection::Vertical);
  audioColumn->setAlign(FlexAlign::Stretch);
  audioColumn->setGap(Style::spaceSm * scale);
  audioColumn->setFlexGrow(2.0f);
  audioColumn->setMinWidth(kAudioColumnMinWidth * scale);
  m_audioColumn = audioColumn.get();

  auto outputVisualizerPlaceholder = std::make_unique<Flex>();
  outputVisualizerPlaceholder->setDirection(FlexDirection::Vertical);
  outputVisualizerPlaceholder->setAlign(FlexAlign::Stretch);
  outputVisualizerPlaceholder->setJustify(FlexJustify::Center);
  outputVisualizerPlaceholder->setMinHeight(Style::controlHeightLg * 5.0f * scale);
  outputVisualizerPlaceholder->setPadding(Style::spaceMd * scale);
  outputVisualizerPlaceholder->setRadius(Style::radiusLg * scale);
  outputVisualizerPlaceholder->setBorderWidth(Style::borderWidth);
  outputVisualizerPlaceholder->setBorderColor(palette.outline);
  outputVisualizerPlaceholder->setBackground(palette.surface);

  auto outputVisualizerLabel = std::make_unique<Label>();
  outputVisualizerLabel->setText("audio visualizer");
  outputVisualizerLabel->setBold(true);
  outputVisualizerLabel->setFontSize(Style::fontSizeBody * scale);
  outputVisualizerLabel->setColor(palette.onSurfaceVariant);
  outputVisualizerPlaceholder->addChild(std::move(outputVisualizerLabel));

  audioColumn->addChild(std::move(outputVisualizerPlaceholder));

  auto outputSpacer = std::make_unique<Flex>();
  outputSpacer->setFlexGrow(1.0f);
  audioColumn->addChild(std::move(outputSpacer));

  auto outputCard = std::make_unique<Flex>();
  applyCard(*outputCard, scale);
  outputCard->setAlign(FlexAlign::Stretch);
  outputCard->setMinHeight(kMediaAudioCardMinHeight * scale);
  m_outputCard = outputCard.get();

  addTitle(*outputCard, "Output", scale);

  auto outputDeviceSelect = std::make_unique<Select>();
  outputDeviceSelect->setPlaceholder("Select output device");
  outputDeviceSelect->setFontSize(Style::fontSizeBody * scale);
  outputDeviceSelect->setControlHeight(Style::controlHeight * scale);
  outputDeviceSelect->setHorizontalPadding(Style::spaceMd * scale);
  outputDeviceSelect->setGlyphSize(14.0f * scale);
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
  outputRow->setGap(Style::spaceSm * scale);

  auto outputSlider = std::make_unique<Slider>();
  outputSlider->setRange(0.0f, 150.0f);
  outputSlider->setStep(1.0f);
  outputSlider->setFlexGrow(1.0f);
  outputSlider->setControlHeight(Style::controlHeight * scale);
  outputSlider->setTrackHeight(6.0f * scale);
  outputSlider->setThumbSize(16.0f * scale);
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
  outputLabel->setFontSize(Style::fontSizeBody * scale);
  outputLabel->setMinWidth(kValueLabelWidth * scale);
  m_outputValue = outputLabel.get();
  outputRow->addChild(std::move(outputLabel));
  outputCard->addChild(std::move(outputRow));
  audioColumn->addChild(std::move(outputCard));

  auto inputCard = std::make_unique<Flex>();
  applyCard(*inputCard, scale);
  inputCard->setAlign(FlexAlign::Stretch);
  inputCard->setMinHeight(kMediaAudioCardMinHeight * scale);
  m_inputCard = inputCard.get();
  addTitle(*inputCard, "Input", scale);

  auto inputDeviceSelect = std::make_unique<Select>();
  inputDeviceSelect->setPlaceholder("Select input device");
  inputDeviceSelect->setFontSize(Style::fontSizeBody * scale);
  inputDeviceSelect->setControlHeight(Style::controlHeight * scale);
  inputDeviceSelect->setHorizontalPadding(Style::spaceMd * scale);
  inputDeviceSelect->setGlyphSize(14.0f * scale);
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
  inputRow->setGap(Style::spaceSm * scale);

  auto inputSlider = std::make_unique<Slider>();
  inputSlider->setRange(0.0f, 150.0f);
  inputSlider->setStep(1.0f);
  inputSlider->setFlexGrow(1.0f);
  inputSlider->setControlHeight(Style::controlHeight * scale);
  inputSlider->setTrackHeight(6.0f * scale);
  inputSlider->setThumbSize(16.0f * scale);
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
  inputLabel->setFontSize(Style::fontSizeBody * scale);
  inputLabel->setMinWidth(kValueLabelWidth * scale);
  m_inputValue = inputLabel.get();
  inputRow->addChild(std::move(inputLabel));
  inputCard->addChild(std::move(inputRow));
  audioColumn->addChild(std::move(inputCard));

  tab->addChild(std::move(mediaColumn));
  tab->addChild(std::move(audioColumn));

  return tab;
}

void MediaTab::layout(Renderer& renderer, float contentWidth, float bodyHeight) {
  if (m_rootLayout == nullptr || m_column == nullptr || m_nowCard == nullptr || m_mediaStack == nullptr ||
      m_outputCard == nullptr || m_inputCard == nullptr) {
    return;
  }

  m_rootLayout->setSize(contentWidth, bodyHeight);
  m_rootLayout->layout(renderer);

  const float scale = contentScale();
  const float cardInnerWidth =
      std::max(0.0f, m_nowCard->width() - (m_nowCard->paddingLeft() + m_nowCard->paddingRight()));
  const float leftInnerWidth =
      std::clamp(cardInnerWidth, kMediaColumnMinWidth * scale, Style::controlHeightLg * 11.0f * scale);
  m_mediaStack->setSize(leftInnerWidth, 0.0f);
  m_mediaStack->layout(renderer);

  const float outputInnerWidth =
      std::max(0.0f, m_outputCard->width() - (m_outputCard->paddingLeft() + m_outputCard->paddingRight()));
  const float inputInnerWidth =
      std::max(0.0f, m_inputCard->width() - (m_inputCard->paddingLeft() + m_inputCard->paddingRight()));
  if (m_playerSelect != nullptr) {
    m_playerSelect->setSize(leftInnerWidth, 0.0f);
  }
  if (m_outputDeviceSelect != nullptr) {
    m_outputDeviceSelect->setSize(outputInnerWidth, 0.0f);
  }
  if (m_inputDeviceSelect != nullptr) {
    m_inputDeviceSelect->setSize(inputInnerWidth, 0.0f);
  }

  if (m_artwork != nullptr) {
    const float mediaArtworkSize = std::min(leftInnerWidth, Style::controlHeightLg * 6 * scale);
    const float mediaMetaHeight =
        (Style::fontSizeTitle + Style::fontSizeBody + Style::fontSizeCaption + Style::spaceMd * 2) * scale;
    const float aspectRatio = m_artwork->hasImage() ? m_artwork->aspectRatio() : 1.0f;
    const bool wideArtwork = aspectRatio > 1.15f;
    const float mediaReservedHeight =
        (Style::controlHeight * 2.0f + kMediaPlayPauseHeight) * scale + mediaMetaHeight + Style::spaceMd * scale * 5.0f;
    const float artworkMaxHeight = std::max(kMediaArtworkMinHeight * scale, m_nowCard->height() - mediaReservedHeight);

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

    const float sideButtonSize = kMediaControlsHeight * scale;
    const float playPauseButtonSize = kMediaPlayPauseHeight * scale;
    const float sideGlyphSize = Style::fontSizeTitle * scale;
    const float playPauseGlyphSize = (Style::fontSizeTitle + Style::spaceXs) * scale;

    for (auto* button : {m_repeatButton, m_prevButton, m_nextButton, m_shuffleButton}) {
      if (button != nullptr) {
        button->setMinWidth(sideButtonSize);
        button->setMinHeight(sideButtonSize);
        button->setGlyphSize(sideGlyphSize);
        button->setPadding(Style::spaceSm * scale, Style::spaceSm * scale, Style::spaceSm * scale,
                           Style::spaceSm * scale);
        button->setRadius(Style::radiusLg * scale);
        button->layout(renderer);
        button->updateInputArea();
      }
    }
    if (m_playPauseButton != nullptr) {
      m_playPauseButton->setMinWidth(playPauseButtonSize);
      m_playPauseButton->setMinHeight(playPauseButtonSize);
      m_playPauseButton->setGlyphSize(playPauseGlyphSize);
      m_playPauseButton->setPadding(Style::spaceSm * scale, Style::spaceSm * scale, Style::spaceSm * scale,
                                    Style::spaceSm * scale);
      m_playPauseButton->setRadius(Style::radiusLg * scale);
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
  if (m_outputValue != nullptr) {
    m_outputValue->measure(renderer);
  }
  if (m_inputValue != nullptr) {
    m_inputValue->measure(renderer);
  }

  m_nowCard->layout(renderer);
  m_outputCard->layout(renderer);
  m_inputCard->layout(renderer);
  m_rootLayout->layout(renderer);
}

void MediaTab::update(Renderer& renderer) { refresh(renderer); }

void MediaTab::onClose() {
  m_rootLayout = nullptr;
  m_artwork = nullptr;
  m_column = nullptr;
  m_nowCard = nullptr;
  m_mediaStack = nullptr;
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
  std::vector<MprisPlayerInfo> players;
  std::optional<MprisPlayerInfo> active;
  if (m_mpris != nullptr) {
    players = m_mpris->listPlayers();
    active = m_mpris->activePlayer();
    kLog.debug("media tab refresh initial players={} active={} active_bus=\"{}\"", players.size(), active.has_value(),
               active.has_value() ? active->busName : std::string{});

    const auto now = std::chrono::steady_clock::now();
    const bool shouldRetryMpris =
        (!active.has_value() || players.empty()) && (m_lastMprisRefreshAttempt.time_since_epoch().count() == 0 ||
                                                     now - m_lastMprisRefreshAttempt >= std::chrono::milliseconds(750));
    if (shouldRetryMpris) {
      m_lastMprisRefreshAttempt = now;
      kLog.debug("media tab retrying mpris discovery players={} active={}", players.size(), active.has_value());
      m_mpris->refreshPlayers();
      players = m_mpris->listPlayers();
      active = m_mpris->activePlayer();
      kLog.debug("media tab refresh after retry players={} active={} active_bus=\"{}\"", players.size(),
                 active.has_value(), active.has_value() ? active->busName : std::string{});
    }
  }

  if (m_playerSelect != nullptr) {
    std::vector<std::string> playerLabels;
    std::vector<std::string> playerBusNames;
    playerLabels.reserve(players.size() + 1);
    playerBusNames.reserve(players.size());
    std::size_t selectedPlayerIndex = 0;

    const std::string activeBusName = active.has_value() ? active->busName : std::string{};
    const auto pinnedBusName = m_mpris != nullptr ? m_mpris->pinnedPlayerPreference() : std::nullopt;

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
    if (active.has_value()) {
      const auto& player = *active;
      const auto now = std::chrono::steady_clock::now();
      const bool seekPending = !m_pendingSeekBusName.empty() && m_pendingSeekBusName == player.busName &&
                               now < m_pendingSeekUntil && m_pendingSeekUs >= 0;
      const bool seekReached = seekPending && std::llabs(player.positionUs - m_pendingSeekUs) <= 1500000;
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

      const std::string resolvedArtUrl = effectiveArtUrl(player);
      std::string artPath = normalizeArtPath(resolvedArtUrl);
      if (artPath.empty() && isRemoteArtUrl(resolvedArtUrl)) {
        const auto cached = artCachePath(resolvedArtUrl);
        std::error_code ec;
        if (std::filesystem::exists(cached, ec) && std::filesystem::file_size(cached, ec) > 0) {
          artPath = cached.string();
        } else if (m_httpClient != nullptr &&
                   m_pendingArtDownloads.find(resolvedArtUrl) == m_pendingArtDownloads.end()) {
          std::filesystem::create_directories(cached.parent_path(), ec);
          m_pendingArtDownloads.insert(resolvedArtUrl);
          m_httpClient->download(resolvedArtUrl, cached, [this, url = resolvedArtUrl](bool success) {
            m_pendingArtDownloads.erase(url);
            if (success) {
              m_lastArtPath.clear();
              PanelManager::instance().refresh();
            }
          });
        }
      }

      if (m_artwork != nullptr && resolvedArtUrl != m_lastArtPath) {
        if (artPath.empty()) {
          if (!resolvedArtUrl.empty()) {
            kLog.debug("artwork unresolved url=\"{}\"", resolvedArtUrl);
          }
          clearArt(renderer);
        } else if (!m_artwork->setSourceFile(renderer, artPath, static_cast<int>(kArtworkSize))) {
          kLog.warn("artwork load failed url=\"{}\" path=\"{}\"", resolvedArtUrl, artPath);
          clearArt(renderer);
        } else {
          kLog.debug("artwork loaded url=\"{}\" path=\"{}\"", resolvedArtUrl, artPath);
        }
        m_lastArtPath = resolvedArtUrl;
      }

      m_syncingProgress = true;
      m_progressSlider->setEnabled(player.canSeek && player.lengthUs > 0);
      m_progressSlider->setRange(0.0f, std::max(1.0f, static_cast<float>(player.lengthUs) / 1000000.0f));
      m_progressSlider->setValue(static_cast<float>(displayPositionUs) / 1000000.0f);
      m_syncingProgress = false;

      m_playPauseButton->setGlyph(playPauseGlyph(player.playbackStatus));
      m_playPauseButton->setVariant(ButtonVariant::Accent);
      if (m_prevButton != nullptr) {
        m_prevButton->setEnabled(player.canGoPrevious);
      }
      if (m_nextButton != nullptr) {
        m_nextButton->setEnabled(player.canGoNext);
      }
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
      if (m_prevButton != nullptr) {
        m_prevButton->setEnabled(false);
      }
      if (m_nextButton != nullptr) {
        m_nextButton->setEnabled(false);
      }
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
