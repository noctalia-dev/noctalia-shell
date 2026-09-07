#include "shell/settings/display/monitor_editor_modal.h"

#include "core/deferred_call.h"
#include "i18n/i18n.h"
#include "render/core/renderer.h"
#include "shell/settings/display/display_layout.h"
#include "shell/settings/display/display_service.h"
#include "shell/settings/display/monitor_layout_canvas.h"
#include "shell/settings/display/revert_dialog_modal.h"
#include "ui/builders.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/select.h"
#include "ui/controls/stepper.h"
#include "ui/controls/toggle.h"
#include "ui/style.h"
#include "util/string_utils.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <utility>

namespace settings::display {

  namespace {

    constexpr auto kTransformOptions = std::array<std::pair<std::string_view, std::string_view>, 8>{{
        {"Normal", "normal"},
        {"90", "90"},
        {"180", "180"},
        {"270", "270"},
        {"Flipped", "flipped"},
        {"Flipped90", "flipped-90"},
        {"Flipped180", "flipped-180"},
        {"Flipped270", "flipped-270"},
    }};

    [[nodiscard]] std::string transformLabel(std::string_view transform) {
      if (transform == "90")
        return "90°";
      if (transform == "180")
        return "180°";
      if (transform == "270")
        return "270°";
      if (transform == "Flipped")
        return i18n::tr("settings.display.flipped");
      if (transform == "Flipped90")
        return i18n::tr("settings.display.flipped-angle", "angle", "90°");
      if (transform == "Flipped180")
        return i18n::tr("settings.display.flipped-angle", "angle", "180°");
      if (transform == "Flipped270")
        return i18n::tr("settings.display.flipped-angle", "angle", "270°");
      return i18n::tr("common.normal");
    }

    [[nodiscard]] std::vector<std::string>
    uniqueResolutions(const std::vector<compositors::display::DisplayMode>& modes) {
      std::vector<std::string> resolutions;
      for (const auto& mode : modes) {
        const auto key = std::to_string(mode.width) + "x" + std::to_string(mode.height);
        if (std::ranges::find(resolutions, key) == resolutions.end()) {
          resolutions.push_back(key);
        }
      }
      return resolutions;
    }

    [[nodiscard]] std::vector<int> sortedRatesForResolution(
        const std::vector<compositors::display::DisplayMode>& modes, const std::string& resolution
    ) {
      std::vector<int> rates;
      for (const auto& mode : modes) {
        const auto key = std::to_string(mode.width) + "x" + std::to_string(mode.height);
        if (key == resolution && std::ranges::find(rates, mode.refreshMhz) == rates.end()) {
          rates.push_back(mode.refreshMhz);
        }
      }
      std::ranges::sort(rates, std::greater<int>());
      return rates;
    }

    [[nodiscard]] bool modeIsPreferred(
        const std::vector<compositors::display::DisplayMode>& modes, const std::string& resolution, int refreshMhz
    ) {
      for (const auto& mode : modes) {
        const auto key = std::to_string(mode.width) + "x" + std::to_string(mode.height);
        if (key == resolution && mode.refreshMhz == refreshMhz && mode.preferred) {
          return true;
        }
      }
      return false;
    }

    [[nodiscard]] int
    firstRateForResolution(const std::vector<compositors::display::DisplayMode>& modes, const std::string& resolution) {
      for (const auto& mode : modes) {
        const auto key = std::to_string(mode.width) + "x" + std::to_string(mode.height);
        if (key == resolution) {
          return mode.refreshMhz;
        }
      }
      return 60000;
    }

    [[nodiscard]] std::unique_ptr<Flex> controlColumn(std::string label, float scale, std::unique_ptr<Node> control) {
      auto column = ui::column({
          .align = FlexAlign::Stretch,
          .gap = Style::spaceXs * scale,
      });
      column->addChild(
          ui::label({
              .text = std::move(label),
              .fontSize = Style::fontSizeCaption * scale,
              .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
          })
      );
      column->addChild(std::move(control));
      return column;
    }

  } // namespace

  MonitorEditorModal::~MonitorEditorModal() {
    if (m_open) {
      close();
    }
    m_aliveGuard.reset();
  }

  void MonitorEditorModal::initialize(SettingsModalHost& host, std::function<void()> dismissSelectDropdown) {
    m_host = &host;
    m_dismissSelectDropdown = std::move(dismissSelectDropdown);
    m_revertDialog = std::make_unique<RevertDialogModal>();
    m_revertDialog->initialize(host);
  }

  void MonitorEditorModal::open(MonitorEditorRequest request) {
    if (m_host == nullptr) {
      return;
    }
    if (m_open) {
      close();
    }
    if (m_dismissSelectDropdown) {
      m_dismissSelectDropdown();
    }

    m_scale = std::max(0.1F, request.scale);
    m_display = request.display;
    m_onOpenEdid = std::move(request.onOpenEdid);
    m_onClosed = std::move(request.onClosed);
    m_selectedOutput.clear();
    m_dirty = false;
    clearNodePointers();

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
                  if (aliveGuard.expired()) {
                    return;
                  }
                  m_open = false;
                  m_modalId.reset();
                  m_display = nullptr;
                  m_selectedOutput.clear();
                  clearNodePointers();
                  if (m_revertDialog != nullptr && m_revertDialog->isOpen()) {
                    m_revertDialog->close();
                  }
                  if (m_onClosed) {
                    m_onClosed();
                  }
                },
            .contentPadding = 0.0F,
            .windowMargin = 12.0F * m_scale,
        }
    );
    m_open = m_modalId.has_value();
    if (!m_open) {
      m_display = nullptr;
      clearNodePointers();
    }
  }

  void MonitorEditorModal::close() {
    if (!m_open || m_host == nullptr || !m_modalId.has_value()) {
      return;
    }
    (void)m_host->pop(*m_modalId);
  }

  void MonitorEditorModal::setSelectedOutput(std::string name) {
    if (m_selectedOutput == name) {
      return;
    }
    m_selectedOutput = std::move(name);
    if (m_open && m_host != nullptr && m_modalId.has_value() && m_host->isTop(*m_modalId)) {
      m_host->rebuildTop();
    } else {
      m_dirty = true;
    }
  }

  void MonitorEditorModal::update(Renderer& renderer) {
    if (m_display != nullptr && m_revertDialog != nullptr) {
      if (m_display->awaitingConfirmation() && !m_revertDialog->isOpen()) {
        m_revertDialog->open(*m_display, m_scale);
      } else if (!m_display->awaitingConfirmation() && m_revertDialog->isOpen()) {
        m_revertDialog->close();
      }
    }
    if (m_dirty && m_open && m_host != nullptr && m_modalId.has_value() && m_host->isTop(*m_modalId)) {
      m_dirty = false;
      m_host->rebuildTop();
    }
  }

  std::unique_ptr<Node> MonitorEditorModal::build() {
    clearNodePointers();
    const float gap = Style::spaceMd * m_scale;
    const float padding = Style::spaceMd * m_scale;
    auto root = ui::column({
        .out = &m_root,
        .align = FlexAlign::Stretch,
        .gap = gap,
        .padding = padding,
        .fillWidth = true,
        .fillHeight = true,
    });

    root->addChild(
        ui::row(
            {
                .align = FlexAlign::Center,
                .gap = Style::spaceSm * m_scale,
            },
            ui::label({
                .text = i18n::tr("settings.display.title"),
                .fontSize = Style::fontSizeTitle * m_scale,
                .fontWeight = FontWeight::Bold,
                .color = colorSpecFromRole(ColorRole::OnSurface),
                .flexGrow = 1.0F,
            }),
            ui::button({
                .glyph = "close",
                .glyphSize = Style::fontSizeBody * m_scale,
                .variant = ButtonVariant::Default,
                .minWidth = Style::controlHeightSm * m_scale,
                .minHeight = Style::controlHeightSm * m_scale,
                .padding = Style::spaceXs * m_scale,
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

    if (m_display != nullptr && !m_display->writable()) {
      root->addChild(
          ui::column(
              {
                  .align = FlexAlign::Stretch,
                  .gap = Style::spaceXs * m_scale,
                  .padding = Style::spaceMd * m_scale,
                  .fillWidth = true,
                  .configure =
                      [this](Flex& box) {
                        box.setRadius(Style::scaledRadiusMd(m_scale));
                        box.setFill(colorSpecFromRole(ColorRole::Error, 0.15F));
                        box.setBorder(colorSpecFromRole(ColorRole::Error), Style::borderWidth);
                      },
              },
              ui::label({
                  .text = i18n::tr("settings.display.hw-control-unavailable"),
                  .fontSize = Style::fontSizeBody * m_scale,
                  .fontWeight = FontWeight::Bold,
                  .color = colorSpecFromRole(ColorRole::Error),
              }),
              ui::label({
                  .text = i18n::tr("settings.display.hw-control-unavailable-desc"),
                  .fontSize = Style::fontSizeCaption * m_scale,
                  .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
                  .maxLines = 0,
              })
          )
      );
    }

    if (m_display != nullptr && !m_display->lastError().empty()) {
      root->addChild(
          ui::label({
              .text = m_display->lastError(),
              .fontSize = Style::fontSizeCaption * m_scale,
              .color = colorSpecFromRole(ColorRole::Error),
          })
      );
    }

    if (m_display != nullptr) {
      root->addChild(
          ui::label({
              .text = i18n::tr("settings.display.monitor-drag-info"),
              .fontSize = Style::fontSizeCaption * m_scale,
              .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
          })
      );
      root->addChild(
          std::make_unique<MonitorLayoutCanvas>(
              *m_display, m_selectedOutput, [this](const std::string& name) { setSelectedOutput(name); }, m_scale
          )
      );
    }

    auto scroll = ui::scrollView({
        .flexGrow = 1.0F,
    });
    auto cards = ui::column({
        .align = FlexAlign::Stretch,
        .gap = gap,
        .fillWidth = true,
    });
    if (m_display != nullptr) {
      for (const auto& [name, output] : m_display->target()) {
        cards->addChild(buildOutputCard(output));
      }
      if (m_display->target().empty() && !m_display->loading()) {
        cards->addChild(
            ui::label({
                .text = i18n::tr("common.no-results"),
                .fontSize = Style::fontSizeBody * m_scale,
                .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
            })
        );
      }
    }
    scroll->addChild(std::move(cards));
    root->addChild(std::move(scroll));

    return root;
  }

  std::unique_ptr<Flex> MonitorEditorModal::buildOutputCard(const compositors::display::OutputState& output) {
    const bool selected = m_selectedOutput == output.name;
    const bool writable = m_display != nullptr && m_display->writable();

    auto card = ui::column({
        .align = FlexAlign::Stretch,
        .gap = Style::spaceSm * m_scale,
        .padding = Style::spaceMd * m_scale,
        .fillWidth = true,
        .configure = [this, selected, writable](Flex& box) {
          box.setRadius(Style::scaledRadiusMd(m_scale));
          box.setFill(
              selected && writable ? colorSpecFromRole(ColorRole::Primary, 0.10F)
                                   : colorSpecFromRole(ColorRole::Surface)
          );
          box.setBorder(
              selected && writable ? colorSpecFromRole(ColorRole::Primary) : colorSpecFromRole(ColorRole::Outline),
              selected ? 2.0F : Style::borderWidth
          );
        },
    });

    card->addChild(
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
                    .text = output.name,
                    .fontSize = Style::fontSizeBody * m_scale,
                    .fontWeight = FontWeight::Bold,
                    .color = selected ? colorSpecFromRole(ColorRole::Primary) : colorSpecFromRole(ColorRole::OnSurface),
                    .maxLines = 1,
                }),
                ui::label({
                    .text = output.make.empty() && output.model.empty()
                        ? i18n::tr("common.unknown")
                        : output.make + (output.make.empty() || output.model.empty() ? "" : " · ") + output.model,
                    .fontSize = Style::fontSizeCaption * m_scale,
                    .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
                    .maxLines = 1,
                })
            ),
            ui::button({
                .glyph = "info-circle",
                .glyphSize = Style::fontSizeBody * m_scale,
                .variant = ButtonVariant::Default,
                .minWidth = Style::controlHeightSm * m_scale,
                .minHeight = Style::controlHeightSm * m_scale,
                .padding = Style::spaceXs * m_scale,
                .radius = Style::scaledRadiusMd(m_scale),
                .onClick = [this, name = output.name]() {
                  if (m_onOpenEdid) {
                    m_selectedOutput = name;
                    m_onOpenEdid(name);
                  }
                },
            })
        )
    );

    const auto sizes = predictedSizes(m_display->outputs(), m_display->target());
    const auto sizeIt = sizes.find(output.name);
    const OutputSize size = sizeIt != sizes.end() ? sizeIt->second : OutputSize{0, 0};

    card->addChild(
        ui::row(
            {
                .align = FlexAlign::Center,
                .gap = Style::spaceLg * m_scale,
                .padding = Style::spaceSm * m_scale,
                .fillWidth = true,
                .configure =
                    [this](Flex& row) {
                      row.setRadius(Style::scaledRadiusSm(m_scale));
                      row.setFill(colorSpecFromRole(ColorRole::SurfaceVariant, 0.35F));
                    },
            },
            ui::column(
                {
                    .align = FlexAlign::Stretch,
                    .gap = Style::spaceXs * m_scale,
                },
                ui::label({
                    .text = i18n::tr("common.position"),
                    .fontSize = Style::fontSizeCaption * m_scale,
                    .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
                }),
                ui::label({
                    .text = "(" + std::to_string(output.x) + ", " + std::to_string(output.y) + ")",
                    .fontSize = Style::fontSizeBody * m_scale,
                    .color = colorSpecFromRole(ColorRole::OnSurface),
                })
            ),
            ui::column(
                {
                    .align = FlexAlign::Stretch,
                    .gap = Style::spaceXs * m_scale,
                },
                ui::label({
                    .text = i18n::tr("settings.display.logical-size"),
                    .fontSize = Style::fontSizeCaption * m_scale,
                    .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
                }),
                ui::label({
                    .text = std::to_string(size.w) + "×" + std::to_string(size.h),
                    .fontSize = Style::fontSizeBody * m_scale,
                    .color = colorSpecFromRole(ColorRole::OnSurface),
                })
            ),
            ui::column(
                {
                    .align = FlexAlign::Stretch,
                    .gap = Style::spaceXs * m_scale,
                },
                ui::label({
                    .text = i18n::tr("common.scale"),
                    .fontSize = Style::fontSizeCaption * m_scale,
                    .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
                }),
                ui::label({
                    .text = StringUtils::formatDotDecimal(output.scale) + "x",
                    .fontSize = Style::fontSizeBody * m_scale,
                    .color = colorSpecFromRole(ColorRole::OnSurface),
                })
            ),
            ui::column(
                {
                    .align = FlexAlign::Stretch,
                    .gap = Style::spaceXs * m_scale,
                },
                ui::label({
                    .text = i18n::tr("settings.display.rotation"),
                    .fontSize = Style::fontSizeCaption * m_scale,
                    .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
                }),
                ui::label({
                    .text = transformLabel(output.transform),
                    .fontSize = Style::fontSizeBody * m_scale,
                    .color = colorSpecFromRole(ColorRole::OnSurface),
                })
            )
        )
    );

    if (!writable || !output.enabled) {
      return card;
    }

    const auto resolutions = uniqueResolutions(output.modes);
    const auto modeParts =
        output.modeStr.empty() ? std::string{"0x0"} : output.modeStr.substr(0, output.modeStr.find('@'));
    const auto resolutionIndex = std::ranges::find(resolutions, modeParts);
    card->addChild(controlColumn(
        i18n::tr("common.resolution"), m_scale,
        ui::select({
            .options = resolutions,
            .selectedIndex = resolutionIndex != resolutions.end()
                ? std::optional<std::size_t>(static_cast<std::size_t>(resolutionIndex - resolutions.begin()))
                : std::nullopt,
            .clearSelection = resolutionIndex == resolutions.end(),
            .fontSize = Style::fontSizeBody * m_scale,
            .controlHeight = Style::controlHeight * m_scale,
            .glyphSize = Style::fontSizeBody * m_scale,
            .onSelectionChanged =
                [this, name = output.name, resolutions](std::size_t index, std::string_view) {
                  if (m_display == nullptr || index >= resolutions.size()) {
                    return;
                  }
                  const auto& target = m_display->target();
                  const auto it = target.find(name);
                  if (it == target.end()) {
                    return;
                  }
                  const int rate = firstRateForResolution(it->second.modes, resolutions[index]);
                  m_display->setMode(name, resolutions[index] + "@" + compositors::display::formatRateHz(rate));
                },
            .configure = [](Select& select) { select.setFillWidth(true); },
        })
    ));

    const auto rates = sortedRatesForResolution(output.modes, modeParts);
    std::vector<std::string> rateLabels;
    rateLabels.reserve(rates.size());
    std::optional<std::size_t> selectedRate;
    for (std::size_t i = 0; i < rates.size(); ++i) {
      char buffer[32];
      std::snprintf(
          buffer, sizeof(buffer), "%.2f Hz%s", rates[i] / 1000.0,
          modeIsPreferred(output.modes, modeParts, rates[i]) ? " *" : ""
      );
      rateLabels.push_back(buffer);
      for (const auto& mode : output.modes) {
        if (mode.current && mode.refreshMhz == rates[i]) {
          selectedRate = i;
        }
      }
    }
    card->addChild(controlColumn(
        i18n::tr("settings.display.refresh-rate"), m_scale,
        ui::select({
            .options = rateLabels,
            .selectedIndex = selectedRate,
            .clearSelection = !selectedRate.has_value(),
            .fontSize = Style::fontSizeBody * m_scale,
            .controlHeight = Style::controlHeight * m_scale,
            .glyphSize = Style::fontSizeBody * m_scale,
            .onSelectionChanged =
                [this, name = output.name, modeParts, rates](std::size_t index, std::string_view) {
                  if (m_display == nullptr || index >= rates.size()) {
                    return;
                  }
                  m_display->setMode(name, modeParts + "@" + compositors::display::formatRateHz(rates[index]));
                },
            .configure = [](Select& select) { select.setFillWidth(true); },
        })
    ));

    card->addChild(controlColumn(
        i18n::tr("common.scale"), m_scale,
        ui::stepper({
            .minValue = 25,
            .maxValue = 400,
            .step = 5,
            .value = static_cast<int>(std::lround(output.scale * 100.0)),
            .scale = m_scale,
            .valueSuffix = "%",
            .onValueCommitted =
                [this, name = output.name](int value) {
                  if (m_display == nullptr) {
                    return;
                  }
                  m_scaleDebounceOutput = name;
                  m_scaleDebounceTimer.start(std::chrono::milliseconds(600), [this, value]() {
                    if (m_display != nullptr) {
                      m_display->setScale(m_scaleDebounceOutput, value / 100.0);
                    }
                  });
                },
            .configure = [](Stepper& stepper) { stepper.setFillWidth(true); },
        })
    ));

    std::vector<std::string> rotationLabels;
    rotationLabels.reserve(kTransformOptions.size());
    for (const auto& [transform, labelKey] : kTransformOptions) {
      rotationLabels.push_back(
          transform == "Flipped90" || transform == "Flipped180" || transform == "Flipped270"
              ? i18n::tr("settings.display.flipped-angle", "angle", transformLabel(transform))
              : transformLabel(transform)
      );
    }
    const auto transformIndex = std::ranges::find_if(kTransformOptions, [&output](const auto& option) {
      return option.first == output.transform;
    });
    card->addChild(controlColumn(
        i18n::tr("settings.display.rotation"), m_scale,
        ui::select({
            .options = rotationLabels,
            .selectedIndex = transformIndex != kTransformOptions.end()
                ? std::optional<std::size_t>(static_cast<std::size_t>(transformIndex - kTransformOptions.begin()))
                : std::nullopt,
            .clearSelection = transformIndex == kTransformOptions.end(),
            .fontSize = Style::fontSizeBody * m_scale,
            .controlHeight = Style::controlHeight * m_scale,
            .glyphSize = Style::fontSizeBody * m_scale,
            .onSelectionChanged =
                [this, name = output.name](std::size_t index, std::string_view) {
                  if (m_display == nullptr || index >= kTransformOptions.size()) {
                    return;
                  }
                  m_display->setTransform(name, std::string(kTransformOptions[index].first));
                },
            .configure = [](Select& select) { select.setFillWidth(true); },
        })
    ));

    card->addChild(
        ui::row(
            {
                .align = FlexAlign::Center,
                .gap = Style::spaceSm * m_scale,
                .fillWidth = true,
            },
            ui::label({
                .text = i18n::tr("settings.display.vrr"),
                .fontSize = Style::fontSizeCaption * m_scale,
                .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
                .flexGrow = 1.0F,
            }),
            ui::toggle({
                .checked = output.vrr,
                .scale = m_scale,
                .onChange = [this, name = output.name](bool checked) {
                  if (m_display != nullptr) {
                    m_display->setVrr(name, checked);
                  }
                },
            })
        )
    );

    int enabledCount = 0;
    for (const auto& [otherName, other] : m_display->target()) {
      if (other.enabled) {
        enabledCount++;
      }
    }
    const bool isLastEnabled = output.enabled && enabledCount <= 1;
    card->addChild(
        ui::row(
            {
                .align = FlexAlign::Center,
                .gap = Style::spaceSm * m_scale,
                .fillWidth = true,
            },
            ui::label({
                .text = i18n::tr("common.enable-display"),
                .fontSize = Style::fontSizeCaption * m_scale,
                .color = colorSpecFromRole(ColorRole::OnSurfaceVariant),
                .flexGrow = 1.0F,
            }),
            ui::toggle({
                .checked = output.enabled,
                .enabled = !isLastEnabled,
                .scale = m_scale,
                .onChange = [this, name = output.name](bool checked) {
                  if (m_display != nullptr) {
                    m_display->toggleOutput(name, checked);
                  }
                },
            })
        )
    );

    return card;
  }

  LayoutSize MonitorEditorModal::measure(Renderer& /*renderer*/, const SettingsModalLayoutSpace& space) {
    if (m_root == nullptr) {
      return {.width = 1.0F, .height = 1.0F};
    }
    return {.width = space.maxContentWidth, .height = space.maxContentHeight};
  }

  void MonitorEditorModal::arrange(Renderer& renderer, float width, float height) {
    if (m_root != nullptr) {
      m_root->arrange(renderer, {.x = 0.0F, .y = 0.0F, .width = width, .height = height});
    }
  }

  void MonitorEditorModal::requestLayout() {
    if (m_open && m_host != nullptr) {
      m_host->requestLayout();
    }
  }

  void MonitorEditorModal::requestRedraw() { requestLayout(); }

  void MonitorEditorModal::clearNodePointers() { m_root = nullptr; }

} // namespace settings::display
