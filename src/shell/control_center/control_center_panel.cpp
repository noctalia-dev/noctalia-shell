#include "shell/control_center/control_center_panel.h"

#include "render/core/renderer.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"

#include <memory>

using namespace control_center;

ControlCenterPanel::ControlCenterPanel(NotificationManager* notifications, PipeWireService* audio, MprisService* mpris,
                                       HttpClient* httpClient, WeatherService* weather) {
  m_tabs[tabIndex(TabId::Overview)] = std::make_unique<OverviewTab>();
  m_tabs[tabIndex(TabId::Media)] = std::make_unique<MediaTab>(mpris, httpClient);
  m_tabs[tabIndex(TabId::Audio)] = std::make_unique<AudioTab>(audio);
  m_tabs[tabIndex(TabId::Weather)] = std::make_unique<WeatherTab>(weather);
  m_tabs[tabIndex(TabId::Calendar)] = std::make_unique<CalendarTab>();
  m_tabs[tabIndex(TabId::Notifications)] = std::make_unique<NotificationsTab>(notifications);
  m_tabs[tabIndex(TabId::Network)] = std::make_unique<NetworkTab>();
  m_tabButtons.fill(nullptr);
  m_tabContainers.fill(nullptr);
}

void ControlCenterPanel::create(Renderer& renderer) {
  const float scale = contentScale();

  auto root = std::make_unique<Flex>();
  root->setDirection(FlexDirection::Horizontal);
  root->setAlign(FlexAlign::Stretch);
  root->setGap(Style::spaceLg * scale);
  root->setPadding(0.0f);
  m_rootLayout = root.get();

  auto sidebar = std::make_unique<Flex>();
  sidebar->setDirection(FlexDirection::Vertical);
  sidebar->setAlign(FlexAlign::Stretch);
  sidebar->setGap(Style::spaceXs * scale);
  sidebar->setPadding(Style::spaceMd * scale);
  sidebar->setFlexGrow(1.0f);
  m_sidebar = sidebar.get();

  for (const auto& tab : kTabs) {
    auto button = std::make_unique<Button>();
    button->setText(tab.title);
    button->setGlyph(tab.glyph);
    button->setGlyphSize(21.0f * scale);
    button->setGap(Style::spaceSm * scale);
    button->label()->setBold(true);
    button->label()->setFontSize(Style::fontSizeBody * scale);
    button->setVariant(ButtonVariant::Tab);
    button->setContentAlign(ButtonContentAlign::Start);
    button->setMinHeight(Style::controlHeightLg * scale);
    button->setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
    button->setRadius(Style::radiusLg * scale);
    button->setOnClick([this, id = tab.id]() {
      selectTab(id);
      PanelManager::instance().refresh();
    });
    m_tabButtons[tabIndex(tab.id)] = button.get();
    sidebar->addChild(std::move(button));
  }
  root->addChild(std::move(sidebar));

  auto content = std::make_unique<Flex>();
  content->setDirection(FlexDirection::Vertical);
  content->setAlign(FlexAlign::Stretch);
  content->setGap(Style::spaceMd * scale);
  content->setPadding(Style::spaceLg * scale);
  content->setRadius(Style::radiusXl * scale);
  content->setBackground(palette.surfaceVariant);
  content->setBorderWidth(0.0f);
  content->setSoftness(1.0f);
  content->setFlexGrow(4.0f);
  m_content = content.get();

  auto title = std::make_unique<Label>();
  title->setText("Overview");
  title->setBold(true);
  title->setFontSize(Style::fontSizeTitle * scale);
  title->setColor(palette.primary);
  m_contentTitle = title.get();
  content->addChild(std::move(title));

  auto bodies = std::make_unique<Flex>();
  bodies->setDirection(FlexDirection::Vertical);
  bodies->setAlign(FlexAlign::Stretch);
  bodies->setGap(0.0f);
  bodies->setFlexGrow(1.0f);
  m_tabBodies = bodies.get();

  for (std::size_t i = 0; i < kTabCount; ++i) {
    m_tabs[i]->setContentScale(scale);
    auto container = m_tabs[i]->build(renderer);
    container->setFlexGrow(1.0f);
    m_tabContainers[i] = container.get();
    m_tabBodies->addChild(std::move(container));
  }

  content->addChild(std::move(bodies));
  root->addChild(std::move(content));
  m_root = std::move(root);

  if (m_animations != nullptr) {
    m_root->setAnimationManager(m_animations);
  }

  for (auto& tab : m_tabs) {
    tab->update(renderer);
  }
  selectTab(m_activeTab);
}

void ControlCenterPanel::layout(Renderer& renderer, float width, float height) {
  if (m_rootLayout == nullptr || m_content == nullptr || m_tabBodies == nullptr) {
    return;
  }

  m_rootLayout->setSize(width, height);
  m_rootLayout->layout(renderer);

  const float contentInnerWidth =
      std::max(0.0f, m_content->width() - (m_content->paddingLeft() + m_content->paddingRight()));
  const float bodyWidth = m_tabBodies->width();
  const float bodyHeight = m_tabBodies->height();

  if (m_contentTitle != nullptr) {
    m_contentTitle->setMaxWidth(contentInnerWidth);
  }

  for (auto* container : m_tabContainers) {
    if (container != nullptr && container->visible()) {
      container->setSize(bodyWidth, bodyHeight);
    }
  }

  for (auto& tab : m_tabs) {
    tab->layout(renderer, bodyWidth, bodyHeight);
  }

  m_rootLayout->layout(renderer);
}

void ControlCenterPanel::update(Renderer& renderer) {
  for (auto& tab : m_tabs) {
    tab->update(renderer);
  }
}

void ControlCenterPanel::onOpen(std::string_view context) { selectTab(tabFromContext(context)); }

void ControlCenterPanel::onClose() {
  for (auto& tab : m_tabs) {
    tab->onClose();
  }
  m_rootLayout = nullptr;
  m_sidebar = nullptr;
  m_content = nullptr;
  m_contentTitle = nullptr;
  m_tabBodies = nullptr;
  m_tabButtons.fill(nullptr);
  m_tabContainers.fill(nullptr);
  m_rootPtr = nullptr;
}

void ControlCenterPanel::selectTab(TabId tab) {
  m_activeTab = tab;
  for (const auto& meta : kTabs) {
    const std::size_t idx = tabIndex(meta.id);
    if (m_tabContainers[idx] != nullptr) {
      m_tabContainers[idx]->setVisible(meta.id == tab);
    }
    if (m_tabButtons[idx] != nullptr) {
      m_tabButtons[idx]->setVariant(meta.id == tab ? ButtonVariant::TabActive : ButtonVariant::Tab);
    }
    if (meta.id == tab && m_contentTitle != nullptr) {
      m_contentTitle->setText(meta.title);
    }
  }

  if (m_contentTitle != nullptr) {
    const bool showTitle = tab != TabId::Notifications;
    m_contentTitle->setVisible(showTitle);
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
