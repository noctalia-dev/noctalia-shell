#include "shell/control_center/overview_tab.h"

#include "config/config_service.h"
#include "core/build_info.h"
#include "dbus/mpris/mpris_art.h"
#include "dbus/mpris/mpris_service.h"
#include "i18n/i18n.h"
#include "render/scene/rect_node.h"
#include "shell/control_center/shortcut_registry.h"
#include "shell/panel/panel_manager.h"
#include "shell/wallpaper/wallpaper.h"
#include "system/distro_info.h"
#include "system/weather_service.h"
#include "time/time_format.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/grid_view.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <format>
#include <memory>
#include <string>
#include <system_error>

using namespace control_center;

namespace {

  constexpr float kOverviewAvatarScale = 2.6f;

  float overviewAvatarSize(float scale) { return Style::controlHeightLg * kOverviewAvatarScale * scale; }

  void applyOverviewCardStyle(Flex& card, float scale) {
    applySectionCardStyle(card, scale);
    card.setGap(Style::spaceSm * scale);
  }

} // namespace

OverviewTab::OverviewTab(MprisService* mpris, WeatherService* weather, PipeWireService* audio,
                         PowerProfilesService* powerProfiles, ConfigService* config, NetworkService* network,
                         BluetoothService* bluetooth, NightLightManager* nightLight,
                         noctalia::theme::ThemeService* theme, NotificationManager* notifications,
                         IdleInhibitor* idleInhibitor, WaylandConnection* wayland, Wallpaper* wallpaper)
    : m_mpris(mpris), m_weather(weather), m_config(config), m_wallpaper(wallpaper),
      m_services{network, bluetooth,     nightLight, theme,   notifications, idleInhibitor,
                 audio,   powerProfiles, mpris,      weather, config,        wayland} {}

OverviewTab::~OverviewTab() = default;

std::unique_ptr<Flex> OverviewTab::create() {
  const float scale = contentScale();
  const std::string displayName = sessionDisplayName();

  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Vertical);
  tab->setAlign(FlexAlign::Stretch);
  tab->setGap(Style::spaceMd * scale);
  m_rootLayout = tab.get();

  // --- User card ---
  auto userCard = std::make_unique<Flex>();
  applyOverviewCardStyle(*userCard, scale);
  userCard->setFlexGrow(1.0f);
  userCard->setFillHeight(true);
  userCard->setJustify(FlexJustify::Center);
  m_userCard = userCard.get();

  {
    auto wpBg = std::make_unique<Image>();
    wpBg->setFit(ImageFit::Cover);
    wpBg->setRadius(std::max(0.0f, Style::radiusXl * scale - Style::borderWidth));
    wpBg->setParticipatesInLayout(false);
    wpBg->setZIndex(-1);
    m_wallpaperBg = wpBg.get();
    userCard->addChild(std::move(wpBg));

    auto gradient = std::make_unique<RectNode>();
    gradient->setParticipatesInLayout(false);
    gradient->setZIndex(-1);
    m_wallpaperGradient = gradient.get();
    userCard->addChild(std::move(gradient));
  }

  auto userRow = std::make_unique<Flex>();
  userRow->setDirection(FlexDirection::Horizontal);
  userRow->setAlign(FlexAlign::Center);
  userRow->setGap(Style::spaceMd * scale);

  const float avatarSize = overviewAvatarSize(scale);
  auto avatar = std::make_unique<Image>();
  avatar->setRadius(avatarSize * 0.5f);
  avatar->setBorder(colorSpecFromRole(ColorRole::Primary), Style::borderWidth * 3.0f);
  avatar->setFit(ImageFit::Cover);
  avatar->setPadding(1.0f * scale);
  avatar->setSize(avatarSize, avatarSize);
  m_userAvatar = avatar.get();
  userRow->addChild(std::move(avatar));

  auto userMain = std::make_unique<Flex>();
  userMain->setDirection(FlexDirection::Vertical);
  userMain->setAlign(FlexAlign::Stretch);
  userMain->setJustify(FlexJustify::Center);
  userMain->setGap(Style::spaceXs * 0.5f * scale);
  userMain->setFlexGrow(1.0f);
  userMain->setMinHeight(avatarSize);
  userMain->setSize(0.0f, avatarSize);
  m_userMain = userMain.get();

  auto userTitle = std::make_unique<Label>();
  userTitle->setText(displayName);
  userTitle->setBold(true);
  userTitle->setFontSize(Style::fontSizeTitle * 1.12f * scale);
  userTitle->setColor(colorSpecFromRole(ColorRole::OnSurface));
  userTitle->setShadow(Color{0.0f, 0.0f, 0.0f, 0.42f}, 0.0f, 1.0f * scale);
  userMain->addChild(std::move(userTitle));

  auto userFacts = std::make_unique<Label>();
  userFacts->setText("…");
  userFacts->setFontSize(Style::fontSizeCaption * scale);
  userFacts->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  userFacts->setShadow(Color{0.0f, 0.0f, 0.0f, 0.36f}, 0.0f, 1.0f * scale);
  m_userFacts = userFacts.get();
  userMain->addChild(std::move(userFacts));

  userRow->addChild(std::move(userMain));
  userCard->addChild(std::move(userRow));
  tab->addChild(std::move(userCard));

  auto middleRow = std::make_unique<Flex>();
  middleRow->setDirection(FlexDirection::Horizontal);
  middleRow->setAlign(FlexAlign::Stretch);
  middleRow->setGap(Style::spaceMd * scale);
  middleRow->setFillWidth(true);

  // --- Date/Time + Weather ---
  auto dateTimeCard = std::make_unique<Flex>();
  applyOverviewCardStyle(*dateTimeCard, scale);
  dateTimeCard->setDirection(FlexDirection::Horizontal);
  dateTimeCard->setJustify(FlexJustify::Center);
  dateTimeCard->setFillWidth(true);
  dateTimeCard->setFlexGrow(2.0f);
  m_dateTimeCard = dateTimeCard.get();

  auto dateTimeContent = std::make_unique<Flex>();
  dateTimeContent->setDirection(FlexDirection::Vertical);
  dateTimeContent->setAlign(FlexAlign::Center);
  dateTimeContent->setJustify(FlexJustify::Center);
  dateTimeContent->setGap(Style::spaceXs * scale);

  auto timeLabel = std::make_unique<Label>();
  timeLabel->setText(formatLocalTime("{:%H:%M}"));
  timeLabel->setBold(true);
  timeLabel->setFontSize(Style::fontSizeTitle * 1.8f * scale);
  timeLabel->setColor(colorSpecFromRole(ColorRole::Primary));
  m_timeLabel = timeLabel.get();
  dateTimeContent->addChild(std::move(timeLabel));

  auto dateLabel = std::make_unique<Label>();
  dateLabel->setText(formatCurrentDate());
  dateLabel->setFontSize(Style::fontSizeBody * scale);
  dateLabel->setColor(colorSpecFromRole(ColorRole::OnSurface));
  m_dateLabel = dateLabel.get();
  dateTimeContent->addChild(std::move(dateLabel));

  auto weatherRow = std::make_unique<Flex>();
  weatherRow->setDirection(FlexDirection::Horizontal);
  weatherRow->setAlign(FlexAlign::Center);
  weatherRow->setGap(Style::spaceXs * scale);

  auto wGlyph = std::make_unique<Glyph>();
  wGlyph->setGlyph("weather-cloud-sun");
  wGlyph->setGlyphSize(Style::fontSizeBody * scale);
  wGlyph->setColor(colorSpecFromRole(ColorRole::Primary));
  m_weatherGlyph = wGlyph.get();

  auto wLine = std::make_unique<Label>();
  wLine->setText("—");
  wLine->setFontSize(Style::fontSizeCaption * scale);
  wLine->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  m_weatherLine = wLine.get();

  weatherRow->addChild(std::move(wGlyph));
  weatherRow->addChild(std::move(wLine));
  dateTimeContent->addChild(std::move(weatherRow));
  dateTimeCard->addChild(std::move(dateTimeContent));

  // --- Media ---
  auto mediaCard = std::make_unique<Flex>();
  applyOverviewCardStyle(*mediaCard, scale);
  mediaCard->setFlexGrow(3.0f);
  mediaCard->setGap(Style::spaceXs * scale);
  m_mediaCard = mediaCard.get();

  auto mediaContent = std::make_unique<Flex>();
  mediaContent->setDirection(FlexDirection::Horizontal);
  mediaContent->setAlign(FlexAlign::Center);
  mediaContent->setGap(Style::spaceSm * scale);

  const float artSize = Style::controlHeightLg * 1.55f * scale;
  auto mediaArt = std::make_unique<Image>();
  mediaArt->setSize(artSize, artSize);
  mediaArt->setRadius(Style::radiusLg * scale);
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
  mediaTrack->setText("...");
  mediaTrack->setFontSize(Style::fontSizeBody * scale);
  mediaTrack->setColor(colorSpecFromRole(ColorRole::OnSurface));
  m_mediaTrack = mediaTrack.get();

  auto mediaArtist = std::make_unique<Label>();
  mediaArtist->setText(i18n::tr("control-center.overview.media.no-active-player"));
  mediaArtist->setFontSize(Style::fontSizeCaption * scale);
  mediaArtist->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  m_mediaArtist = mediaArtist.get();

  auto mediaStatus = std::make_unique<Label>();
  mediaStatus->setText(i18n::tr("control-center.overview.media.idle"));
  mediaStatus->setFontSize(Style::fontSizeCaption * scale);
  mediaStatus->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  m_mediaStatus = mediaStatus.get();

  auto mediaProgress = std::make_unique<Label>();
  mediaProgress->setText(" ");
  mediaProgress->setFontSize(Style::fontSizeCaption * scale);
  mediaProgress->setColor(colorSpecFromRole(ColorRole::Secondary));
  mediaProgress->setVisible(false);
  m_mediaProgress = mediaProgress.get();

  mediaText->addChild(std::move(mediaTrack));
  mediaText->addChild(std::move(mediaArtist));
  mediaText->addChild(std::move(mediaStatus));
  mediaText->addChild(std::move(mediaProgress));
  mediaContent->addChild(std::move(mediaText));
  mediaCard->addChild(std::move(mediaContent));
  middleRow->addChild(std::move(mediaCard));
  middleRow->addChild(std::move(dateTimeCard));

  tab->addChild(std::move(middleRow));

  // --- Shortcuts ---
  const auto& shortcuts =
      m_config != nullptr ? m_config->config().controlCenter.shortcuts : std::vector<ShortcutConfig>{};
  const std::size_t count = std::min(shortcuts.size(), std::size_t{8});

  auto grid = std::make_unique<GridView>();
  grid->setColumns(4);
  grid->setColumnGap(Style::spaceSm * scale);
  grid->setRowGap(Style::spaceSm * scale);
  grid->setUniformCellSize(true);
  grid->setStretchItems(true);
  grid->setMinCellHeight(Style::controlHeightLg * 1.5f * scale);
  grid->setFlexGrow(0.0f);
  m_shortcutsGrid = grid.get();
  m_shortcutPads.clear();

  for (std::size_t i = 0; i < count; ++i) {
    const auto& sc = shortcuts[i];
    auto shortcut = ShortcutRegistry::create(sc.type, m_services);
    if (shortcut == nullptr) {
      continue;
    }

    const std::string label = sc.label.has_value() ? *sc.label : shortcut->displayLabel();
    const bool isActive = shortcut->isToggle() && shortcut->active();

    auto btn = std::make_unique<Button>();
    btn->setGlyph(shortcut->displayIcon());
    btn->setGlyphSize(Style::fontSizeTitle * 1.5f * scale);
    btn->setText(label);
    btn->label()->setFontSize(Style::fontSizeCaption * scale);
    btn->label()->setMaxLines(1);
    btn->setDirection(FlexDirection::Vertical);
    btn->setGap(Style::spaceXs * scale);
    btn->setMinHeight(0.0f);
    btn->setPadding(Style::spaceMd * scale);
    btn->setRadius(Style::radiusLg * scale);
    btn->setVariant(isActive ? ButtonVariant::Accent : ButtonVariant::Outline);

    const std::size_t padIdx = m_shortcutPads.size();
    btn->setOnClick([this, padIdx]() {
      if (padIdx < m_shortcutPads.size()) {
        m_shortcutPads[padIdx].shortcut->onClick();
      }
    });
    btn->setOnRightClick([this, padIdx]() {
      if (padIdx < m_shortcutPads.size()) {
        m_shortcutPads[padIdx].shortcut->onRightClick();
      }
    });

    Button* btnPtr = btn.get();
    ShortcutPad pad;
    pad.shortcut = std::move(shortcut);
    pad.button = btnPtr;
    pad.glyph = btnPtr->glyph();
    pad.label = btnPtr->label();
    pad.labelOverride = sc.label;
    m_shortcutPads.push_back(std::move(pad));
    grid->addChild(std::move(btn));
  }

  tab->addChild(std::move(grid));

  return tab;
}

std::unique_ptr<Flex> OverviewTab::createHeaderActions() {
  const float scale = contentScale();
  auto actions = std::make_unique<Flex>();
  actions->setDirection(FlexDirection::Horizontal);
  actions->setAlign(FlexAlign::Center);
  actions->setGap(Style::spaceSm * scale);

  auto settingsBtn = std::make_unique<Button>();
  settingsBtn->setGlyph("settings");
  settingsBtn->setVariant(ButtonVariant::Default);
  settingsBtn->setGlyphSize(Style::fontSizeBody * scale);
  settingsBtn->setMinWidth(Style::controlHeightSm * scale);
  settingsBtn->setMinHeight(Style::controlHeightSm * scale);
  settingsBtn->setPadding(Style::spaceXs * scale);
  settingsBtn->setRadius(Style::radiusMd * scale);
  settingsBtn->setOnClick([]() { PanelManager::instance().openSettingsWindow(); });
  m_settingsButton = settingsBtn.get();
  actions->addChild(std::move(settingsBtn));

  return actions;
}

void OverviewTab::doLayout(Renderer& renderer, float contentWidth, float bodyHeight) {
  (void)bodyHeight;
  if (m_rootLayout == nullptr) {
    return;
  }

  // Cap shortcut labels to the cell text area so long labels elide rather than
  // stretching the button and breaking the uniform grid.
  if (!m_shortcutPads.empty()) {
    const float scale = contentScale();
    const float cellWidth = (contentWidth - 3.0f * Style::spaceSm * scale) / 4.0f;
    const float labelMaxWidth = std::max(1.0f, cellWidth - 2.0f * Style::spaceMd * scale);
    for (auto& pad : m_shortcutPads) {
      if (pad.label != nullptr) {
        pad.label->setMaxWidth(labelMaxWidth);
      }
    }
  }

  if (m_dateTimeCard != nullptr) {
    m_dateTimeCard->setMinHeight(0.0f);
  }
  if (m_mediaCard != nullptr) {
    m_mediaCard->setMinHeight(0.0f);
  }
  if (m_userAvatar != nullptr && m_userMain != nullptr) {
    const float userMainHeight = std::max(1.0f, m_userAvatar->height());
    m_userMain->setMinHeight(userMainHeight);
    m_userMain->setSize(m_userMain->width(), userMainHeight);
  }
  m_rootLayout->setSize(contentWidth, bodyHeight);
  m_rootLayout->layout(renderer);

  const auto innerWidth = [](Flex* card) {
    if (card == nullptr) {
      return 1.0f;
    }
    return std::max(1.0f, card->width() - (card->paddingLeft() + card->paddingRight()));
  };
  const float dateTimeWrap = innerWidth(m_dateTimeCard);
  const float mediaWrap = innerWidth(m_mediaCard);

  for (Label* label : {m_timeLabel, m_dateLabel, m_weatherLine}) {
    if (label != nullptr) {
      label->setMaxWidth(dateTimeWrap);
      label->setMaxLines(1);
    }
  }
  if (m_mediaCard != nullptr && m_mediaArt != nullptr && m_mediaText != nullptr) {
    const float textWidth = std::max(1.0f, mediaWrap - m_mediaArt->width() - (Style::spaceSm * contentScale()));
    for (Label* label : {m_mediaTrack, m_mediaArtist, m_mediaStatus, m_mediaProgress}) {
      if (label != nullptr) {
        label->setMaxWidth(textWidth);
        label->setMaxLines(1);
      }
    }
  }

  if (m_userCard != nullptr && m_userFacts != nullptr) {
    const float userWrap = innerWidth(m_userCard);
    m_userFacts->setMaxWidth(userWrap);
    m_userFacts->setMaxLines(1);
  }

  if (m_dateTimeCard != nullptr && m_mediaCard != nullptr) {
    const float unifiedCardHeight = std::max(m_dateTimeCard->height(), m_mediaCard->height());
    m_dateTimeCard->setMinHeight(unifiedCardHeight);
    m_mediaCard->setMinHeight(unifiedCardHeight);
  }

  if (m_userAvatar != nullptr && m_userMain != nullptr) {
    const float scale = contentScale();
    const float minAvatar = overviewAvatarSize(scale);
    const float desiredAvatar = std::max(minAvatar, m_userMain->height());
    if (std::abs(m_userAvatar->width() - desiredAvatar) > 0.5f) {
      m_userAvatar->setSize(desiredAvatar, desiredAvatar);
      m_userAvatar->setRadius(desiredAvatar * 0.5f);
      m_userAvatar->setPadding(1.0f * scale);
    }
    m_userMain->setMinHeight(desiredAvatar);
    m_userMain->setSize(m_userMain->width(), desiredAvatar);
  }

  m_rootLayout->layout(renderer);
  layoutWallpaperBackground(renderer);
  if (m_weatherGlyph != nullptr) {
    m_weatherGlyph->measure(renderer);
  }
}

void OverviewTab::layoutWallpaperBackground(Renderer& renderer) {
  if (m_userCard == nullptr || m_wallpaperBg == nullptr) {
    return;
  }

  const float bw = Style::borderWidth;
  const float cw = std::max(0.0f, m_userCard->width() - bw * 2.0f);
  const float ch = std::max(0.0f, m_userCard->height() - bw * 2.0f);
  m_wallpaperBg->setPosition(bw, bw);
  m_wallpaperBg->setSize(cw, ch);

  if (m_wallpaperGradient != nullptr) {
    const float radius = std::max(0.0f, Style::radiusXl * contentScale() - bw);
    m_wallpaperGradient->setPosition(bw, bw);
    m_wallpaperGradient->setFrameSize(cw, ch);
    const Color surface = colorForRole(ColorRole::Surface);
    const Color translucentSurface = rgba(surface.r, surface.g, surface.b, surface.a * 0.9f);
    const Color transparentSurface = rgba(surface.r, surface.g, surface.b, 0.0f);
    m_wallpaperGradient->setStyle(RoundedRectStyle{
        .fill = surface,
        .fillMode = FillMode::LinearGradient,
        .gradientDirection = GradientDirection::Horizontal,
        .gradientStops = {GradientStop{0.0f, translucentSurface}, GradientStop{0.25f, translucentSurface},
                          GradientStop{0.9f, transparentSurface}, GradientStop{1.0f, transparentSurface}},
        .radius = radius,
    });
  }

  syncWallpaperBackground(renderer);
}

void OverviewTab::syncWallpaperBackground(Renderer& renderer) {
  if (m_wallpaperBg == nullptr) {
    return;
  }

  const TextureHandle source = m_wallpaper != nullptr ? m_wallpaper->currentTexture() : TextureHandle{};
  if (!source.valid()) {
    m_wallpaperBg->clear(renderer);
    m_wallpaperBg->setVisible(false);
    return;
  }

  if (m_wallpaperBg->width() <= 0.0f || m_wallpaperBg->height() <= 0.0f) {
    m_wallpaperBg->setVisible(false);
    return;
  }

  m_wallpaperBg->setExternalTexture(renderer, source);
  m_wallpaperBg->setVisible(true);
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
  m_dateTimeCard = nullptr;
  m_mediaCard = nullptr;
  m_mediaText = nullptr;
  m_userCard = nullptr;
  m_userMain = nullptr;
  m_userAvatar = nullptr;
  m_timeLabel = nullptr;
  m_dateLabel = nullptr;
  m_weatherGlyph = nullptr;
  m_weatherLine = nullptr;
  m_userFacts = nullptr;
  m_settingsButton = nullptr;
  m_loadedAvatarPath.clear();
  m_wallpaperBg = nullptr;
  m_wallpaperGradient = nullptr;
  m_mediaTrack = nullptr;
  m_mediaArtist = nullptr;
  m_mediaStatus = nullptr;
  m_mediaProgress = nullptr;
  m_mediaArt = nullptr;
  m_loadedMediaArtUrl.clear();
  m_shortcutsGrid = nullptr;
  m_shortcutPads.clear();
}

void OverviewTab::sync(Renderer& renderer) {
  syncShortcuts();

  if (m_timeLabel != nullptr) {
    m_timeLabel->setText(formatLocalTime("{:%H:%M}"));
  }
  if (m_dateLabel != nullptr) {
    m_dateLabel->setText(formatCurrentDate());
  }

  syncWallpaperBackground(renderer);

  if (m_userAvatar != nullptr && m_config != nullptr) {
    const std::string avatarPath = m_config->config().shell.avatarPath;
    if (avatarPath != m_loadedAvatarPath) {
      if (avatarPath.empty()) {
        m_userAvatar->clear(renderer);
      } else {
        m_userAvatar->setSourceFile(renderer, avatarPath, static_cast<int>(std::round(m_userAvatar->width())), true);
      }
      m_loadedAvatarPath = avatarPath;
    }
  }

  if (m_userFacts != nullptr) {
    const auto uptime = systemUptime();
    const std::string uptimeText =
        uptime.has_value() ? formatDuration(*uptime) : i18n::tr("control-center.overview.unknown");
    m_userFacts->setText(i18n::tr("control-center.overview.user-facts", "user", sessionDisplayName(), "host",
                                  hostName(), "uptime", uptimeText, "version", noctalia::build_info::displayVersion()));
  }

  if (m_weatherGlyph != nullptr && m_weatherLine != nullptr) {
    if (m_weather == nullptr || !m_weather->enabled()) {
      m_weatherGlyph->setGlyph("weather-cloud-off");
      m_weatherGlyph->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
      m_weatherLine->setText(i18n::tr("control-center.overview.weather.disabled"));
    } else if (!m_weather->locationConfigured()) {
      m_weatherGlyph->setGlyph("weather-cloud");
      m_weatherGlyph->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
      m_weatherLine->setText(i18n::tr("control-center.overview.weather.configure-location"));
    } else {
      const auto& snapshot = m_weather->snapshot();
      if (!snapshot.valid) {
        m_weatherGlyph->setGlyph("weather-cloud");
        m_weatherGlyph->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
        m_weatherLine->setText(m_weather->loading() ? i18n::tr("control-center.overview.weather.fetching")
                                                    : i18n::tr("control-center.overview.weather.data-unavailable"));
      } else {
        m_weatherGlyph->setGlyph(WeatherService::glyphForCode(snapshot.current.weatherCode, snapshot.current.isDay));
        m_weatherGlyph->setColor(colorSpecFromRole(ColorRole::Primary));
        const int t = static_cast<int>(std::lround(m_weather->displayTemperature(snapshot.current.temperatureC)));
        m_weatherLine->setText(std::format("{}{} · {}", t, m_weather->displayTemperatureUnit(),
                                           WeatherService::descriptionForCode(snapshot.current.weatherCode)));
      }
    }
  }

  if (m_mediaTrack != nullptr && m_mediaArtist != nullptr && m_mediaStatus != nullptr && m_mediaProgress != nullptr) {
    if (m_mpris == nullptr) {
      m_mediaTrack->setText(i18n::tr("control-center.overview.media.playback-unavailable"));
      m_mediaArtist->setText(i18n::tr("control-center.overview.media.service-unavailable"));
      m_mediaStatus->setText(i18n::tr("control-center.overview.media.unavailable"));
      m_mediaProgress->setText(" ");
      m_mediaProgress->setVisible(false);
      m_mediaStatus->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
      if (m_mediaArt != nullptr) {
        m_mediaArt->clear(renderer);
      }
      m_loadedMediaArtUrl.clear();
    } else {
      const auto active = m_mpris->activePlayer();
      if (!active.has_value()) {
        m_mediaTrack->setText(i18n::tr("control-center.overview.media.nothing-playing"));
        m_mediaArtist->setText(i18n::tr("control-center.overview.media.play-media-hint"));
        m_mediaStatus->setText(i18n::tr("control-center.overview.media.idle"));
        m_mediaProgress->setText(" ");
        m_mediaProgress->setVisible(false);
        m_mediaStatus->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
        if (m_mediaArt != nullptr) {
          m_mediaArt->clear(renderer);
        }
        m_loadedMediaArtUrl.clear();
      } else {
        m_mediaTrack->setText(active->title.empty() ? i18n::tr("control-center.overview.media.unknown-track")
                                                    : active->title);
        const std::string artists = mpris::joinArtists(active->artists);
        m_mediaArtist->setText(artists.empty() ? i18n::tr("control-center.overview.media.unknown-artist") : artists);
        if (active->lengthUs > 0) {
          const std::int64_t positionSec = std::max<std::int64_t>(0, active->positionUs / 1000000);
          const std::int64_t lengthSec = std::max<std::int64_t>(1, active->lengthUs / 1000000);
          m_mediaProgress->setText(std::format("{} / {}", formatClockTime(positionSec), formatClockTime(lengthSec)));
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
          m_mediaStatus->setText(i18n::tr("control-center.overview.media.playing"));
          m_mediaStatus->setColor(colorSpecFromRole(ColorRole::Primary));
        } else if (active->playbackStatus == "Paused") {
          m_mediaStatus->setText(i18n::tr("control-center.overview.media.paused"));
          m_mediaStatus->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
        } else {
          m_mediaStatus->setText(active->playbackStatus);
          m_mediaStatus->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
        }
      }
    }
  }
}

void OverviewTab::syncShortcuts() {
  for (auto& pad : m_shortcutPads) {
    auto& sc = *pad.shortcut;
    const bool on = sc.isToggle() && sc.active();

    if (pad.button != nullptr) {
      pad.button->setVariant(on ? ButtonVariant::Accent : ButtonVariant::Outline);
    }
    if (pad.glyph != nullptr) {
      pad.glyph->setGlyph(sc.displayIcon());
    }
    if (pad.button != nullptr && pad.label != nullptr) {
      const std::string label = pad.labelOverride.has_value() ? *pad.labelOverride : sc.displayLabel();
      if (pad.label->text() != label) {
        pad.button->setText(label);
      }
    }
  }
}
