#include "shell/bar/bar.h"

#include "config/config_service.h"
#include "core/log.h"
#include "dbus/tray/tray_service.h"
#include "render/render_context.h"
#include "render/scene/rect_node.h"
#include "ui/controls/box.h"
#include "shell/widget/widget.h"
#include "time/time_service.h"
#include "ui/controls/flex.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"

#include <algorithm>

#include <wayland-client-core.h>

namespace {

std::uint32_t positionToAnchor(const std::string& position) {
  if (position == "bottom") {
    return LayerShellAnchor::Bottom | LayerShellAnchor::Left | LayerShellAnchor::Right;
  }
  if (position == "left") {
    return LayerShellAnchor::Top | LayerShellAnchor::Bottom | LayerShellAnchor::Left;
  }
  if (position == "right") {
    return LayerShellAnchor::Top | LayerShellAnchor::Bottom | LayerShellAnchor::Right;
  }
  // Default: top
  return LayerShellAnchor::Top | LayerShellAnchor::Left | LayerShellAnchor::Right;
}

} // namespace

Bar::Bar() = default;

bool Bar::initialize(WaylandConnection& wayland, ConfigService* config, TimeService* timeService,
                     NotificationManager* notifications, TrayService* tray, PipeWireService* audio,
                     RenderContext* renderContext) {
  m_wayland = &wayland;
  m_config = config;
  m_time = timeService;
  m_notifications = notifications;
  m_tray = tray;
  m_audio = audio;
  m_renderContext = renderContext;

  m_widgetFactory =
      std::make_unique<WidgetFactory>(*m_wayland, m_time, m_config->config(), m_notifications, m_tray, m_audio);

  if (timeService != nullptr) {
    timeService->setTickSecondCallback([this]() {
      for (auto& inst : m_instances) {
        if (inst->surface == nullptr || m_renderContext == nullptr) {
          continue;
        }
        m_renderContext->makeCurrent(inst->surface->renderTarget());
        updateWidgets(*inst);
        if (inst->sceneRoot != nullptr && inst->sceneRoot->dirty()) {
          inst->surface->requestRedraw();
        }
      }
    });
  }

  m_config->setReloadCallback([this]() { reload(); });

  syncInstances();
  return true;
}

void Bar::reload() {
  logInfo("bar: reloading config");
  m_widgetFactory =
      std::make_unique<WidgetFactory>(*m_wayland, m_time, m_config->config(), m_notifications, m_tray, m_audio);
  m_instances.clear();
  m_surfaceMap.clear();
  m_hoveredInstance = nullptr;
  syncInstances();
}

void Bar::closeAllInstances() {
  m_surfaceMap.clear();
  m_hoveredInstance = nullptr;
  m_instances.clear();
}

void Bar::onOutputChange() { syncInstances(); }

void Bar::onWorkspaceChange() {
  for (auto& inst : m_instances) {
    if (inst->surface == nullptr || m_renderContext == nullptr) {
      continue;
    }
    m_renderContext->makeCurrent(inst->surface->renderTarget());
    updateWidgets(*inst);
    if (inst->sceneRoot != nullptr && (inst->sceneRoot->dirty() || inst->animations.hasActive())) {
      inst->surface->requestRedraw();
    } else {
      inst->surface->renderNow();
    }
  }
}

bool Bar::isRunning() const noexcept {
  return std::any_of(m_instances.begin(), m_instances.end(),
                     [](const auto& inst) { return inst->surface && inst->surface->isRunning(); });
}

void Bar::syncInstances() {
  const auto& outputs = m_wayland->outputs();
  const auto& bars = m_config->config().bars;

  // Remove instances for outputs that no longer exist
  std::erase_if(m_instances, [&outputs](const auto& inst) {
    bool found =
        std::any_of(outputs.begin(), outputs.end(), [&inst](const auto& out) { return out.name == inst->outputName; });
    if (!found) {
      logInfo("bar: removing instance for output {}", inst->outputName);
    }
    return !found;
  });

  // Create instances for each bar definition × each output
  for (std::size_t barIdx = 0; barIdx < bars.size(); ++barIdx) {
    for (const auto& output : outputs) {
      bool exists = std::any_of(m_instances.begin(), m_instances.end(), [&output, barIdx](const auto& inst) {
        return inst->outputName == output.name && inst->barIndex == barIdx;
      });
      if (!exists) {
        auto resolved = ConfigService::resolveForOutput(bars[barIdx], output);
        if (!resolved.enabled) {
          continue;
        }
        createInstance(output, resolved);
        m_instances.back()->barIndex = barIdx;
      }
    }
  }
}

void Bar::createInstance(const WaylandOutput& output, const BarConfig& barConfig) {
  logInfo("bar: creating \"{}\" on {} ({}), height={} position={}", barConfig.name, output.connectorName,
          output.description, barConfig.height, barConfig.position);

  auto instance = std::make_unique<BarInstance>();
  instance->outputName = output.name;
  instance->output = output.output;
  instance->scale = output.scale;
  instance->barConfig = barConfig;

  const auto anchor = positionToAnchor(barConfig.position);
  const bool vertical = (barConfig.position == "left" || barConfig.position == "right");

  // Compositor margins create the floating-bar gap at the protocol level.
  // The exclusive zone includes the margin so other windows are pushed far enough.
  const std::int32_t mH = barConfig.marginH;
  const std::int32_t mV = barConfig.marginV;
  const std::int32_t totalExclusive = barConfig.height + mV;
  const auto uHeight = static_cast<std::uint32_t>(barConfig.height);
  const auto uShadow = static_cast<std::uint32_t>(std::max(0, barConfig.shadowSize));

  // Surface is expanded by shadowSize in the away-from-edge direction so the
  // shadow can bleed into the window area.  The exclusive zone is NOT expanded,
  // so windows keep the same reserved gap.
  auto surfaceConfig = LayerSurfaceConfig{
      .nameSpace = "noctalia-" + barConfig.name,
      .layer = LayerShellLayer::Top,
      .anchor = anchor,
      .width = vertical ? uHeight + uShadow : 0,
      .height = vertical ? 0u : uHeight + uShadow,
      .exclusiveZone = totalExclusive,
      .marginTop = (barConfig.position == "top") ? mV : 0,
      .marginRight = mH,
      .marginBottom = (barConfig.position == "bottom") ? mV : 0,
      .marginLeft = mH,
      .defaultHeight = vertical ? 0u : uHeight + uShadow,
  };

  instance->surface = std::make_unique<LayerSurface>(*m_wayland, std::move(surfaceConfig));
  instance->surface->setRenderContext(m_renderContext);

  auto* inst = instance.get();
  instance->surface->setConfigureCallback(
      [this, inst](std::uint32_t width, std::uint32_t height) { buildScene(*inst, width, height); });

  instance->surface->setAnimationManager(&instance->animations);
  populateWidgets(*instance);

  if (!instance->surface->initialize(output.output, output.scale)) {
    logWarn("bar: failed to initialize surface for output {}", output.name);
    return;
  }

  m_surfaceMap[instance->surface->wlSurface()] = instance.get();
  m_instances.push_back(std::move(instance));
}

void Bar::destroyInstance(std::uint32_t outputName) {
  std::erase_if(m_instances, [outputName](const auto& inst) { return inst->outputName == outputName; });
}

void Bar::populateWidgets(BarInstance& instance) {
  auto createWidgets = [&](const std::vector<std::string>& names, std::vector<std::unique_ptr<Widget>>& dest) {
    for (const auto& name : names) {
      auto widget = m_widgetFactory->create(name, instance.output);
      if (widget != nullptr) {
        dest.push_back(std::move(widget));
      }
    }
  };

  createWidgets(instance.barConfig.startWidgets, instance.startWidgets);
  createWidgets(instance.barConfig.centerWidgets, instance.centerWidgets);
  createWidgets(instance.barConfig.endWidgets, instance.endWidgets);
}

void Bar::buildScene(BarInstance& instance, std::uint32_t width, std::uint32_t height) {
  if (m_renderContext == nullptr) {
    return;
  }
  auto* renderer = m_renderContext;

  const auto w = static_cast<float>(width);
  const auto h = static_cast<float>(height);
  const float paddingH = static_cast<float>(instance.barConfig.paddingH);
  const float widgetSpacing = static_cast<float>(instance.barConfig.widgetSpacing);
  const float shadowSize = static_cast<float>(std::max(0, instance.barConfig.shadowSize));
  const float barH = static_cast<float>(instance.barConfig.height);
  const float radius = static_cast<float>(instance.barConfig.radius);
  const bool isBottom = instance.barConfig.position == "bottom";
  const bool isRight = instance.barConfig.position == "right";
  const bool isVertical = (instance.barConfig.position == "left" || instance.barConfig.position == "right");

  // Coordinates of the bar's visual area within the (possibly taller/wider) surface
  const float barAreaX = isRight ? shadowSize : 0.0f;
  const float barAreaY = isBottom ? shadowSize : 0.0f;
  const float barAreaW = isVertical ? barH : w;
  const float barAreaH = isVertical ? h : barH;

  if (instance.sceneRoot == nullptr) {
    instance.sceneRoot = std::make_unique<Node>();
    instance.sceneRoot->setAnimationManager(&instance.animations);
    instance.sceneRoot->setSize(w, h);

    // Bar background
    auto bg = std::make_unique<Box>();
    bg->setFlatStyle();
    bg->setRadius(radius);
    instance.bg = instance.sceneRoot->addChild(std::move(bg));

    // Shadow — gradient rect that bleeds into the window area
    if (shadowSize > 0.0f) {
      auto shadow = std::make_unique<RectNode>();
      instance.shadow = static_cast<RectNode*>(instance.sceneRoot->addChild(std::move(shadow)));
    }

    // Create section boxes
    auto makeSection = [widgetSpacing]() {
      auto box = std::make_unique<Flex>();
      box->setDirection(FlexDirection::Horizontal);
      box->setGap(widgetSpacing);
      box->setAlign(FlexAlign::Center);
      return box;
    };

    instance.startSection = static_cast<Flex*>(instance.sceneRoot->addChild(makeSection()));
    instance.centerSection = static_cast<Flex*>(instance.sceneRoot->addChild(makeSection()));
    instance.endSection = static_cast<Flex*>(instance.sceneRoot->addChild(makeSection()));

    // Create widgets and transfer their roots to section boxes
    auto initWidgets = [&](std::vector<std::unique_ptr<Widget>>& widgets, Flex* section) {
      for (auto& widget : widgets) {
        widget->setAnimationManager(&instance.animations);
        widget->setRedrawCallback([surface = instance.surface.get()]() {
          if (surface != nullptr) {
            surface->requestRedraw();
          }
        });
        widget->create(*renderer);
        if (widget->root() != nullptr) {
          section->addChild(widget->releaseRoot());
        }
      }
    };

    initWidgets(instance.startWidgets, instance.startSection);
    initWidgets(instance.centerWidgets, instance.centerSection);
    initWidgets(instance.endWidgets, instance.endSection);

    // Wire up InputDispatcher for this instance
    instance.inputDispatcher.setSceneRoot(instance.sceneRoot.get());
    instance.inputDispatcher.setCursorShapeCallback(
        [this](std::uint32_t serial, std::uint32_t shape) { m_wayland->setCursorShape(serial, shape); });

    // Fade-in animation
    instance.sceneRoot->setOpacity(0.0f);
    instance.animations.animate(0.0f, 1.0f, Style::animSlow, Easing::EaseOutCubic,
                                [root = instance.sceneRoot.get()](float v) { root->setOpacity(v); });

    instance.surface->setSceneRoot(instance.sceneRoot.get());
  }

  // Update root size on reconfigure
  instance.sceneRoot->setSize(w, h);

  // Background covers only the bar visual area (not the shadow extension).
  // Expand 1px beyond its edges so SDF fringe lands inside the rect.
  instance.bg->setPosition(barAreaX - 1.0f, barAreaY - 1.0f);
  instance.bg->setSize(barAreaW + 2.0f, barAreaH + 2.0f);

  // Shadow — positioned flush against the bar's outer edge, with the two adjacent
  // corners matching the bar's radius so the shadow silhouette follows the bar shape.
  // Rendered behind the bar (z=-1) so the bar covers the rounded-corner junction.
  if (instance.shadow != nullptr) {
    const Color dark = rgba(0.0f, 0.0f, 0.0f, 0.35f);
    const Color clear = rgba(0.0f, 0.0f, 0.0f, 0.0f);

    // Corner radii: the two corners adjacent to the bar carry the bar's radius;
    // the far corners are 0 so the shadow tapers cleanly to a straight edge.
    Radii shadowRadii{};
    if (!isVertical) {
      if (isBottom) {
        // Shadow above bottom bar — bottom corners match bar's top corners
        shadowRadii = Radii{0, 0, radius, radius};
      } else {
        // Shadow below top bar — top corners match bar's bottom corners
        shadowRadii = Radii{radius, radius, 0, 0};
      }
    } else {
      if (isRight) {
        // Shadow left of right bar — right corners match bar's left corners
        shadowRadii = Radii{0, radius, radius, 0};
      } else {
        // Shadow right of left bar — left corners match bar's right corners
        shadowRadii = Radii{radius, 0, 0, radius};
      }
    }

    RoundedRectStyle shadowStyle{
        .fillMode = FillMode::LinearGradient,
        .gradientDirection = isVertical ? GradientDirection::Horizontal : GradientDirection::Vertical,
        .radius = shadowRadii,
        .softness = 0.0f,
    };
    shadowStyle.border = clear; // default border is opaque — zero it out
    if (isBottom || isRight) {
      shadowStyle.fill = clear;
      shadowStyle.fillEnd = dark;
    } else {
      shadowStyle.fill = dark;
      shadowStyle.fillEnd = clear;
    }
    instance.shadow->setStyle(shadowStyle);
    instance.shadow->setZIndex(-1);

    if (isVertical) {
      const float shadowX = isRight ? 0.0f : barH;
      instance.shadow->setPosition(shadowX, 0.0f);
      instance.shadow->setSize(shadowSize, h);
    } else {
      const float shadowY = isBottom ? 0.0f : barH;
      instance.shadow->setPosition(0.0f, shadowY);
      instance.shadow->setSize(w, shadowSize);
    }
  }

  // Layout widgets
  auto layoutWidgets = [&](std::vector<std::unique_ptr<Widget>>& widgets) {
    for (auto& widget : widgets) {
      widget->layout(*renderer, w, h);
    }
  };
  layoutWidgets(instance.startWidgets);
  layoutWidgets(instance.centerWidgets);
  layoutWidgets(instance.endWidgets);

  // Layout section boxes
  instance.startSection->layout(*renderer);
  instance.centerSection->layout(*renderer);
  instance.endSection->layout(*renderer);

  // Position sections — centre within the bar visual area, not the full surface
  const float contentY = barAreaY + (barAreaH - instance.startSection->height()) * 0.5f;
  instance.startSection->setPosition(paddingH, contentY);

  const float centerX = barAreaX + (barAreaW - instance.centerSection->width()) * 0.5f;
  const float centerY = barAreaY + (barAreaH - instance.centerSection->height()) * 0.5f;
  instance.centerSection->setPosition(centerX, centerY);

  const float endX = barAreaX + barAreaW - instance.endSection->width() - paddingH;
  const float endY = barAreaY + (barAreaH - instance.endSection->height()) * 0.5f;
  instance.endSection->setPosition(endX, endY);
}

void Bar::updateWidgets(BarInstance& instance) {
  if (m_renderContext == nullptr) {
    return;
  }
  auto* renderer = m_renderContext;

  const auto w = static_cast<float>(instance.surface->width());
  const auto h = static_cast<float>(instance.surface->height());
  const float paddingH = static_cast<float>(instance.barConfig.paddingH);
  const float shadowSize = static_cast<float>(std::max(0, instance.barConfig.shadowSize));
  const float barH = static_cast<float>(instance.barConfig.height);
  const bool isBottom = instance.barConfig.position == "bottom";
  const bool isRight = instance.barConfig.position == "right";
  const bool isVertical = (instance.barConfig.position == "left" || instance.barConfig.position == "right");
  const float barAreaX = isRight ? shadowSize : 0.0f;
  const float barAreaY = isBottom ? shadowSize : 0.0f;
  const float barAreaW = isVertical ? barH : w;
  const float barAreaH = isVertical ? h : barH;

  auto updateSection = [&](std::vector<std::unique_ptr<Widget>>& widgets, Flex* section) {
    bool changed = false;
    for (auto& widget : widgets) {
      widget->update(*renderer);
      if (widget->root() != nullptr && widget->root()->dirty()) {
        changed = true;
        widget->layout(*renderer, w, h);
      }
    }
    if (changed) {
      section->layout(*renderer);
    }
  };

  updateSection(instance.startWidgets, instance.startSection);
  updateSection(instance.centerWidgets, instance.centerSection);
  updateSection(instance.endWidgets, instance.endSection);

  // Reposition sections if sizes changed
  if (instance.startSection->dirty() || instance.centerSection->dirty() || instance.endSection->dirty()) {
    const float contentY = barAreaY + (barAreaH - instance.startSection->height()) * 0.5f;
    instance.startSection->setPosition(paddingH, contentY);

    const float centerX = barAreaX + (barAreaW - instance.centerSection->width()) * 0.5f;
    const float centerY = barAreaY + (barAreaH - instance.centerSection->height()) * 0.5f;
    instance.centerSection->setPosition(centerX, centerY);

    const float endX = barAreaX + barAreaW - instance.endSection->width() - paddingH;
    const float endY = barAreaY + (barAreaH - instance.endSection->height()) * 0.5f;
    instance.endSection->setPosition(endX, endY);
  }
}

bool Bar::onPointerEvent(const PointerEvent& event) {
  bool consumed = false;

  switch (event.type) {
  case PointerEvent::Type::Enter: {
    auto it = m_surfaceMap.find(event.surface);
    if (it == m_surfaceMap.end()) {
      break;
    }
    m_hoveredInstance = it->second;
    m_hoveredInstance->inputDispatcher.pointerEnter(static_cast<float>(event.sx), static_cast<float>(event.sy),
                                                    event.serial);
    break;
  }
  case PointerEvent::Type::Leave: {
    if (m_hoveredInstance != nullptr) {
      m_hoveredInstance->inputDispatcher.pointerLeave();
      m_hoveredInstance = nullptr;
    }
    break;
  }
  case PointerEvent::Type::Motion: {
    if (m_hoveredInstance == nullptr)
      break;
    m_hoveredInstance->inputDispatcher.pointerMotion(static_cast<float>(event.sx), static_cast<float>(event.sy), 0);
    break;
  }
  case PointerEvent::Type::Button: {
    if (m_hoveredInstance == nullptr)
      break;
    bool pressed = (event.state == 1); // WL_POINTER_BUTTON_STATE_PRESSED
    consumed = m_hoveredInstance->inputDispatcher.pointerButton(static_cast<float>(event.sx),
                                                                static_cast<float>(event.sy), event.button, pressed);
    break;
  }
  }

  // Trigger redraw if any widget changed visual state
  if (m_hoveredInstance != nullptr && m_hoveredInstance->sceneRoot != nullptr &&
      m_hoveredInstance->sceneRoot->dirty()) {
    m_hoveredInstance->surface->requestRedraw();
  }

  return consumed;
}
