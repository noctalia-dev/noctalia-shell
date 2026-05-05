#include "shell/control_center/overview_tab.h"

#include "config/config_service.h"
#include "core/build_info.h"
#include "dbus/mpris/mpris_art.h"
#include "dbus/mpris/mpris_service.h"
#include "i18n/i18n.h"
#include "shell/control_center/shortcut_registry.h"
#include "shell/panel/panel_manager.h"
#include "shell/wallpaper/wallpaper.h"
#include "system/distro_info.h"
#include "system/weather_service.h"
#include "time/time_format.h"
#include "ui/controls/box.h"
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
  // Bottom row: 1 : 1 — equal split so media/clock and shortcuts feel balanced (tweak either value slightly if needed).
  constexpr float kOverviewMainColumnFlexGrow = 1.66f;
  constexpr float kOverviewShortcutsFlexGrow = 1.0f;
  constexpr auto kOverviewRealtimeUpdateInterval = std::chrono::milliseconds(1000);
  constexpr auto kOverviewMprisPollInterval = std::chrono::milliseconds(1000);
  constexpr auto kOverviewTransientPositionRegressionWindow = std::chrono::milliseconds(1500);
  constexpr std::int64_t kOverviewTransientPositionRegressionFloorUs = 5'000'000;
  constexpr std::int64_t kOverviewTransientPositionRegressionCeilingUs = 1'500'000;
  constexpr std::int64_t kOverviewTransientPositionRegressionDeltaUs = 5'000'000;

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

    auto gradient = std::make_unique<Box>();
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

  auto bottomRow = std::make_unique<Flex>();
  bottomRow->setDirection(FlexDirection::Horizontal);
  bottomRow->setAlign(FlexAlign::Stretch);
  bottomRow->setGap(Style::spaceMd * scale);
  bottomRow->setFillWidth(true);
  m_bottomRow = bottomRow.get();

  auto leftColumn = std::make_unique<Flex>();
  leftColumn->setDirection(FlexDirection::Vertical);
  leftColumn->setAlign(FlexAlign::Stretch);
  leftColumn->setJustify(FlexJustify::Start);
  leftColumn->setGap(Style::spaceSm * scale);
  leftColumn->setFlexGrow(kOverviewMainColumnFlexGrow);
  leftColumn->setFillWidth(true);

  // --- Media (top of left column) ---
  auto mediaCard = std::make_unique<Flex>();
  applyOverviewCardStyle(*mediaCard, scale);
  mediaCard->setFillWidth(true);
  mediaCard->setFillHeight(true);
  mediaCard->setFlexGrow(1.4f);
  mediaCard->setJustify(FlexJustify::Center);
  mediaCard->setGap(Style::spaceXs * scale);
  m_mediaCard = mediaCard.get();

  auto mediaContent = std::make_unique<Flex>();
  mediaContent->setDirection(FlexDirection::Horizontal);
  mediaContent->setAlign(FlexAlign::Center);
  mediaContent->setGap(Style::spaceSm * scale);

  const float artSize = Style::controlHeightLg * 1.22f * scale;
  auto artSlot = std::make_unique<Flex>();
  artSlot->setDirection(FlexDirection::Vertical);
  artSlot->setAlign(FlexAlign::Center);
  artSlot->setJustify(FlexJustify::Center);
  artSlot->setSize(artSize, artSize);
  m_mediaArtSlot = artSlot.get();

  auto artFallback = std::make_unique<Glyph>();
  artFallback->setGlyph("disc-filled");
  artFallback->setGlyphSize(artSize * 0.55f);
  artFallback->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  m_mediaArtFallback = artFallback.get();
  artSlot->addChild(std::move(artFallback));

  auto mediaArt = std::make_unique<Image>();
  mediaArt->setSize(artSize, artSize);
  mediaArt->setRadius(Style::radiusLg * scale);
  mediaArt->setFit(ImageFit::Cover);
  mediaArt->setParticipatesInLayout(false);
  mediaArt->setZIndex(1);
  m_mediaArt = mediaArt.get();
  artSlot->addChild(std::move(mediaArt));

  mediaContent->addChild(std::move(artSlot));

  auto mediaText = std::make_unique<Flex>();
  mediaText->setDirection(FlexDirection::Vertical);
  mediaText->setAlign(FlexAlign::Stretch);
  mediaText->setGap(Style::spaceXs * 0.5f * scale);
  mediaText->setFlexGrow(1.0f);
  m_mediaText = mediaText.get();

  auto mediaTrack = std::make_unique<Label>();
  mediaTrack->setText("...");
  mediaTrack->setFontSize(Style::fontSizeBody * 0.95f * scale);
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

  // --- Date/Time + Weather (below media) ---
  auto dateTimeCard = std::make_unique<Flex>();
  applyOverviewCardStyle(*dateTimeCard, scale);
  dateTimeCard->setDirection(FlexDirection::Horizontal);
  dateTimeCard->setAlign(FlexAlign::Center);
  dateTimeCard->setJustify(FlexJustify::Center);
  dateTimeCard->setGap(Style::spaceLg * scale);
  dateTimeCard->setFillWidth(true);
  dateTimeCard->setFillHeight(true);
  dateTimeCard->setFlexGrow(1.0f);
  m_dateTimeCard = dateTimeCard.get();

  auto timeLabel = std::make_unique<Label>();
  timeLabel->setText(formatLocalTime("{:%H:%M}"));
  timeLabel->setBold(true);
  timeLabel->setFontSize(Style::fontSizeTitle * 1.7f * scale);
  timeLabel->setColor(colorSpecFromRole(ColorRole::Primary));
  m_timeLabel = timeLabel.get();
  dateTimeCard->addChild(std::move(timeLabel));

  auto dateTimeRight = std::make_unique<Flex>();
  dateTimeRight->setDirection(FlexDirection::Vertical);
  dateTimeRight->setAlign(FlexAlign::Start);
  dateTimeRight->setJustify(FlexJustify::Center);
  dateTimeRight->setGap(Style::spaceXs * 0.5f * scale);

  auto dateLabel = std::make_unique<Label>();
  dateLabel->setText(formatCurrentDate());
  dateLabel->setFontSize(Style::fontSizeBody * 0.9f * scale);
  dateLabel->setColor(colorSpecFromRole(ColorRole::OnSurface));
  m_dateLabel = dateLabel.get();
  dateTimeRight->addChild(std::move(dateLabel));

  auto weatherRow = std::make_unique<Flex>();
  weatherRow->setDirection(FlexDirection::Horizontal);
  weatherRow->setAlign(FlexAlign::Center);
  weatherRow->setGap(Style::spaceXs * scale);

  auto wGlyph = std::make_unique<Glyph>();
  wGlyph->setGlyph("weather-cloud-sun");
  wGlyph->setGlyphSize(Style::fontSizeCaption * 1.12f * scale);
  wGlyph->setColor(colorSpecFromRole(ColorRole::Primary));
  m_weatherGlyph = wGlyph.get();

  auto wLine = std::make_unique<Label>();
  wLine->setText("—");
  wLine->setFontSize(Style::fontSizeCaption * scale);
  wLine->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  m_weatherLine = wLine.get();

  weatherRow->addChild(std::move(wGlyph));
  weatherRow->addChild(std::move(wLine));
  dateTimeRight->addChild(std::move(weatherRow));
  dateTimeCard->addChild(std::move(dateTimeRight));

  leftColumn->addChild(std::move(mediaCard));
  leftColumn->addChild(std::move(dateTimeCard));
  bottomRow->addChild(std::move(leftColumn));

  // --- Shortcuts (right of media + clock) ---
  const auto& shortcuts =
      m_config != nullptr ? m_config->config().controlCenter.shortcuts : std::vector<ShortcutConfig>{};
  const std::size_t count = std::min(shortcuts.size(), std::size_t{6});

  auto grid = std::make_unique<GridView>();
  grid->setColumns(2);
  grid->setColumnGap(Style::spaceSm * scale);
  grid->setRowGap(Style::spaceSm * scale);
  grid->setPadding(0.0f);
  grid->setUniformCellSize(true);
  grid->setStretchItems(true);
  grid->setSquareCells(false);
  grid->setMinCellHeight(0.0f);
  grid->setFlexGrow(kOverviewShortcutsFlexGrow);
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
    btn->setGlyphSize(Style::fontSizeTitle * 1.35f * scale);
    btn->setText(label);
    // Match media card column: Stretch so label width follows the cell; Center uses intrinsic text width and fights
    // setMaxWidth.
    btn->setAlign(FlexAlign::Stretch);
    // Label font only — Button::setFontSize also resizes the glyph. Mini + uiScale keeps tiles closer to other CC rows
    // that use raw fontSizeCaption (no * contentScale), while still scaling with shell.uiScale for consistency inside
    // Overview.
    btn->label()->setFontSize(Style::fontSizeMini * scale);
    btn->label()->setBaselineMode(LabelBaselineMode::InkCentered);
    btn->label()->setMaxLines(1);
    btn->label()->setTextAlign(TextAlign::Center);
    btn->setDirection(FlexDirection::Vertical);
    btn->setGap(Style::spaceXs * scale);
    btn->setMinHeight(0.0f);
    btn->setPadding(Style::spaceSm * scale);
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

  bottomRow->addChild(std::move(grid));
  tab->addChild(std::move(bottomRow));

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

  auto sessionBtn = std::make_unique<Button>();
  sessionBtn->setGlyph("shutdown");
  sessionBtn->setVariant(ButtonVariant::Default);
  sessionBtn->setGlyphSize(Style::fontSizeBody * scale);
  sessionBtn->setMinWidth(Style::controlHeightSm * scale);
  sessionBtn->setMinHeight(Style::controlHeightSm * scale);
  sessionBtn->setPadding(Style::spaceXs * scale);
  sessionBtn->setRadius(Style::radiusMd * scale);
  sessionBtn->setOnClick([]() { PanelManager::instance().togglePanel("session"); });
  m_sessionButton = sessionBtn.get();
  actions->addChild(std::move(sessionBtn));

  return actions;
}

void OverviewTab::doLayout(Renderer& renderer, float contentWidth, float bodyHeight) {
  (void)bodyHeight;
  if (m_rootLayout == nullptr) {
    return;
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

  // Cap shortcut labels to the button's content width after cells are sized (avoids elide from grid math mismatch).
  if (!m_shortcutPads.empty() && m_shortcutsGrid != nullptr) {
    const float scale = contentScale();
    for (auto& pad : m_shortcutPads) {
      if (pad.label == nullptr) {
        continue;
      }
      float inner = 1.0f;
      if (pad.button != nullptr && pad.button->width() > 1.0f) {
        inner = std::max(1.0f, pad.button->width() - pad.button->paddingLeft() - pad.button->paddingRight());
      } else {
        const float gridW = m_shortcutsGrid->width();
        const float innerGrid =
            std::max(1.0f, gridW - m_shortcutsGrid->paddingLeft() - m_shortcutsGrid->paddingRight());
        const std::size_t cols = std::max<std::size_t>(1, std::min(m_shortcutsGrid->columns(), m_shortcutPads.size()));
        const float cellWidth =
            (innerGrid - static_cast<float>(cols - 1) * m_shortcutsGrid->columnGap()) / static_cast<float>(cols);
        inner = std::max(1.0f, cellWidth - 2.0f * Style::spaceSm * scale);
      }
      pad.label->setMaxWidth(inner);
    }
  }

  const auto innerWidth = [](Flex* card) {
    if (card == nullptr) {
      return 1.0f;
    }
    return std::max(1.0f, card->width() - (card->paddingLeft() + card->paddingRight()));
  };
  const float dateTimeWrap = innerWidth(m_dateTimeCard);

  for (Label* label : {m_timeLabel, m_dateLabel, m_weatherLine}) {
    if (label != nullptr) {
      label->setMaxWidth(dateTimeWrap);
      label->setMaxLines(1);
    }
  }
  // Grow the album art square to fill the media card height so the row feels balanced
  // when the card flex-grows. Done before label maxWidth so the text wrap width matches
  // the final art size on the very first frame.
  if (m_mediaCard != nullptr && m_mediaArt != nullptr && m_mediaArtSlot != nullptr) {
    const float scale = contentScale();
    const float minArt = Style::controlHeightLg * 1.22f * scale;
    const float maxArt = Style::controlHeightLg * 2.6f * scale;
    const float available =
        std::max(0.0f, m_mediaCard->height() - m_mediaCard->paddingTop() - m_mediaCard->paddingBottom());
    const float desired = std::clamp(available, minArt, maxArt);
    if (std::abs(m_mediaArtSlot->width() - desired) > 0.5f) {
      m_mediaArtSlot->setSize(desired, desired);
      m_mediaArt->setSize(desired, desired);
      m_mediaArt->setRadius(Style::radiusLg * scale);
      if (m_mediaArtFallback != nullptr) {
        m_mediaArtFallback->setGlyphSize(desired * 0.55f);
      }
    }
  }

  // Labels auto-wrap to mediaText's assigned width via Flex stretch propagation.
  for (Label* label : {m_mediaArtist, m_mediaStatus, m_mediaProgress}) {
    if (label != nullptr) {
      label->setMaxLines(1);
    }
  }
  if (m_mediaTrack != nullptr) {
    m_mediaTrack->setMaxLines(2);
  }

  if (m_userCard != nullptr && m_userFacts != nullptr) {
    const float userWrap = innerWidth(m_userCard);
    m_userFacts->setMaxWidth(userWrap);
    m_userFacts->setMaxLines(1);
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

  // Lock the shortcuts grid height to its square-cell natural size so it does not vary
  // when the media or clock cards change. The leftColumn stretches to match this height.
  if (m_shortcutsGrid != nullptr && !m_shortcutPads.empty()) {
    const float gridW = m_shortcutsGrid->width();
    const float innerGridW = std::max(1.0f, gridW - m_shortcutsGrid->paddingLeft() - m_shortcutsGrid->paddingRight());
    const std::size_t cols = std::max<std::size_t>(1, std::min(m_shortcutsGrid->columns(), m_shortcutPads.size()));
    const std::size_t rows = (m_shortcutPads.size() + cols - 1) / cols;
    const float cellWidth = std::max(1.0f, (innerGridW - static_cast<float>(cols - 1) * m_shortcutsGrid->columnGap()) /
                                               static_cast<float>(cols));
    // Cells aim for square but trimmed slightly so the grid stays compact and the bottom row
    // doesn't tower over the user card area.
    const float cellSide = cellWidth * 0.82f;
    const float gridH = static_cast<float>(rows) * cellSide +
                        static_cast<float>(rows > 0 ? rows - 1 : 0) * m_shortcutsGrid->rowGap() +
                        m_shortcutsGrid->paddingTop() + m_shortcutsGrid->paddingBottom();
    if (m_bottomRow != nullptr) {
      m_bottomRow->setMinHeight(gridH);
    }
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
    m_progressTimer.stop();
    return;
  }

  const bool playing =
      m_mpris != nullptr && m_mpris->activePlayer().has_value() && m_mpris->activePlayer()->playbackStatus == "Playing";
  if (playing) {
    if (!m_progressTimer.active()) {
      m_progressTimer.startRepeating(std::chrono::milliseconds(1000), [this]() {
        if (!m_active) {
          return;
        }
        PanelManager::instance().requestUpdateOnly();
        PanelManager::instance().requestRedraw();
      });
    }
  } else {
    m_progressTimer.stop();
  }
  sync(renderer);
}

void OverviewTab::onFrameTick(float /*deltaMs*/) {}

void OverviewTab::setActive(bool active) {
  m_active = active;
  if (!active) {
    m_progressTimer.stop();
    m_nextRealtimeUpdateAt = {};
    m_lastRealtimeMprisPollAt = {};
    m_mediaPositionBusName.clear();
    m_mediaPositionTrackId.clear();
    m_mediaPositionTrackSignature.clear();
    m_mediaLastPlaybackStatus.clear();
    m_mediaPositionUs = 0;
    m_mediaPositionSampleAt = {};
  }
}

void OverviewTab::onClose() {
  m_progressTimer.stop();
  m_rootLayout = nullptr;
  m_bottomRow = nullptr;
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
  m_sessionButton = nullptr;
  m_loadedAvatarPath.clear();
  m_wallpaperBg = nullptr;
  m_wallpaperGradient = nullptr;
  m_mediaTrack = nullptr;
  m_mediaArtist = nullptr;
  m_mediaStatus = nullptr;
  m_mediaProgress = nullptr;
  m_mediaArt = nullptr;
  m_mediaArtSlot = nullptr;
  m_mediaArtFallback = nullptr;
  m_loadedMediaArtUrl.clear();
  m_mediaPositionBusName.clear();
  m_mediaPositionTrackId.clear();
  m_mediaPositionTrackSignature.clear();
  m_mediaLastPlaybackStatus.clear();
  m_mediaPositionUs = 0;
  m_mediaPositionSampleAt = {};
  m_nextRealtimeUpdateAt = {};
  m_lastRealtimeMprisPollAt = {};
  m_shortcutsGrid = nullptr;
  m_shortcutPads.clear();
}

void OverviewTab::syncScaledFonts() {
  const float s = contentScale();
  if (m_timeLabel != nullptr) {
    m_timeLabel->setFontSize(Style::fontSizeTitle * 1.7f * s);
  }
  if (m_dateLabel != nullptr) {
    m_dateLabel->setFontSize(Style::fontSizeBody * 0.9f * s);
  }
  if (m_weatherGlyph != nullptr) {
    m_weatherGlyph->setGlyphSize(Style::fontSizeCaption * 1.12f * s);
  }
  if (m_weatherLine != nullptr) {
    m_weatherLine->setFontSize(Style::fontSizeCaption * s);
  }
  if (m_userFacts != nullptr) {
    m_userFacts->setFontSize(Style::fontSizeCaption * s);
  }
  if (m_mediaTrack != nullptr) {
    m_mediaTrack->setFontSize(Style::fontSizeBody * 0.95f * s);
  }
  if (m_mediaArtist != nullptr) {
    m_mediaArtist->setFontSize(Style::fontSizeCaption * s);
  }
  if (m_mediaStatus != nullptr) {
    m_mediaStatus->setFontSize(Style::fontSizeCaption * s);
  }
  if (m_mediaProgress != nullptr) {
    m_mediaProgress->setFontSize(Style::fontSizeCaption * s);
  }
  for (auto& pad : m_shortcutPads) {
    if (pad.label != nullptr) {
      pad.label->setFontSize(Style::fontSizeMini * s);
    }
    if (pad.glyph != nullptr) {
      pad.glyph->setGlyphSize(Style::fontSizeTitle * 1.35f * s);
    }
  }
}

void OverviewTab::sync(Renderer& renderer) {
  syncScaledFonts();
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
      m_mediaArtist->setText("");
      m_mediaArtist->setVisible(false);
      m_mediaStatus->setText(i18n::tr("control-center.overview.media.unavailable"));
      m_mediaProgress->setText(" ");
      m_mediaProgress->setVisible(false);
      m_mediaStatus->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
      if (m_mediaArt != nullptr) {
        m_mediaArt->clear(renderer);
        m_mediaArt->setVisible(false);
      }
      m_loadedMediaArtUrl.clear();
    } else {
      const auto active = m_mpris->activePlayer();
      if (!active.has_value()) {
        m_mediaPositionBusName.clear();
        m_mediaPositionTrackId.clear();
        m_mediaPositionTrackSignature.clear();
        m_mediaLastPlaybackStatus.clear();
        m_mediaPositionUs = 0;
        m_mediaPositionSampleAt = {};
        m_mediaTrack->setText(i18n::tr("control-center.overview.media.nothing-playing"));
        m_mediaArtist->setText("");
        m_mediaArtist->setVisible(false);
        m_mediaStatus->setText(i18n::tr("control-center.overview.media.idle"));
        m_mediaProgress->setText(" ");
        m_mediaProgress->setVisible(false);
        m_mediaStatus->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
        if (m_mediaArt != nullptr) {
          m_mediaArt->clear(renderer);
          m_mediaArt->setVisible(false);
        }
        m_loadedMediaArtUrl.clear();
      } else {
        m_mediaTrack->setText(active->title.empty() ? i18n::tr("control-center.overview.media.unknown-track")
                                                    : active->title);
        const std::string artists = mpris::joinArtists(active->artists);
        m_mediaArtist->setText(artists.empty() ? i18n::tr("control-center.overview.media.unknown-artist") : artists);
        m_mediaArtist->setVisible(true);
        const std::string trackSignature = std::format("{}\n{}\n{}\n{}\n{}", active->trackId, active->title, artists,
                                                       active->album, active->sourceUrl);
        std::string progressText;
        if (active->lengthUs > 0) {
          const auto now = std::chrono::steady_clock::now();
          std::int64_t livePositionUs = std::max<std::int64_t>(0, active->positionUs);
          livePositionUs = std::clamp<std::int64_t>(livePositionUs, 0, active->lengthUs);
          const bool sameDisplayedTrack =
              m_mediaPositionBusName == active->busName && m_mediaPositionTrackSignature == trackSignature;
          const bool withinTransientRegressionWindow =
              m_mediaPositionSampleAt != std::chrono::steady_clock::time_point{} &&
              now - m_mediaPositionSampleAt <= kOverviewTransientPositionRegressionWindow;
          const bool preserveDisplayedPosition =
              sameDisplayedTrack && m_mediaLastPlaybackStatus == "Playing" && active->playbackStatus == "Playing" &&
              m_mediaPositionUs >= kOverviewTransientPositionRegressionFloorUs &&
              livePositionUs <= kOverviewTransientPositionRegressionCeilingUs &&
              livePositionUs + kOverviewTransientPositionRegressionDeltaUs < m_mediaPositionUs &&
              withinTransientRegressionWindow;
          if (preserveDisplayedPosition) {
            livePositionUs = m_mediaPositionUs;
          }

          m_mediaPositionBusName = active->busName;
          m_mediaPositionTrackId = active->trackId;
          m_mediaPositionTrackSignature = trackSignature;
          m_mediaLastPlaybackStatus = active->playbackStatus;
          if (!preserveDisplayedPosition) {
            m_mediaPositionUs = livePositionUs;
            m_mediaPositionSampleAt = now;
          }

          const std::int64_t positionSec = std::max<std::int64_t>(0, livePositionUs / 1000000);
          const std::int64_t lengthSec = std::max<std::int64_t>(1, active->lengthUs / 1000000);
          progressText = std::format("{} / {}", formatClockTime(positionSec), formatClockTime(lengthSec));
        } else {
          m_mediaPositionBusName.clear();
          m_mediaPositionTrackId.clear();
          m_mediaPositionTrackSignature.clear();
          m_mediaLastPlaybackStatus.clear();
          m_mediaPositionUs = 0;
          m_mediaPositionSampleAt = {};
        }
        m_mediaProgress->setText(" ");
        m_mediaProgress->setVisible(false);
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
            bool loaded = false;
            if (!artPath.empty()) {
              loaded =
                  m_mediaArt->setSourceFile(renderer, artPath, static_cast<int>(std::round(m_mediaArt->width())), true);
              if (!loaded) {
                m_mediaArt->clear(renderer);
              }
            } else {
              m_mediaArt->clear(renderer);
            }
            m_mediaArt->setVisible(loaded);
            m_loadedMediaArtUrl = artUrl;
          }
        }
        std::string statusText;
        if (active->playbackStatus == "Playing") {
          statusText = i18n::tr("control-center.overview.media.playing");
          m_mediaStatus->setColor(colorSpecFromRole(ColorRole::Primary));
        } else if (active->playbackStatus == "Paused") {
          statusText = i18n::tr("control-center.overview.media.paused");
          m_mediaStatus->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
        } else {
          statusText = active->playbackStatus;
          m_mediaStatus->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
        }
        if (!progressText.empty()) {
          statusText = std::format("{} · {}", statusText, progressText);
        }
        m_mediaStatus->setText(statusText);
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
      pad.label->setBaselineMode(LabelBaselineMode::InkCentered);
    }
  }
}
