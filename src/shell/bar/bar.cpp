#include "shell/bar/bar.h"

#include "config/config_service.h"
#include "core/ui_phase.h"
#include "core/log.h"
#include "dbus/power/power_profiles_service.h"
#include "dbus/tray/tray_service.h"
#include "dbus/upower/upower_service.h"
#include "render/render_context.h"
#include "render/scene/rect_node.h"
#include "shell/widget/widget.h"
#include "system/night_light_manager.h"
#include "system/system_monitor_service.h"
#include "system/weather_service.h"
#include "theme/theme_service.h"
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

constexpr Logger kLog("bar");

struct ShadowBleed {
  std::int32_t left = 0, right = 0, up = 0, down = 0;
};

ShadowBleed computeShadowBleed(const BarConfig& cfg) {
  if (cfg.shadowBlur <= 0)
    return {};
  return {
      cfg.shadowBlur + std::max(0, -cfg.shadowOffsetX),
      cfg.shadowBlur + std::max(0, cfg.shadowOffsetX),
      cfg.shadowBlur + std::max(0, -cfg.shadowOffsetY),
      cfg.shadowBlur + std::max(0, cfg.shadowOffsetY),
  };
}

void layoutBarSections(BarInstance& instance, Renderer& renderer, float barAreaW, float barAreaH, float paddingH,
                       bool isVertical) {
  auto layoutWidgets = [&](std::vector<std::unique_ptr<Widget>>& widgets) {
    for (auto& widget : widgets) {
      widget->layout(renderer, barAreaW, barAreaH);
    }
  };
  layoutWidgets(instance.startWidgets);
  layoutWidgets(instance.centerWidgets);
  layoutWidgets(instance.endWidgets);

  const float slotCross = isVertical ? barAreaW : barAreaH;
  const float contentMainStart = paddingH;
  const float contentMainEnd = std::max(contentMainStart, (isVertical ? barAreaH : barAreaW) - paddingH);
  const float contentMainSpan = std::max(0.0f, contentMainEnd - contentMainStart);

  auto configureSlot = [&](Node* slot, float mainOffset, float mainSize) {
    slot->setClipChildren(true);
    if (isVertical) {
      slot->setPosition(0.0f, mainOffset);
      slot->setSize(slotCross, mainSize);
    } else {
      slot->setPosition(mainOffset, 0.0f);
      slot->setSize(mainSize, slotCross);
    }
  };

  auto configureSection = [&](Flex* section, FlexJustify justify) {
    section->setJustify(justify);
    section->layout(renderer);
  };

  configureSection(instance.startSection, FlexJustify::Start);
  configureSection(instance.centerSection, FlexJustify::Center);
  configureSection(instance.endSection, FlexJustify::End);

  const float centerNaturalMain = isVertical ? instance.centerSection->height() : instance.centerSection->width();
  const float centerSlotMain = std::min(contentMainSpan, centerNaturalMain);
  const float centerSlotStart = contentMainStart + std::max(0.0f, (contentMainSpan - centerSlotMain) * 0.5f);
  const float centerSlotEnd = centerSlotStart + centerSlotMain;
  const float startSlotMain = std::max(0.0f, centerSlotStart - contentMainStart);
  const float endSlotMain = std::max(0.0f, contentMainEnd - centerSlotEnd);

  configureSlot(instance.startSlot, contentMainStart, startSlotMain);
  configureSlot(instance.centerSlot, centerSlotStart, centerSlotMain);
  configureSlot(instance.endSlot, centerSlotEnd, endSlotMain);

  if (isVertical) {
    instance.startSection->setPosition((slotCross - instance.startSection->width()) * 0.5f,
                                       (startSlotMain - instance.startSection->height()) * 0.5f);
    instance.centerSection->setPosition((slotCross - instance.centerSection->width()) * 0.5f,
                                        (centerSlotMain - instance.centerSection->height()) * 0.5f);
    instance.endSection->setPosition((slotCross - instance.endSection->width()) * 0.5f,
                                     (endSlotMain - instance.endSection->height()) * 0.5f);
  } else {
    instance.startSection->setPosition(0.0f, (slotCross - instance.startSection->height()) * 0.5f);
    instance.centerSection->setPosition((centerSlotMain - instance.centerSection->width()) * 0.5f,
                                        (slotCross - instance.centerSection->height()) * 0.5f);
    instance.endSection->setPosition(endSlotMain - instance.endSection->width(),
                                     (slotCross - instance.endSection->height()) * 0.5f);
  }
}

void tickWidgets(std::vector<std::unique_ptr<Widget>>& widgets, float deltaMs) {
  for (auto& widget : widgets) {
    if (widget != nullptr && widget->needsFrameTick()) {
      widget->onFrameTick(deltaMs);
    }
  }
}

bool widgetsNeedFrameTick(const std::vector<std::unique_ptr<Widget>>& widgets) {
  return std::any_of(widgets.begin(), widgets.end(),
                     [](const auto& widget) { return widget != nullptr && widget->needsFrameTick(); });
}

} // namespace

Bar::Bar() = default;

bool Bar::initialize(WaylandConnection& wayland, ConfigService* config, TimeService* timeService,
                     NotificationManager* notifications, TrayService* tray, PipeWireService* audio,
                     UPowerService* upower, SystemMonitorService* sysmon, PowerProfilesService* powerProfiles,
                     IdleInhibitor* idleInhibitor, MprisService* mpris, PipeWireSpectrum* audioSpectrum,
                     HttpClient* httpClient, WeatherService* weatherService, RenderContext* renderContext,
                     NightLightManager* nightLight, noctalia::theme::ThemeService* themeService) {
  m_wayland = &wayland;
  m_config = config;
  m_time = timeService;
  m_notifications = notifications;
  m_tray = tray;
  m_audio = audio;
  m_upower = upower;
  m_sysmon = sysmon;
  m_powerProfiles = powerProfiles;
  m_idleInhibitor = idleInhibitor;
  m_mpris = mpris;
  m_audioSpectrum = audioSpectrum;
  m_httpClient = httpClient;
  m_weatherService = weatherService;
  m_renderContext = renderContext;
  m_nightLight = nightLight;
  m_themeService = themeService;

  m_widgetFactory = std::make_unique<WidgetFactory>(*m_wayland, m_time, m_config->config(), m_notifications, m_tray,
                                                    m_audio, m_upower, m_sysmon, m_powerProfiles, m_idleInhibitor,
                                                    m_mpris, m_audioSpectrum, m_httpClient, m_weatherService,
                                                    m_nightLight, m_themeService);

  if (timeService != nullptr) {
    timeService->setTickSecondCallback([this]() {
      for (auto& inst : m_instances) {
        if (inst->surface != nullptr) {
          inst->surface->requestUpdate();
        }
      }
    });
  }

  m_lastBars = m_config->config().bars;
  m_lastWidgets = m_config->config().widgets;
  m_config->addReloadCallback([this]() {
    const auto& cfg = m_config->config();
    if (cfg.bars == m_lastBars && cfg.widgets == m_lastWidgets) {
      return;
    }
    reload();
  });

  syncInstances();
  return true;
}

void Bar::onSecondTick() {
  for (auto& inst : m_instances) {
    if (inst->surface != nullptr) {
      inst->surface->requestUpdate();
    }
  }
}

void Bar::reload() {
  kLog.info("reloading config");
  m_lastBars = m_config->config().bars;
  m_lastWidgets = m_config->config().widgets;
  m_widgetFactory = std::make_unique<WidgetFactory>(*m_wayland, m_time, m_config->config(), m_notifications, m_tray,
                                                    m_audio, m_upower, m_sysmon, m_powerProfiles, m_idleInhibitor,
                                                    m_mpris, m_audioSpectrum, m_httpClient, m_weatherService,
                                                    m_nightLight, m_themeService);
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
    if (inst->surface != nullptr) {
      inst->surface->requestUpdate();
      if (inst->animations.hasActive() || instanceNeedsFrameTick(*inst)) {
        inst->surface->requestRedraw();
      }
    }
  }
}

void Bar::requestRedraw() {
  for (auto& inst : m_instances) {
    if (inst->surface != nullptr) {
      inst->surface->requestRedraw();
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
      if (!output.done) {
        continue;
      }

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
  const bool isBottom = barConfig.position == "bottom";
  const bool isRight = barConfig.position == "right";

  const std::int32_t mH = barConfig.marginH;
  const std::int32_t mV = barConfig.marginV;
  const auto sb = computeShadowBleed(barConfig);

  // Compositor margins absorb the visual gap where the shadow doesn't reach.
  // The surface is sized to cover only the bar rect plus its shadow footprint.
  std::int32_t mLeft = 0, mRight = 0, mTop = 0, mBottom = 0;
  std::uint32_t surfW = 0, surfH = 0;
  std::int32_t exclusiveZone = 0;

  if (!vertical) {
    mLeft  = std::max(0, mH - sb.left);
    mRight = std::max(0, mH - sb.right);
    if (isBottom) {
      mBottom       = std::max(0, mV - sb.down);
      surfH         = static_cast<std::uint32_t>(sb.up + barConfig.height + std::min(mV, sb.down));
      exclusiveZone = barConfig.height + std::min(mV, sb.down);
    } else {
      mTop          = std::max(0, mV - sb.up);
      surfH         = static_cast<std::uint32_t>(std::min(mV, sb.up) + barConfig.height + sb.down);
      exclusiveZone = std::min(mV, sb.up) + barConfig.height;
    }
  } else {
    mTop    = std::max(0, mV - sb.up);
    mBottom = std::max(0, mV - sb.down);
    if (isRight) {
      mRight        = std::max(0, mH - sb.right);
      surfW         = static_cast<std::uint32_t>(sb.left + barConfig.height + std::min(mH, sb.right));
      exclusiveZone = barConfig.height + std::min(mH, sb.right);
    } else {
      mLeft         = std::max(0, mH - sb.left);
      surfW         = static_cast<std::uint32_t>(std::min(mH, sb.left) + barConfig.height + sb.right);
      exclusiveZone = std::min(mH, sb.left) + barConfig.height;
    }
  }

  auto surfaceConfig = LayerSurfaceConfig{
      .nameSpace     = "noctalia-" + barConfig.name,
      .layer         = LayerShellLayer::Top,
      .anchor        = anchor,
      .width         = surfW,
      .height        = surfH,
      .exclusiveZone = exclusiveZone,
      .marginTop     = mTop,
      .marginRight   = mRight,
      .marginBottom  = mBottom,
      .marginLeft    = mLeft,
      .defaultHeight = surfH,
  };

  instance->surface = std::make_unique<LayerSurface>(*m_wayland, std::move(surfaceConfig));
  instance->surface->setRenderContext(m_renderContext);

  auto* inst = instance.get();
  instance->surface->setConfigureCallback(
      [this, inst](std::uint32_t width, std::uint32_t height) { buildScene(*inst, width, height); });
  instance->surface->setPrepareFrameCallback(
      [this, inst](bool needsUpdate, bool needsLayout) { prepareFrame(*inst, needsUpdate, needsLayout); });
  instance->surface->setFrameTickCallback([inst](float deltaMs) {
    tickWidgets(inst->startWidgets, deltaMs);
    tickWidgets(inst->centerWidgets, deltaMs);
    tickWidgets(inst->endWidgets, deltaMs);
  });

  instance->surface->setAnimationManager(&instance->animations);
  populateWidgets(*instance);

  if (!instance->surface->initialize(output.output)) {
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

void Bar::tickWidgets(std::vector<std::unique_ptr<Widget>>& widgets, float deltaMs) { ::tickWidgets(widgets, deltaMs); }

bool Bar::widgetsNeedFrameTick(const std::vector<std::unique_ptr<Widget>>& widgets) { return ::widgetsNeedFrameTick(widgets); }

bool Bar::instanceNeedsFrameTick(const BarInstance& instance) {
  return widgetsNeedFrameTick(instance.startWidgets) || widgetsNeedFrameTick(instance.centerWidgets) ||
         widgetsNeedFrameTick(instance.endWidgets);
}

void Bar::applyBackgroundPalette(BarInstance& instance) {
  if (instance.bg == nullptr) {
    return;
  }
  auto style = instance.bg->style();
  style.fill = resolveThemeColor(roleColor(ColorRole::Surface, instance.barConfig.backgroundOpacity));
  style.border = resolveThemeColor(roleColor(ColorRole::Outline));
  instance.bg->setStyle(style);
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
  const bool isBottom = instance.barConfig.position == "bottom";
  const bool isRight = instance.barConfig.position == "right";
  const bool isVertical = (instance.barConfig.position == "left" || instance.barConfig.position == "right");
  const Radii barRadii{
      static_cast<float>(instance.barConfig.radiusTopLeft),
      static_cast<float>(instance.barConfig.radiusTopRight),
      static_cast<float>(instance.barConfig.radiusBottomRight),
      static_cast<float>(instance.barConfig.radiusBottomLeft),
  };

  // Shadow bleed in each direction (matches createInstance geometry).
  const auto sbi = computeShadowBleed(instance.barConfig);
  const float bleedLeft  = static_cast<float>(sbi.left);
  const float bleedRight = static_cast<float>(sbi.right);
  const float bleedUp    = static_cast<float>(sbi.up);
  const float bleedDown  = static_cast<float>(sbi.down);

  // The bar's visual area within the tight surface.
  // compositor margins absorbed the outer gap; only the shadow bleed (capped at the gap)
  // remains as padding between the surface edge and the bar rect.
  float barAreaX, barAreaY, barAreaW, barAreaH;
  if (isVertical) {
    barAreaX = isRight ? bleedLeft : std::min(marginH, bleedLeft);
    barAreaY = std::min(marginV, bleedUp);
    barAreaW = barH;
    barAreaH = h - barAreaY - std::min(marginV, bleedDown);
  } else {
    barAreaX = std::min(marginH, bleedLeft);
    barAreaY = isBottom ? bleedUp : std::min(marginV, bleedUp);
    barAreaW = w - barAreaX - std::min(marginH, bleedRight);
    barAreaH = barH;
  }

  if (instance.sceneRoot == nullptr) {
    instance.sceneRoot = std::make_unique<Node>();
    instance.sceneRoot->setAnimationManager(&instance.animations);
    instance.sceneRoot->setSize(w, h);

    // Bar background
    auto bg = std::make_unique<RectNode>();
    instance.bg = static_cast<RectNode*>(instance.sceneRoot->addChild(std::move(bg)));

    // Shadow — bar shape copy rendered with large SDF softness to simulate a blurred drop shadow.
    if (shadowSize > 0.0f) {
      auto shadow = std::make_unique<RectNode>();
      instance.shadow = static_cast<RectNode*>(instance.sceneRoot->addChild(std::move(shadow)));
    }
    // Note: shadow is inserted before bar sections so it renders below them (z=-1 is set below).

    auto contentClip = std::make_unique<Node>();
    contentClip->setClipChildren(true);
    instance.contentClip = instance.sceneRoot->addChild(std::move(contentClip));

    auto makeSlot = [&instance]() {
      auto slot = std::make_unique<Node>();
      slot->setClipChildren(true);
      return instance.contentClip->addChild(std::move(slot));
    };
    instance.startSlot = makeSlot();
    instance.centerSlot = makeSlot();
    instance.endSlot = makeSlot();

    // Create section boxes
    auto makeSection = [widgetSpacing]() {
      auto box = std::make_unique<Flex>();
      box->setDirection(FlexDirection::Horizontal);
      box->setGap(widgetSpacing);
      box->setAlign(FlexAlign::Center);
      return box;
    };

    instance.startSection = static_cast<Flex*>(instance.startSlot->addChild(makeSection()));
    instance.centerSection = static_cast<Flex*>(instance.centerSlot->addChild(makeSection()));
    instance.endSection = static_cast<Flex*>(instance.endSlot->addChild(makeSection()));

    // Create widgets and transfer their roots to section boxes
    auto initWidgets = [&](std::vector<std::unique_ptr<Widget>>& widgets, Flex* section) {
      for (auto& widget : widgets) {
        widget->setAnimationManager(&instance.animations);
        widget->setRedrawCallback([surface = instance.surface.get()]() {
          if (surface != nullptr) {
            surface->requestRedraw();
          }
        });
        widget->create();
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
  if (instance.bg != nullptr) {
    const RoundedRectStyle bgStyle{
        .fill = resolveThemeColor(roleColor(ColorRole::Surface, instance.barConfig.backgroundOpacity)),
        .fillEnd = {},
        .border = resolveThemeColor(roleColor(ColorRole::Outline)),
        .fillMode = FillMode::Solid,
        .radius = barRadii,
        .softness = 0.0f,
        .borderWidth = 0.0f,
    };
    instance.bg->setStyle(bgStyle);
    instance.bg->setPosition(barAreaX - 1.0f, barAreaY - 1.0f);
    instance.bg->setSize(barAreaW + 2.0f, barAreaH + 2.0f);
  }

  instance.paletteConn = paletteChanged().connect([inst = &instance] {
    applyBackgroundPalette(*inst);
    if (inst->surface != nullptr) {
      inst->surface->requestRedraw();
    }
  });
  if (instance.contentClip != nullptr) {
    instance.contentClip->setPosition(barAreaX, barAreaY);
    instance.contentClip->setSize(barAreaW, barAreaH);
  }

  // Shadow — same shape as the bar, offset by (shadowOffsetX, shadowOffsetY), rendered with large
  // SDF softness to produce a Gaussian-like blurred drop shadow. Rendered at z=-1 so the bar sits
  // on top and hides the shadow's opaque interior.
  if (instance.shadow != nullptr) {
    const RoundedRectStyle shadowStyle{
        .fill = rgba(0.0f, 0.0f, 0.0f, 0.55f),
        .fillEnd = {},
        .border = clearColor(),
        .fillMode = FillMode::Solid,
        .radius = barRadii,
        .softness = shadowSize,
    };
    instance.shadow->setStyle(shadowStyle);
    instance.shadow->setZIndex(-1);
    instance.shadow->setPosition(barAreaX + shadowOffsetX, barAreaY + shadowOffsetY);
    instance.shadow->setSize(barAreaW, barAreaH);
  }

  layoutBarSections(instance, *renderer, barAreaW, barAreaH, paddingH, isVertical);

  instance.surface->setInputRegion({InputRect{
      static_cast<int>(barAreaX),
      static_cast<int>(barAreaY),
      static_cast<int>(barAreaW),
      static_cast<int>(barAreaH),
  }});
}

void Bar::updateWidgets(BarInstance& instance) {
  if (m_renderContext == nullptr) {
    return;
  }
  auto* renderer = m_renderContext;

  const auto w = static_cast<float>(instance.surface->width());
  const auto h = static_cast<float>(instance.surface->height());
  const float paddingH = static_cast<float>(instance.barConfig.paddingH);
  const float barH = static_cast<float>(instance.barConfig.height);
  const float marginH = static_cast<float>(instance.barConfig.marginH);
  const float marginV = static_cast<float>(instance.barConfig.marginV);
  const bool isVertical = (instance.barConfig.position == "left" || instance.barConfig.position == "right");
  const auto sbi = computeShadowBleed(instance.barConfig);
  const float bleedLeft  = static_cast<float>(sbi.left);
  const float bleedRight = static_cast<float>(sbi.right);
  const float bleedUp    = static_cast<float>(sbi.up);
  const float bleedDown  = static_cast<float>(sbi.down);
  float barAreaW, barAreaH;
  if (isVertical) {
    const float barAreaY = std::min(marginV, bleedUp);
    barAreaW = barH;
    barAreaH = h - barAreaY - std::min(marginV, bleedDown);
  } else {
    const float barAreaX = std::min(marginH, bleedLeft);
    barAreaW = w - barAreaX - std::min(marginH, bleedRight);
    barAreaH = barH;
  }

  auto updateSection = [&](std::vector<std::unique_ptr<Widget>>& widgets) {
    bool changed = false;
    for (auto& widget : widgets) {
      widget->update(*renderer);
      if (widget->root() != nullptr && widget->root()->dirty()) {
        changed = true;
        widget->layout(*renderer, barAreaW, barAreaH);
      }
    }
    return changed;
  };

  const bool startChanged = updateSection(instance.startWidgets);
  const bool centerChanged = updateSection(instance.centerWidgets);
  const bool endChanged = updateSection(instance.endWidgets);

  if (startChanged || centerChanged || endChanged || instance.startSection->dirty() || instance.centerSection->dirty() ||
      instance.endSection->dirty()) {
    layoutBarSections(instance, *renderer, barAreaW, barAreaH, paddingH, isVertical);
  }
}

void Bar::prepareFrame(BarInstance& instance, bool needsUpdate, bool needsLayout) {
  if (m_renderContext == nullptr || instance.surface == nullptr) {
    return;
  }

  m_renderContext->makeCurrent(instance.surface->renderTarget());
  m_renderContext->syncContentScale(instance.surface->renderTarget());

  if (needsUpdate) {
    UiPhaseScope updatePhase(UiPhase::Update);
    updateWidgets(instance);
    return;
  }

  if (!needsLayout) {
    return;
  }

  const auto w = static_cast<float>(instance.surface->width());
  const auto h = static_cast<float>(instance.surface->height());
  const float paddingH = static_cast<float>(instance.barConfig.paddingH);
  const float barH = static_cast<float>(instance.barConfig.height);
  const float marginH = static_cast<float>(instance.barConfig.marginH);
  const float marginV = static_cast<float>(instance.barConfig.marginV);
  const bool isVertical = (instance.barConfig.position == "left" || instance.barConfig.position == "right");
  const auto sbi = computeShadowBleed(instance.barConfig);
  const float bleedLeft = static_cast<float>(sbi.left);
  const float bleedRight = static_cast<float>(sbi.right);
  const float bleedUp = static_cast<float>(sbi.up);
  const float bleedDown = static_cast<float>(sbi.down);
  float barAreaW = 0.0f;
  float barAreaH = 0.0f;
  if (isVertical) {
    const float barAreaY = std::min(marginV, bleedUp);
    barAreaW = barH;
    barAreaH = h - barAreaY - std::min(marginV, bleedDown);
  } else {
    const float barAreaX = std::min(marginH, bleedLeft);
    barAreaW = w - barAreaX - std::min(marginH, bleedRight);
    barAreaH = barH;
  }

  {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    for (auto& widget : instance.startWidgets) {
      widget->layout(*m_renderContext, barAreaW, barAreaH);
    }
    for (auto& widget : instance.centerWidgets) {
      widget->layout(*m_renderContext, barAreaW, barAreaH);
    }
    for (auto& widget : instance.endWidgets) {
      widget->layout(*m_renderContext, barAreaW, barAreaH);
    }
    layoutBarSections(instance, *m_renderContext, barAreaW, barAreaH, paddingH, isVertical);
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
