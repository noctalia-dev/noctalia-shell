#include "shell/bar/bar.h"

#include "config/config_service.h"
#include "core/log.h"
#include "core/ui_phase.h"
#include "dbus/power/power_profiles_service.h"
#include "dbus/tray/tray_service.h"
#include "dbus/upower/upower_service.h"
#include "ipc/ipc_service.h"
#include "render/render_context.h"
#include "render/scene/rect_node.h"
#include "shell/bar/widget.h"
#include "shell/surface_shadow.h"
#include "system/night_light_manager.h"
#include "system/system_monitor_service.h"
#include "system/weather_service.h"
#include "theme/theme_service.h"
#include "time/time_service.h"
#include "ui/controls/box.h"
#include "ui/controls/flex.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cmath>
#include <wayland-client-core.h>

namespace {

  constexpr float kCircularCapsuleNarrowWidthEpsilon = 1.0f;
  constexpr std::int32_t kAutoHideTriggerPx = 2;
  constexpr float kAutoHideSlideExtraPx = 16.0f;

  [[nodiscard]] CornerShapes attachedPanelCornerShapes() {
    return CornerShapes{
        .tl = CornerShape::Concave,
        .tr = CornerShape::Concave,
        .br = CornerShape::Convex,
        .bl = CornerShape::Convex,
    };
  }

  [[nodiscard]] RectInsets attachedPanelLogicalInset(float radius) {
    return RectInsets{
        .left = radius,
        .top = 0.0f,
        .right = radius,
        .bottom = 0.0f,
    };
  }

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

  ThemeColor withOpacity(const ThemeColor& color, float opacity) {
    ThemeColor out = color;
    out.alpha = std::clamp(out.alpha * std::clamp(opacity, 0.0f, 1.0f), 0.0f, 1.0f);
    return out;
  }

  struct BarVisualGeometry {
    float x = 0.0f;
    float y = 0.0f;
    float width = 0.0f;
    float height = 0.0f;
  };

  // Returns true when two bar configs would produce an identical layer-shell
  // surface (same anchor, size, exclusive zone, namespace). When true, an
  // existing BarInstance can be retained on reload and only its widget tree
  // rebuilt — avoiding the screen-shift caused by destroying and recreating
  // the exclusive zone.
  bool barConfigSurfaceFieldsEqual(const BarConfig& a, const BarConfig& b,
                                   const ShellConfig::ShadowConfig& previousShadow,
                                   const ShellConfig::ShadowConfig& nextShadow) {
    const bool sameShadowSurface =
        (!a.shadow && !b.shadow) || shell::surface_shadow::sameSurfaceMetrics(previousShadow, nextShadow);
    return a.name == b.name && a.position == b.position && a.enabled == b.enabled && a.autoHide == b.autoHide &&
           a.reserveSpace == b.reserveSpace && a.thickness == b.thickness && a.marginH == b.marginH &&
           a.marginV == b.marginV && a.shadow == b.shadow && sameShadowSurface &&
           a.monitorOverrides == b.monitorOverrides;
  }

  BarVisualGeometry computeBarVisualGeometry(const BarConfig& cfg, const ShellConfig::ShadowConfig& shadow,
                                             float surfaceWidth, float surfaceHeight) {
    const float barThickness = static_cast<float>(cfg.thickness);
    const float marginH = static_cast<float>(cfg.marginH);
    const float marginV = static_cast<float>(cfg.marginV);
    const bool isBottom = cfg.position == "bottom";
    const bool isRight = cfg.position == "right";
    const bool isVertical = (cfg.position == "left" || cfg.position == "right");
    const auto sbi = shell::surface_shadow::bleed(cfg.shadow, shadow);
    const float bleedLeft = static_cast<float>(sbi.left);
    const float bleedRight = static_cast<float>(sbi.right);
    const float bleedUp = static_cast<float>(sbi.up);
    const float bleedDown = static_cast<float>(sbi.down);

    if (isVertical) {
      const float x = isRight ? bleedLeft : std::min(marginH, bleedLeft);
      const float y = std::min(marginV, bleedUp);
      return {
          .x = x,
          .y = y,
          .width = barThickness,
          .height = surfaceHeight - y - std::min(marginV, bleedDown),
      };
    }

    const float x = std::min(marginH, bleedLeft);
    const float y = isBottom ? bleedUp : std::min(marginV, bleedUp);
    return {
        .x = x,
        .y = y,
        .width = surfaceWidth - x - std::min(marginH, bleedRight),
        .height = barThickness,
    };
  }

  std::pair<float, float> computeAutoHideHiddenDelta(bool isVertical, bool isBottom, bool isRight, float w, float h,
                                                     float contentLeft, float contentTop, float contentRight,
                                                     float contentBottom) {
    const float k = kAutoHideSlideExtraPx;
    if (!isVertical) {
      if (isBottom) {
        return {0.0f, (h - contentTop) + k};
      }
      return {0.0f, -(contentBottom + k)};
    }
    if (isRight) {
      return {(w - contentLeft) + k, 0.0f};
    }
    return {-(contentRight + k), 0.0f};
  }

  void layoutBarSections(BarInstance& instance, Renderer& renderer, float barAreaW, float barAreaH, float padding,
                         bool isVertical) {
    const float slotCross = isVertical ? barAreaW : barAreaH;

    auto layoutWidgets = [&](std::vector<std::unique_ptr<Widget>>& widgets) {
      for (auto& widget : widgets) {
        if (widget->root() != nullptr) {
          widget->layout(renderer, barAreaW, barAreaH);
        }
      }
    };
    layoutWidgets(instance.startWidgets);
    layoutWidgets(instance.centerWidgets);
    layoutWidgets(instance.endWidgets);

    float cachedBodyExtent = -1.0f;
    float cachedBodyExtentScale = -1.0f;
    auto finalizeCapsules = [isVertical, slotCross, &renderer, &cachedBodyExtent,
                             &cachedBodyExtentScale](std::vector<std::unique_ptr<Widget>>& widgets) {
      for (auto& w : widgets) {
        if (w == nullptr || !w->barCapsuleSpec().enabled) {
          continue;
        }
        Node* shell = w->barCapsuleShell();
        Box* bg = w->barCapsuleBox();
        Node* inner = w->root();
        if (shell == nullptr || bg == nullptr || inner == nullptr) {
          continue;
        }
        shell->setVisible(inner->visible());
        const float scale = w->contentScale();
        const float iw = inner->width();
        const float ih = inner->height();
        if (!w->shouldShowBarCapsule()) {
          shell->setSize(iw, ih);
          inner->setPosition(0.0f, 0.0f);
          bg->setVisible(false);
          bg->setPosition(0.0f, 0.0f);
          bg->setSize(iw, ih);
          continue;
        }
        if (scale != cachedBodyExtentScale) {
          const auto refMetrics = renderer.measureText("A", Style::fontSizeBody * scale);
          cachedBodyExtent = std::round(refMetrics.bottom - refMetrics.top);
          cachedBodyExtentScale = scale;
        }
        const float bodyExtent = cachedBodyExtent;
        const float pad = w->barCapsuleSpec().padding * scale;
        const float padMain = pad;
        const float padCross = std::min(pad, Style::spaceXs * scale);
        float shellMain = (isVertical ? ih : iw) + 2.0f * padMain;
        float shellCross = bodyExtent + 2.0f * padCross;
        if (isVertical) {
          shellCross = std::min(shellCross, slotCross);
        }
        float shellW = isVertical ? shellCross : shellMain;
        float shellH = isVertical ? shellMain : shellCross;
        float innerX = std::round((shellW - iw) * 0.5f);
        float innerY = std::round((shellH - ih) * 0.5f);
        // Glyph-only widgets have content close to bodyExtent on both axes — round
        // them into a circular capsule. Multi-line / wide content (e.g. stacked
        // vertical clock) must NOT be squared, or the capsule collapses on the
        // main axis.
        const float iconThreshold = bodyExtent + (kCircularCapsuleNarrowWidthEpsilon * scale);
        const bool iconSized = iw <= iconThreshold && ih <= iconThreshold;
        if (iconSized) {
          float side = std::max(shellW, shellH);
          if (isVertical) {
            side = std::min(side, slotCross);
          }
          shellW = side;
          shellH = side;
          innerX = std::round((shellW - iw) * 0.5f);
          innerY = std::round((shellH - ih) * 0.5f);
        }
        shell->setSize(shellW, shellH);
        bg->setVisible(true);
        bg->setPosition(0.0f, 0.0f);
        bg->setSize(shellW, shellH);
        inner->setPosition(innerX, innerY);
        bg->setRadius(std::min(shellW, shellH) * 0.5f);
      }
    };
    finalizeCapsules(instance.startWidgets);
    finalizeCapsules(instance.centerWidgets);
    finalizeCapsules(instance.endWidgets);

    const float contentMainStart = padding;
    const float contentMainEnd = std::max(contentMainStart, (isVertical ? barAreaH : barAreaW) - padding);
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

    // Anchor mode: if a center widget is flagged as the anchor, pin its center to the
    // bar midline so surrounding siblings growing/shrinking cannot drift it sideways.
    const Node* anchorNode = nullptr;
    for (const auto& widget : instance.centerWidgets) {
      if (widget != nullptr && widget->isAnchor() && widget->layoutBoundsNode() != nullptr) {
        anchorNode = widget->layoutBoundsNode();
        break;
      }
    }

    const float barMidline = contentMainStart + contentMainSpan * 0.5f;
    const float centerNaturalMain = isVertical ? instance.centerSection->height() : instance.centerSection->width();

    float centerSlotStart;
    float centerSlotMain;
    float centerSectionOffset; // offset of section origin within its slot along main axis
    if (anchorNode != nullptr) {
      const float anchorOffsetInSection = isVertical ? anchorNode->y() : anchorNode->x();
      const float anchorSpan = isVertical ? anchorNode->height() : anchorNode->width();
      const float anchorCenterInSection = anchorOffsetInSection + anchorSpan * 0.5f;
      // Place the section so that the anchor's center sits at barMidline.
      float desiredSectionStart = barMidline - anchorCenterInSection;
      // Clamp so the section stays within the content area.
      const float maxStart = contentMainEnd - centerNaturalMain;
      desiredSectionStart = std::clamp(desiredSectionStart, contentMainStart, std::max(contentMainStart, maxStart));
      centerSlotStart = desiredSectionStart;
      centerSlotMain = std::min(centerNaturalMain, contentMainEnd - centerSlotStart);
      centerSectionOffset = 0.0f;
    } else {
      centerSlotMain = std::min(contentMainSpan, centerNaturalMain);
      centerSlotStart = contentMainStart + std::max(0.0f, (contentMainSpan - centerSlotMain) * 0.5f);
      centerSectionOffset = (centerSlotMain - centerNaturalMain) * 0.5f;
    }
    const float centerSlotEnd = centerSlotStart + centerSlotMain;
    const float startSlotMain = std::max(0.0f, centerSlotStart - contentMainStart);
    const float endSlotMain = std::max(0.0f, contentMainEnd - centerSlotEnd);

    configureSlot(instance.startSlot, contentMainStart, startSlotMain);
    configureSlot(instance.centerSlot, centerSlotStart, centerSlotMain);
    configureSlot(instance.endSlot, centerSlotEnd, endSlotMain);

    if (isVertical) {
      instance.startSection->setPosition((slotCross - instance.startSection->width()) * 0.5f, 0.0f);
      instance.centerSection->setPosition((slotCross - instance.centerSection->width()) * 0.5f, centerSectionOffset);
      instance.endSection->setPosition((slotCross - instance.endSection->width()) * 0.5f,
                                       endSlotMain - instance.endSection->height());
    } else {
      instance.startSection->setPosition(0.0f, (slotCross - instance.startSection->height()) * 0.5f);
      instance.centerSection->setPosition(centerSectionOffset, (slotCross - instance.centerSection->height()) * 0.5f);
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
                     NetworkService* network, IdleInhibitor* idleInhibitor, MprisService* mpris,
                     PipeWireSpectrum* audioSpectrum, HttpClient* httpClient, WeatherService* weatherService,
                     RenderContext* renderContext, NightLightManager* nightLight,
                     noctalia::theme::ThemeService* themeService, BluetoothService* bluetooth,
                     BrightnessService* brightness, FileWatcher* fileWatcher) {
  m_wayland = &wayland;
  m_config = config;
  m_notifications = notifications;
  m_tray = tray;
  m_audio = audio;
  m_upower = upower;
  m_sysmon = sysmon;
  m_powerProfiles = powerProfiles;
  m_network = network;
  m_idleInhibitor = idleInhibitor;
  m_mpris = mpris;
  m_audioSpectrum = audioSpectrum;
  m_httpClient = httpClient;
  m_weatherService = weatherService;
  m_renderContext = renderContext;
  m_nightLight = nightLight;
  m_themeService = themeService;
  m_bluetooth = bluetooth;
  m_brightness = brightness;
  m_fileWatcher = fileWatcher;

  m_widgetFactory = std::make_unique<WidgetFactory>(
      *m_wayland, m_config->config(), m_notifications, m_tray, m_audio, m_upower, m_sysmon, m_powerProfiles, m_network,
      m_idleInhibitor, m_mpris, m_audioSpectrum, m_httpClient, m_weatherService, m_nightLight, m_themeService,
      m_bluetooth, m_brightness, m_fileWatcher);

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
  m_lastShadow = m_config->config().shell.shadow;
  m_config->addReloadCallback([this]() {
    const auto& cfg = m_config->config();
    if (cfg.bars == m_lastBars && cfg.widgets == m_lastWidgets && cfg.shell.shadow == m_lastShadow) {
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
  const auto previousShadow = m_lastShadow;
  m_lastBars = m_config->config().bars;
  m_lastWidgets = m_config->config().widgets;
  m_lastShadow = m_config->config().shell.shadow;
  m_widgetFactory = std::make_unique<WidgetFactory>(
      *m_wayland, m_config->config(), m_notifications, m_tray, m_audio, m_upower, m_sysmon, m_powerProfiles, m_network,
      m_idleInhibitor, m_mpris, m_audioSpectrum, m_httpClient, m_weatherService, m_nightLight, m_themeService,
      m_bluetooth, m_brightness, m_fileWatcher);

  // Look up new bar configs by name.
  std::unordered_map<std::string, std::pair<const BarConfig*, std::size_t>> newBarsByName;
  newBarsByName.reserve(m_lastBars.size());
  for (std::size_t i = 0; i < m_lastBars.size(); ++i) {
    newBarsByName[m_lastBars[i].name] = {&m_lastBars[i], i};
  }

  // For each existing instance, decide whether to rebuild contents in place
  // (surface preserved → no exclusive-zone churn) or destroy (will be recreated
  // by syncInstances below).
  bool destroyedAny = false;
  std::erase_if(m_instances, [&](const std::unique_ptr<BarInstance>& instUp) {
    auto& inst = *instUp;
    auto it = newBarsByName.find(inst.barConfig.name);
    auto destroy = [&]() {
      if (inst.surface != nullptr) {
        m_surfaceMap.erase(inst.surface->wlSurface());
      }
      if (m_hoveredInstance == &inst) {
        m_hoveredInstance = nullptr;
      }
      destroyedAny = true;
      return true;
    };
    if (it == newBarsByName.end()) {
      return destroy();
    }

    const auto& outputs = m_wayland->outputs();
    auto outIt =
        std::find_if(outputs.begin(), outputs.end(), [&inst](const auto& o) { return o.name == inst.outputName; });
    if (outIt == outputs.end()) {
      return destroy();
    }

    auto resolved = ConfigService::resolveForOutput(*it->second.first, *outIt);
    if (!resolved.enabled) {
      return destroy();
    }
    if (!barConfigSurfaceFieldsEqual(inst.barConfig, resolved, previousShadow, m_lastShadow)) {
      return destroy();
    }

    inst.barIndex = it->second.second;
    rebuildInstanceContents(inst, resolved);
    return false;
  });

  if (destroyedAny) {
    // Drain pending Wayland events for the just-destroyed surfaces before
    // creating new ones. Without this, the roundtrip inside LayerSurface::initialize
    // reads stale closures for dead proxies, which libwayland drops without freeing.
    wl_display_roundtrip(m_wayland->display());
  }

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

void Bar::requestLayout() {
  for (auto& inst : m_instances) {
    if (inst->surface != nullptr) {
      inst->surface->requestLayout();
    }
  }
}

void Bar::setAutoHideSuppressionCallback(std::function<bool()> callback) {
  m_autoHideSuppressionCallback = std::move(callback);
}

bool Bar::isRunning() const noexcept {
  if (m_forceHidden) {
    return true; // hidden but still alive — do not exit the main loop
  }
  return std::any_of(m_instances.begin(), m_instances.end(),
                     [](const auto& inst) { return inst->surface && inst->surface->isRunning(); });
}

std::optional<LayerPopupParentContext> Bar::popupParentContextForSurface(wl_surface* surface) const noexcept {
  auto* instance = instanceForSurface(surface);
  if (instance == nullptr || instance->surface == nullptr) {
    return std::nullopt;
  }

  auto* layerSurface = instance->surface->layerSurface();
  const auto width = instance->surface->width();
  const auto height = instance->surface->height();
  if (layerSurface == nullptr || width == 0 || height == 0) {
    return std::nullopt;
  }

  return LayerPopupParentContext{
      .surface = instance->surface->wlSurface(),
      .layerSurface = layerSurface,
      .output = instance->output,
      .width = width,
      .height = height,
  };
}

std::optional<LayerPopupParentContext> Bar::preferredPopupParentContext(wl_output* output) const noexcept {
  BarInstance* instance = instanceForOutput(output);
  if (instance == nullptr && !m_instances.empty()) {
    instance = m_instances.front().get();
  }
  return instance != nullptr && instance->surface != nullptr
             ? popupParentContextForSurface(instance->surface->wlSurface())
             : std::nullopt;
}

std::optional<AttachedPanelParentContext> Bar::attachedPanelParentContext(wl_output* output) const noexcept {
  BarInstance* instance = instanceForOutput(output);
  if (instance == nullptr) {
    for (const auto& candidate : m_instances) {
      if (candidate != nullptr && candidate->surface != nullptr && candidate->barConfig.position == "top") {
        instance = candidate.get();
        break;
      }
    }
  }
  if (instance == nullptr || instance->surface == nullptr || instance->barConfig.position != "top") {
    return std::nullopt;
  }

  const auto surfaceWidth = instance->surface->width();
  const auto surfaceHeight = instance->surface->height();
  if (instance->surface->wlSurface() == nullptr || surfaceWidth == 0 || surfaceHeight == 0) {
    return std::nullopt;
  }

  const auto bar = computeBarVisualGeometry(instance->barConfig, m_config->config().shell.shadow,
                                            static_cast<float>(surfaceWidth), static_cast<float>(surfaceHeight));
  if (bar.width <= 0.0f || bar.height <= 0.0f) {
    return std::nullopt;
  }

  return AttachedPanelParentContext{
      .parentSurface = instance->surface->wlSurface(),
      .output = instance->output,
      .barX = static_cast<std::int32_t>(std::lround(bar.x)),
      .barY = static_cast<std::int32_t>(std::lround(bar.y)),
      .barWidth = static_cast<std::int32_t>(std::lround(bar.width)),
      .barHeight = static_cast<std::int32_t>(std::lround(bar.height)),
      .parentWidth = surfaceWidth,
      .parentHeight = surfaceHeight,
  };
}

void Bar::setAttachedPanelGeometry(wl_output* output, std::optional<AttachedPanelGeometry> geometry) {
  BarInstance* instance = instanceForOutput(output);
  if (instance == nullptr) {
    return;
  }

  instance->attachedPanelGeometry = geometry;
  if (instance->surface != nullptr && instance->surface->width() > 0 && instance->surface->height() > 0) {
    buildScene(*instance, instance->surface->width(), instance->surface->height());
    instance->surface->requestRedraw();
  }
}

void Bar::beginAttachedPopup(wl_surface* surface) {
  auto* instance = instanceForSurface(surface);
  if (instance == nullptr) {
    return;
  }
  ++instance->attachedPopupCount;
}

void Bar::endAttachedPopup(wl_surface* surface) {
  auto* instance = instanceForSurface(surface);
  if (instance == nullptr) {
    return;
  }
  if (instance->attachedPopupCount > 0) {
    --instance->attachedPopupCount;
  }
  if (m_wayland != nullptr) {
    instance->pointerInside = (m_wayland->lastPointerSurface() == surface);
  }
  if (!instance->pointerInside && m_hoveredInstance == instance) {
    m_hoveredInstance = nullptr;
  } else if (instance->pointerInside) {
    m_hoveredInstance = instance;
  }
  if (instance->attachedPopupCount > 0 || !instance->barConfig.autoHide || instance->pointerInside) {
    return;
  }
  const bool suppressAutoHide = (m_autoHideSuppressionCallback != nullptr) ? m_autoHideSuppressionCallback() : false;
  if (!suppressAutoHide) {
    startHideFadeOut(*instance);
  }
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
            output.description, barConfig.thickness, barConfig.position);

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
  const auto sb = shell::surface_shadow::bleed(barConfig.shadow, m_config->config().shell.shadow);
  const bool reserveExclusiveZone = barConfig.reserveSpace;

  // Compositor margins absorb the visual gap where the shadow doesn't reach.
  // The surface is sized to cover only the bar rect plus its shadow footprint.
  std::int32_t mLeft = 0, mRight = 0, mTop = 0, mBottom = 0;
  std::uint32_t surfW = 0, surfH = 0;
  std::int32_t exclusiveZone = 0;

  if (!vertical) {
    mLeft = std::max(0, mH - sb.left);
    mRight = std::max(0, mH - sb.right);
    if (isBottom) {
      mBottom = std::max(0, mV - sb.down);
      surfH = static_cast<std::uint32_t>(sb.up + barConfig.thickness + std::min(mV, sb.down));
      exclusiveZone = reserveExclusiveZone ? (barConfig.thickness + std::min(mV, sb.down)) : 0;
    } else {
      mTop = std::max(0, mV - sb.up);
      surfH = static_cast<std::uint32_t>(std::min(mV, sb.up) + barConfig.thickness + sb.down);
      exclusiveZone = reserveExclusiveZone ? (std::min(mV, sb.up) + barConfig.thickness) : 0;
    }
  } else {
    mTop = std::max(0, mV - sb.up);
    mBottom = std::max(0, mV - sb.down);
    if (isRight) {
      mRight = std::max(0, mH - sb.right);
      surfW = static_cast<std::uint32_t>(sb.left + barConfig.thickness + std::min(mH, sb.right));
      exclusiveZone = reserveExclusiveZone ? (barConfig.thickness + std::min(mH, sb.right)) : 0;
    } else {
      mLeft = std::max(0, mH - sb.left);
      surfW = static_cast<std::uint32_t>(std::min(mH, sb.left) + barConfig.thickness + sb.right);
      exclusiveZone = reserveExclusiveZone ? (std::min(mH, sb.left) + barConfig.thickness) : 0;
    }
  }

  auto surfaceConfig = LayerSurfaceConfig{
      .nameSpace = "noctalia-" + barConfig.name,
      .layer = LayerShellLayer::Top,
      .anchor = anchor,
      .width = surfW,
      .height = surfH,
      .exclusiveZone = exclusiveZone,
      .marginTop = mTop,
      .marginRight = mRight,
      .marginBottom = mBottom,
      .marginLeft = mLeft,
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
  const auto& widgetConfigs = m_config->config().widgets;
  auto createWidgets = [&](const std::vector<std::string>& names, std::vector<std::unique_ptr<Widget>>& dest) {
    for (const auto& name : names) {
      auto widget = m_widgetFactory->create(name, instance.output, instance.barConfig.scale);
      if (widget != nullptr) {
        const WidgetConfig* wcPtr = nullptr;
        if (auto it = widgetConfigs.find(name); it != widgetConfigs.end()) {
          wcPtr = &it->second;
          widget->setAnchor(wcPtr->getBool("anchor", false));
        }
        widget->setBarCapsuleSpec(resolveWidgetBarCapsuleSpec(instance.barConfig, wcPtr));
        if (wcPtr != nullptr && wcPtr->hasSetting("color")) {
          widget->setWidgetForeground(themeColorFromConfigString(wcPtr->getString("color", "")));
        } else if (instance.barConfig.widgetColor.has_value()) {
          widget->setWidgetForeground(*instance.barConfig.widgetColor);
        }
        dest.push_back(std::move(widget));
      }
    }
  };

  createWidgets(instance.barConfig.startWidgets, instance.startWidgets);
  createWidgets(instance.barConfig.centerWidgets, instance.centerWidgets);
  createWidgets(instance.barConfig.endWidgets, instance.endWidgets);
}

void Bar::attachWidgetsToSections(BarInstance& instance) {
  auto attach = [&](std::vector<std::unique_ptr<Widget>>& widgets, Flex* section) {
    if (section == nullptr) {
      return;
    }
    for (auto& widget : widgets) {
      widget->setAnimationManager(&instance.animations);
      widget->setUpdateCallback([surface = instance.surface.get()]() {
        if (surface != nullptr) {
          surface->requestUpdate();
        }
      });
      widget->setRedrawCallback([surface = instance.surface.get()]() {
        if (surface != nullptr) {
          surface->requestRedraw();
        }
      });
      widget->create();
      if (widget->root() == nullptr) {
        continue;
      }
      if (widget->barCapsuleSpec().enabled) {
        const auto& cap = widget->barCapsuleSpec();
        auto shell = std::make_unique<Node>();
        Node* shellPtr = shell.get();
        auto capsuleBg = std::make_unique<Box>();
        Box* bgPtr = capsuleBg.get();
        capsuleBg->setFill(withOpacity(cap.fill, cap.opacity));
        const float scale = widget->contentScale();
        if (cap.border.has_value()) {
          capsuleBg->setBorder(*cap.border, Style::borderWidth * scale);
        } else {
          capsuleBg->clearBorder();
        }
        capsuleBg->setZIndex(-1);
        shellPtr->addChild(std::move(capsuleBg));
        shellPtr->addChild(widget->releaseRoot());
        widget->setBarCapsuleScene(shellPtr, bgPtr);
        section->addChild(std::move(shell));
      } else {
        widget->setBarCapsuleScene(nullptr, nullptr);
        section->addChild(widget->releaseRoot());
      }
    }
  };

  attach(instance.startWidgets, instance.startSection);
  attach(instance.centerWidgets, instance.centerSection);
  attach(instance.endWidgets, instance.endSection);
}

void Bar::rebuildInstanceContents(BarInstance& instance, const BarConfig& newConfig) {
  // Drop any pointer hover/capture state pointing into the widgets we're about
  // to destroy. Hover will be re-acquired on the next pointer motion.
  instance.inputDispatcher.pointerLeave();

  instance.barConfig = newConfig;

  // Detach old widget root nodes from their sections and destroy the widgets.
  // Widgets release their root into the section on creation, so the section
  // owns those nodes — clearing the section frees the scene tree.
  auto clearChildren = [](Node* node) {
    if (node == nullptr) {
      return;
    }
    while (!node->children().empty()) {
      node->removeChild(node->children().back().get());
    }
  };
  clearChildren(instance.startSection);
  clearChildren(instance.centerSection);
  clearChildren(instance.endSection);
  instance.startWidgets.clear();
  instance.centerWidgets.clear();
  instance.endWidgets.clear();

  // Refresh section-level layout knobs that may have changed (gap; direction
  // doesn't change because position is part of the surface-fields gate).
  const float widgetSpacing = static_cast<float>(instance.barConfig.widgetSpacing);
  if (instance.startSection != nullptr) {
    instance.startSection->setGap(widgetSpacing);
  }
  if (instance.centerSection != nullptr) {
    instance.centerSection->setGap(widgetSpacing);
  }
  if (instance.endSection != nullptr) {
    instance.endSection->setGap(widgetSpacing);
  }

  populateWidgets(instance);
  attachWidgetsToSections(instance);

  applyBackgroundPalette(instance);
  applyBarCompositorBlur(instance);

  if (instance.surface != nullptr) {
    // Re-run buildScene at the current surface size so radii / styling pick
    // up changes. The first-frame branch is skipped because sceneRoot is
    // already in place.
    const auto w = instance.surface->width();
    const auto h = instance.surface->height();
    if (w > 0 && h > 0) {
      buildScene(instance, w, h);
    }
    instance.surface->requestLayout();
  }
}

void Bar::tickWidgets(std::vector<std::unique_ptr<Widget>>& widgets, float deltaMs) { ::tickWidgets(widgets, deltaMs); }

bool Bar::widgetsNeedFrameTick(const std::vector<std::unique_ptr<Widget>>& widgets) {
  return ::widgetsNeedFrameTick(widgets);
}

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

void Bar::syncBarSlideLayerTransform(BarInstance& instance) const {
  if (instance.slideRoot == nullptr) {
    return;
  }
  if (instance.barConfig.autoHide) {
    const float t = 1.0f - instance.hideOpacity;
    instance.slideRoot->setPosition(instance.slideHiddenDx * t, instance.slideHiddenDy * t);
  } else {
    instance.slideRoot->setPosition(0.0f, 0.0f);
  }
}

void Bar::applyBarCompositorBlur(BarInstance& instance) const {
  if (instance.surface == nullptr) {
    return;
  }
  if (!instance.barConfig.backgroundBlur) {
    instance.surface->clearBlurRegion();
    return;
  }

  constexpr float kBlurVisibleOpacity = 0.02f;
  if (instance.barConfig.autoHide && instance.hideOpacity < kBlurVisibleOpacity) {
    instance.surface->clearBlurRegion();
    return;
  }

  if (instance.bg == nullptr) {
    return;
  }
  float absX = 0.0f;
  float absY = 0.0f;
  Node::absolutePosition(instance.bg, absX, absY);
  const int px = static_cast<int>(std::lround(absX + 1.0f));
  const int py = static_cast<int>(std::lround(absY + 1.0f));
  const int pw = static_cast<int>(std::lround(std::max(0.0f, instance.bg->width() - 2.0f)));
  const int ph = static_cast<int>(std::lround(std::max(0.0f, instance.bg->height() - 2.0f)));
  auto blurStrips = Surface::tessellateRoundedRect(px, py, pw, ph, static_cast<float>(instance.barConfig.radiusTopLeft),
                                                   static_cast<float>(instance.barConfig.radiusTopRight),
                                                   static_cast<float>(instance.barConfig.radiusBottomRight),
                                                   static_cast<float>(instance.barConfig.radiusBottomLeft));
  instance.surface->setBlurRegion(blurStrips);
}

void Bar::startHideFadeOut(BarInstance& instance) {
  const float current = instance.hideOpacity;
  instance.animations.animate(
      current, 0.0f, Style::animSlow, Easing::EaseInQuad,
      [this, inst = &instance](float v) {
        inst->hideOpacity = v;
        syncBarSlideLayerTransform(*inst);
        applyBarCompositorBlur(*inst);
      },
      [this, inst = &instance]() {
        if (inst->surface == nullptr) {
          return;
        }
        const bool isVertical = (inst->barConfig.position == "left" || inst->barConfig.position == "right");
        const bool isBottom = inst->barConfig.position == "bottom";
        const int surfW = static_cast<int>(inst->surface->width());
        const int surfH = static_cast<int>(inst->surface->height());
        if (!isVertical) {
          const int triggerY = isBottom ? std::max(0, surfH - kAutoHideTriggerPx) : 0;
          inst->surface->setInputRegion({InputRect{0, triggerY, surfW, kAutoHideTriggerPx}});
        } else if (inst->barConfig.position == "left") {
          inst->surface->setInputRegion(
              {InputRect{std::max(0, surfW - kAutoHideTriggerPx), 0, kAutoHideTriggerPx, surfH}});
        } else {
          inst->surface->setInputRegion({InputRect{0, 0, kAutoHideTriggerPx, surfH}});
        }
      });
  if (instance.surface != nullptr) {
    instance.surface->requestRedraw();
  }
}

void Bar::buildScene(BarInstance& instance, std::uint32_t width, std::uint32_t height) {
  uiAssertNotRendering("Bar::buildScene");
  if (m_renderContext == nullptr) {
    return;
  }
  auto* renderer = m_renderContext;

  const auto w = static_cast<float>(width);
  const auto h = static_cast<float>(height);
  const float padding = static_cast<float>(instance.barConfig.padding);
  const float widgetSpacing = static_cast<float>(instance.barConfig.widgetSpacing);
  const auto& shadowConfig = m_config->config().shell.shadow;
  const float shadowSize = shell::surface_shadow::enabled(instance.barConfig.shadow, shadowConfig)
                               ? static_cast<float>(shadowConfig.blur)
                               : 0.0f;
  const float shadowOffsetX = static_cast<float>(shadowConfig.offsetX);
  const float shadowOffsetY = static_cast<float>(shadowConfig.offsetY);
  const bool isBottom = instance.barConfig.position == "bottom";
  const bool isRight = instance.barConfig.position == "right";
  const bool isVertical = (instance.barConfig.position == "left" || instance.barConfig.position == "right");
  const Radii barRadii{
      static_cast<float>(instance.barConfig.radiusTopLeft),
      static_cast<float>(instance.barConfig.radiusTopRight),
      static_cast<float>(instance.barConfig.radiusBottomRight),
      static_cast<float>(instance.barConfig.radiusBottomLeft),
  };

  const auto barVisual = computeBarVisualGeometry(instance.barConfig, shadowConfig, w, h);
  const float barAreaX = barVisual.x;
  const float barAreaY = barVisual.y;
  const float barAreaW = barVisual.width;
  const float barAreaH = barVisual.height;

  if (instance.sceneRoot == nullptr) {
    instance.sceneRoot = std::make_unique<Node>();
    instance.sceneRoot->setAnimationManager(&instance.animations);
    instance.sceneRoot->setSize(w, h);

    auto slide = std::make_unique<Node>();
    slide->setParticipatesInLayout(false);
    instance.slideRoot = instance.sceneRoot->addChild(std::move(slide));

    // Bar background
    auto bg = std::make_unique<RectNode>();
    instance.bg = static_cast<RectNode*>(instance.slideRoot->addChild(std::move(bg)));

    // Shadow — bar shape copy rendered with large SDF softness to simulate a blurred drop shadow.
    if (shadowSize > 0.0f) {
      auto shadow = std::make_unique<RectNode>();
      instance.shadow = static_cast<RectNode*>(instance.slideRoot->addChild(std::move(shadow)));

      auto leftClip = std::make_unique<Node>();
      leftClip->setClipChildren(true);
      leftClip->setZIndex(-1);
      instance.shadowLeftClip = instance.slideRoot->addChild(std::move(leftClip));
      auto leftShadow = std::make_unique<RectNode>();
      instance.shadowLeft = static_cast<RectNode*>(instance.shadowLeftClip->addChild(std::move(leftShadow)));

      auto rightClip = std::make_unique<Node>();
      rightClip->setClipChildren(true);
      rightClip->setZIndex(-1);
      instance.shadowRightClip = instance.slideRoot->addChild(std::move(rightClip));
      auto rightShadow = std::make_unique<RectNode>();
      instance.shadowRight = static_cast<RectNode*>(instance.shadowRightClip->addChild(std::move(rightShadow)));
    }
    // Note: shadow is inserted before bar sections so it renders below them (z=-1 is set below).

    auto contentClip = std::make_unique<Node>();
    contentClip->setClipChildren(true);
    instance.contentClip = instance.slideRoot->addChild(std::move(contentClip));

    auto makeSlot = [&instance]() {
      auto slot = std::make_unique<Node>();
      slot->setClipChildren(true);
      return instance.contentClip->addChild(std::move(slot));
    };
    instance.startSlot = makeSlot();
    instance.centerSlot = makeSlot();
    instance.endSlot = makeSlot();

    // Create section boxes
    auto makeSection = [widgetSpacing, isVertical]() {
      auto box = std::make_unique<Flex>();
      box->setDirection(isVertical ? FlexDirection::Vertical : FlexDirection::Horizontal);
      box->setGap(widgetSpacing);
      box->setAlign(FlexAlign::Center);
      return box;
    };

    instance.startSection = static_cast<Flex*>(instance.startSlot->addChild(makeSection()));
    instance.centerSection = static_cast<Flex*>(instance.centerSlot->addChild(makeSection()));
    instance.endSection = static_cast<Flex*>(instance.endSlot->addChild(makeSection()));

    attachWidgetsToSections(instance);

    // Wire up InputDispatcher for this instance
    instance.inputDispatcher.setSceneRoot(instance.sceneRoot.get());
    instance.inputDispatcher.setCursorShapeCallback(
        [this](std::uint32_t serial, std::uint32_t shape) { m_wayland->setCursorShape(serial, shape); });

    if (instance.barConfig.autoHide) {
      instance.slideRoot->setOpacity(1.0f);
      instance.hideOpacity = 0.0f;
    } else {
      instance.slideRoot->setOpacity(0.0f);
      instance.hideOpacity = 1.0f;
      instance.animations.animate(
          0.0f, 1.0f, Style::animSlow, Easing::EaseOutCubic,
          [slide = instance.slideRoot](float v) { slide->setOpacity(v); }, {}, instance.slideRoot);
    }

    instance.surface->setSceneRoot(instance.sceneRoot.get());
  }

  // Update root size on reconfigure
  instance.sceneRoot->setSize(w, h);
  if (instance.slideRoot != nullptr) {
    instance.slideRoot->setSize(w, h);
  }

  // Background covers only the bar visual area (not the shadow extension).
  // Keep it exactly aligned with the shadow shape; the shadow shader now
  // draws only outside the rect, so any size mismatch is visible at corners.
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
    instance.bg->setPosition(barAreaX, barAreaY);
    instance.bg->setSize(barAreaW, barAreaH);
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
    const float bgOpacity = std::clamp(instance.barConfig.backgroundOpacity, 0.0f, 1.0f);
    const float shadowX = barAreaX + shadowOffsetX;
    const float shadowY = barAreaY + shadowOffsetY;
    RoundedRectStyle shadowStyle =
        shell::surface_shadow::style(shadowConfig, bgOpacity, shell::surface_shadow::Shape{.radius = barRadii});
    const bool panelShadowExclusion = !isVertical && !isBottom && instance.attachedPanelGeometry.has_value() &&
                                      instance.attachedPanelGeometry->width > 0.0f &&
                                      instance.attachedPanelGeometry->height > 0.0f;
    if (panelShadowExclusion) {
      const auto& attached = *instance.attachedPanelGeometry;
      const float radius = std::max(0.0f, attached.cornerRadius);
      shadowStyle.shadowExclusion = true;
      shadowStyle.shadowExclusionOffsetX = shadowX - attached.x;
      shadowStyle.shadowExclusionOffsetY = shadowY - attached.y;
      shadowStyle.shadowExclusionWidth = attached.width;
      shadowStyle.shadowExclusionHeight = attached.height;
      shadowStyle.shadowExclusionCorners = attachedPanelCornerShapes();
      shadowStyle.shadowExclusionLogicalInset = attachedPanelLogicalInset(radius);
      shadowStyle.shadowExclusionRadius = Radii{radius, radius, radius, radius};
    }

    auto configureShadow = [&](RectNode* node, float x, float y) {
      if (node == nullptr) {
        return;
      }
      node->setStyle(shadowStyle);
      node->setZIndex(-1);
      node->setPosition(x, y);
      node->setSize(barAreaW, barAreaH);
    };

    instance.shadow->setVisible(true);
    configureShadow(instance.shadow, shadowX, shadowY);

    if (instance.shadowLeftClip != nullptr) {
      instance.shadowLeftClip->setVisible(false);
    }
    if (instance.shadowRightClip != nullptr) {
      instance.shadowRightClip->setVisible(false);
    }
  }

  layoutBarSections(instance, *renderer, barAreaW, barAreaH, padding, isVertical);

  if (instance.barConfig.autoHide) {
    float contentLeft = barAreaX;
    float contentTop = barAreaY;
    float contentRight = barAreaX + barAreaW;
    float contentBottom = barAreaY + barAreaH;
    if (instance.shadow != nullptr) {
      const float sx = barAreaX + shadowOffsetX;
      const float sy = barAreaY + shadowOffsetY;
      contentLeft = std::min(contentLeft, sx);
      contentTop = std::min(contentTop, sy);
      contentRight = std::max(contentRight, sx + barAreaW);
      contentBottom = std::max(contentBottom, sy + barAreaH);
    }
    const auto hiddenDelta = computeAutoHideHiddenDelta(isVertical, isBottom, isRight, w, h, contentLeft, contentTop,
                                                        contentRight, contentBottom);
    instance.slideHiddenDx = hiddenDelta.first;
    instance.slideHiddenDy = hiddenDelta.second;
  } else {
    instance.slideHiddenDx = 0.0f;
    instance.slideHiddenDy = 0.0f;
  }
  syncBarSlideLayerTransform(instance);

  const InputRect barRect{
      static_cast<int>(barAreaX),
      static_cast<int>(barAreaY),
      static_cast<int>(barAreaW),
      static_cast<int>(barAreaH),
  };
  if (instance.barConfig.autoHide && instance.hideOpacity < 0.5f) {
    const int surfW = static_cast<int>(w);
    const int surfH = static_cast<int>(h);
    if (!isVertical) {
      const int triggerY = isBottom ? std::max(0, surfH - kAutoHideTriggerPx) : 0;
      instance.surface->setInputRegion({InputRect{0, triggerY, surfW, kAutoHideTriggerPx}});
    } else if (instance.barConfig.position == "left") {
      instance.surface->setInputRegion(
          {InputRect{std::max(0, surfW - kAutoHideTriggerPx), 0, kAutoHideTriggerPx, surfH}});
    } else {
      instance.surface->setInputRegion({InputRect{0, 0, kAutoHideTriggerPx, surfH}});
    }
  } else {
    instance.surface->setInputRegion({barRect});
  }
  applyBarCompositorBlur(instance);
}

void Bar::updateWidgets(BarInstance& instance) {
  if (m_renderContext == nullptr) {
    return;
  }
  auto* renderer = m_renderContext;

  const auto w = static_cast<float>(instance.surface->width());
  const auto h = static_cast<float>(instance.surface->height());
  const float padding = static_cast<float>(instance.barConfig.padding);
  const float barThickness = static_cast<float>(instance.barConfig.thickness);
  const float marginH = static_cast<float>(instance.barConfig.marginH);
  const float marginV = static_cast<float>(instance.barConfig.marginV);
  const bool isVertical = (instance.barConfig.position == "left" || instance.barConfig.position == "right");
  const auto sbi = shell::surface_shadow::bleed(instance.barConfig.shadow, m_config->config().shell.shadow);
  const float bleedLeft = static_cast<float>(sbi.left);
  const float bleedRight = static_cast<float>(sbi.right);
  const float bleedUp = static_cast<float>(sbi.up);
  const float bleedDown = static_cast<float>(sbi.down);
  float barAreaW, barAreaH;
  if (isVertical) {
    const float barAreaY = std::min(marginV, bleedUp);
    barAreaW = barThickness;
    barAreaH = h - barAreaY - std::min(marginV, bleedDown);
  } else {
    const float barAreaX = std::min(marginH, bleedLeft);
    barAreaW = w - barAreaX - std::min(marginH, bleedRight);
    barAreaH = barThickness;
  }

  auto updateSection = [&](std::vector<std::unique_ptr<Widget>>& widgets) {
    for (auto& widget : widgets) {
      if (widget->root() == nullptr) {
        continue;
      }
      widget->update(*renderer);
      widget->layout(*renderer, barAreaW, barAreaH);
    }
  };

  updateSection(instance.startWidgets);
  updateSection(instance.centerWidgets);
  updateSection(instance.endWidgets);
  layoutBarSections(instance, *renderer, barAreaW, barAreaH, padding, isVertical);
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
  const float padding = static_cast<float>(instance.barConfig.padding);
  const float barThickness = static_cast<float>(instance.barConfig.thickness);
  const float marginH = static_cast<float>(instance.barConfig.marginH);
  const float marginV = static_cast<float>(instance.barConfig.marginV);
  const bool isVertical = (instance.barConfig.position == "left" || instance.barConfig.position == "right");
  const auto sbi = shell::surface_shadow::bleed(instance.barConfig.shadow, m_config->config().shell.shadow);
  const float bleedLeft = static_cast<float>(sbi.left);
  const float bleedRight = static_cast<float>(sbi.right);
  const float bleedUp = static_cast<float>(sbi.up);
  const float bleedDown = static_cast<float>(sbi.down);
  float barAreaW = 0.0f;
  float barAreaH = 0.0f;
  if (isVertical) {
    const float barAreaY = std::min(marginV, bleedUp);
    barAreaW = barThickness;
    barAreaH = h - barAreaY - std::min(marginV, bleedDown);
  } else {
    const float barAreaX = std::min(marginH, bleedLeft);
    barAreaW = w - barAreaX - std::min(marginH, bleedRight);
    barAreaH = barThickness;
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
    layoutBarSections(instance, *m_renderContext, barAreaW, barAreaH, padding, isVertical);
  }
}

bool Bar::onPointerEvent(const PointerEvent& event) {
  bool consumed = false;
  BarInstance* targetInstance = nullptr;
  if (event.surface != nullptr) {
    targetInstance = instanceForSurface(event.surface);
  } else {
    targetInstance = m_hoveredInstance;
  }

  if (targetInstance != nullptr && targetInstance->attachedPopupCount > 0) {
    switch (event.type) {
    case PointerEvent::Type::Enter:
      m_hoveredInstance = targetInstance;
      targetInstance->pointerInside = true;
      break;
    case PointerEvent::Type::Leave:
      targetInstance->pointerInside = false;
      if (m_hoveredInstance == targetInstance) {
        m_hoveredInstance = nullptr;
      }
      break;
    case PointerEvent::Type::Motion:
    case PointerEvent::Type::Button:
    case PointerEvent::Type::Axis:
      break;
    }
    return false;
  }

  switch (event.type) {
  case PointerEvent::Type::Enter: {
    auto it = m_surfaceMap.find(event.surface);
    if (it == m_surfaceMap.end()) {
      break;
    }
    m_hoveredInstance = it->second;
    m_hoveredInstance->pointerInside = true;
    m_hoveredInstance->inputDispatcher.pointerEnter(static_cast<float>(event.sx), static_cast<float>(event.sy),
                                                    event.serial);
    if (m_hoveredInstance->barConfig.autoHide && m_hoveredInstance->sceneRoot != nullptr) {
      const float current = m_hoveredInstance->hideOpacity;
      m_hoveredInstance->animations.animate(current, 1.0f, Style::animNormal, Easing::EaseOutCubic,
                                            [inst = m_hoveredInstance, this](float v) {
                                              inst->hideOpacity = v;
                                              syncBarSlideLayerTransform(*inst);
                                              applyBarCompositorBlur(*inst);
                                            });
      if (m_hoveredInstance->surface != nullptr) {
        const int sw = static_cast<int>(m_hoveredInstance->surface->width());
        const int sh = static_cast<int>(m_hoveredInstance->surface->height());
        m_hoveredInstance->surface->setInputRegion({InputRect{0, 0, sw, sh}});
      }
      m_hoveredInstance->surface->requestRedraw();
    }
    break;
  }
  case PointerEvent::Type::Leave: {
    if (m_hoveredInstance != nullptr) {
      m_hoveredInstance->pointerInside = false;
      m_hoveredInstance->inputDispatcher.pointerLeave();
      const bool suppressAutoHide =
          (m_autoHideSuppressionCallback != nullptr) ? m_autoHideSuppressionCallback() : false;
      if (m_hoveredInstance->barConfig.autoHide && !suppressAutoHide) {
        startHideFadeOut(*m_hoveredInstance);
      }
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
  case PointerEvent::Type::Axis: {
    if (m_hoveredInstance == nullptr)
      break;
    m_hoveredInstance->inputDispatcher.pointerAxis(static_cast<float>(event.sx), static_cast<float>(event.sy),
                                                   event.axis, event.axisSource, event.axisValue, event.axisDiscrete,
                                                   event.axisValue120, event.axisLines);
    break;
  }
  }

  // Trigger redraw if any widget changed visual state
  if (m_hoveredInstance != nullptr && m_hoveredInstance->sceneRoot != nullptr &&
      (m_hoveredInstance->sceneRoot->paintDirty() || m_hoveredInstance->sceneRoot->layoutDirty())) {
    if (m_hoveredInstance->sceneRoot->layoutDirty()) {
      m_hoveredInstance->surface->requestLayout();
    } else {
      m_hoveredInstance->surface->requestRedraw();
    }
  }

  return consumed;
}

BarInstance* Bar::instanceForSurface(wl_surface* surface) const noexcept {
  if (surface == nullptr) {
    return nullptr;
  }
  const auto it = m_surfaceMap.find(surface);
  return it != m_surfaceMap.end() ? it->second : nullptr;
}

BarInstance* Bar::instanceForOutput(wl_output* output) const noexcept {
  if (output == nullptr) {
    return nullptr;
  }

  for (const auto& instance : m_instances) {
    if (instance != nullptr && instance->output == output && instance->surface != nullptr) {
      return instance.get();
    }
  }
  return nullptr;
}

void Bar::registerIpc(IpcService& ipc) {
  ipc.registerHandler(
      "bar-show",
      [this](const std::string&) -> std::string {
        show();
        return "ok\n";
      },
      "bar-show", "Show the bar");

  ipc.registerHandler(
      "bar-hide",
      [this](const std::string&) -> std::string {
        hide();
        return "ok\n";
      },
      "bar-hide", "Hide the bar");

  ipc.registerHandler(
      "bar-toggle",
      [this](const std::string&) -> std::string {
        isVisible() ? hide() : show();
        return "ok\n";
      },
      "bar-toggle", "Toggle bar visibility");
}
