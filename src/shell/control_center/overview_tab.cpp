#include "shell/control_center/overview_tab.h"

#include "config/config_service.h"
#include "core/build_info.h"
#include "i18n/i18n.h"
#include "shell/control_center/shortcut_registry.h"
#include "shell/panel/panel_manager.h"
#include "system/distro_info.h"
#include "system/weather_service.h"
#include "time/time_format.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/grid_view.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"

#include <cmath>
#include <format>
#include <memory>
#include <string>

using namespace control_center;

namespace {

  void applyOverviewCardStyle(Flex& card, float scale) {
    applySectionCardStyle(card, scale);
    card.setGap(Style::spaceSm * scale);
  }

} // namespace

OverviewTab::OverviewTab(MprisService* mpris, WeatherService* weather, PipeWireService* audio,
                         PowerProfilesService* powerProfiles, ConfigService* config, NetworkService* network,
                         BluetoothService* bluetooth, NightLightManager* nightLight,
                         noctalia::theme::ThemeService* theme, NotificationManager* notifications,
                         IdleInhibitor* idleInhibitor)
    : m_config(config), m_services{network,       bluetooth, nightLight,    theme, notifications,
                                   idleInhibitor, audio,     powerProfiles, mpris, weather} {}

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
  m_userCard = userCard.get();

  auto userRow = std::make_unique<Flex>();
  userRow->setDirection(FlexDirection::Horizontal);
  userRow->setAlign(FlexAlign::Center);
  userRow->setGap(Style::spaceMd * scale);

  const float avatarSize = Style::controlHeightLg * 3.2f * scale;
  auto avatar = std::make_unique<Image>();
  avatar->setRadius(avatarSize * 0.5f);
  avatar->setBorder(roleColor(ColorRole::Primary), Style::borderWidth * 3.0f);
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
  m_userMain = userMain.get();

  auto userTitle = std::make_unique<Label>();
  userTitle->setText(displayName);
  userTitle->setBold(true);
  userTitle->setFontSize(Style::fontSizeTitle * 1.12f * scale);
  userTitle->setColor(roleColor(ColorRole::OnSurface));
  userMain->addChild(std::move(userTitle));

  auto userFacts = std::make_unique<Label>();
  userFacts->setText("…");
  userFacts->setFontSize(Style::fontSizeCaption * scale);
  userFacts->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_userFacts = userFacts.get();
  userMain->addChild(std::move(userFacts));

  userRow->addChild(std::move(userMain));
  userCard->addChild(std::move(userRow));
  tab->addChild(std::move(userCard));

  // --- Date/Time + Weather ---
  auto dateTimeCard = std::make_unique<Flex>();
  applyOverviewCardStyle(*dateTimeCard, scale);
  dateTimeCard->setDirection(FlexDirection::Horizontal);
  dateTimeCard->setJustify(FlexJustify::Center);
  dateTimeCard->setFillParentMainAxis(true);

  auto dateTimeContent = std::make_unique<Flex>();
  dateTimeContent->setDirection(FlexDirection::Vertical);
  dateTimeContent->setAlign(FlexAlign::Center);
  dateTimeContent->setJustify(FlexJustify::Center);
  dateTimeContent->setGap(Style::spaceXs * scale);

  auto timeLabel = std::make_unique<Label>();
  timeLabel->setText(formatLocalTime("{:%H:%M}"));
  timeLabel->setBold(true);
  timeLabel->setFontSize(Style::fontSizeTitle * 2.2f * scale);
  timeLabel->setColor(roleColor(ColorRole::Primary));
  m_timeLabel = timeLabel.get();
  dateTimeContent->addChild(std::move(timeLabel));

  auto dateLabel = std::make_unique<Label>();
  dateLabel->setText(formatCurrentDate());
  dateLabel->setFontSize(Style::fontSizeBody * scale);
  dateLabel->setColor(roleColor(ColorRole::OnSurface));
  m_dateLabel = dateLabel.get();
  dateTimeContent->addChild(std::move(dateLabel));

  auto weatherRow = std::make_unique<Flex>();
  weatherRow->setDirection(FlexDirection::Horizontal);
  weatherRow->setAlign(FlexAlign::Center);
  weatherRow->setGap(Style::spaceXs * scale);

  auto wGlyph = std::make_unique<Glyph>();
  wGlyph->setGlyph("weather-cloud-sun");
  wGlyph->setGlyphSize(Style::fontSizeBody * scale);
  wGlyph->setColor(roleColor(ColorRole::Primary));
  m_weatherGlyph = wGlyph.get();

  auto wLine = std::make_unique<Label>();
  wLine->setText("—");
  wLine->setFontSize(Style::fontSizeCaption * scale);
  wLine->setColor(roleColor(ColorRole::OnSurfaceVariant));
  m_weatherLine = wLine.get();

  weatherRow->addChild(std::move(wGlyph));
  weatherRow->addChild(std::move(wLine));
  dateTimeContent->addChild(std::move(weatherRow));
  dateTimeCard->addChild(std::move(dateTimeContent));
  tab->addChild(std::move(dateTimeCard));

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
  grid->setMinCellHeight(Style::controlHeightLg * 2.0f * scale);
  grid->setFlexGrow(1.0f);
  m_shortcutsGrid = grid.get();
  m_shortcutPads.clear();

  for (std::size_t i = 0; i < count; ++i) {
    const auto& sc = shortcuts[i];
    auto shortcut = ShortcutRegistry::create(sc.type, m_services);
    if (shortcut == nullptr) {
      continue;
    }

    const std::string label = sc.label.value_or(std::string(shortcut->defaultLabel()));
    const bool isActive = shortcut->isToggle() && shortcut->active();

    auto btn = std::make_unique<Button>();
    btn->setGlyph(std::string(shortcut->currentIcon()));
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

    Label* descPtr = nullptr;
    if (shortcut->hasDescription()) {
      auto desc = std::make_unique<Label>();
      desc->setText("");
      desc->setFontSize(Style::fontSizeCaption * 0.8f * scale);
      desc->setMaxLines(1);
      descPtr = static_cast<Label*>(btn->addChild(std::move(desc)));
    }

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
    pad.description = descPtr;
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
  m_rootLayout->setSize(contentWidth, bodyHeight);
  m_rootLayout->layout(renderer);

  if (m_userCard != nullptr && m_userFacts != nullptr) {
    const float userWrap =
        std::max(1.0f, m_userCard->width() - (m_userCard->paddingLeft() + m_userCard->paddingRight()));
    m_userFacts->setMaxWidth(userWrap);
    m_userFacts->setMaxLines(1);
  }

  if (m_userAvatar != nullptr && m_userMain != nullptr) {
    const float scale = contentScale();
    const float minAvatar = Style::controlHeightLg * 3.2f * scale;
    const float desiredAvatar = std::max(minAvatar, m_userMain->height());
    if (std::abs(m_userAvatar->width() - desiredAvatar) > 0.5f) {
      m_userAvatar->setSize(desiredAvatar, desiredAvatar);
      m_userAvatar->setRadius(Style::radiusLg * scale);
      m_userAvatar->setPadding(1.0f * scale);
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
    const std::string uptimeText =
        uptime.has_value() ? formatDuration(*uptime) : i18n::tr("control-center.overview.unknown");
    m_userFacts->setText(i18n::tr("control-center.overview.user-facts", "user", sessionDisplayName(), "host",
                                  hostName(), "uptime", uptimeText, "version", noctalia::build_info::displayVersion()));
  }

  if (m_weatherGlyph != nullptr && m_weatherLine != nullptr) {
    if (m_services.weather == nullptr || !m_services.weather->enabled()) {
      m_weatherGlyph->setGlyph("weather-cloud-off");
      m_weatherGlyph->setColor(roleColor(ColorRole::OnSurfaceVariant));
      m_weatherLine->setText(i18n::tr("control-center.overview.weather.disabled"));
    } else if (!m_services.weather->locationConfigured()) {
      m_weatherGlyph->setGlyph("weather-cloud");
      m_weatherGlyph->setColor(roleColor(ColorRole::OnSurfaceVariant));
      m_weatherLine->setText(i18n::tr("control-center.overview.weather.configure-location"));
    } else {
      const auto& snapshot = m_services.weather->snapshot();
      if (!snapshot.valid) {
        m_weatherGlyph->setGlyph("weather-cloud");
        m_weatherGlyph->setColor(roleColor(ColorRole::OnSurfaceVariant));
        m_weatherLine->setText(m_services.weather->loading()
                                   ? i18n::tr("control-center.overview.weather.fetching")
                                   : i18n::tr("control-center.overview.weather.data-unavailable"));
      } else {
        m_weatherGlyph->setGlyph(WeatherService::glyphForCode(snapshot.current.weatherCode, snapshot.current.isDay));
        m_weatherGlyph->setColor(roleColor(ColorRole::Primary));
        const int t =
            static_cast<int>(std::lround(m_services.weather->displayTemperature(snapshot.current.temperatureC)));
        m_weatherLine->setText(std::format("{}{} · {}", t, m_services.weather->displayTemperatureUnit(),
                                           WeatherService::descriptionForCode(snapshot.current.weatherCode)));
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
      pad.glyph->setGlyph(std::string(sc.currentIcon()));
    }
    if (pad.description != nullptr && sc.hasDescription()) {
      pad.description->setText(sc.description());
    }
  }
}
