#include "shell/desktop/desktop_widgets_editor.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "cursor-shape-v1-client-protocol.h"
#include "i18n/i18n.h"
#include "pipewire/pipewire_spectrum.h"
#include "render/render_context.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/desktop/desktop_widget_layout.h"
#include "time/time_format.h"
#include "ui/controls/box.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/controls/select.h"
#include "ui/dialogs/file_dialog.h"
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
  constexpr float kDefaultDesktopAudioVisualizerAspectRatio = 240.0f / 96.0f;
  constexpr float kDefaultDesktopAudioVisualizerMinValue = 0.02f;
  constexpr float kSelectionStroke = 2.0f;
  constexpr float kShadowExpand = 1.0f;
  const Color kShadowColor = rgba(0.0f, 0.0f, 0.0f, 0.45f);
  constexpr float kRotatePadding = 14.0f;
  constexpr float kHandleSize = 14.0f;
  constexpr float kMinScale = 0.2f;
  constexpr float kMaxScale = 8.0f;
  constexpr float kDisabledWidgetOpacity = 0.25f;
  constexpr float kRotationSnap = static_cast<float>(M_PI) / 12.0f;
  constexpr std::array<const char*, 6> kWidgetTypeLabelKeys{
      "desktop-widgets.editor.types.clock",        "desktop-widgets.editor.types.audio-visualizer",
      "desktop-widgets.editor.types.sticker",      "desktop-widgets.editor.types.weather",
      "desktop-widgets.editor.types.media-player", "desktop-widgets.editor.types.system-monitor"};
  constexpr std::string_view kDesktopWidgetIdPrefix = "desktop-widget-";
  constexpr std::size_t kScaleCornerCount = 4;

  struct CornerSigns {
    float x = 1.0f;
    float y = 1.0f;
  };

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

  CornerSigns cornerSigns(std::size_t cornerIndex) {
    switch (cornerIndex) {
    case 0:
      return {-1.0f, -1.0f};
    case 1:
      return {1.0f, -1.0f};
    case 2:
      return {-1.0f, 1.0f};
    case 3:
    default:
      return {1.0f, 1.0f};
    }
  }

  std::pair<float, float> rotatedCorner(float cx, float cy, float halfWidth, float halfHeight, float rotationRad) {
    const float cosTheta = std::cos(rotationRad);
    const float sinTheta = std::sin(rotationRad);
    return {cx + halfWidth * cosTheta - halfHeight * sinTheta, cy + halfWidth * sinTheta + halfHeight * cosTheta};
  }

} // namespace

void DesktopWidgetsEditor::initialize(WaylandConnection& wayland, ConfigService* config,
                                      PipeWireSpectrum* pipewireSpectrum, const WeatherService* weather,
                                      RenderContext* renderContext, MprisService* mpris, HttpClient* httpClient,
                                      SystemMonitorService* sysmon) {
  m_wayland = &wayland;
  m_config = config;
  m_renderContext = renderContext;
  m_factory = std::make_unique<DesktopWidgetFactory>(pipewireSpectrum, weather, mpris, httpClient, sysmon);
}

void DesktopWidgetsEditor::setExitRequestedCallback(std::function<void()> callback) {
  m_exitRequestedCallback = std::move(callback);
}

void DesktopWidgetsEditor::open(const DesktopWidgetsSnapshot& snapshot) {
  m_snapshot = snapshot;
  m_open = true;
  m_selectedWidgetId.clear();
  m_drag = {};
  m_shiftHeld = false;
  m_leftShiftHeld = false;
  m_rightShiftHeld = false;
  syncSurfaces();
  requestLayout();
}

DesktopWidgetsSnapshot DesktopWidgetsEditor::close() {
  Select::closeAnyOpen();
  m_surfaces.clear();
  m_drag = {};
  m_selectedWidgetId.clear();
  m_shiftHeld = false;
  m_leftShiftHeld = false;
  m_rightShiftHeld = false;
  m_open = false;
  return m_snapshot;
}

bool DesktopWidgetsEditor::isOpen() const noexcept { return m_open; }

float DesktopWidgetsEditor::widgetContentScale(const DesktopWidgetState& state) const {
  const float baseUiScale = m_config != nullptr ? m_config->config().shell.uiScale : 1.0f;
  return desktop_widgets::widgetContentScale(baseUiScale, state);
}

void DesktopWidgetsEditor::syncSurfaces() {
  if (!m_open || m_wayland == nullptr || m_renderContext == nullptr) {
    return;
  }

  const auto& outputs = m_wayland->outputs();
  std::erase_if(m_surfaces, [&outputs](const auto& surface) {
    return std::none_of(outputs.begin(), outputs.end(), [&surface](const auto& output) {
      return output.done && output.output != nullptr && desktop_widgets::outputKey(output) == surface->outputName;
    });
  });

  for (const auto& output : outputs) {
    if (!output.done || output.output == nullptr) {
      continue;
    }
    const std::string key = desktop_widgets::outputKey(output);
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
  overlay->outputName = desktop_widgets::outputKey(output);
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

DesktopWidgetsEditor::OverlaySurface* DesktopWidgetsEditor::findSurface(const std::string& outputName) {
  for (auto& overlay : m_surfaces) {
    if (overlay->outputName == outputName) {
      return overlay.get();
    }
  }
  return nullptr;
}

DesktopWidgetsEditor::OverlaySurface* DesktopWidgetsEditor::findSurfaceForWidget(const std::string& widgetId) {
  for (auto& overlay : m_surfaces) {
    if (overlay->views.contains(widgetId)) {
      return overlay.get();
    }
  }
  return nullptr;
}

DesktopWidgetsEditor::EditorWidgetView* DesktopWidgetsEditor::findView(const std::string& id) {
  for (auto& overlay : m_surfaces) {
    const auto it = overlay->views.find(id);
    if (it != overlay->views.end()) {
      return &it->second;
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
  if (const WaylandOutput* output = desktop_widgets::resolveEffectiveOutput(*m_wayland, state.outputName);
      output != nullptr) {
    return desktop_widgets::outputKey(*output);
  }
  return {};
}

bool DesktopWidgetsEditor::shouldSnap() const {
  return (m_snapshot.grid.visible != m_shiftHeld) && m_snapshot.grid.cellSize > 0;
}

void DesktopWidgetsEditor::prepareFrame(OverlaySurface& surface, bool needsUpdate, bool needsLayout) {
  if (m_renderContext == nullptr) {
    return;
  }

  if (surface.sceneRoot == nullptr || surface.sceneRebuildRequested) {
    rebuildScene(surface);
    surface.sceneRebuildRequested = false;
  }

  if (needsUpdate) {
    for (auto& [id, view] : surface.views) {
      (void)id;
      if (view.widget != nullptr) {
        view.widget->update(*m_renderContext);
      }
    }
  }

  if (needsLayout && surface.sceneRoot != nullptr) {
    surface.sceneRoot->layout(*m_renderContext);
  }
}

void DesktopWidgetsEditor::rebuildScene(OverlaySurface& surface) {
  surface.views.clear();
  surface.selectionFrameTransform = nullptr;
  surface.selectionBorder = nullptr;
  surface.rotationRing = nullptr;
  surface.rotateArea = nullptr;
  surface.scaleHandles.fill(nullptr);
  surface.scaleAreas.fill(nullptr);
  surface.toolbar = nullptr;

  auto root = std::make_unique<InputArea>();
  root->setEnabled(false);
  root->setAnimationManager(&surface.animations);
  root->setFrameSize(static_cast<float>(surface.surface->width()), static_cast<float>(surface.surface->height()));

  auto dim = std::make_unique<Box>();
  dim->setFill(colorSpecFromRole(ColorRole::SurfaceVariant, 0.14f));
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
      line->setFill(colorSpecFromRole(major ? ColorRole::Primary : ColorRole::Outline, major ? 0.18f : 0.08f));
      line->setPosition(x, 0.0f);
      line->setFrameSize(1.0f, height);
      line->setZIndex(2);
      root->addChild(std::move(line));
    }

    for (float y = 0.0f; y <= height; y += cell) {
      auto line = std::make_unique<Box>();
      const bool major = (static_cast<int>(std::lround(y / cell)) % majorInterval) == 0;
      line->setFill(colorSpecFromRole(major ? ColorRole::Primary : ColorRole::Outline, major ? 0.18f : 0.08f));
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

    auto widget = m_factory->create(widgetState.type, widgetState.settings, widgetContentScale(widgetState));
    if (widget == nullptr) {
      continue;
    }

    widget->create();
    widget->setAnimationManager(&surface.animations);
    auto* surfacePtr = &surface;
    widget->setUpdateCallback([surfacePtr]() {
      if (surfacePtr->surface != nullptr) {
        surfacePtr->surface->requestUpdateOnly();
      }
    });
    widget->setLayoutCallback([surfacePtr]() {
      if (surfacePtr->surface != nullptr) {
        surfacePtr->surface->requestUpdate();
      }
    });
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
    view.transformNode->setScale(1.0f);
    view.transformNode->setOpacity(widgetState.enabled ? 1.0f : kDisabledWidgetOpacity);
    view.transformNode->setZIndex(4);
    view.bodyArea->setOnPress([this, id = widgetState.id](const InputArea::PointerData& data) {
      if (data.button != BTN_LEFT) {
        return;
      }
      if (data.pressed) {
        if (m_selectedWidgetId != id) {
          m_selectedWidgetId = id;
          DeferredCall::callLater([this]() { requestLayout(); });
        }
        startDrag(DragMode::Move, id, false);
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
    selectedIt->second.bodyArea->setZIndex(101);

    auto selectionFrameTransform = std::make_unique<Node>();
    selectionFrameTransform->setZIndex(100);
    surface.selectionFrameTransform = selectionFrameTransform.get();

    auto ringShadow = std::make_unique<Box>();
    ringShadow->setBorder(kShadowColor, 1.0f + kShadowExpand * 2.0f);
    ringShadow->setFill(clearColorSpec());
    ringShadow->setRadius(Style::radiusMd + kRotatePadding + kShadowExpand);
    surface.rotationRingShadow = ringShadow.get();
    surface.selectionFrameTransform->addChild(std::move(ringShadow));

    auto ring = std::make_unique<Box>();
    ring->setBorder(colorSpecFromRole(ColorRole::Primary), 1.0f);
    ring->setFill(clearColorSpec());
    ring->setRadius(Style::radiusMd + kRotatePadding);
    ring->setZIndex(1);
    surface.rotationRing = ring.get();
    surface.selectionFrameTransform->addChild(std::move(ring));

    auto rotateArea = std::make_unique<InputArea>();
    rotateArea->setZIndex(1);
    rotateArea->setOnPress([this, id = m_selectedWidgetId](const InputArea::PointerData& data) {
      if (data.button != BTN_LEFT) {
        return;
      }
      if (data.pressed) {
        startDrag(DragMode::Rotate, id, false);
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
    surface.selectionFrameTransform->addChild(std::move(rotateArea));

    root->addChild(std::move(selectionFrameTransform));

    auto selectionBorderTransform = std::make_unique<Node>();
    selectionBorderTransform->setZIndex(102);
    selectionBorderTransform->setHitTestVisible(false);
    surface.selectionBorderTransform = selectionBorderTransform.get();

    auto selectionBorderShadow = std::make_unique<Box>();
    selectionBorderShadow->setBorder(kShadowColor, kSelectionStroke + kShadowExpand * 2.0f);
    selectionBorderShadow->setFill(clearColorSpec());
    selectionBorderShadow->setRadius(Style::radiusMd + kShadowExpand);
    surface.selectionBorderShadow = selectionBorderShadow.get();
    selectionBorderTransform->addChild(std::move(selectionBorderShadow));

    auto selectionBorder = std::make_unique<Box>();
    selectionBorder->setBorder(colorSpecFromRole(ColorRole::Primary), kSelectionStroke);
    selectionBorder->setFill(clearColorSpec());
    selectionBorder->setRadius(Style::radiusMd);
    selectionBorder->setZIndex(1);
    surface.selectionBorder = selectionBorder.get();
    selectionBorderTransform->addChild(std::move(selectionBorder));
    root->addChild(std::move(selectionBorderTransform));

    for (std::size_t i = 0; i < kScaleCornerCount; ++i) {
      const ScaleCorner corner = static_cast<ScaleCorner>(i);

      auto scaleHandleShadow = std::make_unique<Box>();
      scaleHandleShadow->setBorder(kShadowColor, kShadowExpand);
      scaleHandleShadow->setFill(clearColorSpec());
      scaleHandleShadow->setRadius(Style::radiusSm + kShadowExpand);
      scaleHandleShadow->setZIndex(103);
      surface.scaleHandleShadows[i] = scaleHandleShadow.get();
      root->addChild(std::move(scaleHandleShadow));

      auto scaleHandle = std::make_unique<Box>();
      scaleHandle->setFill(colorSpecFromRole(ColorRole::Primary));
      scaleHandle->setRadius(Style::radiusSm);
      scaleHandle->setZIndex(104);
      surface.scaleHandles[i] = scaleHandle.get();
      root->addChild(std::move(scaleHandle));

      auto scaleArea = std::make_unique<InputArea>();
      scaleArea->setZIndex(105);
      scaleArea->setOnPress([this, id = m_selectedWidgetId, corner](const InputArea::PointerData& data) {
        if (data.button != BTN_LEFT) {
          return;
        }
        if (data.pressed) {
          startDrag(DragMode::Scale, id, false, corner);
        } else if (m_drag.mode == DragMode::Scale && m_drag.widgetId == id) {
          finishDrag();
        }
      });
      scaleArea->setOnMotion([this, id = m_selectedWidgetId](const InputArea::PointerData& /*data*/) {
        if (m_drag.mode == DragMode::Scale && m_drag.widgetId == id) {
          updateDrag();
        }
      });
      surface.scaleAreas[i] = scaleArea.get();
      root->addChild(std::move(scaleArea));
    }

    updateSelectionVisuals(surface);
  }

  auto toolbar = std::make_unique<Flex>();
  toolbar->setDirection(FlexDirection::Horizontal);
  toolbar->setAlign(FlexAlign::Center);
  toolbar->setGap(Style::spaceSm);
  toolbar->setPadding(Style::spaceSm, Style::spaceMd);
  toolbar->setFill(colorSpecFromRole(ColorRole::Surface, 0.94f));
  toolbar->setBorder(colorSpecFromRole(ColorRole::Outline), Style::borderWidth);
  toolbar->setRadius(Style::radiusXl);
  toolbar->setZIndex(200);

  auto toolbarHandle = std::make_unique<Flex>();
  toolbarHandle->setDirection(FlexDirection::Horizontal);
  toolbarHandle->setAlign(FlexAlign::Center);
  toolbarHandle->setGap(Style::spaceXs);
  toolbarHandle->setPadding(Style::spaceXs, Style::spaceSm);
  toolbarHandle->setFill(colorSpecFromRole(ColorRole::SurfaceVariant, 0.85f));
  toolbarHandle->setRadius(Style::radiusLg);
  toolbarHandle->setMinHeight(Style::controlHeightSm);

  auto handleGlyph = std::make_unique<Glyph>();
  handleGlyph->setGlyph("menu");
  handleGlyph->setGlyphSize(14.0f);
  toolbarHandle->addChild(std::move(handleGlyph));

  auto title = std::make_unique<Label>();
  title->setText(i18n::tr("desktop-widgets.editor.title"));
  title->setBold(true);
  title->setFontSize(Style::fontSizeBody);
  toolbarHandle->addChild(std::move(title));

  auto toolbarHandleArea = std::make_unique<InputArea>();
  toolbarHandleArea->setParticipatesInLayout(false);
  toolbarHandleArea->setZIndex(1);
  toolbarHandleArea->setCursorShape(WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_MOVE);
  toolbarHandleArea->setOnPress([this, outputName = surface.outputName](const InputArea::PointerData& data) {
    if (data.button != BTN_LEFT) {
      return;
    }
    if (data.pressed) {
      startToolbarDrag(outputName);
    } else if (m_drag.mode == DragMode::ToolbarMove && m_drag.surfaceOutputName == outputName) {
      finishDrag();
    }
  });
  toolbarHandleArea->setOnMotion([this, outputName = surface.outputName](const InputArea::PointerData& /*data*/) {
    if (m_drag.mode == DragMode::ToolbarMove && m_drag.surfaceOutputName == outputName) {
      updateDrag();
    }
  });
  auto* toolbarHandlePtr = toolbarHandle.get();
  auto* toolbarHandleAreaPtr = toolbarHandleArea.get();
  toolbarHandle->addChild(std::move(toolbarHandleArea));
  toolbar->addChild(std::move(toolbarHandle));

  const auto selectedWidgetIt = std::find_if(m_snapshot.widgets.begin(), m_snapshot.widgets.end(),
                                             [this](const auto& widget) { return widget.id == m_selectedWidgetId; });
  const bool hasSelectedWidget = selectedWidgetIt != m_snapshot.widgets.end();
  const bool selectedWidgetEnabled = hasSelectedWidget ? selectedWidgetIt->enabled : false;
  const bool canSendSelectedToBack = hasSelectedWidget && selectedWidgetIt != m_snapshot.widgets.begin();
  const bool canBringSelectedToFront = hasSelectedWidget && std::next(selectedWidgetIt) != m_snapshot.widgets.end();

  auto typeSelect = std::make_unique<Select>();
  typeSelect->setOptions({i18n::tr(kWidgetTypeLabelKeys[0]), i18n::tr(kWidgetTypeLabelKeys[1]),
                          i18n::tr(kWidgetTypeLabelKeys[2]), i18n::tr(kWidgetTypeLabelKeys[3]),
                          i18n::tr(kWidgetTypeLabelKeys[4]), i18n::tr(kWidgetTypeLabelKeys[5])});
  typeSelect->setSelectedIndex(m_addWidgetType == "audio_visualizer" ? 1
                               : m_addWidgetType == "sticker"        ? 2
                               : m_addWidgetType == "weather"        ? 3
                               : m_addWidgetType == "media_player"   ? 4
                               : m_addWidgetType == "sysmon"         ? 5
                                                                     : 0);
  typeSelect->setControlHeight(Style::controlHeightSm);
  typeSelect->setOnSelectionChanged([this](std::size_t index, std::string_view /*text*/) {
    switch (index) {
    case 1:
      m_addWidgetType = "audio_visualizer";
      break;
    case 2:
      m_addWidgetType = "sticker";
      break;
    case 3:
      m_addWidgetType = "weather";
      break;
    case 4:
      m_addWidgetType = "media_player";
      break;
    case 5:
      m_addWidgetType = "sysmon";
      break;
    default:
      m_addWidgetType = "clock";
      break;
    }
  });
  toolbar->addChild(std::move(typeSelect));

  auto addButton = std::make_unique<Button>();
  addButton->setText("+");
  addButton->setVariant(ButtonVariant::Accent);
  addButton->setOnClick([this, outputName = surface.outputName]() {
    deferEditorMutation([this, outputName]() { addWidget(outputName, m_addWidgetType); });
  });
  toolbar->addChild(std::move(addButton));

  auto backButton = std::make_unique<Button>();
  backButton->setText(i18n::tr("desktop-widgets.editor.actions.back"));
  backButton->setVariant(ButtonVariant::Outline);
  backButton->setEnabled(canSendSelectedToBack);
  backButton->setOnClick([this]() { deferEditorMutation([this]() { sendSelectedWidgetToBack(); }); });
  toolbar->addChild(std::move(backButton));

  auto frontButton = std::make_unique<Button>();
  frontButton->setText(i18n::tr("desktop-widgets.editor.actions.front"));
  frontButton->setVariant(ButtonVariant::Outline);
  frontButton->setEnabled(canBringSelectedToFront);
  frontButton->setOnClick([this]() { deferEditorMutation([this]() { bringSelectedWidgetToFront(); }); });
  toolbar->addChild(std::move(frontButton));

  auto enabledButton = std::make_unique<Button>();
  enabledButton->setText(selectedWidgetEnabled ? i18n::tr("desktop-widgets.editor.state.enabled")
                                               : i18n::tr("desktop-widgets.editor.state.disabled"));
  enabledButton->setVariant(ButtonVariant::Outline);
  enabledButton->setSelected(selectedWidgetEnabled);
  enabledButton->setEnabled(hasSelectedWidget);
  enabledButton->setOnClick([this]() { deferEditorMutation([this]() { toggleSelectedWidgetEnabled(); }); });
  toolbar->addChild(std::move(enabledButton));

  auto deleteButton = std::make_unique<Button>();
  deleteButton->setText(i18n::tr("desktop-widgets.editor.actions.delete"));
  deleteButton->setVariant(ButtonVariant::Destructive);
  deleteButton->setEnabled(hasSelectedWidget);
  deleteButton->setOnClick([this]() { deferEditorMutation([this]() { removeSelectedWidget(); }); });
  toolbar->addChild(std::move(deleteButton));

  auto gridButton = std::make_unique<Button>();
  gridButton->setText(m_snapshot.grid.visible ? i18n::tr("desktop-widgets.editor.state.grid-on")
                                              : i18n::tr("desktop-widgets.editor.state.grid-off"));
  gridButton->setVariant(ButtonVariant::Outline);
  gridButton->setSelected(m_snapshot.grid.visible);
  gridButton->setOnClick([this]() {
    deferEditorMutation([this]() {
      m_snapshot.grid.visible = !m_snapshot.grid.visible;
      requestLayout();
    });
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
    deferEditorMutation([this, value = std::string(text)]() {
      try {
        m_snapshot.grid.cellSize = std::stoi(value);
        requestLayout();
      } catch (...) {
      }
    });
  });
  toolbar->addChild(std::move(gridSizeSelect));

  auto doneButton = std::make_unique<Button>();
  doneButton->setText(i18n::tr("desktop-widgets.editor.actions.done"));
  doneButton->setVariant(ButtonVariant::Secondary);
  doneButton->setOnClick([this]() { requestExit(); });
  toolbar->addChild(std::move(doneButton));

  auto* toolbarPtr = toolbar.get();
  surface.toolbar = toolbarPtr;
  root->addChild(std::move(toolbar));
  toolbarPtr->layout(*m_renderContext);
  toolbarHandleAreaPtr->setPosition(0.0f, 0.0f);
  toolbarHandleAreaPtr->setFrameSize(toolbarHandlePtr->width(), toolbarHandlePtr->height());

  if (!surface.toolbarPositionInitialized) {
    surface.toolbarX = std::round((root->width() - toolbarPtr->width()) * 0.5f);
    surface.toolbarY = kToolbarY;
    surface.toolbarPositionInitialized = true;
  }
  clampToolbarPosition(surface, toolbarPtr->width(), toolbarPtr->height());
  toolbarPtr->setPosition(surface.toolbarX, surface.toolbarY);

  surface.sceneRoot = std::move(root);
  surface.surface->setSceneRoot(surface.sceneRoot.get());
  surface.inputDispatcher.setSceneRoot(surface.sceneRoot.get());
}

void DesktopWidgetsEditor::updateSelectionVisuals(OverlaySurface& surface) {
  const auto selectedIt = surface.views.find(m_selectedWidgetId);
  const DesktopWidgetState* state = findWidgetState(m_selectedWidgetId);
  if (selectedIt == surface.views.end() || state == nullptr || surface.selectionFrameTransform == nullptr ||
      surface.selectionBorderTransform == nullptr || surface.selectionBorder == nullptr ||
      surface.rotationRing == nullptr || surface.rotateArea == nullptr) {
    return;
  }
  for (std::size_t i = 0; i < kScaleCornerCount; ++i) {
    if (surface.scaleHandles[i] == nullptr || surface.scaleAreas[i] == nullptr) {
      return;
    }
  }

  const float width = selectedIt->second.intrinsicWidth;
  const float height = selectedIt->second.intrinsicHeight;
  const float left = state->cx - width * 0.5f;
  const float top = state->cy - height * 0.5f;

  surface.selectionFrameTransform->setFrameSize(width, height);
  surface.selectionFrameTransform->setPosition(left, top);
  surface.selectionFrameTransform->setRotation(state->rotationRad);

  surface.selectionBorderTransform->setFrameSize(width, height);
  surface.selectionBorderTransform->setPosition(left, top);
  surface.selectionBorderTransform->setRotation(state->rotationRad);

  const float ringPadExp = kRotatePadding + kShadowExpand;
  if (surface.rotationRingShadow != nullptr) {
    surface.rotationRingShadow->setPosition(-ringPadExp, -ringPadExp);
    surface.rotationRingShadow->setFrameSize(width + ringPadExp * 2.0f, height + ringPadExp * 2.0f);
  }

  surface.rotationRing->setPosition(-kRotatePadding, -kRotatePadding);
  surface.rotationRing->setFrameSize(width + kRotatePadding * 2.0f, height + kRotatePadding * 2.0f);

  surface.rotateArea->setPosition(-kRotatePadding, -kRotatePadding);
  surface.rotateArea->setFrameSize(width + kRotatePadding * 2.0f, height + kRotatePadding * 2.0f);

  if (surface.selectionBorderShadow != nullptr) {
    surface.selectionBorderShadow->setPosition(-kShadowExpand, -kShadowExpand);
    surface.selectionBorderShadow->setFrameSize(width + kShadowExpand * 2.0f, height + kShadowExpand * 2.0f);
  }

  surface.selectionBorder->setPosition(0.0f, 0.0f);
  surface.selectionBorder->setFrameSize(width, height);

  for (std::size_t i = 0; i < kScaleCornerCount; ++i) {
    const CornerSigns signs = cornerSigns(i);
    const auto [cornerX, cornerY] =
        rotatedCorner(state->cx, state->cy, width * 0.5f * signs.x, height * 0.5f * signs.y, state->rotationRad);

    const float shadowSize = kHandleSize + kShadowExpand * 2.0f;
    if (surface.scaleHandleShadows[i] != nullptr) {
      surface.scaleHandleShadows[i]->setPosition(cornerX - shadowSize * 0.5f, cornerY - shadowSize * 0.5f);
      surface.scaleHandleShadows[i]->setFrameSize(shadowSize, shadowSize);
    }

    surface.scaleHandles[i]->setPosition(cornerX - kHandleSize * 0.5f, cornerY - kHandleSize * 0.5f);
    surface.scaleHandles[i]->setFrameSize(kHandleSize, kHandleSize);

    surface.scaleAreas[i]->setPosition(cornerX - kHandleSize, cornerY - kHandleSize);
    surface.scaleAreas[i]->setFrameSize(kHandleSize * 1.5f, kHandleSize * 1.5f);
  }
}

void DesktopWidgetsEditor::applyViewState(EditorWidgetView& view, const DesktopWidgetState& state,
                                          bool refreshContent) {
  if (view.widget == nullptr || view.transformNode == nullptr || m_renderContext == nullptr) {
    return;
  }

  if (refreshContent) {
    view.widget->setContentScale(widgetContentScale(state));
    view.widget->update(*m_renderContext);
    view.widget->layout(*m_renderContext);
    view.intrinsicWidth = std::max(1.0f, view.widget->intrinsicWidth());
    view.intrinsicHeight = std::max(1.0f, view.widget->intrinsicHeight());
  }

  view.transformNode->setFrameSize(view.intrinsicWidth, view.intrinsicHeight);
  view.transformNode->setPosition(state.cx - view.intrinsicWidth * 0.5f, state.cy - view.intrinsicHeight * 0.5f);
  view.transformNode->setRotation(state.rotationRad);
  view.transformNode->setScale(1.0f);
  view.transformNode->setOpacity(state.enabled ? 1.0f : kDisabledWidgetOpacity);
}

void DesktopWidgetsEditor::updateViewTransforms(const std::string* relayoutWidgetId) {
  for (auto& surface : m_surfaces) {
    for (auto& [id, view] : surface->views) {
      const DesktopWidgetState* state = findWidgetState(id);
      if (state == nullptr) {
        continue;
      }
      applyViewState(view, *state, relayoutWidgetId != nullptr && *relayoutWidgetId == id);
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
  if (const WaylandOutput* output = desktop_widgets::resolveEffectiveOutput(*m_wayland, outputName);
      output != nullptr) {
    const int logicalWidth =
        output->logicalWidth > 0 ? output->logicalWidth : output->width / std::max(1, output->scale);
    const int logicalHeight =
        output->logicalHeight > 0 ? output->logicalHeight : output->height / std::max(1, output->scale);
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
    widget.settings.emplace("aspect_ratio", static_cast<double>(kDefaultDesktopAudioVisualizerAspectRatio));
    widget.settings.emplace("bands", static_cast<std::int64_t>(32));
    widget.settings.emplace("min_value", static_cast<double>(kDefaultDesktopAudioVisualizerMinValue));
  }

  if (widget.type == "sticker") {
    widget.settings.emplace("opacity", static_cast<double>(1.0));
    auto widgetId = widget.id;
    m_snapshot.widgets.push_back(std::move(widget));

    FileDialogOptions options;
    options.mode = FileDialogMode::Open;
    options.title = i18n::tr("desktop-widgets.editor.dialogs.select-sticker-image");
    options.extensions = {".png", ".jpg", ".jpeg", ".webp", ".svg", ".gif"};
    if (!FileDialog::open(std::move(options), [this, widgetId](std::optional<std::filesystem::path> result) {
          deferEditorMutation([this, widgetId, result = std::move(result)]() {
            auto* state = findWidgetState(widgetId);
            if (state == nullptr) {
              return;
            }
            if (result) {
              state->settings["image_path"] = result->string();
            } else {
              std::erase_if(m_snapshot.widgets, [&](const auto& w) { return w.id == widgetId; });
              if (m_selectedWidgetId == widgetId) {
                m_selectedWidgetId.clear();
              }
            }
            requestLayout();
          });
        })) {
      std::erase_if(m_snapshot.widgets, [&](const auto& w) { return w.id == widgetId; });
      requestLayout();
      return;
    }

    m_selectedWidgetId = m_snapshot.widgets.back().id;
    requestLayout();
    return;
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

void DesktopWidgetsEditor::toggleSelectedWidgetEnabled() {
  if (m_selectedWidgetId.empty()) {
    return;
  }
  DesktopWidgetState* state = findWidgetState(m_selectedWidgetId);
  if (state == nullptr) {
    return;
  }
  state->enabled = !state->enabled;
  requestLayout();
}

void DesktopWidgetsEditor::sendSelectedWidgetToBack() {
  if (m_selectedWidgetId.empty()) {
    return;
  }

  auto it = std::find_if(m_snapshot.widgets.begin(), m_snapshot.widgets.end(),
                         [this](const auto& widget) { return widget.id == m_selectedWidgetId; });
  if (it == m_snapshot.widgets.end() || it == m_snapshot.widgets.begin()) {
    return;
  }

  std::rotate(m_snapshot.widgets.begin(), it, std::next(it));
  requestLayout();
}

void DesktopWidgetsEditor::bringSelectedWidgetToFront() {
  if (m_selectedWidgetId.empty()) {
    return;
  }

  auto it = std::find_if(m_snapshot.widgets.begin(), m_snapshot.widgets.end(),
                         [this](const auto& widget) { return widget.id == m_selectedWidgetId; });
  if (it == m_snapshot.widgets.end() || std::next(it) == m_snapshot.widgets.end()) {
    return;
  }

  std::rotate(it, std::next(it), m_snapshot.widgets.end());
  requestLayout();
}

void DesktopWidgetsEditor::startToolbarDrag(const std::string& outputName) {
  OverlaySurface* surface = findSurface(outputName);
  if (surface == nullptr || surface->toolbar == nullptr) {
    return;
  }

  m_drag = {};
  m_drag.mode = DragMode::ToolbarMove;
  m_drag.startSceneX = m_currentEventSceneX;
  m_drag.startSceneY = m_currentEventSceneY;
  m_drag.surfaceOutputName = outputName;
  m_drag.initialToolbarX = surface->toolbarX;
  m_drag.initialToolbarY = surface->toolbarY;
}

void DesktopWidgetsEditor::clampToolbarPosition(OverlaySurface& surface, float toolbarWidth, float toolbarHeight) {
  if (surface.surface == nullptr) {
    return;
  }

  const float maxX = std::max(0.0f, static_cast<float>(surface.surface->width()) - toolbarWidth);
  const float maxY = std::max(0.0f, static_cast<float>(surface.surface->height()) - toolbarHeight);
  surface.toolbarX = std::clamp(surface.toolbarX, 0.0f, maxX);
  surface.toolbarY = std::clamp(surface.toolbarY, 0.0f, maxY);
}

void DesktopWidgetsEditor::deferEditorMutation(std::function<void()> action) {
  DeferredCall::callLater([this, action = std::move(action)]() mutable {
    if (m_open) {
      action();
    }
  });
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

void DesktopWidgetsEditor::startDrag(DragMode mode, const std::string& widgetId, bool rebuildOnFinish,
                                     ScaleCorner scaleCorner) {
  DesktopWidgetState* state = findWidgetState(widgetId);
  if (state == nullptr) {
    return;
  }

  EditorWidgetView* view = findView(widgetId);
  if (view == nullptr) {
    return;
  }

  m_drag.mode = mode;
  m_drag.widgetId = widgetId;
  m_drag.startSceneX = m_currentEventSceneX;
  m_drag.startSceneY = m_currentEventSceneY;
  m_drag.initialState = *state;
  m_drag.intrinsicWidth = view->intrinsicWidth;
  m_drag.intrinsicHeight = view->intrinsicHeight;
  m_drag.scaleCorner = scaleCorner;
  m_drag.rebuildOnFinish = rebuildOnFinish;

  if (mode == DragMode::Scale && view->widget != nullptr && m_renderContext != nullptr) {
    DesktopWidgetState maxState = *state;
    maxState.scale = kMaxScale;
    view->widget->setContentScale(widgetContentScale(maxState));
    view->widget->update(*m_renderContext);
    view->widget->layout(*m_renderContext);
    m_drag.sourceIntrinsicWidth = std::max(1.0f, view->widget->intrinsicWidth());
    m_drag.sourceIntrinsicHeight = std::max(1.0f, view->widget->intrinsicHeight());
    m_drag.sourceScale = kMaxScale;

    const float visualScale = state->scale / kMaxScale;
    view->transformNode->setScale(visualScale);
    view->transformNode->setFrameSize(m_drag.sourceIntrinsicWidth, m_drag.sourceIntrinsicHeight);
    view->transformNode->setPosition(state->cx - m_drag.sourceIntrinsicWidth * 0.5f,
                                     state->cy - m_drag.sourceIntrinsicHeight * 0.5f);
    view->intrinsicWidth = m_drag.sourceIntrinsicWidth * visualScale;
    view->intrinsicHeight = m_drag.sourceIntrinsicHeight * visualScale;
  }
}

void DesktopWidgetsEditor::updateDrag() {
  if (m_drag.mode == DragMode::None) {
    return;
  }

  if (m_drag.mode == DragMode::ToolbarMove) {
    OverlaySurface* surface = findSurface(m_drag.surfaceOutputName);
    if (surface == nullptr || surface->toolbar == nullptr) {
      return;
    }

    surface->toolbarX = m_drag.initialToolbarX + (m_currentEventSceneX - m_drag.startSceneX);
    surface->toolbarY = m_drag.initialToolbarY + (m_currentEventSceneY - m_drag.startSceneY);
    clampToolbarPosition(*surface, surface->toolbar->width(), surface->toolbar->height());
    surface->toolbar->setPosition(surface->toolbarX, surface->toolbarY);
    surface->surface->requestRedraw();
    return;
  }

  DesktopWidgetState* state = findWidgetState(m_drag.widgetId);
  if (state == nullptr) {
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
    const float startAngle =
        std::atan2(m_drag.startSceneY - m_drag.initialState.cy, m_drag.startSceneX - m_drag.initialState.cx);
    const float currentAngle =
        std::atan2(m_currentEventSceneY - m_drag.initialState.cy, m_currentEventSceneX - m_drag.initialState.cx);
    float rotation = normalizeAngle(m_drag.initialState.rotationRad + (currentAngle - startAngle));
    if (shouldSnap()) {
      rotation = std::round(rotation / kRotationSnap) * kRotationSnap;
    }
    state->rotationRad = rotation;
  } else if (m_drag.mode == DragMode::Scale) {
    const CornerSigns signs = cornerSigns(static_cast<std::size_t>(m_drag.scaleCorner));
    const float cornerX =
        shouldSnap() ? snapToGrid(m_currentEventSceneX, m_snapshot.grid.cellSize) : m_currentEventSceneX;
    const float cornerY =
        shouldSnap() ? snapToGrid(m_currentEventSceneY, m_snapshot.grid.cellSize) : m_currentEventSceneY;
    const float dx = cornerX - m_drag.initialState.cx;
    const float dy = cornerY - m_drag.initialState.cy;
    const float cosTheta = std::cos(-m_drag.initialState.rotationRad);
    const float sinTheta = std::sin(-m_drag.initialState.rotationRad);
    const float localX = (dx * cosTheta - dy * sinTheta) * signs.x;
    const float localY = (dx * sinTheta + dy * cosTheta) * signs.y;
    const float halfWidth = std::max(1.0f, m_drag.intrinsicWidth * 0.5f);
    const float halfHeight = std::max(1.0f, m_drag.intrinsicHeight * 0.5f);
    const float denominator = halfWidth * halfWidth + halfHeight * halfHeight;
    const float relativeScale = (localX * halfWidth + localY * halfHeight) / std::max(1.0f, denominator);
    state->scale = std::clamp(m_drag.initialState.scale * relativeScale, kMinScale, kMaxScale);
  }

  float clampWidth = m_drag.intrinsicWidth;
  float clampHeight = m_drag.intrinsicHeight;
  const std::string* relayoutWidgetId = nullptr;
  float dragVisualScale = 1.0f;
  if (m_drag.mode == DragMode::Scale && m_drag.sourceScale > 0.0f) {
    dragVisualScale = state->scale / m_drag.sourceScale;
    clampWidth = m_drag.sourceIntrinsicWidth * dragVisualScale;
    clampHeight = m_drag.sourceIntrinsicHeight * dragVisualScale;
    if (EditorWidgetView* view = findView(m_drag.widgetId); view != nullptr) {
      view->intrinsicWidth = clampWidth;
      view->intrinsicHeight = clampHeight;
    }
  }

  if (m_wayland != nullptr) {
    desktop_widgets::clampStateToOutput(*m_wayland, *state, clampWidth, clampHeight);
  }

  updateViewTransforms(relayoutWidgetId);

  if (m_drag.mode == DragMode::Scale && m_drag.sourceScale > 0.0f) {
    if (EditorWidgetView* view = findView(m_drag.widgetId); view != nullptr) {
      view->transformNode->setScale(dragVisualScale);
      view->transformNode->setFrameSize(m_drag.sourceIntrinsicWidth, m_drag.sourceIntrinsicHeight);
      view->transformNode->setPosition(state->cx - m_drag.sourceIntrinsicWidth * 0.5f,
                                       state->cy - m_drag.sourceIntrinsicHeight * 0.5f);
    }
  }

  if (OverlaySurface* dragSurface = findSurfaceForWidget(m_drag.widgetId);
      dragSurface != nullptr && dragSurface->surface != nullptr) {
    dragSurface->surface->requestRedraw();
  }
}

void DesktopWidgetsEditor::finishDrag() {
  const bool rebuild = m_drag.rebuildOnFinish || m_drag.mode == DragMode::Scale;
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

  if (!event.preedit) {
    const bool shiftFromMask = (event.modifiers & KeyMod::Shift) != 0;
    if (event.sym == XKB_KEY_Shift_L) {
      m_leftShiftHeld = event.pressed;
    } else if (event.sym == XKB_KEY_Shift_R) {
      m_rightShiftHeld = event.pressed;
    }

    // wl_keyboard.modifiers is delivered separately from key up/down, so the
    // modifier bit on a Shift key event can lag by one transition. Track the
    // physical Shift keys directly and only fall back to the mask when we have
    // no concrete Shift key state yet.
    m_shiftHeld = m_leftShiftHeld || m_rightShiftHeld;
    if (!m_shiftHeld && event.sym != XKB_KEY_Shift_L && event.sym != XKB_KEY_Shift_R) {
      m_shiftHeld = shiftFromMask;
    }
  }

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
  if (!m_open || m_drag.mode != DragMode::None) {
    return;
  }

  const bool minuteBoundary = formatLocalTime("{:%S}") == "00";
  const bool needsSeconds = std::any_of(m_snapshot.widgets.begin(), m_snapshot.widgets.end(),
                                        [](const auto& widget) { return formatShowsSeconds(widget); });
  if (minuteBoundary || needsSeconds) {
    requestLayout();
  }

  for (auto& surface : m_surfaces) {
    if (surface->surface == nullptr) {
      continue;
    }
    const bool hasSecondTickWidget = std::any_of(surface->views.begin(), surface->views.end(), [](const auto& entry) {
      return entry.second.widget != nullptr && entry.second.widget->wantsSecondTicks();
    });
    if (hasSecondTickWidget) {
      surface->surface->requestUpdate();
    }
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
