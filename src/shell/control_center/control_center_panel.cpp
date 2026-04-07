#include "shell/control_center/control_center_panel.h"

#include "render/core/renderer.h"
#include "dbus/mpris/mpris_service.h"
#include "shell/panel/panel_manager.h"
#include "shell/control_center/common.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/select.h"
#include "ui/controls/slider.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <memory>

using namespace control_center;

ControlCenterPanel::ControlCenterPanel(NotificationManager* notifications, PipeWireService* audio, MprisService* mpris,
                                       HttpClient* httpClient)
    : m_notifications(notifications), m_audio(audio), m_mpris(mpris), m_httpClient(httpClient) {
  m_tabButtons.fill(nullptr);
  m_tabContainers.fill(nullptr);
}

void ControlCenterPanel::create(Renderer& renderer) {
  auto root = std::make_unique<Flex>();
  root->setDirection(FlexDirection::Horizontal);
  root->setAlign(FlexAlign::Start);
  root->setGap(Style::spaceLg);
  root->setPadding(0.0f);
  m_rootLayout = root.get();

  auto sidebar = std::make_unique<Flex>();
  sidebar->setDirection(FlexDirection::Vertical);
  sidebar->setAlign(FlexAlign::Start);
  sidebar->setGap(Style::spaceXs);
  sidebar->setPadding(Style::spaceMd);
  sidebar->setMinWidth(kSidebarWidth);
  m_sidebar = sidebar.get();

  for (const auto& tab : kTabs) {
    auto button = std::make_unique<Button>();
    button->setText(tab.title);
    button->setGlyph(tab.glyph);
    button->setVariant(ButtonVariant::Tab);
    button->setMinimalChrome(true);
    button->setMinHeight(Style::controlHeightLg);
    button->setPadding(Style::spaceSm, Style::spaceMd,
                       Style::spaceSm, Style::spaceMd);
    button->setRadius(Style::radiusLg);
    button->setOnClick([this, id = tab.id]() {
      selectTab(id);
      PanelManager::instance().refresh();
    });
    button->setMinWidth(kSidebarButtonWidth);
    auto* ptr = button.get();
    m_tabButtons[tabIndex(tab.id)] = ptr;
    sidebar->addChild(std::move(button));
  }
  root->addChild(std::move(sidebar));

  auto content = std::make_unique<Flex>();
  content->setDirection(FlexDirection::Vertical);
  content->setAlign(FlexAlign::Start);
  content->setGap(Style::spaceMd);
  content->setPadding(Style::spaceLg);
  content->setRadius(Style::radiusXl);
  content->setBackground(alphaSurfaceVariant(0.9f));
  content->setBorderWidth(0.0f);
  content->setSoftness(1.0f);
  content->setMinWidth(kContentMinWidth);
  m_content = content.get();

  auto title = std::make_unique<Label>();
  title->setText("Overview");
  title->setBold(true);
  title->setFontSize(Style::fontSizeTitle);
  title->setColor(palette.primary);
  m_contentTitle = title.get();
  content->addChild(std::move(title));

  auto bodies = std::make_unique<Flex>();
  bodies->setDirection(FlexDirection::Vertical);
  bodies->setAlign(FlexAlign::Start);
  bodies->setGap(0.0f);
  m_tabBodies = bodies.get();

  buildOverviewTab();
  buildMediaTab();
  buildCalendarTab();
  buildNotificationsTab();
  buildNetworkTab();

  content->addChild(std::move(bodies));
  root->addChild(std::move(content));
  m_root = std::move(root);

  if (m_animations != nullptr) {
    m_root->setAnimationManager(m_animations);
  }

  rebuildCalendar(renderer);
  selectTab(m_activeTab);
  refreshMediaState(renderer);
  rebuildNotifications(renderer, kContentMinWidth);
}

void ControlCenterPanel::layout(Renderer& renderer, float width, float height) {
  if (m_rootLayout == nullptr || m_content == nullptr || m_tabBodies == nullptr) {
    return;
  }

  const float sidebarWidth = std::round(std::max(0.0f, width * kSidebarWidthRatio));
  const float sidebarButtonWidth = std::max(0.0f, sidebarWidth - Style::spaceMd * 2);

  for (auto* button : m_tabButtons) {
    if (button != nullptr) {
      button->setMinWidth(sidebarButtonWidth);
      button->layout(renderer);
      button->updateInputArea();
    }
  }

  const float rightSurfaceGutter = Style::spaceXs;
  const float contentOuterWidth =
      std::max(0.0f, width - sidebarWidth - Style::spaceLg - rightSurfaceGutter);
  const float contentInnerWidth = std::max(0.0f, contentOuterWidth - Style::spaceLg * 2);
  const float contentInnerHeight = std::max(0.0f, height - Style::spaceLg * 2);
  const float bodyHeight = std::max(0.0f, contentInnerHeight - kHeaderReserveHeight);

  if (m_sidebar != nullptr) {
    m_sidebar->setMinWidth(sidebarWidth);
    m_sidebar->layout(renderer);
  }

  if (m_contentTitle != nullptr) {
    m_contentTitle->setMaxWidth(contentInnerWidth);
    m_contentTitle->measure(renderer);
  }

  for (auto* tab : m_tabContainers) {
    if (tab == nullptr) {
      continue;
    }
    tab->setMinWidth(contentInnerWidth);
    tab->setSize(contentInnerWidth, bodyHeight);
  }

  if (m_tabContainers[tabIndex(TabId::Calendar)] != nullptr) {
    rebuildCalendar(renderer);
  }

  if (m_tabContainers[tabIndex(TabId::Media)] != nullptr) {
    const float mediaGap = Style::spaceMd;
    const float mediaContentWidth = std::max(0.0f, contentInnerWidth);
    const float leftPreferred = std::clamp(mediaContentWidth * 0.48f, 260.0f, 360.0f);
    const float rightWidth = std::max(220.0f, mediaContentWidth - leftPreferred - mediaGap);
    const float leftWidth = std::max(220.0f, mediaContentWidth - rightWidth - mediaGap);
    const float leftInnerWidth = std::max(0.0f, leftWidth - Style::spaceMd * 2);
    const float rightInnerWidth = std::max(0.0f, rightWidth - Style::spaceMd * 2);
    const float mediaArtworkSize = std::min(leftInnerWidth, Style::controlHeightLg * 6);

    if (m_mediaColumn != nullptr) {
      m_mediaColumn->setMinWidth(leftWidth);
      m_mediaColumn->setSize(leftWidth, bodyHeight);
    }
    if (m_mediaNowCard != nullptr) {
      m_mediaNowCard->setMinWidth(leftWidth);
      m_mediaNowCard->setMinHeight(std::max(kMediaNowCardMinHeight, bodyHeight));
    }
    if (m_mediaAudioColumn != nullptr) {
      m_mediaAudioColumn->setMinWidth(rightWidth);
      m_mediaAudioColumn->setSize(rightWidth, bodyHeight);
    }
    if (m_mediaOutputCard != nullptr) {
      m_mediaOutputCard->setMinWidth(rightWidth);
      m_mediaOutputCard->setMinHeight(kMediaAudioCardMinHeight);
    }
    if (m_mediaInputCard != nullptr) {
      m_mediaInputCard->setMinWidth(rightWidth);
      m_mediaInputCard->setMinHeight(kMediaAudioCardMinHeight);
    }
    if (m_mediaPlayerSelect != nullptr) {
      m_mediaPlayerSelect->setSize(leftInnerWidth, 0.0f);
    }
    if (m_outputDeviceSelect != nullptr) {
      m_outputDeviceSelect->setSize(rightInnerWidth, 0.0f);
    }
    if (m_inputDeviceSelect != nullptr) {
      m_inputDeviceSelect->setSize(rightInnerWidth, 0.0f);
    }
    if (m_mediaArtwork != nullptr) {
      const float mediaMetaHeight = Style::fontSizeTitle + Style::fontSizeBody +
                                   Style::fontSizeCaption + Style::spaceMd * 2;
      const float aspectRatio = m_mediaArtwork->hasImage() ? m_mediaArtwork->aspectRatio() : 1.0f;
      const bool wideArtwork = aspectRatio > 1.15f;
      const float mediaReservedHeight =
          kMediaPlayerSelectHeight + kMediaPlayPauseHeight + Style::controlHeight +
          mediaMetaHeight + Style::spaceMd * 5;
      const float artworkMaxHeight = std::max(kMediaArtworkMinHeight, bodyHeight - mediaReservedHeight);

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

      m_mediaArtwork->setSize(std::max(0.0f, artworkWidth), std::max(0.0f, artworkHeight));

      const float sideButtonSize = kMediaControlsHeight;
      const float playPauseButtonSize = kMediaPlayPauseHeight;
      const float sideGlyphSize = Style::fontSizeTitle;
      const float playPauseGlyphSize = Style::fontSizeTitle + Style::spaceXs;

      for (auto* button : {m_mediaRepeatButton, m_mediaPrevButton, m_mediaNextButton, m_mediaShuffleButton}) {
        if (button != nullptr) {
          button->setMinWidth(sideButtonSize);
          button->setMinHeight(sideButtonSize);
          button->setGlyphSize(sideGlyphSize);
          button->layout(renderer);
          button->updateInputArea();
        }
      }
      if (m_mediaPlayPauseButton != nullptr) {
        m_mediaPlayPauseButton->setMinWidth(playPauseButtonSize);
        m_mediaPlayPauseButton->setMinHeight(playPauseButtonSize);
        m_mediaPlayPauseButton->setGlyphSize(playPauseGlyphSize);
        m_mediaPlayPauseButton->layout(renderer);
        m_mediaPlayPauseButton->updateInputArea();
      }
    }
    if (m_mediaTrackTitle != nullptr) {
      m_mediaTrackTitle->setMaxWidth(leftInnerWidth);
      m_mediaTrackTitle->measure(renderer);
    }
    if (m_mediaTrackArtist != nullptr) {
      m_mediaTrackArtist->setMaxWidth(leftInnerWidth);
      m_mediaTrackArtist->measure(renderer);
    }
    if (m_mediaTrackAlbum != nullptr) {
      m_mediaTrackAlbum->setMaxWidth(leftInnerWidth);
      m_mediaTrackAlbum->measure(renderer);
    }
    if (m_mediaProgressSlider != nullptr) {
      m_mediaProgressSlider->setSize(leftInnerWidth, 0.0f);
      m_mediaProgressSlider->layout(renderer);
    }
    if (m_outputSlider != nullptr) {
      m_outputSlider->setSize(std::max(120.0f, rightInnerWidth - kValueLabelWidth - Style::spaceSm), 0.0f);
      m_outputSlider->layout(renderer);
    }
    if (m_inputSlider != nullptr) {
      m_inputSlider->setSize(std::max(120.0f, rightInnerWidth - kValueLabelWidth - Style::spaceSm), 0.0f);
      m_inputSlider->layout(renderer);
    }
  }

  if (m_notificationScroll != nullptr) {
    m_notificationScroll->setSize(contentInnerWidth, bodyHeight);
    m_notificationScroll->layout(renderer);
    rebuildNotifications(renderer, m_notificationScroll->contentViewportWidth());
    m_notificationScroll->layout(renderer);
  }

  if (m_outputSlider != nullptr) {
    m_outputSlider->layout(renderer);
  }
  if (m_inputSlider != nullptr) {
    m_inputSlider->layout(renderer);
  }
  if (m_outputValue != nullptr) {
    m_outputValue->measure(renderer);
  }
  if (m_inputValue != nullptr) {
    m_inputValue->measure(renderer);
  }

  m_content->setMinWidth(contentOuterWidth);
  m_content->setMinHeight(height);
  m_content->setSize(contentOuterWidth, height);
  m_content->layout(renderer);

  m_rootLayout->setSize(width, height);
  m_rootLayout->layout(renderer);
}

void ControlCenterPanel::update(Renderer& renderer) {
  refreshMediaState(renderer);

  const float listWidth = m_notificationScroll != nullptr ? m_notificationScroll->contentViewportWidth() : 0.0f;
  rebuildNotifications(renderer, listWidth);
}

void ControlCenterPanel::onOpen(std::string_view context) { selectTab(tabFromContext(context)); }

void ControlCenterPanel::onClose() {
  m_rootLayout = nullptr;
  m_sidebar = nullptr;
  m_content = nullptr;
  m_contentTitle = nullptr;
  m_tabBodies = nullptr;
  m_tabButtons.fill(nullptr);
  m_tabContainers.fill(nullptr);
  m_notificationScroll = nullptr;
  m_notificationList = nullptr;
  m_outputSlider = nullptr;
  m_outputValue = nullptr;
  m_inputSlider = nullptr;
  m_inputValue = nullptr;
  m_mediaArtwork = nullptr;
  m_mediaColumn = nullptr;
  m_mediaNowCard = nullptr;
  m_mediaAudioColumn = nullptr;
  m_mediaOutputCard = nullptr;
  m_mediaInputCard = nullptr;
  m_mediaTrackTitle = nullptr;
  m_mediaTrackArtist = nullptr;
  m_mediaTrackAlbum = nullptr;
  m_mediaProgressSlider = nullptr;
  m_mediaPlayerSelect = nullptr;
  m_outputDeviceSelect = nullptr;
  m_inputDeviceSelect = nullptr;
  m_mediaPrevButton = nullptr;
  m_mediaPlayPauseButton = nullptr;
  m_mediaNextButton = nullptr;
  m_mediaRepeatButton = nullptr;
  m_mediaShuffleButton = nullptr;
  m_lastMediaArtPath.clear();
  m_lastMediaBusName.clear();
  m_lastMediaPlaybackStatus.clear();
  m_lastMediaLoopStatus.clear();
  m_mediaPlayerBusNames.clear();
  m_outputDeviceIds.clear();
  m_inputDeviceIds.clear();
  m_calendarCard = nullptr;
  m_calendarMonthLabel = nullptr;
  m_calendarGrid = nullptr;
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
      m_tabButtons[idx]->setMinimalChrome(true);
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
