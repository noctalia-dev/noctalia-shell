#include "shell/settings/display/revert_dialog_modal.h"

#include "core/deferred_call.h"
#include "i18n/i18n.h"
#include "render/core/renderer.h"
#include "shell/settings/display/display_service.h"
#include "ui/builders.h"
#include "ui/controls/flex.h"
#include "ui/style.h"

#include <algorithm>
#include <utility>

namespace settings::display {

  namespace {

    constexpr float kDialogWidth = 420.0F;
    constexpr int kRevertTimeoutSeconds = 15;

  } // namespace

  RevertDialogModal::~RevertDialogModal() {
    if (m_open) {
      close();
    }
    m_aliveGuard.reset();
  }

  void RevertDialogModal::initialize(SettingsModalHost& host) { m_host = &host; }

  void RevertDialogModal::open(DisplayService& display, float scale) {
    if (m_host == nullptr || m_open) {
      return;
    }
    m_display = &display;
    m_scale = std::max(0.1F, scale);
    m_lastCountdown = -1;

    const std::weak_ptr<void> aliveGuard = m_aliveGuard;
    m_modalId = m_host->push(
        SettingsModalRequest{
            .build = [this, aliveGuard]() -> std::unique_ptr<Node> { return aliveGuard.expired() ? nullptr : build(); },
            .measure =
                [this](Renderer& renderer, const SettingsModalLayoutSpace& space) { return measure(renderer, space); },
            .arrange = [this](Renderer& renderer, float width, float height) { arrange(renderer, width, height); },
            .update = [this](Renderer& renderer) { update(renderer); },
            .requestClose =
                [this, aliveGuard]() {
                  if (!aliveGuard.expired()) {
                    close();
                  }
                },
            .onClosed =
                [this, aliveGuard]() {
                  if (!aliveGuard.expired()) {
                    m_open = false;
                    m_modalId.reset();
                    m_display = nullptr;
                    m_root = nullptr;
                  }
                },
            .contentPadding = Style::spaceMd * m_scale,
            .windowMargin = 24.0F * m_scale,
        }
    );
    m_open = m_modalId.has_value();
    if (!m_open) {
      m_display = nullptr;
      m_root = nullptr;
    }
  }

  void RevertDialogModal::close() {
    if (!m_open || m_host == nullptr || !m_modalId.has_value()) {
      return;
    }
    (void)m_host->pop(*m_modalId);
  }

  void RevertDialogModal::update(Renderer& renderer) {
    if (!m_open || m_display == nullptr) {
      return;
    }
    if (!m_display->awaitingConfirmation()) {
      close();
      return;
    }
    if (m_lastCountdown != m_display->revertCountdown()
        && m_host != nullptr
        && m_modalId.has_value()
        && m_host->isTop(*m_modalId)) {
      m_lastCountdown = m_display->revertCountdown();
      m_host->rebuildTop();
    }
  }

  std::unique_ptr<Node> RevertDialogModal::build() {
    const float gap = Style::spaceMd * m_scale;
    auto root = ui::column({
        .out = &m_root,
        .align = FlexAlign::Stretch,
        .gap = gap,
        .padding = Style::spaceMd * m_scale,
        .fillWidth = true,
    });

    const int countdown = m_display != nullptr ? std::max(0, m_display->revertCountdown()) : 0;
    root->addChild(
        ui::label({
            .text = i18n::tr("settings.display.keep-changes"),
            .fontSize = Style::fontSizeTitle * m_scale,
            .fontWeight = FontWeight::Bold,
            .color = colorSpecFromRole(ColorRole::OnSurface),
        })
    );
    root->addChild(
        ui::label({
            .text = i18n::tr("settings.display.reverting-in-seconds", "seconds", countdown),
            .fontSize = Style::fontSizeBody * m_scale,
            .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
        })
    );

    const float barWidth = (kDialogWidth - 4.0F * Style::spaceMd) * m_scale;
    const float fraction = static_cast<float>(countdown) / static_cast<float>(kRevertTimeoutSeconds);
    auto bar = ui::column({
        .align = FlexAlign::Stretch,
        .fillWidth = true,
    });
    auto barFill = ui::box({
        .fill = colorSpecFromRole(ColorRole::Error),
        .radius = 3.0F * m_scale,
    });
    barFill->setParticipatesInLayout(false);
    barFill->setSize(barWidth * fraction, 6.0F * m_scale);
    bar->addChild(std::move(barFill));
    bar->setFill(colorSpecFromRole(ColorRole::SurfaceVariant));
    bar->setRadius(3.0F * m_scale);
    bar->setSize(barWidth, 6.0F * m_scale);
    root->addChild(std::move(bar));

    root->addChild(
        ui::row(
            {
                .align = FlexAlign::Center,
                .justify = FlexJustify::Center,
                .gap = Style::spaceMd * m_scale,
            },
            ui::button({
                .text = i18n::tr("common.revert"),
                .fontSize = Style::fontSizeBody * m_scale,
                .variant = ButtonVariant::Ghost,
                .minHeight = Style::controlHeight * m_scale,
                .paddingV = Style::spaceXs * m_scale,
                .paddingH = Style::spaceMd * m_scale,
                .radius = Style::scaledRadiusMd(m_scale),
                .onClick =
                    [this]() {
                      const std::weak_ptr<void> aliveGuard = m_aliveGuard;
                      DeferredCall::callLater([this, aliveGuard]() {
                        if (aliveGuard.expired()) {
                          return;
                        }
                        if (m_display != nullptr) {
                          m_display->revertChanges();
                        }
                        close();
                      });
                    },
            }),
            ui::button({
                .text = i18n::tr("common.keep"),
                .fontSize = Style::fontSizeBody * m_scale,
                .variant = ButtonVariant::Primary,
                .minHeight = Style::controlHeight * m_scale,
                .paddingV = Style::spaceXs * m_scale,
                .paddingH = Style::spaceMd * m_scale,
                .radius = Style::scaledRadiusMd(m_scale),
                .onClick = [this]() {
                  const std::weak_ptr<void> aliveGuard = m_aliveGuard;
                  DeferredCall::callLater([this, aliveGuard]() {
                    if (aliveGuard.expired()) {
                      return;
                    }
                    if (m_display != nullptr) {
                      m_display->keepChanges();
                    }
                    close();
                  });
                },
            })
        )
    );

    return root;
  }

  LayoutSize RevertDialogModal::measure(Renderer& renderer, const SettingsModalLayoutSpace& space) {
    if (m_root == nullptr) {
      return {.width = 1.0F, .height = 1.0F};
    }
    const float width = std::min(kDialogWidth * m_scale, space.maxContentWidth);
    LayoutConstraints constraints;
    constraints.setExactWidth(width);
    const float height = std::min(m_root->measure(renderer, constraints).height, space.maxContentHeight);
    return {.width = width, .height = height};
  }

  void RevertDialogModal::arrange(Renderer& renderer, float width, float height) {
    if (m_root != nullptr) {
      m_root->arrange(renderer, {.x = 0.0F, .y = 0.0F, .width = width, .height = height});
    }
  }

  void RevertDialogModal::requestLayout() {
    if (m_open && m_host != nullptr) {
      m_host->requestLayout();
    }
  }

} // namespace settings::display
