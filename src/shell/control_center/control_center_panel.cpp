#include "shell/control_center/control_center_panel.h"

#include "i18n/i18n.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"

#include <memory>

using namespace control_center;

ControlCenterPanel::ControlCenterPanel(NotificationManager* notifications, PipeWireService* audio, MprisService* mpris,
                                       ConfigService* config, HttpClient* httpClient, WeatherService* weather,
                                       PipeWireSpectrum* spectrum, UPowerService* upower,
                                       PowerProfilesService* powerProfiles, NetworkService* network,
                                       NetworkSecretAgent* networkSecrets, BluetoothService* bluetooth,
                                       BluetoothAgent* bluetoothAgent, BrightnessService* brightness,
                                       SystemMonitorService* sysmon, NightLightManager* nightLight,
                                       noctalia::theme::ThemeService* theme, IdleInhibitor* idleInhibitor,
                                       WaylandConnection* wayland, Wallpaper* wallpaper) {
  (void)upower;
  m_tabs[tabIndex(TabId::Overview)] =
      std::make_unique<OverviewTab>(mpris, weather, audio, powerProfiles, config, network, bluetooth, nightLight, theme,
                                    notifications, idleInhibitor, wayland, wallpaper);
  m_tabs[tabIndex(TabId::Media)] = std::make_unique<MediaTab>(mpris, httpClient, spectrum);
  m_tabs[tabIndex(TabId::Audio)] = std::make_unique<AudioTab>(audio, mpris, config);
  m_tabs[tabIndex(TabId::Weather)] = std::make_unique<WeatherTab>(weather, config);
  m_tabs[tabIndex(TabId::Calendar)] = std::make_unique<CalendarTab>();
  m_tabs[tabIndex(TabId::Notifications)] = std::make_unique<NotificationsTab>(notifications);
  m_tabs[tabIndex(TabId::Network)] = std::make_unique<NetworkTab>(network, networkSecrets);
  m_tabs[tabIndex(TabId::Bluetooth)] = std::make_unique<BluetoothTab>(bluetooth, bluetoothAgent);
  m_tabs[tabIndex(TabId::Display)] = std::make_unique<DisplayTab>(brightness, config);
  m_tabs[tabIndex(TabId::System)] = std::make_unique<SystemTab>(sysmon);
  m_tabButtons.fill(nullptr);
  m_tabContainers.fill(nullptr);
  m_tabHeaderActions.fill(nullptr);
}

bool ControlCenterPanel::dismissTransientUi() {
  const std::size_t activeIdx = tabIndex(m_activeTab);
  return m_tabs[activeIdx] != nullptr && m_tabs[activeIdx]->dismissTransientUi();
}

void ControlCenterPanel::create() {
  const float scale = contentScale();

  for (auto& tab : m_tabs) {
    tab->setContentScale(scale);
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
  sidebar->setFill(roleColor(ColorRole::Surface));
  sidebar->setRadius(Style::radiusXl * scale);
  m_sidebar = sidebar.get();

  for (const auto& tab : kTabs) {
    auto button = std::make_unique<Button>();
    button->setText(i18n::tr(tab.titleKey));
    button->setGlyph(tab.glyph);
    button->setGlyphSize(21.0f * scale);
    button->setGap(Style::spaceSm * scale);
    button->label()->setBold(true);
    button->label()->setFontSize(Style::fontSizeBody * scale);
    button->setVariant(ButtonVariant::Tab);
    button->setContentAlign(ButtonContentAlign::Start);
    button->setMinHeight(Style::controlHeight * scale);
    button->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
    button->setRadius(Style::radiusLg * scale);
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
  title->setText(i18n::tr("control-center.tabs.overview"));
  title->setBold(true);
  title->setFontSize(Style::fontSizeTitle * scale);
  title->setColor(roleColor(ColorRole::Primary));
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
  closeButton->setVariant(ButtonVariant::Default);
  closeButton->setGlyphSize(Style::fontSizeBody * scale);
  closeButton->setMinWidth(Style::controlHeightSm * scale);
  closeButton->setMinHeight(Style::controlHeightSm * scale);
  closeButton->setPadding(Style::spaceXs * scale);
  closeButton->setRadius(Style::radiusMd * scale);
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

void ControlCenterPanel::onOpen(std::string_view context) { selectTab(tabFromContext(context)); }

bool ControlCenterPanel::isContextActive(std::string_view context) const {
  return m_activeTab == tabFromContext(context);
}

void ControlCenterPanel::onClose() {
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
}

ControlCenterPanel::TabId ControlCenterPanel::tabFromContext(std::string_view context) {
  for (const auto& tab : kTabs) {
    if (context == tab.key) {
      return tab.id;
    }
  }
  return TabId::Overview;
}

std::size_t ControlCenterPanel::tabIndex(TabId id) { return static_cast<std::size_t>(id); }
