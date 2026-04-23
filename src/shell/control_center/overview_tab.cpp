#include "shell/control_center/overview_tab.h"

#include "config/config_service.h"
#include "dbus/mpris/mpris_service.h"
#include "dbus/power/power_profiles_service.h"
#include "dbus/upower/upower_service.h"
#include "pipewire/pipewire_service.h"
#include "shell/panel/panel_manager.h"
#include "system/distro_info.h"
#include "system/weather_service.h"
#include "time/time_service.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"

#include <cmath>
#include <format>
#include <memory>
#include <string>

using namespace control_center;

namespace {

  void styleOverviewCard(Flex& card, float scale) {
    applyOutlinedCard(card, scale);
    card.setGap(Style::spaceSm * scale);
  }

} // namespace

OverviewTab::OverviewTab(MprisService* mpris, WeatherService* weather, PipeWireService* audio, UPowerService* upower,
                         PowerProfilesService* powerProfiles, ConfigService* config)
    : m_mpris(mpris), m_weather(weather), m_audio(audio), m_upower(upower), m_powerProfiles(powerProfiles),
      m_config(config) {}

std::unique_ptr<Flex> OverviewTab::create() {
  const float scale = contentScale();
  const std::string displayName = sessionDisplayName();

  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Vertical);
  tab->setAlign(FlexAlign::Stretch);
  tab->setGap(Style::spaceMd * scale);
  m_rootLayout = tab.get();

  auto topRow = std::make_unique<Flex>();
  topRow->setDirection(FlexDirection::Horizontal);
  topRow->setAlign(FlexAlign::Stretch);
  topRow->setGap(Style::spaceMd * scale);

  // --- Weather ---
  auto weatherCard = std::make_unique<Flex>();
  styleOverviewCard(*weatherCard, scale);
  m_weatherCard = weatherCard.get();
  weatherCard->setFlexGrow(1.0f);
  addTitle(*weatherCard, "Today", scale);

  auto weatherRow = std::make_unique<Flex>();
  weatherRow->setDirection(FlexDirection::Horizontal);
  weatherRow->setAlign(FlexAlign::Center);
  weatherRow->setGap(Style::spaceSm * scale);

  auto weatherGlyph = std::make_unique<Glyph>();
  weatherGlyph->setGlyph("weather-cloud-sun");
  weatherGlyph->setGlyphSize(Style::fontSizeTitle * 2.2f * scale);
  weatherGlyph->setColor(roleColor(ColorRole::Primary));
  m_weatherGlyph = weatherGlyph.get();

  auto weatherText = std::make_unique<Flex>();
  weatherText->setDirection(FlexDirection::Vertical);
  weatherText->setAlign(FlexAlign::Stretch);
  weatherText->setGap(Style::spaceXs * scale);
  weatherText->setFlexGrow(1.0f);

  auto weatherTemp = std::make_unique<Label>();
  weatherTemp->setText("—");
  weatherTemp->setBold(true);
  weatherTemp->setFontSize(Style::fontSizeTitle * 1.85f * scale);
  weatherTemp->setColor(roleColor(ColorRole::OnSurface));
  m_weatherTemp = weatherTemp.get();

  auto weatherSub = std::make_unique<Label>();
  weatherSub->setText(" ");
  weatherSub->setFontSize(Style::fontSizeBody * scale);
  weatherSub->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_weatherSub = weatherSub.get();

  weatherText->addChild(std::move(weatherTemp));
  weatherText->addChild(std::move(weatherSub));
  weatherRow->addChild(std::move(weatherGlyph));
  weatherRow->addChild(std::move(weatherText));
  weatherCard->addChild(std::move(weatherRow));
  topRow->addChild(std::move(weatherCard));

  // --- Media ---
  auto mediaCard = std::make_unique<Flex>();
  styleOverviewCard(*mediaCard, scale);
  m_mediaCard = mediaCard.get();
  mediaCard->setFlexGrow(1.0f);

  m_mediaKicker = addTitle(*mediaCard, "Now playing", scale);

  auto mediaTrack = std::make_unique<Label>();
  mediaTrack->setText("…");
  mediaTrack->setBold(true);
  mediaTrack->setFontSize(Style::fontSizeTitle * scale);
  mediaTrack->setColor(roleColor(ColorRole::OnSurface));
  m_mediaTrack = mediaTrack.get();

  auto mediaArtist = std::make_unique<Label>();
  mediaArtist->setText(" ");
  mediaArtist->setFontSize(Style::fontSizeBody * scale);
  mediaArtist->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_mediaArtist = mediaArtist.get();

  auto mediaStatus = std::make_unique<Label>();
  mediaStatus->setText(" ");
  mediaStatus->setFontSize(Style::fontSizeCaption * scale);
  mediaStatus->setColor(roleColor(ColorRole::Secondary));
  m_mediaStatus = mediaStatus.get();

  mediaCard->addChild(std::move(mediaTrack));
  mediaCard->addChild(std::move(mediaArtist));
  mediaCard->addChild(std::move(mediaStatus));
  topRow->addChild(std::move(mediaCard));

  // --- Session (display name + uptime) ---
  auto userCard = std::make_unique<Flex>();
  styleOverviewCard(*userCard, scale);
  m_userCard = userCard.get();
  auto userRow = std::make_unique<Flex>();
  userRow->setDirection(FlexDirection::Horizontal);
  userRow->setAlign(FlexAlign::Center);
  userRow->setGap(Style::spaceMd * scale);

  auto avatar = std::make_unique<Image>();
  avatar->setCornerRadius(Style::radiusLg * scale);
  avatar->setBackground(roleColor(ColorRole::SurfaceVariant));
  avatar->setBorder(roleColor(ColorRole::Primary), Style::borderWidth * 2.0f);
  avatar->setFit(ImageFit::Cover);
  avatar->setPadding(1.0f * scale);
  const float avatarSize = Style::controlHeightLg * 2.2f * scale;
  avatar->setSize(avatarSize, avatarSize);
  m_userAvatar = avatar.get();
  userRow->addChild(std::move(avatar));

  auto userMain = std::make_unique<Flex>();
  userMain->setDirection(FlexDirection::Vertical);
  userMain->setAlign(FlexAlign::Stretch);
  userMain->setJustify(FlexJustify::Center);
  userMain->setGap(Style::spaceXs * 0.5f * scale);
  userMain->setFlexGrow(1.0f);
  m_userMain = userMain.get();

  auto userHeader = std::make_unique<Flex>();
  userHeader->setDirection(FlexDirection::Horizontal);
  userHeader->setAlign(FlexAlign::Center);
  userHeader->setJustify(FlexJustify::SpaceBetween);
  userHeader->setGap(Style::spaceSm * scale);

  auto userTitle = std::make_unique<Label>();
  userTitle->setText(displayName);
  userTitle->setBold(true);
  userTitle->setFontSize(Style::fontSizeTitle * 1.12f * scale);
  userTitle->setColor(roleColor(ColorRole::OnSurface));
  userHeader->addChild(std::move(userTitle));

  auto actions = std::make_unique<Flex>();
  actions->setDirection(FlexDirection::Horizontal);
  actions->setAlign(FlexAlign::Center);
  actions->setGap(Style::spaceSm * scale);

  auto settingsBtn = std::make_unique<Button>();
  settingsBtn->setGlyph("settings");
  settingsBtn->setVariant(ButtonVariant::Default);
  settingsBtn->setMinHeight(Style::controlHeight * scale);
  settingsBtn->setMinWidth(Style::controlHeight * scale);
  settingsBtn->setPadding(Style::spaceSm * scale, Style::spaceSm * scale);
  settingsBtn->setOnClick([]() { PanelManager::instance().openSettingsWindow(); });
  m_settingsButton = settingsBtn.get();
  actions->addChild(std::move(settingsBtn));

  auto sessionBtn = std::make_unique<Button>();
  sessionBtn->setGlyph("shutdown");
  sessionBtn->setVariant(ButtonVariant::Default);
  sessionBtn->setMinHeight(Style::controlHeight * scale);
  sessionBtn->setMinWidth(Style::controlHeight * scale);
  sessionBtn->setPadding(Style::spaceSm * scale, Style::spaceSm * scale);
  sessionBtn->setOnClick([]() { PanelManager::instance().togglePanel("session"); });
  m_sessionMenuButton = sessionBtn.get();
  actions->addChild(std::move(sessionBtn));

  userHeader->addChild(std::move(actions));
  userMain->addChild(std::move(userHeader));

  auto userFacts = std::make_unique<Label>();
  userFacts->setText("…");
  userFacts->setFontSize(Style::fontSizeCaption * scale);
  userFacts->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_userFacts = userFacts.get();
  userMain->addChild(std::move(userFacts));
  userRow->addChild(std::move(userMain));
  userCard->addChild(std::move(userRow));

  tab->addChild(std::move(userCard));
  tab->addChild(std::move(topRow));

  auto bottomRow = std::make_unique<Flex>();
  bottomRow->setDirection(FlexDirection::Horizontal);
  bottomRow->setAlign(FlexAlign::Stretch);
  bottomRow->setGap(Style::spaceMd * scale);

  auto powerCard = std::make_unique<Flex>();
  styleOverviewCard(*powerCard, scale);
  m_powerCard = powerCard.get();
  powerCard->setFlexGrow(1.0f);
  addTitle(*powerCard, "Power", scale);

  auto powerLine = std::make_unique<Label>();
  powerLine->setText("…");
  powerLine->setFontSize(Style::fontSizeBody * scale);
  powerLine->setColor(roleColor(ColorRole::OnSurface));
  m_powerLine = powerLine.get();
  powerCard->addChild(std::move(powerLine));

  auto powerSub = std::make_unique<Label>();
  powerSub->setText(" ");
  powerSub->setFontSize(Style::fontSizeCaption * scale);
  powerSub->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_powerSub = powerSub.get();
  powerCard->addChild(std::move(powerSub));
  bottomRow->addChild(std::move(powerCard));

  auto audioCard = std::make_unique<Flex>();
  styleOverviewCard(*audioCard, scale);
  m_audioCard = audioCard.get();
  audioCard->setFlexGrow(1.0f);
  addTitle(*audioCard, "Audio", scale);

  auto audioLine = std::make_unique<Label>();
  audioLine->setText("…");
  audioLine->setFontSize(Style::fontSizeBody * scale);
  audioLine->setColor(roleColor(ColorRole::OnSurface));
  m_audioLine = audioLine.get();
  audioCard->addChild(std::move(audioLine));

  auto audioSub = std::make_unique<Label>();
  audioSub->setText(" ");
  audioSub->setFontSize(Style::fontSizeCaption * scale);
  audioSub->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_audioSub = audioSub.get();
  audioCard->addChild(std::move(audioSub));
  bottomRow->addChild(std::move(audioCard));

  tab->addChild(std::move(bottomRow));

  return tab;
}

void OverviewTab::doLayout(Renderer& renderer, float contentWidth, float bodyHeight) {
  (void)bodyHeight;
  if (m_rootLayout == nullptr) {
    return;
  }
  m_rootLayout->setSize(contentWidth, bodyHeight);
  m_rootLayout->layout(renderer);

  const auto innerWidth = [](Flex* card) {
    if (card == nullptr) {
      return 1.0f;
    }
    return std::max(1.0f, card->width() - (card->paddingLeft() + card->paddingRight()));
  };
  const float weatherWrap = innerWidth(m_weatherCard);
  const float mediaWrap = innerWidth(m_mediaCard);
  const float userWrap = innerWidth(m_userCard);
  const float powerWrap = innerWidth(m_powerCard);
  const float audioWrap = innerWidth(m_audioCard);

  for (Label* label : {m_weatherTemp, m_weatherSub}) {
    if (label != nullptr) {
      label->setMaxWidth(weatherWrap);
    }
  }
  for (Label* label : {m_mediaKicker, m_mediaTrack, m_mediaArtist, m_mediaStatus}) {
    if (label != nullptr) {
      label->setMaxWidth(mediaWrap);
    }
  }
  for (Label* label : {m_userFacts}) {
    if (label != nullptr) {
      label->setMaxWidth(userWrap);
    }
  }
  for (Label* label : {m_powerLine, m_powerSub}) {
    if (label != nullptr) {
      label->setMaxWidth(powerWrap);
    }
  }
  for (Label* label : {m_audioLine, m_audioSub}) {
    if (label != nullptr) {
      label->setMaxWidth(audioWrap);
    }
  }

  if (m_weatherCard != nullptr && m_mediaCard != nullptr) {
    m_mediaCard->setMinHeight(m_weatherCard->height());
  }

  if (m_userAvatar != nullptr && m_userMain != nullptr) {
    const float scale = contentScale();
    const float minAvatar = Style::controlHeightLg * 2.2f * scale;
    const float desiredAvatar = std::max(minAvatar, m_userMain->height());
    if (std::abs(m_userAvatar->width() - desiredAvatar) > 0.5f) {
      m_userAvatar->setSize(desiredAvatar, desiredAvatar);
    }
    m_userMain->setMinHeight(desiredAvatar);
  }

  m_rootLayout->layout(renderer);
  if (m_weatherGlyph != nullptr) {
    m_weatherGlyph->measure(renderer);
  }
}

void OverviewTab::doUpdate(Renderer& renderer) {
  if (!m_active) {
    return;
  }
  sync(renderer);
}

void OverviewTab::setActive(bool active) { m_active = active; }

void OverviewTab::onClose() {
  m_rootLayout = nullptr;
  m_weatherCard = nullptr;
  m_mediaCard = nullptr;
  m_userCard = nullptr;
  m_userMain = nullptr;
  m_powerCard = nullptr;
  m_audioCard = nullptr;
  m_weatherGlyph = nullptr;
  m_weatherTemp = nullptr;
  m_weatherSub = nullptr;
  m_userAvatar = nullptr;
  m_userFacts = nullptr;
  m_sessionMenuButton = nullptr;
  m_settingsButton = nullptr;
  m_loadedAvatarPath.clear();
  m_mediaKicker = nullptr;
  m_mediaTrack = nullptr;
  m_mediaArtist = nullptr;
  m_mediaStatus = nullptr;
  m_powerLine = nullptr;
  m_powerSub = nullptr;
  m_audioLine = nullptr;
  m_audioSub = nullptr;
}

void OverviewTab::sync(Renderer& renderer) {
  if (m_userAvatar != nullptr && m_config != nullptr) {
    const std::string avatarPath = m_config->config().shell.avatarPath;
    if (avatarPath != m_loadedAvatarPath) {
      if (avatarPath.empty()) {
        m_userAvatar->clear(renderer);
      } else {
        m_userAvatar->setSourceFile(renderer, avatarPath, static_cast<int>(std::round(m_userAvatar->width())));
      }
      m_loadedAvatarPath = avatarPath;
    }
  }

  if (m_userFacts != nullptr) {
    const auto uptime = systemUptime();
    const std::string uptimeText = uptime.has_value() ? formatDuration(*uptime) : "unknown";
    m_userFacts->setText(std::format("{}@{}\nUptime · {}", sessionDisplayName(), hostName(), uptimeText));
  }

  if (m_weatherGlyph != nullptr && m_weatherTemp != nullptr && m_weatherSub != nullptr) {
    if (m_weather == nullptr || !m_weather->enabled()) {
      m_weatherGlyph->setGlyph("weather-cloud-off");
      m_weatherGlyph->setColor(roleColor(ColorRole::OnSurfaceVariant));
      m_weatherTemp->setText("—");
      m_weatherSub->setText("Weather is disabled in config.");
    } else if (!m_weather->locationConfigured()) {
      m_weatherGlyph->setGlyph("weather-cloud");
      m_weatherGlyph->setColor(roleColor(ColorRole::OnSurfaceVariant));
      m_weatherTemp->setText("—");
      m_weatherSub->setText("Add [weather].address or enable auto_locate.");
    } else {
      const auto& snapshot = m_weather->snapshot();
      if (!snapshot.valid) {
        m_weatherGlyph->setGlyph("weather-cloud");
        m_weatherGlyph->setColor(roleColor(ColorRole::OnSurfaceVariant));
        m_weatherTemp->setText("—");
        m_weatherSub->setText(m_weather->loading() ? "Fetching forecast…" : "Weather data unavailable.");
      } else {
        m_weatherGlyph->setGlyph(WeatherService::glyphForCode(snapshot.current.weatherCode, snapshot.current.isDay));
        m_weatherGlyph->setColor(roleColor(ColorRole::Primary));
        const int t = static_cast<int>(std::lround(m_weather->displayTemperature(snapshot.current.temperatureC)));
        m_weatherTemp->setText(std::format("{}{}", t, m_weather->displayTemperatureUnit()));
        const std::string place = snapshot.locationName.empty() ? "Current location" : snapshot.locationName;
        m_weatherSub->setText(
            std::format("{}\n{}", WeatherService::descriptionForCode(snapshot.current.weatherCode), place));
      }
    }
  }

  if (m_mediaTrack != nullptr && m_mediaArtist != nullptr && m_mediaStatus != nullptr) {
    if (m_mpris == nullptr) {
      m_mediaTrack->setText("Playback unavailable");
      m_mediaArtist->setText(" ");
      m_mediaStatus->setText(" ");
      m_mediaStatus->setColor(roleColor(ColorRole::OnSurfaceVariant));
    } else {
      const auto active = m_mpris->activePlayer();
      if (!active.has_value()) {
        m_mediaTrack->setText("Nothing playing");
        m_mediaArtist->setText("Start something in an MPRIS app to see it here.");
        m_mediaStatus->setText(" ");
        m_mediaStatus->setColor(roleColor(ColorRole::OnSurfaceVariant));
      } else {
        m_mediaTrack->setText(active->title.empty() ? "Unknown track" : active->title);
        const std::string artists = joinedArtists(active->artists);
        m_mediaArtist->setText(artists.empty() ? "Unknown artist" : artists);
        if (active->playbackStatus == "Playing") {
          m_mediaStatus->setText("Playing");
          m_mediaStatus->setColor(roleColor(ColorRole::Primary));
        } else if (active->playbackStatus == "Paused") {
          m_mediaStatus->setText("Paused");
          m_mediaStatus->setColor(roleColor(ColorRole::OnSurfaceVariant));
        } else {
          m_mediaStatus->setText(active->playbackStatus);
          m_mediaStatus->setColor(roleColor(ColorRole::OnSurfaceVariant));
        }
      }
    }
  }

  if (m_powerLine != nullptr && m_powerSub != nullptr) {
    if (m_upower == nullptr) {
      m_powerLine->setText("Power unavailable");
      m_powerSub->setText(" ");
    } else {
      const auto& st = m_upower->state();
      if (!st.isPresent) {
        m_powerLine->setText(st.onBattery ? "On battery" : "AC connected");
      } else {
        m_powerLine->setText(std::format("{} · {:.0f}%", batteryStateLabel(st.state), st.percentage));
      }
      if (m_powerProfiles != nullptr && !m_powerProfiles->activeProfile().empty()) {
        m_powerSub->setText(std::format("Mode · {}", profileLabel(m_powerProfiles->activeProfile())));
      } else {
        m_powerSub->setText(st.onBattery ? "Battery power" : "Plugged in");
      }
    }
  }

  if (m_audioLine != nullptr && m_audioSub != nullptr) {
    if (m_audio == nullptr) {
      m_audioLine->setText("Audio unavailable");
      m_audioSub->setText(" ");
    } else if (const AudioNode* sink = m_audio->defaultSink(); sink != nullptr) {
      const int volumePct = static_cast<int>(std::lround(std::clamp(sink->volume, 0.0f, 1.5f) * 100.0f));
      m_audioLine->setText(sink->description.empty() ? sink->name : sink->description);
      m_audioSub->setText(std::format("{}{}%", sink->muted ? "Muted · " : "Volume · ", volumePct));
    } else {
      m_audioLine->setText("No output device");
      m_audioSub->setText(" ");
    }
  }
}
