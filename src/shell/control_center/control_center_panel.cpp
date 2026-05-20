#include "shell/control_center/control_center_panel.h"

#include "compositors/compositor_platform.h"
#include "config/config_service.h"
#include "core/deferred_call.h"
#include "dbus/mpris/mpris_service.h"
#include "dbus/network/inetwork_service.h"
#include "i18n/i18n.h"
#include "notification/notification_manager.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/panel/panel_button_style.h"
#include "shell/panel/panel_manager.h"
#include "system/dependency_service.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"

#include <chrono>
#include <memory>

using namespace control_center;

namespace {
  constexpr auto kMprisRefreshMinInterval = std::chrono::milliseconds(750);
}

ControlCenterPanel::ControlCenterPanel(
    NotificationManager* notifications, PipeWireService* audio, MprisService* mpris, ConfigService* config,
    HttpClient* httpClient, WeatherService* weather, PipeWireSpectrum* spectrum, UPowerService* upower,
    PowerProfilesService* powerProfiles, INetworkService* network, NetworkSecretAgent* networkSecrets,
    BluetoothService* bluetooth, BluetoothAgent* bluetoothAgent, BrightnessService* brightness,
    SystemMonitorService* sysmon, GammaService* nightLight, noctalia::theme::ThemeService* theme,
    IdleInhibitor* idleInhibitor, DependencyService* dependencies, CompositorPlatform* platform, Wallpaper* wallpaper,
    IwdAgent* iwdAgent) {
  (void)upower;
  WaylandConnection* wayland = platform != nullptr ? &platform->wayland() : nullptr;
  m_config = config;
  m_mpris = mpris;
  m_notificationManager = notifications;
  m_dependencies = dependencies;
  m_tabs[tabIndex(TabId::Home)] =
      std::make_unique<HomeTab>(mpris, httpClient, weather, audio, powerProfiles, config, network, bluetooth,
                                nightLight, theme, notifications, idleInhibitor, dependencies, platform, wallpaper);
  m_tabs[tabIndex(TabId::Media)] = std::make_unique<MediaTab>(mpris, httpClient, spectrum, config, wayland,
                                                              PanelManager::instance().renderContext());
  m_tabs[tabIndex(TabId::Audio)] =
      std::make_unique<AudioTab>(audio, mpris, config, wayland, PanelManager::instance().renderContext());
  m_tabs[tabIndex(TabId::Weather)] = std::make_unique<WeatherTab>(weather, config);
  m_tabs[tabIndex(TabId::Calendar)] = std::make_unique<CalendarTab>(config);
  m_tabs[tabIndex(TabId::Notifications)] = std::make_unique<NotificationsTab>(notifications);
  m_tabs[tabIndex(TabId::Network)] = std::make_unique<NetworkTab>(network, networkSecrets, iwdAgent);
  m_tabs[tabIndex(TabId::Bluetooth)] = std::make_unique<BluetoothTab>(bluetooth, bluetoothAgent);
  m_tabs[tabIndex(TabId::Display)] = std::make_unique<DisplayTab>(brightness, config);
  m_tabs[tabIndex(TabId::System)] = std::make_unique<SystemTab>(sysmon);
  m_tabButtons.fill(nullptr);
  m_tabContainers.fill(nullptr);
  m_tabHeaderActions.fill(nullptr);
}

float ControlCenterPanel::preferredWidth() const {
  const bool compact = m_config != nullptr && m_config->config().controlCenter.compact;
  return scaled(compact ? 660.0f : 780.0f);
}

PanelPlacement ControlCenterPanel::panelPlacement() const noexcept {
  return m_config == nullptr ? PanelPlacement::Attached : m_config->config().shell.panel.controlCenterPlacement;
}

bool ControlCenterPanel::dismissTransientUi() {
  const std::size_t activeIdx = tabIndex(m_activeTab);
  return m_tabs[activeIdx] != nullptr && m_tabs[activeIdx]->dismissTransientUi();
}

void ControlCenterPanel::create() {
  const float scale = contentScale();
  m_compact = m_config != nullptr && m_config->config().controlCenter.compact;

  for (auto& tab : m_tabs) {
    tab->setContentScale(scale);
    tab->setPanelCardOpacity(panelCardOpacity());
  }

  auto rootLayout = std::make_unique<Flex>();
  rootLayout->setDirection(FlexDirection::Horizontal);
  rootLayout->setAlign(FlexAlign::Stretch);
  rootLayout->setGap(Style::panelPadding * scale);
  rootLayout->setPadding(0.0f);
  m_rootLayout = rootLayout.get();

  auto sidebar = std::make_unique<Flex>();
  sidebar->setDirection(FlexDirection::Vertical);
  sidebar->setAlign(FlexAlign::Stretch);
  sidebar->setGap(Style::spaceXs * scale);
  sidebar->setPadding(Style::spaceSm * scale);
  sidebar->setFillHeight(true);
  sidebar->setFill(colorSpecFromRole(ColorRole::SurfaceVariant, panelCardOpacity()));
  sidebar->setRadius(Style::scaledRadiusXl(scale));
  m_sidebar = sidebar.get();

  for (const auto& tab : kTabs) {
    auto button = std::make_unique<Button>();
    if (!m_compact) {
      button->setText(i18n::tr(tab.titleKey));
    }
    button->setGlyph(tab.glyph);
    button->setGlyphSize(21.0f * scale);
    button->setGap(Style::spaceSm * scale);
    if (button->label() != nullptr) {
      button->label()->setBold(true);
      button->label()->setFontSize(Style::fontSizeBody * scale);
    }
    button->setVariant(ButtonVariant::Tab);
    button->setContentAlign(m_compact ? ButtonContentAlign::Center : ButtonContentAlign::Start);
    button->setMinHeight(Style::controlHeight * scale);
    if (m_compact) {
      button->setMinWidth(Style::controlHeight * scale);
      button->setPadding(Style::spaceSm * scale);
    } else {
      button->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
    }
    button->setRadius(Style::scaledRadiusLg(scale));
    button->setOnClick([this, id = tab.id]() {
      selectTab(id);
      PanelManager::instance().refresh();
    });
    m_tabButtons[tabIndex(tab.id)] = button.get();
    sidebar->addChild(std::move(button));
  }
  rootLayout->addChild(std::move(sidebar));

  auto content = std::make_unique<Flex>();
  content->setDirection(FlexDirection::Vertical);
  content->setAlign(FlexAlign::Stretch);
  content->setGap(Style::spaceMd * scale);
  content->setFlexGrow(4.0f);
  content->setClipChildren(true);
  m_content = content.get();

  auto dismissArea = std::make_unique<InputArea>();
  dismissArea->setParticipatesInLayout(false);
  dismissArea->setZIndex(-1);
  dismissArea->setOnPress([this](const InputArea::PointerData&) {
    const std::size_t activeIdx = tabIndex(m_activeTab);
    if (m_tabs[activeIdx] != nullptr && m_tabs[activeIdx]->dismissTransientUi()) {
      PanelManager::instance().refresh();
    }
  });
  m_contentDismissArea = static_cast<InputArea*>(content->addChild(std::move(dismissArea)));

  auto header = std::make_unique<Flex>();
  header->setDirection(FlexDirection::Horizontal);
  header->setAlign(FlexAlign::Center);
  header->setJustify(FlexJustify::SpaceBetween);
  header->setGap(Style::spaceSm * scale);
  m_contentHeader = header.get();

  auto title = std::make_unique<Label>();
  title->setText(i18n::tr("control-center.tabs.home"));
  title->setBold(true);
  title->setFontSize(Style::fontSizeTitle * scale);
  title->setColor(colorSpecFromRole(ColorRole::Primary));
  title->setFlexGrow(1.0f);
  m_contentTitle = title.get();
  header->addChild(std::move(title));

  auto headerActions = std::make_unique<Flex>();
  headerActions->setDirection(FlexDirection::Horizontal);
  headerActions->setAlign(FlexAlign::Center);
  headerActions->setGap(Style::spaceSm * scale);
  m_contentHeaderActions = headerActions.get();

  for (std::size_t i = 0; i < kTabCount; ++i) {
    auto actions = m_tabs[i]->createHeaderActions();
    m_tabHeaderActions[i] = actions.get();
    if (actions != nullptr) {
      actions->setVisible(false);
      m_contentHeaderActions->addChild(std::move(actions));
    }
  }

  auto closeButton = std::make_unique<Button>();
  closeButton->setGlyph("close");
  panel_button_style::configureHeaderIconButton(*closeButton, scale, panelCardOpacity());
  closeButton->setOnClick([]() { PanelManager::instance().close(); });
  m_closeButton = closeButton.get();
  m_contentHeaderActions->addChild(std::move(closeButton));
  header->addChild(std::move(headerActions));

  content->addChild(std::move(header));

  auto bodies = std::make_unique<Flex>();
  bodies->setDirection(FlexDirection::Vertical);
  bodies->setAlign(FlexAlign::Stretch);
  bodies->setGap(0.0f);
  bodies->setFlexGrow(1.0f);
  m_tabBodies = bodies.get();

  for (std::size_t i = 0; i < kTabCount; ++i) {
    auto container = m_tabs[i]->create();
    container->setFlexGrow(1.0f);
    m_tabContainers[i] = container.get();
    m_tabBodies->addChild(std::move(container));
  }

  content->addChild(std::move(bodies));
  rootLayout->addChild(std::move(content));
  setRoot(std::move(rootLayout));

  if (m_animations != nullptr) {
    root()->setAnimationManager(m_animations);
  }

  selectTab(m_activeTab);
}

void ControlCenterPanel::onPanelCardOpacityChanged(float opacity) {
  for (auto& tab : m_tabs) {
    if (tab != nullptr) {
      tab->setPanelCardOpacity(opacity);
    }
  }
  if (m_sidebar != nullptr) {
    m_sidebar->setFill(colorSpecFromRole(ColorRole::SurfaceVariant, opacity));
  }
  if (m_closeButton != nullptr) {
    panel_button_style::applyHeaderButtonStyle(*m_closeButton, opacity);
  }
}

void ControlCenterPanel::doLayout(Renderer& renderer, float width, float height) {
  if (m_rootLayout == nullptr || m_content == nullptr || m_tabBodies == nullptr) {
    return;
  }

  m_rootLayout->setSize(width, height);
  m_rootLayout->layout(renderer);

  const float contentInnerWidth =
      std::max(0.0f, m_content->width() - (m_content->paddingLeft() + m_content->paddingRight()));
  const float bodyWidth = m_tabBodies->width();
  const float bodyHeight = m_tabBodies->height();

  if (m_contentDismissArea != nullptr) {
    m_contentDismissArea->setPosition(0.0f, 0.0f);
    m_contentDismissArea->setFrameSize(m_content->width(), m_content->height());
  }

  if (m_contentHeader != nullptr) {
    m_contentHeader->setSize(contentInnerWidth, 0.0f);
  }

  if (m_contentTitle != nullptr) {
    const float actionsWidth = m_contentHeaderActions != nullptr ? m_contentHeaderActions->width() : 0.0f;
    const float headerGap = m_contentHeader != nullptr ? m_contentHeader->gap() : 0.0f;
    const float titleWidth = std::max(0.0f, contentInnerWidth - actionsWidth - headerGap);
    m_contentTitle->setMaxWidth(titleWidth);
  }

  for (auto* container : m_tabContainers) {
    if (container != nullptr && container->visible()) {
      container->setSize(bodyWidth, bodyHeight);
    }
  }

  const std::size_t activeIdx = tabIndex(m_activeTab);
  if (m_tabs[activeIdx] != nullptr) {
    m_tabs[activeIdx]->layout(renderer, bodyWidth, bodyHeight);
  }
}

void ControlCenterPanel::doUpdate(Renderer& renderer) {
  const std::size_t activeIdx = tabIndex(m_activeTab);
  if (m_tabs[activeIdx] != nullptr) {
    m_tabs[activeIdx]->update(renderer);
  }
}

void ControlCenterPanel::onFrameTick(float deltaMs) {
  const std::size_t activeIdx = tabIndex(m_activeTab);
  if (m_tabs[activeIdx] != nullptr) {
    m_tabs[activeIdx]->onFrameTick(deltaMs);
  }
}

void ControlCenterPanel::onOpen(std::string_view context) {
  if (m_dependencies != nullptr) {
    m_dependencies->rescan();
  }
  selectTab(tabFromContext(context));
}

bool ControlCenterPanel::isContextActive(std::string_view context) const {
  return m_activeTab == tabFromContext(context);
}

void ControlCenterPanel::onClose() {
  m_activeTab = TabId::Home;
  for (auto& tab : m_tabs) {
    tab->setActive(false);
    tab->onClose();
  }
  m_rootLayout = nullptr;
  m_sidebar = nullptr;
  m_content = nullptr;
  m_contentDismissArea = nullptr;
  m_contentHeader = nullptr;
  m_contentHeaderActions = nullptr;
  m_contentTitle = nullptr;
  m_closeButton = nullptr;
  m_tabBodies = nullptr;
  m_tabButtons.fill(nullptr);
  m_tabContainers.fill(nullptr);
  m_tabHeaderActions.fill(nullptr);
  clearReleasedRoot();
}

bool ControlCenterPanel::deferExternalRefresh() const {
  if (m_activeTab != TabId::Audio) {
    return false;
  }
  const auto* audioTab = dynamic_cast<const AudioTab*>(m_tabs[tabIndex(TabId::Audio)].get());
  return audioTab != nullptr && audioTab->dragging();
}

bool ControlCenterPanel::deferPointerRelayout() const { return deferExternalRefresh(); }

void ControlCenterPanel::selectTab(TabId tab) {
  m_activeTab = tab;
  if (tab == TabId::Notifications && m_notificationManager != nullptr) {
    m_notificationManager->markNotificationHistorySeen();
  }
  for (const auto& meta : kTabs) {
    const std::size_t idx = tabIndex(meta.id);
    if (m_tabContainers[idx] != nullptr) {
      m_tabContainers[idx]->setVisible(meta.id == tab);
    }
    if (m_tabs[idx] != nullptr) {
      m_tabs[idx]->setActive(meta.id == tab);
    }
    if (m_tabButtons[idx] != nullptr) {
      m_tabButtons[idx]->setVariant(meta.id == tab ? ButtonVariant::TabActive : ButtonVariant::Tab);
    }
    if (meta.id == tab && m_contentTitle != nullptr) {
      m_contentTitle->setText(i18n::tr(meta.titleKey));
    }
    if (m_tabHeaderActions[idx] != nullptr) {
      m_tabHeaderActions[idx]->setVisible(meta.id == tab);
    }
  }

  if (m_contentTitle != nullptr) {
    m_contentTitle->setVisible(true);
  }
  if (m_contentHeaderActions != nullptr) {
    m_contentHeaderActions->setVisible(true);
  }

  scheduleMprisRefreshFor(tab);
}

void ControlCenterPanel::scheduleMprisRefreshFor(TabId tab) {
  if (m_mpris == nullptr || m_mprisRefreshScheduled || (tab != TabId::Home && tab != TabId::Media)) {
    return;
  }

  const auto now = std::chrono::steady_clock::now();
  if (m_lastMprisRefreshAt.time_since_epoch().count() != 0 && now - m_lastMprisRefreshAt < kMprisRefreshMinInterval) {
    return;
  }

  m_lastMprisRefreshAt = now;
  m_mprisRefreshScheduled = true;
  DeferredCall::callLater([this]() {
    m_mprisRefreshScheduled = false;
    if (m_mpris == nullptr || !PanelManager::instance().isOpenPanel("control-center")) {
      return;
    }
    m_mpris->refreshPlayers();
    PanelManager::instance().requestUpdateOnly();
    PanelManager::instance().requestRedraw();
  });
}

ControlCenterPanel::TabId ControlCenterPanel::tabFromContext(std::string_view context) {
  for (const auto& tab : kTabs) {
    if (context == tab.key) {
      return tab.id;
    }
  }
  return TabId::Home;
}

std::size_t ControlCenterPanel::tabIndex(TabId id) { return static_cast<std::size_t>(id); }
