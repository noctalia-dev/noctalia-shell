#include "shell/control_center/overview_tab.h"

#include "config/config_service.h"
#include "dbus/mpris/mpris_art.h"
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
#include <ctime>
#include <filesystem>
#include <format>
#include <memory>
#include <string>

using namespace control_center;

namespace {

  void styleOverviewCard(Flex& card, float scale) {
    applyOutlinedCard(card, scale);
    card.setGap(Style::spaceSm * scale);
  }

  std::string formatClockDuration(std::int64_t seconds) {
    if (seconds <= 0) {
      return "0:00";
    }
    const std::int64_t totalMinutes = seconds / 60;
    const std::int64_t hours = totalMinutes / 60;
    const std::int64_t minutes = totalMinutes % 60;
    const std::int64_t secs = seconds % 60;
    if (hours > 0) {
      return std::format("{}:{:02}:{:02}", hours, minutes, secs);
    }
    return std::format("{}:{:02}", minutes, secs);
  }

  std::string formatEta(std::int64_t seconds) {
    if (seconds <= 0) {
      return {};
    }
    const std::int64_t totalMinutes = seconds / 60;
    const std::int64_t hours = totalMinutes / 60;
    const std::int64_t minutes = totalMinutes % 60;
    if (hours > 0) {
      return std::format("{}h {}m", hours, minutes);
    }
    return std::format("{}m", minutes);
  }

  std::string currentDateText() {
    const std::time_t now = std::time(nullptr);
    const std::tm local = *std::localtime(&now);
    char day[32]{};
    std::strftime(day, sizeof(day), "%d %b %Y", &local);
    return std::string(day);
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
  weatherCard->setGap(Style::spaceXs * scale);

  auto weatherHeader = std::make_unique<Flex>();
  weatherHeader->setDirection(FlexDirection::Horizontal);
  weatherHeader->setAlign(FlexAlign::Center);
  weatherHeader->setJustify(FlexJustify::SpaceBetween);
  weatherHeader->setGap(Style::spaceSm * scale);

  Label* weatherTitle = addTitle(*weatherHeader, "Today", scale);
  weatherTitle->setFlexGrow(1.0f);

  auto weatherDate = std::make_unique<Label>();
  weatherDate->setText(currentDateText());
  weatherDate->setFontSize(Style::fontSizeCaption * scale);
  weatherDate->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_weatherDate = weatherDate.get();
  weatherHeader->addChild(std::move(weatherDate));
  weatherCard->addChild(std::move(weatherHeader));

  auto weatherRow = std::make_unique<Flex>();
  weatherRow->setDirection(FlexDirection::Horizontal);
  weatherRow->setAlign(FlexAlign::Center);
  weatherRow->setGap(Style::spaceSm * scale);

  auto weatherGlyph = std::make_unique<Glyph>();
  weatherGlyph->setGlyph("weather-cloud-sun");
  weatherGlyph->setGlyphSize(Style::controlHeightLg * 1.25f * scale);
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
  weatherTemp->setFontSize(Style::fontSizeBody * 1.15f * scale);
  weatherTemp->setColor(roleColor(ColorRole::OnSurface));
  m_weatherTemp = weatherTemp.get();

  auto weatherSub = std::make_unique<Label>();
  weatherSub->setText("Weather unavailable");
  weatherSub->setFontSize(Style::fontSizeCaption * scale);
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
  mediaCard->setGap(Style::spaceXs * scale);

  m_mediaKicker = addTitle(*mediaCard, "Now playing", scale);
  m_mediaKicker->setFontSize(Style::fontSizeBody * scale);

  auto mediaContent = std::make_unique<Flex>();
  mediaContent->setDirection(FlexDirection::Horizontal);
  mediaContent->setAlign(FlexAlign::Center);
  mediaContent->setGap(Style::spaceSm * scale);

  auto mediaArt = std::make_unique<Image>();
  const float artSize = Style::controlHeightLg * 1.55f * scale;
  mediaArt->setSize(artSize, artSize);
  mediaArt->setCornerRadius(Style::radiusLg * scale);
  mediaArt->setBackground(roleColor(ColorRole::SurfaceVariant));
  mediaArt->setFit(ImageFit::Cover);
  m_mediaArt = mediaArt.get();
  mediaContent->addChild(std::move(mediaArt));

  auto mediaText = std::make_unique<Flex>();
  mediaText->setDirection(FlexDirection::Vertical);
  mediaText->setAlign(FlexAlign::Stretch);
  mediaText->setGap(Style::spaceXs * 0.5f * scale);
  mediaText->setFlexGrow(1.0f);
  m_mediaText = mediaText.get();

  auto mediaTrack = std::make_unique<Label>();
  mediaTrack->setText("…");
  mediaTrack->setBold(false);
  mediaTrack->setFontSize(Style::fontSizeBody * scale);
  mediaTrack->setColor(roleColor(ColorRole::OnSurface));
  m_mediaTrack = mediaTrack.get();

  auto mediaArtist = std::make_unique<Label>();
  mediaArtist->setText("No active player");
  mediaArtist->setFontSize(Style::fontSizeCaption * scale);
  mediaArtist->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_mediaArtist = mediaArtist.get();

  auto mediaStatus = std::make_unique<Label>();
  mediaStatus->setText("Idle");
  mediaStatus->setFontSize(Style::fontSizeCaption * scale);
  mediaStatus->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_mediaStatus = mediaStatus.get();

  auto mediaProgress = std::make_unique<Label>();
  mediaProgress->setText(" ");
  mediaProgress->setFontSize(Style::fontSizeCaption * scale);
  mediaProgress->setColor(roleColor(ColorRole::Secondary));
  mediaProgress->setVisible(false);
  m_mediaProgress = mediaProgress.get();

  mediaText->addChild(std::move(mediaTrack));
  mediaText->addChild(std::move(mediaArtist));
  mediaText->addChild(std::move(mediaStatus));
  mediaText->addChild(std::move(mediaProgress));
  mediaContent->addChild(std::move(mediaText));
  mediaCard->addChild(std::move(mediaContent));
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

  for (Label* label : {m_weatherDate, m_weatherTemp, m_weatherSub}) {
    if (label != nullptr) {
      label->setMaxWidth(weatherWrap);
    }
  }
  for (Label* label : {m_mediaKicker, m_mediaTrack, m_mediaArtist, m_mediaStatus, m_mediaProgress}) {
    if (label != nullptr) {
      label->setMaxWidth(mediaWrap);
    }
  }
  if (m_mediaCard != nullptr && m_mediaArt != nullptr && m_mediaText != nullptr) {
    const float mediaInner =
        std::max(1.0f, m_mediaCard->width() - (m_mediaCard->paddingLeft() + m_mediaCard->paddingRight()));
    const float textWidth = std::max(1.0f, mediaInner - m_mediaArt->width() - (Style::spaceSm * contentScale()));
    for (Label* label : {m_mediaTrack, m_mediaArtist, m_mediaStatus, m_mediaProgress}) {
      if (label != nullptr) {
        label->setMaxWidth(textWidth);
      }
    }
  }
  if (m_mediaKicker != nullptr) {
    m_mediaKicker->setMaxLines(1);
  }
  if (m_weatherTemp != nullptr) {
    m_weatherTemp->setMaxLines(1);
  }
  if (m_weatherSub != nullptr) {
    m_weatherSub->setMaxLines(2);
  }
  if (m_weatherDate != nullptr) {
    m_weatherDate->setMaxLines(1);
  }
  if (m_mediaTrack != nullptr) {
    m_mediaTrack->setMaxLines(1);
  }
  if (m_mediaArtist != nullptr) {
    m_mediaArtist->setMaxLines(1);
  }
  if (m_mediaStatus != nullptr) {
    m_mediaStatus->setMaxLines(1);
  }
  if (m_mediaProgress != nullptr) {
    m_mediaProgress->setMaxLines(1);
  }
  if (m_audioLine != nullptr) {
    m_audioLine->setMaxLines(1);
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
    const float unifiedTopCardHeight = std::max(m_weatherCard->height(), m_mediaCard->height());
    m_weatherCard->setMinHeight(unifiedTopCardHeight);
    m_mediaCard->setMinHeight(unifiedTopCardHeight);
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
  m_weatherDate = nullptr;
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
  m_mediaProgress = nullptr;
  m_mediaText = nullptr;
  m_mediaArt = nullptr;
  m_loadedMediaArtUrl.clear();
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
  if (m_weatherDate != nullptr) {
    m_weatherDate->setText(currentDateText());
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
        std::string hiLoText;
        if (!snapshot.forecastDays.empty()) {
          const int hi = static_cast<int>(
              std::lround(m_weather->displayTemperature(snapshot.forecastDays.front().temperatureMaxC)));
          const int lo = static_cast<int>(
              std::lround(m_weather->displayTemperature(snapshot.forecastDays.front().temperatureMinC)));
          hiLoText = std::format(" · {} / {}{}", hi, lo, m_weather->displayTemperatureUnit());
        }
        const bool showLocation = m_config == nullptr || m_config->config().shell.showLocation;
        if (showLocation) {
          const std::string place = snapshot.locationName.empty() ? "Current location" : snapshot.locationName;
          m_weatherSub->setText(std::format(
              "{}{} · {}", WeatherService::descriptionForCode(snapshot.current.weatherCode), hiLoText, place));
        } else {
          m_weatherSub->setText(
              std::format("{}{}", WeatherService::descriptionForCode(snapshot.current.weatherCode), hiLoText));
        }
      }
    }
  }

  if (m_mediaTrack != nullptr && m_mediaArtist != nullptr && m_mediaStatus != nullptr && m_mediaProgress != nullptr) {
    if (m_mpris == nullptr) {
      m_mediaTrack->setText("Playback unavailable");
      m_mediaArtist->setText("Media service unavailable");
      m_mediaStatus->setText("Unavailable");
      m_mediaProgress->setText(" ");
      m_mediaProgress->setVisible(false);
      m_mediaStatus->setColor(roleColor(ColorRole::OnSurfaceVariant));
      if (m_mediaArt != nullptr) {
        m_mediaArt->clear(renderer);
      }
      m_loadedMediaArtUrl.clear();
    } else {
      const auto active = m_mpris->activePlayer();
      if (!active.has_value()) {
        m_mediaTrack->setText("Nothing playing");
        m_mediaArtist->setText("Play media to see details.");
        m_mediaStatus->setText("Idle");
        m_mediaProgress->setText(" ");
        m_mediaProgress->setVisible(false);
        m_mediaStatus->setColor(roleColor(ColorRole::OnSurfaceVariant));
        if (m_mediaArt != nullptr) {
          m_mediaArt->clear(renderer);
        }
        m_loadedMediaArtUrl.clear();
      } else {
        m_mediaTrack->setText(active->title.empty() ? "Unknown track" : active->title);
        const std::string artists = joinedArtists(active->artists);
        m_mediaArtist->setText(artists.empty() ? "Unknown artist" : artists);
        if (active->lengthUs > 0) {
          const std::int64_t positionSec = std::max<std::int64_t>(0, active->positionUs / 1000000);
          const std::int64_t lengthSec = std::max<std::int64_t>(1, active->lengthUs / 1000000);
          m_mediaProgress->setText(
              std::format("{} / {}", formatClockDuration(positionSec), formatClockDuration(lengthSec)));
          m_mediaProgress->setVisible(true);
        } else {
          m_mediaProgress->setText(" ");
          m_mediaProgress->setVisible(false);
        }
        if (m_mediaArt != nullptr) {
          const std::string artUrl = mpris::effectiveArtUrl(*active);
          if (artUrl != m_loadedMediaArtUrl) {
            std::string artPath = mpris::normalizeArtPath(artUrl);
            if (artPath.empty() && mpris::isRemoteArtUrl(artUrl)) {
              const auto cached = mpris::artCachePath(artUrl);
              std::error_code ec;
              if (std::filesystem::exists(cached, ec) && std::filesystem::file_size(cached, ec) > 0) {
                artPath = cached.string();
              }
            }
            if (!artPath.empty()) {
              if (!m_mediaArt->setSourceFile(renderer, artPath, static_cast<int>(std::round(m_mediaArt->width())),
                                             true)) {
                m_mediaArt->clear(renderer);
              }
            } else {
              m_mediaArt->clear(renderer);
            }
            m_loadedMediaArtUrl = artUrl;
          }
        }
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
        std::string etaSuffix;
        if (st.isPresent && st.state == BatteryState::Discharging) {
          const std::string eta = formatEta(st.timeToEmpty);
          if (!eta.empty()) {
            etaSuffix = " · " + eta + " left";
          }
        } else if (st.isPresent && st.state == BatteryState::Charging) {
          const std::string eta = formatEta(st.timeToFull);
          if (!eta.empty()) {
            etaSuffix = " · " + eta + " to full";
          }
        }
        m_powerSub->setText(std::format("Mode · {}{}", profileLabel(m_powerProfiles->activeProfile()), etaSuffix));
      } else {
        std::string etaSuffix;
        if (st.isPresent && st.state == BatteryState::Discharging) {
          const std::string eta = formatEta(st.timeToEmpty);
          if (!eta.empty()) {
            etaSuffix = " · " + eta + " left";
          }
        } else if (st.isPresent && st.state == BatteryState::Charging) {
          const std::string eta = formatEta(st.timeToFull);
          if (!eta.empty()) {
            etaSuffix = " · " + eta + " to full";
          }
        }
        m_powerSub->setText(std::format("{}{}", st.onBattery ? "Battery power" : "Plugged in", etaSuffix));
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
