#include "shell/settings/display/edid_dialog_modal.h"

#include "core/deferred_call.h"
#include "i18n/i18n.h"
#include "render/core/renderer.h"
#include "shell/settings/display/display_service.h"
#include "ui/builders.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"
#include "ui/style.h"
#include "wayland/clipboard_service.h"

#include <algorithm>
#include <utility>

namespace settings::display {

  namespace {

    constexpr float kDialogWidth = 640.0F;
    constexpr float kDialogHeight = 520.0F;

    [[nodiscard]] std::string formatHexDump(const std::string& hex) {
      std::string dump;
      dump.reserve(hex.size() + hex.size() / 2 + hex.size() / 32);
      for (std::size_t i = 0; i < hex.size(); i += 2) {
        if (i > 0 && i % 32 == 0) {
          dump.push_back('\n');
        }
        if (!dump.empty() && dump.back() != '\n') {
          dump.push_back(' ');
        }
        dump.push_back(hex[i]);
        if (i + 1 < hex.size()) {
          dump.push_back(hex[i + 1]);
        }
      }
      return dump;
    }

  } // namespace

  EdidDialogModal::~EdidDialogModal() {
    if (m_open) {
      close();
    }
    m_aliveGuard.reset();
  }

  void EdidDialogModal::initialize(SettingsModalHost& host) { m_host = &host; }

  void EdidDialogModal::open(EdidDialogRequest request) {
    if (m_host == nullptr) {
      return;
    }
    if (m_open) {
      close();
    }
    m_display = request.display;
    m_clipboard = request.clipboard;
    m_outputName = std::move(request.outputName);
    m_scale = std::max(0.1F, request.scale);
    m_dirty = false;
    m_showRaw = false;
    m_root = nullptr;

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
                    m_clipboard = nullptr;
                    m_outputName.clear();
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
      m_clipboard = nullptr;
      m_outputName.clear();
      m_root = nullptr;
    }
  }

  void EdidDialogModal::close() {
    if (!m_open || m_host == nullptr || !m_modalId.has_value()) {
      return;
    }
    (void)m_host->pop(*m_modalId);
  }

  void EdidDialogModal::update(Renderer& renderer) {
    if (m_dirty && m_open && m_host != nullptr && m_modalId.has_value() && m_host->isTop(*m_modalId)) {
      m_dirty = false;
      m_host->rebuildTop();
    }
  }

  std::string EdidDialogModal::contentText() const {
    if (m_display == nullptr) {
      return {};
    }
    const auto& summary = m_display->edidSummary();
    if (m_showRaw) {
      return formatHexDump(m_display->edidHex());
    }
    if (summary.status == EdidStatus::ReadError
        || summary.status == EdidStatus::DecodeError
        || summary.status == EdidStatus::DecodedEmpty) {
      return i18n::tr("settings.display.edid-empty");
    }
    std::string text;
    const auto addLine = [&text](std::string line) {
      if (!line.empty()) {
        if (!text.empty()) {
          text.push_back('\n');
        }
        text += line;
      }
    };
    if (!summary.monitorName.empty()) {
      addLine(i18n::tr("settings.display.edid-field-monitor-name", "value", summary.monitorName));
    }
    if (!summary.manufacturerId.empty()) {
      addLine(i18n::tr("settings.display.edid-field-manufacturer-id", "value", summary.manufacturerId));
    }
    if (!summary.productCode.empty()) {
      addLine(i18n::tr("settings.display.edid-field-product-code", "value", summary.productCode));
    }
    const std::string serial = !summary.serialText.empty() ? summary.serialText : summary.serialNumber;
    if (!serial.empty()) {
      addLine(i18n::tr("settings.display.edid-field-serial-number", "value", serial));
    }
    if (!summary.version.empty()) {
      addLine(i18n::tr("settings.display.edid-field-version", "value", summary.version));
    }
    if (summary.week > 0 && summary.year > 0) {
      addLine(i18n::tr("settings.display.edid-field-manufactured", "week", summary.week, "year", summary.year));
    }
    if (!summary.inputType.empty()) {
      addLine(i18n::tr("settings.display.edid-field-input-type", "value", summary.inputType));
    }
    if (summary.sizeWidthCm > 0 && summary.sizeHeightCm > 0) {
      addLine(
          i18n::tr(
              "settings.display.edid-field-physical-size", "value",
              i18n::tr("settings.display.edid-size-cm", "width", summary.sizeWidthCm, "height", summary.sizeHeightCm)
          )
      );
    }
    if (!summary.preferredMode.empty()) {
      addLine(i18n::tr("settings.display.edid-field-preferred-mode", "value", summary.preferredMode));
    }
    return text.empty() ? i18n::tr("settings.display.edid-empty") : text;
  }

  std::string EdidDialogModal::copyPayload() const {
    if (m_display == nullptr) {
      return {};
    }
    std::string payload = i18n::tr("settings.display.edid-title", "output", m_outputName);
    payload += "\n\n";
    payload += contentText();
    return payload;
  }

  std::unique_ptr<Node> EdidDialogModal::build() {
    const float gap = Style::spaceMd * m_scale;
    auto root = ui::column({
        .out = &m_root,
        .align = FlexAlign::Stretch,
        .gap = gap,
        .fillWidth = true,
        .fillHeight = true,
    });

    root->addChild(
        ui::row(
            {
                .align = FlexAlign::Center,
                .gap = Style::spaceSm * m_scale,
            },
            ui::column(
                {
                    .align = FlexAlign::Stretch,
                    .gap = Style::spaceXs * m_scale,
                    .flexGrow = 1.0F,
                },
                ui::label({
                    .text = i18n::tr("settings.display.edid-title", "output", m_outputName),
                    .fontSize = Style::fontSizeTitle * m_scale,
                    .fontWeight = FontWeight::Bold,
                    .color = colorSpecFromRole(ColorRole::Primary),
                    .maxLines = 1,
                }),
                ui::label({
                    .text = i18n::tr("settings.display.edid-description"),
                    .fontSize = Style::fontSizeCaption * m_scale,
                    .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
                })
            ),
            ui::button({
                .text = i18n::tr("settings.display.edid-view-original"),
                .fontSize = Style::fontSizeCaption * m_scale,
                .variant = m_showRaw ? ButtonVariant::Primary : ButtonVariant::Ghost,
                .minHeight = Style::controlHeightSm * m_scale,
                .paddingV = Style::spaceXs * m_scale,
                .paddingH = Style::spaceMd * m_scale,
                .radius = Style::scaledRadiusMd(m_scale),
                .onClick = [this]() {
                  const std::weak_ptr<void> aliveGuard = m_aliveGuard;
                  DeferredCall::callLater([this, aliveGuard]() {
                    if (aliveGuard.expired()) {
                      return;
                    }
                    m_showRaw = !m_showRaw;
                    m_dirty = true;
                    m_host->rebuildTop();
                  });
                },
            })
        )
    );

    root->addChild(
        ui::column(
            {
                .align = FlexAlign::Stretch,
                .gap = Style::spaceSm * m_scale,
                .padding = Style::spaceSm * m_scale,
                .flexGrow = 1.0F,
                .configure =
                    [this](Flex& box) {
                      box.setRadius(Style::scaledRadiusMd(m_scale));
                      box.setFill(colorSpecFromRole(ColorRole::SurfaceVariant));
                      box.setBorder(colorSpecFromRole(ColorRole::Outline), Style::borderWidth);
                    },
            },
            ui::label({
                .text = contentText(),
                .fontSize = Style::fontSizeCaption * m_scale,
                .fontFamily = "monospace",
                .color = colorSpecFromRole(ColorRole::OnSurface),
                .maxLines = 0,
            })
        )
    );

    root->addChild(
        ui::row(
            {
                .align = FlexAlign::Center,
                .justify = FlexJustify::End,
                .gap = Style::spaceSm * m_scale,
            },
            ui::button({
                .text = i18n::tr("common.refresh"),
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
                          m_showRaw = false;
                          m_display->readEdid(m_outputName);
                        }
                      });
                    },
            }),
            ui::button({
                .text = i18n::tr("settings.display.copy-edid"),
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
                        if (m_clipboard != nullptr) {
                          m_clipboard->setClipboardText(copyPayload());
                        }
                      });
                    },
            }),
            ui::button({
                .text = i18n::tr("common.close"),
                .fontSize = Style::fontSizeBody * m_scale,
                .variant = ButtonVariant::Default,
                .minHeight = Style::controlHeight * m_scale,
                .paddingV = Style::spaceXs * m_scale,
                .paddingH = Style::spaceMd * m_scale,
                .radius = Style::scaledRadiusMd(m_scale),
                .onClick = [this]() {
                  const std::weak_ptr<void> aliveGuard = m_aliveGuard;
                  DeferredCall::callLater([this, aliveGuard]() {
                    if (!aliveGuard.expired()) {
                      close();
                    }
                  });
                },
            })
        )
    );

    return root;
  }

  LayoutSize EdidDialogModal::measure(Renderer& renderer, const SettingsModalLayoutSpace& space) {
    if (m_root == nullptr) {
      return {.width = 1.0F, .height = 1.0F};
    }
    const float width = std::min(kDialogWidth * m_scale, space.maxContentWidth);
    const float height = std::min(kDialogHeight * m_scale, space.maxContentHeight);
    return {.width = width, .height = height};
  }

  void EdidDialogModal::arrange(Renderer& renderer, float width, float height) {
    if (m_root != nullptr) {
      m_root->arrange(renderer, {.x = 0.0F, .y = 0.0F, .width = width, .height = height});
    }
  }

  void EdidDialogModal::requestLayout() {
    if (m_open && m_host != nullptr) {
      m_host->requestLayout();
    }
  }

} // namespace settings::display
