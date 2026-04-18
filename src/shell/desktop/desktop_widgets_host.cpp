#include "shell/desktop/desktop_widgets_host.h"

#include "config/config_service.h"
#include "core/log.h"
#include "pipewire/pipewire_spectrum.h"
#include "render/render_context.h"
#include "render/scene/node.h"
#include "shell/desktop/widget_transform.h"
#include "time/time_service.h"
#include "wayland/layer_surface.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cmath>
#include <string>

namespace {

constexpr Logger kLog("desktop");

std::string outputKey(const WaylandOutput& output) {
  if (!output.connectorName.empty()) {
    return output.connectorName;
  }
  return std::to_string(output.name);
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

DesktopWidgetState* findStateById(DesktopWidgetsSnapshot& snapshot, const std::string& id) {
  for (auto& widget : snapshot.widgets) {
    if (widget.id == id) {
      return &widget;
    }
  }
  return nullptr;
}

} // namespace

void DesktopWidgetsHost::initialize(WaylandConnection& wayland, ConfigService* config, TimeService* timeService,
                                    PipeWireSpectrum* pipewireSpectrum, RenderContext* renderContext) {
  m_wayland = &wayland;
  m_config = config;
  m_timeService = timeService;
  m_renderContext = renderContext;
  m_factory = std::make_unique<DesktopWidgetFactory>(timeService, pipewireSpectrum);
}

void DesktopWidgetsHost::show(const DesktopWidgetsSnapshot& snapshot) {
  m_snapshot = snapshot;
  m_visible = true;
  syncInstances();
}

void DesktopWidgetsHost::hide() {
  m_visible = false;
  m_instances.clear();
}

void DesktopWidgetsHost::rebuild(const DesktopWidgetsSnapshot& snapshot) {
  m_snapshot = snapshot;
  if (!m_visible) {
    return;
  }
  syncInstances();
}

void DesktopWidgetsHost::onOutputChange() {
  if (!m_visible) {
    return;
  }
  syncInstances();
}

void DesktopWidgetsHost::onSecondTick() {
  if (!m_visible || m_timeService == nullptr) {
    return;
  }

  const bool minuteBoundary = m_timeService->format("{:%S}") == "00";
  for (auto& instance : m_instances) {
    if (instance->surface == nullptr || instance->widget == nullptr) {
      continue;
    }
    if (instance->widget->wantsSecondTicks() || minuteBoundary) {
      instance->surface->requestUpdate();
    }
  }
}

void DesktopWidgetsHost::requestLayout() {
  for (auto& instance : m_instances) {
    if (instance->surface != nullptr) {
      instance->surface->requestLayout();
    }
  }
}

void DesktopWidgetsHost::requestRedraw() {
  for (auto& instance : m_instances) {
    if (instance->surface != nullptr) {
      instance->surface->requestRedraw();
    }
  }
}

DesktopWidgetsHost::DesktopWidgetInstance* DesktopWidgetsHost::findInstance(const std::string& id) {
  for (auto& instance : m_instances) {
    if (instance->state.id == id) {
      return instance.get();
    }
  }
  return nullptr;
}

void DesktopWidgetsHost::syncInstances() {
  if (!m_visible || m_wayland == nullptr || m_renderContext == nullptr || m_factory == nullptr) {
    return;
  }

  std::erase_if(m_instances, [this](const auto& instance) {
    return findStateById(m_snapshot, instance->state.id) == nullptr;
  });

  for (const auto& state : m_snapshot.widgets) {
    const WaylandOutput* output = resolveEffectiveOutput(*m_wayland, state.outputName);
    if (output == nullptr) {
      continue;
    }

    DesktopWidgetInstance* existing = findInstance(state.id);
    if (existing == nullptr) {
      createInstance(state, *output);
      continue;
    }

    const std::string effectiveOutputName = outputKey(*output);
    const bool widgetDefinitionChanged =
        existing->state.type != state.type || existing->state.settings != state.settings ||
        existing->effectiveOutputName != effectiveOutputName;

    if (widgetDefinitionChanged) {
      std::erase_if(m_instances, [&state](const auto& instance) { return instance->state.id == state.id; });
      createInstance(state, *output);
      continue;
    }

    if (!(existing->state == state)) {
      existing->state = state;
      if (existing->surface != nullptr) {
        existing->surface->requestLayout();
      }
    }
  }
}

void DesktopWidgetsHost::createInstance(const DesktopWidgetState& state, const WaylandOutput& output) {
  if (m_factory == nullptr || m_renderContext == nullptr) {
    return;
  }

  auto widget = m_factory->create(state.type, state.settings,
                                  m_config != nullptr ? m_config->config().shell.uiScale : 1.0f);
  if (widget == nullptr) {
    return;
  }

  widget->create();
  widget->update(*m_renderContext);
  widget->layout(*m_renderContext);

  const float intrinsicWidth = std::max(1.0f, widget->intrinsicWidth());
  const float intrinsicHeight = std::max(1.0f, widget->intrinsicHeight());
  const WidgetTransformSurfaceGeometry geometry =
      computeWidgetSurfaceGeometry(state.cx, state.cy, intrinsicWidth, intrinsicHeight, state.scale, state.rotationRad);

  auto surfaceConfig = LayerSurfaceConfig{
      .nameSpace = "noctalia-desktop-widget",
      .layer = LayerShellLayer::Bottom,
      .anchor = LayerShellAnchor::Top | LayerShellAnchor::Left,
      .width = geometry.surfaceWidth,
      .height = geometry.surfaceHeight,
      .exclusiveZone = 0,
      .marginTop = geometry.marginTop,
      .marginLeft = geometry.marginLeft,
      .keyboard = LayerShellKeyboard::None,
      .defaultWidth = geometry.surfaceWidth,
      .defaultHeight = geometry.surfaceHeight,
  };

  auto instance = std::make_unique<DesktopWidgetInstance>();
  instance->state = state;
  instance->effectiveOutputName = outputKey(output);
  instance->output = output.output;
  instance->widget = std::move(widget);
  instance->intrinsicWidth = intrinsicWidth;
  instance->intrinsicHeight = intrinsicHeight;

  instance->surface = std::make_unique<LayerSurface>(*m_wayland, std::move(surfaceConfig));
  instance->surface->setRenderContext(m_renderContext);
  instance->surface->setAnimationManager(&instance->animations);

  auto* rawInstance = instance.get();
  instance->widget->setAnimationManager(&instance->animations);
  instance->widget->setRedrawCallback([rawInstance]() {
    if (rawInstance->surface != nullptr) {
      rawInstance->surface->requestRedraw();
    }
  });

  instance->surface->setConfigureCallback(
      [rawInstance](std::uint32_t /*width*/, std::uint32_t /*height*/) { rawInstance->surface->requestLayout(); });
  instance->surface->setPrepareFrameCallback(
      [this, rawInstance](bool needsUpdate, bool needsLayout) { prepareFrame(*rawInstance, needsUpdate, needsLayout); });
  instance->surface->setFrameTickCallback([this, rawInstance](float deltaMs) {
    if (rawInstance->widget == nullptr || m_renderContext == nullptr) {
      return;
    }
    rawInstance->widget->onFrameTick(deltaMs, *m_renderContext);
  });

  if (!instance->surface->initialize(output.output)) {
    kLog.warn("desktop widgets host: failed to initialize widget {} on {}", state.id, instance->effectiveOutputName);
    return;
  }

  instance->surface->setClickThrough(true);
  m_instances.push_back(std::move(instance));
}

void DesktopWidgetsHost::buildScene(DesktopWidgetInstance& instance) {
  if (instance.sceneRoot == nullptr) {
    instance.sceneRoot = std::make_unique<Node>();
    instance.sceneRoot->setAnimationManager(&instance.animations);

    auto transformNode = std::make_unique<Node>();
    instance.transformNode = instance.sceneRoot->addChild(std::move(transformNode));
    if (instance.widget != nullptr) {
      instance.transformNode->addChild(instance.widget->releaseRoot());
    }

    if (instance.surface != nullptr) {
      instance.surface->setSceneRoot(instance.sceneRoot.get());
    }
  }
}

void DesktopWidgetsHost::prepareFrame(DesktopWidgetInstance& instance, bool needsUpdate, bool needsLayout) {
  if (instance.widget == nullptr || instance.surface == nullptr || m_renderContext == nullptr) {
    return;
  }

  buildScene(instance);

  if (needsUpdate) {
    instance.widget->update(*m_renderContext);
  }
  if (needsLayout) {
    instance.widget->layout(*m_renderContext);
    instance.intrinsicWidth = std::max(1.0f, instance.widget->intrinsicWidth());
    instance.intrinsicHeight = std::max(1.0f, instance.widget->intrinsicHeight());
  }

  if (m_wayland != nullptr) {
    if (const WaylandOutput* output = resolveEffectiveOutput(*m_wayland, instance.state.outputName); output != nullptr) {
      const WidgetTransformClampResult clamped = clampWidgetCenterToOutput(
          instance.state.cx, instance.state.cy, instance.intrinsicWidth, instance.intrinsicHeight, instance.state.scale,
          instance.state.rotationRad, outputLogicalWidth(*output), outputLogicalHeight(*output),
          kDesktopWidgetMinVisibleFraction);
      instance.state.cx = clamped.cx;
      instance.state.cy = clamped.cy;
    }
  }

  const WidgetTransformSurfaceGeometry geometry = computeWidgetSurfaceGeometry(
      instance.state.cx, instance.state.cy, instance.intrinsicWidth, instance.intrinsicHeight, instance.state.scale,
      instance.state.rotationRad);

  if (instance.surface->width() != geometry.surfaceWidth || instance.surface->height() != geometry.surfaceHeight) {
    instance.surface->requestSize(geometry.surfaceWidth, geometry.surfaceHeight);
  }
  instance.surface->setMargins(geometry.marginTop, 0, 0, geometry.marginLeft);

  if (instance.sceneRoot != nullptr) {
    instance.sceneRoot->setFrameSize(static_cast<float>(instance.surface->width()),
                                     static_cast<float>(instance.surface->height()));
  }
  if (instance.transformNode != nullptr) {
    instance.transformNode->setFrameSize(instance.intrinsicWidth, instance.intrinsicHeight);
    instance.transformNode->setPosition((static_cast<float>(instance.surface->width()) - instance.intrinsicWidth) * 0.5f,
                                        (static_cast<float>(instance.surface->height()) - instance.intrinsicHeight) *
                                            0.5f);
    instance.transformNode->setRotation(instance.state.rotationRad);
    instance.transformNode->setScale(instance.state.scale);
  }
}
