#include "shell/desktop/desktop_widgets_editor.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "pipewire/pipewire_spectrum.h"
#include "render/render_context.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/desktop/widget_transform.h"
#include "time/time_service.h"
#include "ui/controls/box.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"
#include "ui/controls/select.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/layer_surface.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"

#include <algorithm>
#include <array>
#include <charconv>
#include <cmath>
#include <format>
#include <limits>
#include <linux/input-event-codes.h>
#include <memory>
#include <string>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

constexpr Logger kLog("desktop");
constexpr float kToolbarY = 68.0f;
constexpr float kSelectionStroke = 2.0f;
constexpr float kRotatePadding = 14.0f;
constexpr float kHandleSize = 14.0f;
constexpr float kMinScale = 0.2f;
constexpr float kMaxScale = 8.0f;
constexpr float kRotationSnap = static_cast<float>(M_PI) / 12.0f;
constexpr std::array<const char*, 2> kWidgetTypeLabels{"Clock", "Audio Visualizer"};
constexpr std::string_view kDesktopWidgetIdPrefix = "desktop-widget-";

std::string outputKey(const WaylandOutput& output) {
  if (!output.connectorName.empty()) {
    return output.connectorName;
  }
  return std::to_string(output.name);
}

const WaylandOutput* resolveEffectiveOutput(const WaylandConnection& wayland, const std::string& requestedOutput) {
  const auto& outputs = wayland.outputs();
  const WaylandOutput* primary = nullptr;
  for (const auto& output : outputs) {
    if (!output.done || output.output == nullptr) {
      continue;
    }
    if (primary == nullptr) {
      primary = &output;
    }
    if (!requestedOutput.empty() && outputKey(output) == requestedOutput) {
      return &output;
    }
  }
  return primary;
}

float snapToGrid(float value, std::int32_t cellSize) {
  if (cellSize <= 0) {
    return value;
  }
  return std::round(value / static_cast<float>(cellSize)) * static_cast<float>(cellSize);
}

float normalizeAngle(float radians) {
  while (radians > static_cast<float>(M_PI)) {
    radians -= static_cast<float>(M_PI * 2.0);
  }
  while (radians < -static_cast<float>(M_PI)) {
    radians += static_cast<float>(M_PI * 2.0);
  }
  return radians;
}

float outputLogicalWidth(const WaylandOutput& output) {
  if (output.logicalWidth > 0) {
    return static_cast<float>(output.logicalWidth);
  }
  return static_cast<float>(std::max(1, output.width / std::max(1, output.scale)));
}

float outputLogicalHeight(const WaylandOutput& output) {
  if (output.logicalHeight > 0) {
    return static_cast<float>(output.logicalHeight);
  }
  return static_cast<float>(std::max(1, output.height / std::max(1, output.scale)));
}

bool formatShowsSeconds(const DesktopWidgetState& state) {
  if (state.type != "clock") {
    return false;
  }
  const auto it = state.settings.find("format");
  if (it == state.settings.end()) {
    return false;
  }
  const auto* format = std::get_if<std::string>(&it->second);
  if (format == nullptr) {
    return false;
  }
  return format->find("%S") != std::string::npos || format->find("%T") != std::string::npos ||
         format->find("%X") != std::string::npos;
}

bool parseDesktopWidgetCounter(std::string_view id, std::uint64_t& value) {
  if (!id.starts_with(kDesktopWidgetIdPrefix)) {
    return false;
  }

  const std::string_view suffix = id.substr(kDesktopWidgetIdPrefix.size());
  if (suffix.empty()) {
    return false;
  }

  value = 0;
  const auto* begin = suffix.data();
  const auto* end = suffix.data() + suffix.size();
  const auto [ptr, ec] = std::from_chars(begin, end, value, 16);
  return ec == std::errc{} && ptr == end;
}

std::string nextDesktopWidgetId(const DesktopWidgetsSnapshot& snapshot) {
  std::uint64_t maxCounter = 0;
  for (const auto& widget : snapshot.widgets) {
    std::uint64_t counter = 0;
    if (parseDesktopWidgetCounter(widget.id, counter)) {
      maxCounter = std::max(maxCounter, counter);
    }
  }

  const std::uint64_t nextCounter =
      maxCounter == std::numeric_limits<std::uint64_t>::max() ? maxCounter : (maxCounter + 1);
  return std::format("desktop-widget-{:016x}", nextCounter);
}

} // namespace

void DesktopWidgetsEditor::initialize(WaylandConnection& wayland, ConfigService* config, TimeService* timeService,
                                      PipeWireSpectrum* pipewireSpectrum, RenderContext* renderContext) {
  m_wayland = &wayland;
  m_config = config;
  m_timeService = timeService;
  m_renderContext = renderContext;
  m_factory = std::make_unique<DesktopWidgetFactory>(timeService, pipewireSpectrum);
}

void DesktopWidgetsEditor::setExitRequestedCallback(std::function<void()> callback) {
  m_exitRequestedCallback = std::move(callback);
}

void DesktopWidgetsEditor::open(const DesktopWidgetsSnapshot& snapshot) {
  m_snapshot = snapshot;
  m_open = true;
  m_selectedWidgetId.clear();
  m_drag = {};
  syncSurfaces();
  requestLayout();
}

DesktopWidgetsSnapshot DesktopWidgetsEditor::close() {
  Select::closeAnyOpen();
  m_surfaces.clear();
  m_drag = {};
  m_selectedWidgetId.clear();
  m_open = false;
  return m_snapshot;
}

bool DesktopWidgetsEditor::isOpen() const noexcept { return m_open; }

void DesktopWidgetsEditor::syncSurfaces() {
  if (!m_open || m_wayland == nullptr || m_renderContext == nullptr) {
    return;
  }

  const auto& outputs = m_wayland->outputs();
  std::erase_if(m_surfaces, [&outputs](const auto& surface) {
    return std::none_of(outputs.begin(), outputs.end(), [&surface](const auto& output) {
      return output.done && output.output != nullptr && outputKey(output) == surface->outputName;
    });
  });

  for (const auto& output : outputs) {
    if (!output.done || output.output == nullptr) {
      continue;
    }
    const std::string key = outputKey(output);
    const bool exists = std::any_of(m_surfaces.begin(), m_surfaces.end(),
                                    [&key](const auto& surface) { return surface->outputName == key; });
    if (!exists) {
      createSurface(output);
    }
  }
}

void DesktopWidgetsEditor::createSurface(const WaylandOutput& output) {
  auto surfaceConfig = LayerSurfaceConfig{
      .nameSpace = "noctalia-desktop-widgets-editor",
      .layer = LayerShellLayer::Bottom,
      .anchor = LayerShellAnchor::Top | LayerShellAnchor::Bottom | LayerShellAnchor::Left | LayerShellAnchor::Right,
      .width = 0,
      .height = 0,
      .exclusiveZone = -1,
      .keyboard = LayerShellKeyboard::OnDemand,
      .defaultWidth = output.logicalWidth > 0 ? static_cast<std::uint32_t>(output.logicalWidth)
                                              : static_cast<std::uint32_t>(std::max(1, output.width)),
      .defaultHeight = output.logicalHeight > 0 ? static_cast<std::uint32_t>(output.logicalHeight)
                                                : static_cast<std::uint32_t>(std::max(1, output.height)),
  };

  auto overlay = std::make_unique<OverlaySurface>();
  overlay->outputName = outputKey(output);
  overlay->output = output.output;
  overlay->sceneRebuildRequested = true;
  overlay->surface = std::make_unique<LayerSurface>(*m_wayland, std::move(surfaceConfig));
  overlay->surface->setRenderContext(m_renderContext);
  overlay->surface->setAnimationManager(&overlay->animations);
  overlay->inputDispatcher.setCursorShapeCallback(
      [this](std::uint32_t serial, std::uint32_t shape) { m_wayland->setCursorShape(serial, shape); });

  auto* rawOverlay = overlay.get();
  overlay->surface->setConfigureCallback(
      [rawOverlay](std::uint32_t /*width*/, std::uint32_t /*height*/) { rawOverlay->surface->requestLayout(); });
  overlay->surface->setPrepareFrameCallback(
      [this, rawOverlay](bool needsUpdate, bool needsLayout) { prepareFrame(*rawOverlay, needsUpdate, needsLayout); });
  overlay->surface->setFrameTickCallback([this, rawOverlay](float deltaMs) {
    if (m_renderContext == nullptr) {
      return;
    }
    for (auto& [id, view] : rawOverlay->views) {
      (void)id;
      if (view.widget != nullptr) {
        view.widget->onFrameTick(deltaMs, *m_renderContext);
      }
    }
  });

  if (!overlay->surface->initialize(output.output)) {
    kLog.warn("desktop widgets editor: failed to initialize overlay on {}", overlay->outputName);
    return;
  }

  m_surfaces.push_back(std::move(overlay));
}

DesktopWidgetsEditor::OverlaySurface* DesktopWidgetsEditor::findSurface(wl_surface* surface) {
  for (auto& overlay : m_surfaces) {
    if (overlay->surface != nullptr && overlay->surface->wlSurface() == surface) {
      return overlay.get();
    }
  }
  return nullptr;
}

DesktopWidgetState* DesktopWidgetsEditor::findWidgetState(const std::string& id) {
  for (auto& widget : m_snapshot.widgets) {
    if (widget.id == id) {
      return &widget;
    }
  }
  return nullptr;
}

const DesktopWidgetState* DesktopWidgetsEditor::findWidgetState(const std::string& id) const {
  for (const auto& widget : m_snapshot.widgets) {
    if (widget.id == id) {
      return &widget;
    }
  }
  return nullptr;
}

std::string DesktopWidgetsEditor::effectiveOutputName(const DesktopWidgetState& state) const {
  if (m_wayland == nullptr) {
    return state.outputName;
  }
  if (const WaylandOutput* output = resolveEffectiveOutput(*m_wayland, state.outputName); output != nullptr) {
    return outputKey(*output);
  }
  return {};
}

bool DesktopWidgetsEditor::shouldSnap() const {
  return m_snapshot.grid.visible && !m_shiftHeld && m_snapshot.grid.cellSize > 0;
}

void DesktopWidgetsEditor::prepareFrame(OverlaySurface& surface, bool needsUpdate, bool needsLayout) {
  if (m_renderContext == nullptr) {
    return;
  }

  if (surface.sceneRoot == nullptr || surface.sceneRebuildRequested || needsUpdate) {
    rebuildScene(surface);
    surface.sceneRebuildRequested = false;
    return;
  }

  if (needsLayout && surface.sceneRoot != nullptr) {
    surface.sceneRoot->layout(*m_renderContext);
  }
}

void DesktopWidgetsEditor::rebuildScene(OverlaySurface& surface) {
  surface.views.clear();
  surface.selectionBorder = nullptr;
  surface.rotationRing = nullptr;
  surface.scaleHandle = nullptr;
  surface.rotateArea = nullptr;
  surface.scaleArea = nullptr;

  auto root = std::make_unique<InputArea>();
  root->setEnabled(false);
  root->setAnimationManager(&surface.animations);
  root->setFrameSize(static_cast<float>(surface.surface->width()), static_cast<float>(surface.surface->height()));

  auto dim = std::make_unique<Box>();
  dim->setFill(roleColor(ColorRole::SurfaceVariant, 0.14f));
  dim->setPosition(0.0f, 0.0f);
  dim->setFrameSize(root->width(), root->height());
  dim->setZIndex(0);
  root->addChild(std::move(dim));

  auto backgroundArea = std::make_unique<InputArea>();
  backgroundArea->setPosition(0.0f, 0.0f);
  backgroundArea->setFrameSize(root->width(), root->height());
  backgroundArea->setZIndex(1);
  backgroundArea->setOnClick([this](const InputArea::PointerData& data) {
    if (data.button != BTN_LEFT || !m_drag.widgetId.empty()) {
      return;
    }
    if (!m_selectedWidgetId.empty()) {
      m_selectedWidgetId.clear();
      requestLayout();
    }
  });
  root->addChild(std::move(backgroundArea));

  if (m_snapshot.grid.visible && m_snapshot.grid.cellSize > 0) {
    const float width = root->width();
    const float height = root->height();
    const float cell = static_cast<float>(m_snapshot.grid.cellSize);
    const std::int32_t majorInterval = std::max(1, m_snapshot.grid.majorInterval);

    for (float x = 0.0f; x <= width; x += cell) {
      auto line = std::make_unique<Box>();
      const bool major = (static_cast<int>(std::lround(x / cell)) % majorInterval) == 0;
      line->setFill(roleColor(major ? ColorRole::Primary : ColorRole::Outline, major ? 0.18f : 0.08f));
      line->setPosition(x, 0.0f);
      line->setFrameSize(1.0f, height);
      line->setZIndex(2);
      root->addChild(std::move(line));
    }

    for (float y = 0.0f; y <= height; y += cell) {
      auto line = std::make_unique<Box>();
      const bool major = (static_cast<int>(std::lround(y / cell)) % majorInterval) == 0;
      line->setFill(roleColor(major ? ColorRole::Primary : ColorRole::Outline, major ? 0.18f : 0.08f));
      line->setPosition(0.0f, y);
      line->setFrameSize(width, 1.0f);
      line->setZIndex(2);
      root->addChild(std::move(line));
    }
  }

  for (const auto& widgetState : m_snapshot.widgets) {
    if (effectiveOutputName(widgetState) != surface.outputName || m_factory == nullptr) {
      continue;
    }

    auto widget = m_factory->create(widgetState.type, widgetState.settings,
                                    m_config != nullptr ? m_config->config().shell.uiScale : 1.0f);
    if (widget == nullptr) {
      continue;
    }

    widget->create();
    widget->setAnimationManager(&surface.animations);
    auto* surfacePtr = &surface;
    widget->setRedrawCallback([surfacePtr]() {
      if (surfacePtr->surface != nullptr) {
        surfacePtr->surface->requestRedraw();
      }
    });
    widget->update(*m_renderContext);
    widget->layout(*m_renderContext);

    EditorWidgetView view;
    view.intrinsicWidth = std::max(1.0f, widget->intrinsicWidth());
    view.intrinsicHeight = std::max(1.0f, widget->intrinsicHeight());

    auto bodyArea = std::make_unique<InputArea>();
    view.bodyArea = bodyArea.get();
    view.transformNode = view.bodyArea;
    view.transformNode->setFrameSize(view.intrinsicWidth, view.intrinsicHeight);
    view.transformNode->setPosition(widgetState.cx - view.intrinsicWidth * 0.5f,
                                    widgetState.cy - view.intrinsicHeight * 0.5f);
    view.transformNode->setRotation(widgetState.rotationRad);
    view.transformNode->setScale(widgetState.scale);
    view.transformNode->setZIndex(4);
    view.bodyArea->setOnPress([this, id = widgetState.id, w = view.intrinsicWidth, h = view.intrinsicHeight](
                                  const InputArea::PointerData& data) {
      if (data.button != BTN_LEFT) {
        return;
      }
      if (data.pressed) {
        const bool rebuildOnFinish = m_selectedWidgetId != id;
        m_selectedWidgetId = id;
        startDrag(DragMode::Move, id, w, h, rebuildOnFinish);
      } else if (m_drag.mode == DragMode::Move && m_drag.widgetId == id) {
        finishDrag();
      }
    });
    view.bodyArea->setOnMotion([this, id = widgetState.id](const InputArea::PointerData& /*data*/) {
      if (m_drag.mode == DragMode::Move && m_drag.widgetId == id) {
        updateDrag();
      }
    });
    view.transformNode->addChild(widget->releaseRoot());

    root->addChild(std::move(bodyArea));
    view.widget = std::move(widget);
    surface.views.emplace(widgetState.id, std::move(view));
  }

  const auto selectedIt = surface.views.find(m_selectedWidgetId);
  if (selectedIt != surface.views.end()) {
    auto ring = std::make_unique<Box>();
    ring->setBorder(roleColor(ColorRole::Primary, 0.55f), 1.0f);
    ring->setFill(clearThemeColor());
    ring->setRadius(Style::radiusMd + kRotatePadding);
    ring->setZIndex(3);
    surface.rotationRing = ring.get();
    root->addChild(std::move(ring));

    auto rotateArea = std::make_unique<InputArea>();
    rotateArea->setZIndex(3);
    rotateArea->setOnPress([this, id = m_selectedWidgetId, w = selectedIt->second.intrinsicWidth,
                            h = selectedIt->second.intrinsicHeight](const InputArea::PointerData& data) {
      if (data.button != BTN_LEFT) {
        return;
      }
      if (data.pressed) {
        startDrag(DragMode::Rotate, id, w, h, false);
      } else if (m_drag.mode == DragMode::Rotate && m_drag.widgetId == id) {
        finishDrag();
      }
    });
    rotateArea->setOnMotion([this, id = m_selectedWidgetId](const InputArea::PointerData& /*data*/) {
      if (m_drag.mode == DragMode::Rotate && m_drag.widgetId == id) {
        updateDrag();
      }
    });
    surface.rotateArea = rotateArea.get();
    root->addChild(std::move(rotateArea));

    auto selectionBorder = std::make_unique<Box>();
    selectionBorder->setBorder(roleColor(ColorRole::Primary), kSelectionStroke);
    selectionBorder->setFill(clearThemeColor());
    selectionBorder->setRadius(Style::radiusMd);
    // Keep the selection stroke below the body InputArea so the visual outline
    // does not steal hit-tests from move-drag interactions after selection.
    selectionBorder->setZIndex(3);
    surface.selectionBorder = selectionBorder.get();
    root->addChild(std::move(selectionBorder));

    auto scaleHandle = std::make_unique<Box>();
    scaleHandle->setFill(roleColor(ColorRole::Primary));
    scaleHandle->setRadius(Style::radiusSm);
    scaleHandle->setZIndex(6);
    surface.scaleHandle = scaleHandle.get();
    root->addChild(std::move(scaleHandle));

    auto scaleArea = std::make_unique<InputArea>();
    scaleArea->setZIndex(7);
    scaleArea->setOnPress([this, id = m_selectedWidgetId, w = selectedIt->second.intrinsicWidth,
                           h = selectedIt->second.intrinsicHeight](const InputArea::PointerData& data) {
      if (data.button != BTN_LEFT) {
        return;
      }
      if (data.pressed) {
        startDrag(DragMode::Scale, id, w, h, false);
      } else if (m_drag.mode == DragMode::Scale && m_drag.widgetId == id) {
        finishDrag();
      }
    });
    scaleArea->setOnMotion([this, id = m_selectedWidgetId](const InputArea::PointerData& /*data*/) {
      if (m_drag.mode == DragMode::Scale && m_drag.widgetId == id) {
        updateDrag();
      }
    });
    surface.scaleArea = scaleArea.get();
    root->addChild(std::move(scaleArea));

    updateSelectionVisuals(surface);
  }

  auto toolbar = std::make_unique<Flex>();
  toolbar->setDirection(FlexDirection::Horizontal);
  toolbar->setAlign(FlexAlign::Center);
  toolbar->setGap(Style::spaceSm);
  toolbar->setPadding(Style::spaceSm, Style::spaceMd);
  toolbar->setBackground(roleColor(ColorRole::Surface, 0.94f));
  toolbar->setBorderColor(roleColor(ColorRole::Outline));
  toolbar->setBorderWidth(Style::borderWidth);
  toolbar->setRadius(Style::radiusXl);
  toolbar->setZIndex(20);

  auto title = std::make_unique<Label>();
  title->setText("Desktop Widgets");
  title->setBold(true);
  title->setFontSize(Style::fontSizeBody);
  toolbar->addChild(std::move(title));

  auto typeSelect = std::make_unique<Select>();
  typeSelect->setOptions({kWidgetTypeLabels[0], kWidgetTypeLabels[1]});
  typeSelect->setSelectedIndex(m_addWidgetType == "audio_visualizer" ? 1 : 0);
  typeSelect->setControlHeight(Style::controlHeightSm);
  typeSelect->setOnSelectionChanged([this](std::size_t index, std::string_view /*text*/) {
    m_addWidgetType = index == 1 ? "audio_visualizer" : "clock";
  });
  toolbar->addChild(std::move(typeSelect));

  auto addButton = std::make_unique<Button>();
  addButton->setText("+");
  addButton->setVariant(ButtonVariant::Accent);
  addButton->setOnClick([this, outputName = surface.outputName]() { addWidget(outputName, m_addWidgetType); });
  toolbar->addChild(std::move(addButton));

  auto gridButton = std::make_unique<Button>();
  gridButton->setText(m_snapshot.grid.visible ? "Grid On" : "Grid Off");
  gridButton->setVariant(ButtonVariant::Outline);
  gridButton->setSelected(m_snapshot.grid.visible);
  gridButton->setOnClick([this]() {
    m_snapshot.grid.visible = !m_snapshot.grid.visible;
    requestLayout();
  });
  toolbar->addChild(std::move(gridButton));

  auto gridSizeSelect = std::make_unique<Select>();
  gridSizeSelect->setOptions({"8", "16", "24", "32", "64"});
  gridSizeSelect->setControlHeight(Style::controlHeightSm);
  const std::array<std::int32_t, 5> gridSizes{8, 16, 24, 32, 64};
  std::size_t selectedGridIndex = 1;
  for (std::size_t i = 0; i < gridSizes.size(); ++i) {
    if (gridSizes[i] == m_snapshot.grid.cellSize) {
      selectedGridIndex = i;
      break;
    }
  }
  gridSizeSelect->setSelectedIndex(selectedGridIndex);
  gridSizeSelect->setOnSelectionChanged([this](std::size_t /*index*/, std::string_view text) {
    try {
      m_snapshot.grid.cellSize = std::stoi(std::string(text));
      requestLayout();
    } catch (...) {
    }
  });
  toolbar->addChild(std::move(gridSizeSelect));

  auto doneButton = std::make_unique<Button>();
  doneButton->setText("Done");
  doneButton->setVariant(ButtonVariant::Secondary);
  doneButton->setOnClick([this]() { requestExit(); });
  toolbar->addChild(std::move(doneButton));

  auto* toolbarPtr = toolbar.get();
  root->addChild(std::move(toolbar));
  toolbarPtr->layout(*m_renderContext);
  toolbarPtr->setPosition(std::round((root->width() - toolbarPtr->width()) * 0.5f), kToolbarY);

  surface.sceneRoot = std::move(root);
  surface.surface->setSceneRoot(surface.sceneRoot.get());
  surface.inputDispatcher.setSceneRoot(surface.sceneRoot.get());
}

void DesktopWidgetsEditor::updateSelectionVisuals(OverlaySurface& surface) {
  const auto selectedIt = surface.views.find(m_selectedWidgetId);
  const DesktopWidgetState* state = findWidgetState(m_selectedWidgetId);
  if (selectedIt == surface.views.end() || state == nullptr || surface.selectionBorder == nullptr ||
      surface.rotationRing == nullptr || surface.scaleHandle == nullptr || surface.rotateArea == nullptr ||
      surface.scaleArea == nullptr) {
    return;
  }

  const WidgetTransformBounds bounds = computeWidgetTransformBounds(
      state->cx, state->cy, selectedIt->second.intrinsicWidth, selectedIt->second.intrinsicHeight, state->scale,
      state->rotationRad);

  surface.rotationRing->setPosition(bounds.left - kRotatePadding, bounds.top - kRotatePadding);
  surface.rotationRing->setFrameSize(bounds.aabbWidth + kRotatePadding * 2.0f, bounds.aabbHeight + kRotatePadding * 2.0f);

  surface.rotateArea->setPosition(bounds.left - kRotatePadding, bounds.top - kRotatePadding);
  surface.rotateArea->setFrameSize(bounds.aabbWidth + kRotatePadding * 2.0f, bounds.aabbHeight + kRotatePadding * 2.0f);

  surface.selectionBorder->setPosition(bounds.left, bounds.top);
  surface.selectionBorder->setFrameSize(bounds.aabbWidth, bounds.aabbHeight);

  surface.scaleHandle->setPosition(bounds.left + bounds.aabbWidth - kHandleSize * 0.5f,
                                   bounds.top + bounds.aabbHeight - kHandleSize * 0.5f);
  surface.scaleHandle->setFrameSize(kHandleSize, kHandleSize);

  surface.scaleArea->setPosition(bounds.left + bounds.aabbWidth - kHandleSize,
                                 bounds.top + bounds.aabbHeight - kHandleSize);
  surface.scaleArea->setFrameSize(kHandleSize * 1.5f, kHandleSize * 1.5f);
}

void DesktopWidgetsEditor::updateViewTransforms() {
  for (auto& surface : m_surfaces) {
    for (auto& [id, view] : surface->views) {
      const DesktopWidgetState* state = findWidgetState(id);
      if (state == nullptr) {
        continue;
      }
      view.transformNode->setFrameSize(view.intrinsicWidth, view.intrinsicHeight);
      view.transformNode->setPosition(state->cx - view.intrinsicWidth * 0.5f, state->cy - view.intrinsicHeight * 0.5f);
      view.transformNode->setRotation(state->rotationRad);
      view.transformNode->setScale(state->scale);
    }
    updateSelectionVisuals(*surface);
  }
}

void DesktopWidgetsEditor::addWidget(const std::string& outputName, const std::string& type) {
  if (!m_open || m_wayland == nullptr) {
    return;
  }

  float centerX = 320.0f;
  float centerY = 240.0f;
  if (const WaylandOutput* output = resolveEffectiveOutput(*m_wayland, outputName); output != nullptr) {
    const int logicalWidth = output->logicalWidth > 0 ? output->logicalWidth
                                                       : output->width / std::max(1, output->scale);
    const int logicalHeight = output->logicalHeight > 0 ? output->logicalHeight
                                                         : output->height / std::max(1, output->scale);
    centerX = static_cast<float>(std::max(1, logicalWidth)) * 0.5f;
    centerY = static_cast<float>(std::max(1, logicalHeight)) * 0.5f;
  }

  DesktopWidgetState widget;
  widget.id = nextDesktopWidgetId(m_snapshot);
  widget.type = type.empty() ? "clock" : type;
  widget.outputName = outputName;
  widget.cx = centerX;
  widget.cy = centerY;
  widget.scale = 1.0f;
  widget.rotationRad = 0.0f;
  if (widget.type == "audio_visualizer") {
    widget.settings.emplace("width", 240.0);
    widget.settings.emplace("height", 96.0);
    widget.settings.emplace("bands", static_cast<std::int64_t>(32));
  }

  m_snapshot.widgets.push_back(std::move(widget));
  m_selectedWidgetId = m_snapshot.widgets.back().id;
  requestLayout();
}

void DesktopWidgetsEditor::removeSelectedWidget() {
  if (m_selectedWidgetId.empty()) {
    return;
  }
  std::erase_if(m_snapshot.widgets, [this](const auto& widget) { return widget.id == m_selectedWidgetId; });
  m_selectedWidgetId.clear();
  requestLayout();
}

void DesktopWidgetsEditor::requestExit() {
  if (!m_exitRequestedCallback) {
    return;
  }
  DeferredCall::callLater([this]() {
    if (m_open && m_exitRequestedCallback) {
      m_exitRequestedCallback();
    }
  });
}

void DesktopWidgetsEditor::startDrag(DragMode mode, const std::string& widgetId, float intrinsicWidth,
                                     float intrinsicHeight, bool rebuildOnFinish) {
  DesktopWidgetState* state = findWidgetState(widgetId);
  if (state == nullptr) {
    return;
  }

  m_drag.mode = mode;
  m_drag.widgetId = widgetId;
  m_drag.startSceneX = m_currentEventSceneX;
  m_drag.startSceneY = m_currentEventSceneY;
  m_drag.initialState = *state;
  m_drag.intrinsicWidth = intrinsicWidth;
  m_drag.intrinsicHeight = intrinsicHeight;
  m_drag.rebuildOnFinish = rebuildOnFinish;
}

void DesktopWidgetsEditor::updateDrag() {
  DesktopWidgetState* state = findWidgetState(m_drag.widgetId);
  if (state == nullptr || m_drag.mode == DragMode::None) {
    return;
  }

  if (m_drag.mode == DragMode::Move) {
    state->cx = m_drag.initialState.cx + (m_currentEventSceneX - m_drag.startSceneX);
    state->cy = m_drag.initialState.cy + (m_currentEventSceneY - m_drag.startSceneY);
    if (shouldSnap()) {
      state->cx = snapToGrid(state->cx, m_snapshot.grid.cellSize);
      state->cy = snapToGrid(state->cy, m_snapshot.grid.cellSize);
    }
  } else if (m_drag.mode == DragMode::Rotate) {
    const float startAngle = std::atan2(m_drag.startSceneY - m_drag.initialState.cy,
                                        m_drag.startSceneX - m_drag.initialState.cx);
    const float currentAngle =
        std::atan2(m_currentEventSceneY - m_drag.initialState.cy, m_currentEventSceneX - m_drag.initialState.cx);
    float rotation = normalizeAngle(m_drag.initialState.rotationRad + (currentAngle - startAngle));
    if (shouldSnap()) {
      rotation = std::round(rotation / kRotationSnap) * kRotationSnap;
    }
    state->rotationRad = rotation;
  } else if (m_drag.mode == DragMode::Scale) {
    if (shouldSnap()) {
      const float snappedCornerX = snapToGrid(m_currentEventSceneX, m_snapshot.grid.cellSize);
      const float snappedCornerY = snapToGrid(m_currentEventSceneY, m_snapshot.grid.cellSize);
      const WidgetTransformBounds baseBounds = computeWidgetTransformBounds(
          m_drag.initialState.cx, m_drag.initialState.cy, m_drag.intrinsicWidth, m_drag.intrinsicHeight, 1.0f,
          m_drag.initialState.rotationRad);
      const float scaleX =
          std::max(0.0f, (snappedCornerX - m_drag.initialState.cx) * 2.0f / std::max(1.0f, baseBounds.aabbWidth));
      const float scaleY =
          std::max(0.0f, (snappedCornerY - m_drag.initialState.cy) * 2.0f / std::max(1.0f, baseBounds.aabbHeight));
      state->scale = std::clamp(std::max(scaleX, scaleY), kMinScale, kMaxScale);
    } else {
      const float dx = m_currentEventSceneX - m_drag.initialState.cx;
      const float dy = m_currentEventSceneY - m_drag.initialState.cy;
      const float cosTheta = std::cos(-m_drag.initialState.rotationRad);
      const float sinTheta = std::sin(-m_drag.initialState.rotationRad);
      const float localX = dx * cosTheta - dy * sinTheta;
      const float localY = dx * sinTheta + dy * cosTheta;
      const float halfWidth = std::max(1.0f, m_drag.intrinsicWidth * 0.5f);
      const float halfHeight = std::max(1.0f, m_drag.intrinsicHeight * 0.5f);
      const float denominator = halfWidth * halfWidth + halfHeight * halfHeight;
      const float scale = (localX * halfWidth + localY * halfHeight) / std::max(1.0f, denominator);
      state->scale = std::clamp(scale, kMinScale, kMaxScale);
    }
  }

  if (m_wayland != nullptr) {
    if (const WaylandOutput* output = resolveEffectiveOutput(*m_wayland, state->outputName); output != nullptr) {
      const WidgetTransformClampResult clamped =
          clampWidgetCenterToOutput(state->cx, state->cy, m_drag.intrinsicWidth, m_drag.intrinsicHeight, state->scale,
                                    state->rotationRad, outputLogicalWidth(*output), outputLogicalHeight(*output),
                                    kDesktopWidgetMinVisibleFraction);
      state->cx = clamped.cx;
      state->cy = clamped.cy;
    }
  }

  updateViewTransforms();
  requestRedraw();
}

void DesktopWidgetsEditor::finishDrag() {
  const bool rebuild = m_drag.rebuildOnFinish;
  m_drag = {};
  if (rebuild) {
    requestLayout();
  }
}

bool DesktopWidgetsEditor::onPointerEvent(const PointerEvent& event) {
  if (!m_open) {
    return false;
  }

  wl_surface* eventSurface = event.surface;
  if (eventSurface == nullptr && m_wayland != nullptr) {
    // wl_pointer.motion does not carry the surface; reuse the seat's current
    // pointer focus so drags continue after the initial press.
    eventSurface = m_wayland->lastPointerSurface();
  }

  OverlaySurface* surface = findSurface(eventSurface);
  if (surface == nullptr) {
    return false;
  }

  m_currentEventSceneX = static_cast<float>(event.sx);
  m_currentEventSceneY = static_cast<float>(event.sy);

  switch (event.type) {
  case PointerEvent::Type::Enter:
    surface->pointerInside = true;
    surface->inputDispatcher.pointerEnter(static_cast<float>(event.sx), static_cast<float>(event.sy), event.serial);
    break;
  case PointerEvent::Type::Leave:
    surface->pointerInside = false;
    surface->inputDispatcher.pointerLeave();
    break;
  case PointerEvent::Type::Motion:
    surface->inputDispatcher.pointerMotion(static_cast<float>(event.sx), static_cast<float>(event.sy), event.serial);
    break;
  case PointerEvent::Type::Button:
    if (event.state == 1) {
      Select::handleGlobalPointerPress(surface->inputDispatcher.hoveredArea());
    }
    surface->inputDispatcher.pointerButton(static_cast<float>(event.sx), static_cast<float>(event.sy), event.button,
                                           event.state == 1);
    if (event.state == 0 && m_drag.mode != DragMode::None && event.button == BTN_LEFT) {
      finishDrag();
    }
    break;
  case PointerEvent::Type::Axis:
    surface->inputDispatcher.pointerAxis(static_cast<float>(event.sx), static_cast<float>(event.sy), event.axis,
                                         event.axisSource, event.axisValue, event.axisDiscrete, event.axisValue120,
                                         event.axisLines);
    break;
  }

  if (surface->sceneRoot != nullptr && (surface->sceneRoot->layoutDirty() || surface->sceneRoot->paintDirty())) {
    if (surface->sceneRoot->layoutDirty()) {
      surface->surface->requestLayout();
    } else {
      surface->surface->requestRedraw();
    }
  }

  return true;
}

void DesktopWidgetsEditor::onKeyboardEvent(const KeyboardEvent& event) {
  if (!m_open) {
    return;
  }

  m_shiftHeld = (event.modifiers & KeyMod::Shift) != 0;

  if (!event.pressed || event.preedit) {
    return;
  }

  if (event.sym == XKB_KEY_Escape) {
    requestExit();
    return;
  }

  if (event.sym == XKB_KEY_Delete || event.sym == XKB_KEY_BackSpace) {
    removeSelectedWidget();
    return;
  }

  if (event.sym == XKB_KEY_g || event.sym == XKB_KEY_G || event.utf32 == static_cast<std::uint32_t>('g') ||
      event.utf32 == static_cast<std::uint32_t>('G')) {
    m_snapshot.grid.visible = !m_snapshot.grid.visible;
    requestLayout();
  }
}

void DesktopWidgetsEditor::onOutputChange() {
  if (!m_open) {
    return;
  }
  syncSurfaces();
  requestLayout();
}

void DesktopWidgetsEditor::onSecondTick() {
  if (!m_open || m_drag.mode != DragMode::None || m_timeService == nullptr) {
    return;
  }

  const bool minuteBoundary = m_timeService->format("{:%S}") == "00";
  const bool needsSeconds = std::any_of(m_snapshot.widgets.begin(), m_snapshot.widgets.end(),
                                        [](const auto& widget) { return formatShowsSeconds(widget); });
  if (minuteBoundary || needsSeconds) {
    requestLayout();
  }
}

void DesktopWidgetsEditor::requestLayout() {
  for (auto& surface : m_surfaces) {
    if (surface->surface != nullptr) {
      surface->sceneRebuildRequested = true;
      surface->surface->requestLayout();
    }
  }
}

void DesktopWidgetsEditor::requestRedraw() {
  for (auto& surface : m_surfaces) {
    if (surface->surface != nullptr) {
      surface->surface->requestRedraw();
    }
  }
}
