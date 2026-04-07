#include "shell/control_center/control_center_panel.h"

#include "dbus/mpris/mpris_service.h"
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
#include <cstdio>
#include <filesystem>
#include <cmath>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include <fcntl.h>
#include <sys/wait.h>
#include <unistd.h>

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

bool runDownloader(const std::vector<std::string>& args) {
  if (args.empty()) {
    return false;
  }

  const pid_t pid = fork();
  if (pid < 0) {
    return false;
  }

  if (pid == 0) {
    const int devNull = open("/dev/null", O_WRONLY);
    if (devNull >= 0) {
      dup2(devNull, STDOUT_FILENO);
      dup2(devNull, STDERR_FILENO);
      close(devNull);
    }

    std::vector<char*> argv;
    argv.reserve(args.size() + 1);
    for (const auto& arg : args) {
      argv.push_back(const_cast<char*>(arg.c_str()));
    }
    argv.push_back(nullptr);

    execvp(argv[0], argv.data());
    _exit(127);
  }

  int status = 0;
  if (waitpid(pid, &status, 0) < 0) {
    return false;
  }

  return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

std::optional<std::string> fetchRemoteArt(std::string_view artUrl) {
  if (!isRemoteArtUrl(artUrl)) {
    return std::nullopt;
  }

  namespace fs = std::filesystem;
  const fs::path cacheDir = fs::path("/tmp") / "noctalia-media-art";
  std::error_code ec;
  fs::create_directories(cacheDir, ec);

  const std::size_t hash = std::hash<std::string_view>{}(artUrl);
  const fs::path finalPath = cacheDir / (std::to_string(hash) + ".img");
  const fs::path tempPath = cacheDir / (std::to_string(hash) + ".part");

  if (fs::exists(finalPath, ec) && fs::file_size(finalPath, ec) > 0) {
    return finalPath.string();
  }

  const std::string url(artUrl);
  const std::string temp = tempPath.string();

  const bool curlOk = runDownloader({"curl", "-LfsS", "--output", temp, url});
  const bool wgetOk = !curlOk && runDownloader({"wget", "-q", "-O", temp, url});
  if (!curlOk && !wgetOk) {
    std::error_code removeEc;
    fs::remove(tempPath, removeEc);
    return std::nullopt;
  }

  if (!fs::exists(tempPath, ec) || fs::file_size(tempPath, ec) == 0) {
    std::error_code removeEc;
    fs::remove(tempPath, removeEc);
    return std::nullopt;
  }

  fs::rename(tempPath, finalPath, ec);
  if (ec) {
    std::error_code copyEc;
    fs::copy_file(tempPath, finalPath, fs::copy_options::overwrite_existing, copyEc);
    std::error_code removeEc;
    fs::remove(tempPath, removeEc);
    if (copyEc) {
      return std::nullopt;
    }
  }

  return finalPath.string();
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

void ControlCenterPanel::buildMediaTab() {
  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Horizontal);
  tab->setAlign(FlexAlign::Start);
  tab->setGap(Style::spaceMd);
  m_tabContainers[tabIndex(TabId::Media)] = tab.get();

  auto mediaColumn = std::make_unique<Flex>();
  mediaColumn->setDirection(FlexDirection::Vertical);
  mediaColumn->setAlign(FlexAlign::Start);
  mediaColumn->setGap(0.0f);
  mediaColumn->setMinWidth(kMediaColumnWidth);
  m_mediaColumn = mediaColumn.get();

  auto nowCard = std::make_unique<Flex>();
  applyCard(*nowCard);
  nowCard->setAlign(FlexAlign::Center);
  nowCard->setGap(Style::spaceMd);
  nowCard->setMinWidth(kMediaColumnWidth);
  nowCard->setMinHeight(kMediaNowCardMinHeight);
  m_mediaNowCard = nowCard.get();

  auto artwork = std::make_unique<Image>();
  artwork->setCornerRadius(Style::radiusLg);
  artwork->setBackground(alphaSurfaceVariant(0.95f));
  artwork->setFit(ImageFit::Contain);
  artwork->setSize(kArtworkSize, kArtworkSize);
  m_mediaArtwork = artwork.get();
  nowCard->addChild(std::move(artwork));

  auto title = std::make_unique<Label>();
  title->setText("Nothing playing");
  title->setBold(true);
  title->setFontSize(Style::fontSizeTitle);
  title->setColor(palette.onSurface);
  title->setMaxWidth(kMediaColumnWidth - Style::spaceMd * 2);
  m_mediaTrackTitle = title.get();
  nowCard->addChild(std::move(title));

  auto artist = std::make_unique<Label>();
  artist->setText("Start playback in an MPRIS app");
  artist->setColor(palette.onSurfaceVariant);
  artist->setMaxWidth(kMediaColumnWidth - Style::spaceMd * 2);
  m_mediaTrackArtist = artist.get();
  nowCard->addChild(std::move(artist));

  auto album = std::make_unique<Label>();
  album->setText(" ");
  album->setCaptionStyle();
  album->setColor(palette.onSurfaceVariant);
  album->setMaxWidth(kMediaColumnWidth - Style::spaceMd * 2);
  m_mediaTrackAlbum = album.get();
  nowCard->addChild(std::move(album));

  auto progress = std::make_unique<Slider>();
  progress->setRange(0.0f, 100.0f);
  progress->setStep(1.0f);
  progress->setSize(kMediaColumnWidth - Style::spaceMd * 2, 0.0f);
  progress->setOnValueChanged([this](float value) {
    if (m_syncingMediaProgress || m_mpris == nullptr) {
      return;
    }
    const auto active = m_mpris->activePlayer();
    const std::int64_t targetUs = static_cast<std::int64_t>(std::llround(value * 1000000.0f));
    if (active.has_value()) {
      m_pendingMediaSeekBusName = active->busName;
      m_pendingMediaSeekUs = targetUs;
      m_pendingMediaSeekUntil = std::chrono::steady_clock::now() + std::chrono::milliseconds(1500);
    }
    m_mpris->setPositionActive(targetUs);
  });
  m_mediaProgressSlider = progress.get();
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
  m_mediaRepeatButton = repeat.get();
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
  m_mediaPrevButton = previous.get();
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
  m_mediaPlayPauseButton = playPause.get();
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
  m_mediaNextButton = next.get();
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
  m_mediaShuffleButton = shuffle.get();
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
    } else if (index - 1 < m_mediaPlayerBusNames.size()) {
      m_mpris->setPinnedPlayerPreference(m_mediaPlayerBusNames[index - 1]);
    }
    PanelManager::instance().refresh();
  });
  m_mediaPlayerSelect = playerSelect.get();
  nowCard->addChild(std::move(playerSelect));

  mediaColumn->addChild(std::move(nowCard));

  auto audioColumn = std::make_unique<Flex>();
  audioColumn->setDirection(FlexDirection::Vertical);
  audioColumn->setAlign(FlexAlign::Start);
  audioColumn->setGap(Style::spaceSm);
  audioColumn->setMinWidth(kAudioColumnWidth);
  m_mediaAudioColumn = audioColumn.get();

  auto outputCard = std::make_unique<Flex>();
  applyCard(*outputCard);
  outputCard->setMinWidth(kAudioColumnWidth);
  outputCard->setMinHeight(kMediaAudioCardMinHeight);
  m_mediaOutputCard = outputCard.get();
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
  m_mediaInputCard = inputCard.get();
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

  m_tabBodies->addChild(std::move(tab));
}

void ControlCenterPanel::refreshMediaState(Renderer& renderer) {
  if (m_mpris != nullptr && m_mediaPlayerSelect != nullptr) {
    const auto players = m_mpris->listPlayers();
    std::vector<std::string> playerLabels;
    std::vector<std::string> playerBusNames;
    playerLabels.reserve(players.size() + 1);
    playerBusNames.reserve(players.size());
    std::size_t selectedPlayerIndex = 0;

    const auto active = m_mpris->activePlayer();
    const std::string activeBusName = active.has_value() ? active->busName : std::string{};
    const auto pinnedBusName = m_mpris->pinnedPlayerPreference();

    playerLabels.push_back(active.has_value() ? "Active player" : "Active player");

    for (std::size_t i = 0; i < players.size(); ++i) {
      const auto& player = players[i];
      playerBusNames.push_back(player.busName);
      playerLabels.push_back(player.identity.empty() ? player.busName : player.identity);
      if (pinnedBusName.has_value() && player.busName == *pinnedBusName) {
        selectedPlayerIndex = i + 1;
      }
    }

    m_mediaPlayerBusNames = std::move(playerBusNames);
    m_syncingPlayerSelect = true;
    m_mediaPlayerSelect->setOptions(std::move(playerLabels));
    m_mediaPlayerSelect->setEnabled(!m_mediaPlayerBusNames.empty());
    if (!m_mediaPlayerBusNames.empty()) {
      m_mediaPlayerSelect->setSelectedIndex(selectedPlayerIndex);
    }
    m_syncingPlayerSelect = false;
  }

  if (m_mediaTrackTitle != nullptr && m_mediaTrackArtist != nullptr && m_mediaProgressSlider != nullptr &&
      m_mediaPlayPauseButton != nullptr && m_mediaRepeatButton != nullptr && m_mediaShuffleButton != nullptr) {
    const auto active = m_mpris != nullptr ? m_mpris->activePlayer() : std::nullopt;
    if (active.has_value()) {
      const auto& player = *active;
      const auto now = std::chrono::steady_clock::now();
      const bool seekPending =
          !m_pendingMediaSeekBusName.empty() && m_pendingMediaSeekBusName == player.busName &&
          now < m_pendingMediaSeekUntil && m_pendingMediaSeekUs >= 0;
      const bool seekReached =
          seekPending && std::llabs(player.positionUs - m_pendingMediaSeekUs) <= 1500000;
      const std::int64_t displayPositionUs = seekPending && !seekReached ? m_pendingMediaSeekUs : player.positionUs;
      if (!seekPending || seekReached) {
        m_pendingMediaSeekBusName.clear();
        m_pendingMediaSeekUs = -1;
      }

      m_mediaTrackTitle->setText(player.title.empty() ? player.identity : player.title);
      m_mediaTrackTitle->measure(renderer);
      m_mediaTrackArtist->setText(joinArtists(player.artists).empty() ? player.identity : joinArtists(player.artists));
      m_mediaTrackArtist->measure(renderer);
      if (m_mediaTrackAlbum != nullptr) {
        m_mediaTrackAlbum->setText(player.album.empty() ? " " : player.album);
        m_mediaTrackAlbum->measure(renderer);
      }

      std::string artPath = normalizeArtPath(player.artUrl);
      if (artPath.empty() && isRemoteArtUrl(player.artUrl)) {
        const auto cachedArt = fetchRemoteArt(player.artUrl);
        if (cachedArt.has_value()) {
          artPath = *cachedArt;
        }
      }

      if (m_mediaArtwork != nullptr && player.artUrl != m_lastMediaArtPath) {
        if (artPath.empty()) {
          clearMediaArt(renderer);
        } else if (!m_mediaArtwork->setSourceFile(renderer, artPath, static_cast<int>(kArtworkSize))) {
          clearMediaArt(renderer);
        }
        m_lastMediaArtPath = player.artUrl;
      }

      m_syncingMediaProgress = true;
      m_mediaProgressSlider->setEnabled(player.canSeek && player.lengthUs > 0);
      m_mediaProgressSlider->setRange(0.0f, std::max(1.0f, static_cast<float>(player.lengthUs) / 1000000.0f));
      m_mediaProgressSlider->setValue(static_cast<float>(displayPositionUs) / 1000000.0f);
      m_syncingMediaProgress = false;

      m_mediaPlayPauseButton->setGlyph(playPauseGlyph(player.playbackStatus));
      m_mediaPlayPauseButton->setVariant(ButtonVariant::Accent);
      m_mediaPrevButton->setEnabled(player.canGoPrevious);
      m_mediaNextButton->setEnabled(player.canGoNext);
      m_mediaRepeatButton->setGlyph(repeatGlyph(player.loopStatus));
      m_mediaRepeatButton->setVariant(toggleVariant(player.loopStatus != "None"));
      m_mediaShuffleButton->setVariant(toggleVariant(player.shuffle));

      m_lastMediaBusName = player.busName;
      m_lastMediaPlaybackStatus = player.playbackStatus;
      m_lastMediaLoopStatus = player.loopStatus;
      m_lastMediaShuffle = player.shuffle;
    } else {
      m_pendingMediaSeekBusName.clear();
      m_pendingMediaSeekUs = -1;
      m_mediaTrackTitle->setText("Nothing playing");
      m_mediaTrackTitle->measure(renderer);
      m_mediaTrackArtist->setText("Start playback in an MPRIS app");
      m_mediaTrackArtist->measure(renderer);
      if (m_mediaTrackAlbum != nullptr) {
        m_mediaTrackAlbum->setText(" ");
        m_mediaTrackAlbum->measure(renderer);
      }
      clearMediaArt(renderer);
      m_lastMediaArtPath.clear();
      m_mediaProgressSlider->setEnabled(false);
      m_syncingMediaProgress = true;
      m_mediaProgressSlider->setRange(0.0f, 100.0f);
      m_mediaProgressSlider->setValue(0.0f);
      m_syncingMediaProgress = false;
      m_mediaPlayPauseButton->setGlyph("media-play");
      m_mediaPrevButton->setEnabled(false);
      m_mediaNextButton->setEnabled(false);
      m_mediaRepeatButton->setGlyph("repeat");
      m_mediaRepeatButton->setVariant(ButtonVariant::Ghost);
      m_mediaShuffleButton->setVariant(ButtonVariant::Ghost);
      m_lastMediaBusName.clear();
      m_lastMediaPlaybackStatus.clear();
      m_lastMediaLoopStatus.clear();
      m_lastMediaShuffle = false;
    }
  }

  if (m_audio != nullptr) {
    const auto sink = m_audio->defaultSink();
    const auto source = m_audio->defaultSource();

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

    (void)sink;
    (void)source;
  }

  if (m_audio == nullptr) {
    if (m_outputSlider != nullptr) {
      m_outputSlider->setEnabled(false);
    }
    if (m_inputSlider != nullptr) {
      m_inputSlider->setEnabled(false);
    }
    return;
  }

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
}

void ControlCenterPanel::clearMediaArt(Renderer& renderer) {
  if (m_mediaArtwork != nullptr) {
    m_mediaArtwork->clear(renderer);
  }
}
