#include "shell/bar/bar.h"

#include "config/config_service.h"
#include "core/log.h"
#include "dbus/tray/tray_service.h"
#include "dbus/upower/upower_service.h"
#include "render/render_context.h"
#include "render/scene/rect_node.h"
#include "shell/widget/widget.h"
#include "system/system_monitor_service.h"
#include "system/weather_service.h"
#include "time/time_service.h"
#include "ui/controls/box.h"
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

constexpr Logger kLog("bar");

} // namespace

Bar::Bar() = default;

bool Bar::initialize(WaylandConnection& wayland, ConfigService* config, TimeService* timeService,
                     NotificationManager* notifications, TrayService* tray, PipeWireService* audio,
                     UPowerService* upower, SystemMonitorService* sysmon, MprisService* mpris,
                     HttpClient* httpClient, WeatherService* weatherService, RenderContext* renderContext) {
  m_wayland = &wayland;
  m_config = config;
  m_time = timeService;
  m_notifications = notifications;
  m_tray = tray;
  m_audio = audio;
  m_upower = upower;
  m_sysmon = sysmon;
  m_mpris = mpris;
  m_httpClient = httpClient;
  m_weatherService = weatherService;
  m_renderContext = renderContext;

  m_widgetFactory = std::make_unique<WidgetFactory>(*m_wayland, m_time, m_config->config(), m_notifications, m_tray,
                                                    m_audio, m_upower, m_sysmon, m_mpris, m_httpClient,
                                                    m_weatherService);

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

  m_config->addReloadCallback([this]() { reload(); });

  syncInstances();
  return true;
}

void Bar::reload() {
  kLog.info("reloading config");
  m_widgetFactory = std::make_unique<WidgetFactory>(*m_wayland, m_time, m_config->config(), m_notifications, m_tray,
                                                    m_audio, m_upower, m_sysmon, m_mpris, m_httpClient,
                                                    m_weatherService);
  m_instances.clear();
  m_surfaceMap.clear();
  m_hoveredInstance = nullptr;

  // Drain any pending Wayland events for the just-destroyed surfaces before
  // creating new ones. Without this, the roundtrip inside LayerSurface::initialize
  // reads stale closures for dead proxies, which libwayland drops without freeing.
  wl_display_roundtrip(m_wayland->display());

  syncInstances();
}

void Bar::closeAllInstances() {
  m_surfaceMap.clear();
  m_hoveredInstance = nullptr;
  m_instances.clear();
}

void Bar::onOutputChange() { syncInstances(); }

void Bar::refresh() {
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
  if (m_forceHidden) {
    return true; // hidden but still alive — do not exit the main loop
  }
  return std::any_of(m_instances.begin(), m_instances.end(),
                     [](const auto& inst) { return inst->surface && inst->surface->isRunning(); });
}

void Bar::show() {
  if (!m_forceHidden) {
    return;
  }
  m_forceHidden = false;
  syncInstances();
}

void Bar::hide() {
  if (m_forceHidden) {
    return;
  }
  m_forceHidden = true;
  closeAllInstances();
}

void Bar::syncInstances() {
  if (m_forceHidden) {
    return;
  }
  const auto& outputs = m_wayland->outputs();
  const auto& bars = m_config->config().bars;

  // Remove instances for outputs that no longer exist
  std::erase_if(m_instances, [&outputs](const auto& inst) {
    bool found =
        std::any_of(outputs.begin(), outputs.end(), [&inst](const auto& out) { return out.name == inst->outputName; });
    if (!found) {
      kLog.info("removing instance for output {}", inst->outputName);
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
  kLog.info("creating \"{}\" on {} ({}), height={} position={}", barConfig.name, output.connectorName,
            output.description, barConfig.height, barConfig.position);

  auto instance = std::make_unique<BarInstance>();
  instance->outputName = output.name;
  instance->output = output.output;
  instance->scale = output.scale;
  instance->barConfig = barConfig;

  const auto anchor = positionToAnchor(barConfig.position);
  const bool vertical = (barConfig.position == "left" || barConfig.position == "right");

  // All compositor margins are zero — the visual gaps (mH, mV) and shadow space are all
  // rendered within the surface itself. This lets the shadow bleed toward the screen edge
  // without being clipped by a surface boundary; only the physical screen edge clips it.
  const std::int32_t mH = barConfig.marginH;
  const std::int32_t mV = barConfig.marginV;
  // Exclusive zone reserves barH + edge-gap from the anchor edge so windows stay clear.
  const std::int32_t totalExclusive = barConfig.height + (vertical ? mH : mV);
  const auto uHeight = static_cast<std::uint32_t>(barConfig.height);
  const auto uMH = static_cast<std::uint32_t>(std::max(0, mH));
  const auto uMV = static_cast<std::uint32_t>(std::max(0, mV));

  // Shadow expansion toward content (the "inward" side of the bar).
  const auto shadowExpand = [&]() -> std::uint32_t {
    if (barConfig.shadowBlur <= 0)
      return 0u;
    if (vertical) {
      const std::int32_t inward = barConfig.position == "right" ? -barConfig.shadowOffsetX : barConfig.shadowOffsetX;
      return static_cast<std::uint32_t>(barConfig.shadowBlur + std::max(0, inward));
    }
    const std::int32_t inward = barConfig.position == "bottom" ? -barConfig.shadowOffsetY : barConfig.shadowOffsetY;
    return static_cast<std::uint32_t>(barConfig.shadowBlur + std::max(0, inward));
  }();

  // Surface spans the full axis (no perpendicular compositor margins) plus the edge gap so
  // the shadow can bleed all the way to the screen edge without hitting a surface boundary.
  auto surfaceConfig = LayerSurfaceConfig{
      .nameSpace = "noctalia-" + barConfig.name,
      .layer = LayerShellLayer::Top,
      .anchor = anchor,
      .width = vertical ? uMH + uHeight + shadowExpand : 0,
      .height = vertical ? 0u : uMV + uHeight + shadowExpand,
      .exclusiveZone = totalExclusive,
      .marginTop = 0,
      .marginRight = 0,
      .marginBottom = 0,
      .marginLeft = 0,
      .defaultHeight = vertical ? 0u : uMV + uHeight + shadowExpand,
  };

  instance->surface = std::make_unique<LayerSurface>(*m_wayland, std::move(surfaceConfig));
  instance->surface->setRenderContext(m_renderContext);

  auto* inst = instance.get();
  instance->surface->setConfigureCallback(
      [this, inst](std::uint32_t width, std::uint32_t height) { buildScene(*inst, width, height); });

  instance->surface->setAnimationManager(&instance->animations);
  populateWidgets(*instance);

  if (!instance->surface->initialize(output.output, output.scale)) {
    kLog.warn("failed to initialize surface for output {}", output.name);
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
      auto widget = m_widgetFactory->create(name, instance.output, instance.barConfig.scale);
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
  const float shadowSize = static_cast<float>(std::max(0, instance.barConfig.shadowBlur));
  const float shadowOffsetX = static_cast<float>(instance.barConfig.shadowOffsetX);
  const float shadowOffsetY = static_cast<float>(instance.barConfig.shadowOffsetY);
  const float barH = static_cast<float>(instance.barConfig.height);
  const float marginH = static_cast<float>(instance.barConfig.marginH);
  const float marginV = static_cast<float>(instance.barConfig.marginV);
  const float radius = static_cast<float>(instance.barConfig.radius);
  const bool isBottom = instance.barConfig.position == "bottom";
  const bool isRight = instance.barConfig.position == "right";
  const bool isVertical = (instance.barConfig.position == "left" || instance.barConfig.position == "right");

  // Compute the surface expansion (must match createInstance).
  const float shadowExpand = [&]() -> float {
    if (shadowSize <= 0.0f)
      return 0.0f;
    if (isVertical) {
      const float inward = isRight ? -shadowOffsetX : shadowOffsetX;
      return shadowSize + std::max(0.0f, inward);
    }
    const float inward = isBottom ? -shadowOffsetY : shadowOffsetY;
    return shadowSize + std::max(0.0f, inward);
  }();

  // The bar's visual area within the surface.
  // All compositor margins are zero; mH and mV are embedded here as the visual gap.
  // For the anchor-edge side: the gap (mV for horizontal, mH for vertical) sits between
  // the surface/screen edge and the bar, so barAreaY/X offsets by that amount.
  const float barAreaX = isVertical ? (isRight ? shadowExpand : marginH) : marginH;
  const float barAreaY = isVertical ? marginV : (isBottom ? shadowExpand : marginV);
  const float barAreaW = isVertical ? barH : (w - 2.0f * marginH);
  const float barAreaH = isVertical ? (h - 2.0f * marginV) : barH;

  if (instance.sceneRoot == nullptr) {
    instance.sceneRoot = std::make_unique<Node>();
    instance.sceneRoot->setAnimationManager(&instance.animations);
    instance.sceneRoot->setSize(w, h);

    // Bar background
    auto bg = std::make_unique<Box>();
    bg->setFlatStyle();
    bg->setRadius(radius);
    instance.bg = instance.sceneRoot->addChild(std::move(bg));

    // Shadow — bar shape copy rendered with large SDF softness to simulate a blurred drop shadow.
    if (shadowSize > 0.0f) {
      auto shadow = std::make_unique<RectNode>();
      instance.shadow = static_cast<RectNode*>(instance.sceneRoot->addChild(std::move(shadow)));
    }
    // Note: shadow is inserted before bar sections so it renders below them (z=-1 is set below).

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

  // Shadow — same shape as the bar, offset by (shadowOffsetX, shadowOffsetY), rendered with large
  // SDF softness to produce a Gaussian-like blurred drop shadow. Rendered at z=-1 so the bar sits
  // on top and hides the shadow's opaque interior.
  if (instance.shadow != nullptr) {
    const RoundedRectStyle shadowStyle{
        .fill = rgba(0.0f, 0.0f, 0.0f, 0.55f),
        .fillEnd = {},
        .border = rgba(0.0f, 0.0f, 0.0f, 0.0f),
        .fillMode = FillMode::Solid,
        .radius = radius,
        .softness = shadowSize,
    };
    instance.shadow->setStyle(shadowStyle);
    instance.shadow->setZIndex(-1);
    instance.shadow->setPosition(barAreaX + shadowOffsetX, barAreaY + shadowOffsetY);
    instance.shadow->setSize(barAreaW, barAreaH);
  }

  // Layout widgets
  auto layoutWidgets = [&](std::vector<std::unique_ptr<Widget>>& widgets) {
    for (auto& widget : widgets) {
      widget->layout(*renderer, barAreaW, barAreaH);
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
  instance.startSection->setPosition(barAreaX + paddingH, contentY);

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
  const float shadowSize = static_cast<float>(std::max(0, instance.barConfig.shadowBlur));
  const float shadowOffsetX = static_cast<float>(instance.barConfig.shadowOffsetX);
  const float shadowOffsetY = static_cast<float>(instance.barConfig.shadowOffsetY);
  const float barH = static_cast<float>(instance.barConfig.height);
  const float marginH = static_cast<float>(instance.barConfig.marginH);
  const float marginV = static_cast<float>(instance.barConfig.marginV);
  const bool isBottom = instance.barConfig.position == "bottom";
  const bool isRight = instance.barConfig.position == "right";
  const bool isVertical = (instance.barConfig.position == "left" || instance.barConfig.position == "right");
  const float shadowExpand = [&]() -> float {
    if (shadowSize <= 0.0f)
      return 0.0f;
    if (isVertical) {
      const float inward = isRight ? -shadowOffsetX : shadowOffsetX;
      return shadowSize + std::max(0.0f, inward);
    }
    const float inward = isBottom ? -shadowOffsetY : shadowOffsetY;
    return shadowSize + std::max(0.0f, inward);
  }();
  const float barAreaX = isVertical ? (isRight ? shadowExpand : marginH) : marginH;
  const float barAreaY = isVertical ? marginV : (isBottom ? shadowExpand : marginV);
  const float barAreaW = isVertical ? barH : (w - 2.0f * marginH);
  const float barAreaH = isVertical ? (h - 2.0f * marginV) : barH;

  auto updateSection = [&](std::vector<std::unique_ptr<Widget>>& widgets, Flex* section) {
    bool changed = false;
    for (auto& widget : widgets) {
      widget->update(*renderer);
      if (widget->root() != nullptr && widget->root()->dirty()) {
        changed = true;
        widget->layout(*renderer, barAreaW, barAreaH);
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
    instance.startSection->setPosition(barAreaX + paddingH, contentY);

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
  case PointerEvent::Type::Axis:
    break;
  }

  // Trigger redraw if any widget changed visual state
  if (m_hoveredInstance != nullptr && m_hoveredInstance->sceneRoot != nullptr &&
      m_hoveredInstance->sceneRoot->dirty()) {
    m_hoveredInstance->surface->requestRedraw();
  }

  return consumed;
}
