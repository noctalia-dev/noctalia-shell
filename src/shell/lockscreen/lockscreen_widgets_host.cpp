#include "shell/lockscreen/lockscreen_widgets_host.h"

#include "config/config_service.h"
#include "core/log.h"
#include "pipewire/pipewire_spectrum.h"
#include "render/render_context.h"
#include "render/scene/node.h"
#include "shell/desktop/desktop_widget_layout.h"
#include "shell/lockscreen/lock_screen.h"
#include "shell/lockscreen/lock_surface.h"
#include "shell/lockscreen/lockscreen_login_box.h"
#include "time/time_format.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <string>

namespace {

  constexpr Logger kLog("lockscreen");

  DesktopWidgetState* findStateById(LockscreenWidgetsSnapshot& snapshot, const std::string& id) {
    for (auto& widget : snapshot.widgets) {
      if (widget.id == id) {
        return &widget;
      }
    }
    return nullptr;
  }

} // namespace

void LockscreenWidgetsHost::initialize(
    WaylandConnection& wayland, ConfigService* config, PipeWireSpectrum* pipewireSpectrum,
    const WeatherService* weather, RenderContext* renderContext, MprisService* mpris, HttpClient* httpClient,
    SystemMonitorService* sysmon
) {
  m_wayland = &wayland;
  m_config = config;
  m_renderContext = renderContext;
  m_factory = std::make_unique<DesktopWidgetFactory>(pipewireSpectrum, weather, mpris, httpClient, sysmon);
}

void LockscreenWidgetsHost::show(const LockscreenWidgetsSnapshot& snapshot, LockScreen& lockScreen) {
  m_snapshot = snapshot;
  m_visible = true;
  syncSurfaces(lockScreen);
}

void LockscreenWidgetsHost::hide() {
  for (auto& instance : m_instances) {
    if (instance->widget != nullptr) {
      instance->widget->setFrameTickRequestCallback(nullptr);
      instance->widget->setUpdateCallback(nullptr);
      instance->widget->setLayoutCallback(nullptr);
      instance->widget->setRedrawCallback(nullptr);
    }
    detachFromSurface(*instance);
  }
  m_visible = false;
  m_instances.clear();
}

void LockscreenWidgetsHost::rebuild(const LockscreenWidgetsSnapshot& snapshot, LockScreen& lockScreen) {
  m_snapshot = snapshot;
  if (!m_visible) {
    return;
  }
  syncSurfaces(lockScreen);
}

void LockscreenWidgetsHost::onOutputChange(LockScreen& lockScreen) {
  if (!m_visible) {
    return;
  }
  syncSurfaces(lockScreen);
}

void LockscreenWidgetsHost::onSecondTick() {
  if (!m_visible) {
    return;
  }

  const bool minuteBoundary = formatLocalTime("{:%S}") == "00";
  for (auto& instance : m_instances) {
    if (instance->surface == nullptr || instance->widget == nullptr) {
      continue;
    }
    if (instance->widget->wantsSecondTicks() || minuteBoundary) {
      instance->surface->requestUpdate();
    }
  }
}

LockscreenWidgetsHost::WidgetInstance* LockscreenWidgetsHost::findInstance(const std::string& id) {
  for (auto& instance : m_instances) {
    if (instance->state.id == id) {
      return instance.get();
    }
  }
  return nullptr;
}

LockSurface* LockscreenWidgetsHost::findSurfaceForOutput(LockScreen& lockScreen, const std::string& outputKey) const {
  LockSurface* found = nullptr;
  lockScreen.forEachSurface([&](LockSurface& surface) {
    if (found != nullptr || m_wayland == nullptr) {
      return;
    }
    const WaylandOutput* output = m_wayland->findOutputByWl(surface.output());
    if (output == nullptr) {
      return;
    }
    if (desktop_widgets::outputKey(*output) == outputKey) {
      found = &surface;
    }
  });
  return found;
}

void LockscreenWidgetsHost::syncSurfaces(LockScreen& lockScreen) {
  if (!m_visible || m_wayland == nullptr || m_renderContext == nullptr || m_factory == nullptr) {
    return;
  }

  std::erase_if(m_instances, [this](std::unique_ptr<WidgetInstance>& instance) {
    const DesktopWidgetState* state = findStateById(m_snapshot, instance->state.id);
    if (state == nullptr || !state->enabled) {
      detachFromSurface(*instance);
      return true;
    }
    return instance->surface == nullptr;
  });

  for (const auto& state : m_snapshot.widgets) {
    if (!state.enabled || lockscreen_login_box::isLoginBoxWidget(state)) {
      continue;
    }

    const WaylandOutput* output = desktop_widgets::resolveStateOutput(*m_wayland, state);
    if (output == nullptr) {
      std::erase_if(m_instances, [this, &state](std::unique_ptr<WidgetInstance>& instance) {
        if (instance->state.id == state.id) {
          detachFromSurface(*instance);
          return true;
        }
        return false;
      });
      continue;
    }

    const std::string outputKey = desktop_widgets::outputKey(*output);
    LockSurface* surface = findSurfaceForOutput(lockScreen, outputKey);
    if (surface == nullptr) {
      std::erase_if(m_instances, [this, &state](std::unique_ptr<WidgetInstance>& instance) {
        if (instance->state.id == state.id) {
          detachFromSurface(*instance);
          return true;
        }
        return false;
      });
      continue;
    }

    WidgetInstance* existing = findInstance(state.id);
    if (existing == nullptr) {
      createInstance(state, *surface, *output);
      continue;
    }

    const bool widgetDefinitionChanged = existing->state.type != state.type
        || existing->state.settings != state.settings
        || existing->surface != surface;

    if (widgetDefinitionChanged) {
      detachFromSurface(*existing);
      std::erase_if(m_instances, [this, &state](std::unique_ptr<WidgetInstance>& instance) {
        detachFromSurface(*instance);
        return instance->state.id == state.id;
      });
      createInstance(state, *surface, *output);
      continue;
    }

    if (!(existing->state == state)) {
      existing->state = state;
      if (existing->surface != nullptr) {
        existing->surface->requestLayout();
      }
    }
  }

  updateBuiltinClockVisibility(lockScreen);

  lockScreen.forEachSurface([&](LockSurface& surface) { surface.setWidgetsHost(this); });
}

void LockscreenWidgetsHost::createInstance(
    const DesktopWidgetState& state, LockSurface& surface, const WaylandOutput& output
) {
  if (m_factory == nullptr || m_renderContext == nullptr) {
    return;
  }

  const float baseUiScale = m_config != nullptr ? m_config->config().shell.uiScale : 1.0f;
  auto widget = m_factory->create(state.type, state.settings, desktop_widgets::widgetContentScale(baseUiScale, state));
  if (widget == nullptr) {
    return;
  }

  widget->create();
  widget->update(*m_renderContext);
  widget->layout(*m_renderContext);

  const float intrinsicWidth = std::max(1.0f, widget->intrinsicWidth());
  const float intrinsicHeight = std::max(1.0f, widget->intrinsicHeight());

  DesktopWidgetState clampedState = state;
  desktop_widgets::clampStateToOutput(*m_wayland, clampedState, intrinsicWidth, intrinsicHeight);

  auto instance = std::make_unique<WidgetInstance>();
  instance->state = clampedState;
  instance->surface = &surface;
  instance->widget = std::move(widget);
  instance->intrinsicWidth = intrinsicWidth;
  instance->intrinsicHeight = intrinsicHeight;

  auto* rawInstance = instance.get();
  instance->widget->setAnimationManager(&instance->animations);
  instance->widget->setUpdateCallback([rawInstance]() {
    if (rawInstance->surface != nullptr) {
      rawInstance->surface->requestUpdateOnly();
    }
  });
  instance->widget->setLayoutCallback([rawInstance]() {
    if (rawInstance->surface != nullptr) {
      rawInstance->surface->requestUpdate();
    }
  });
  instance->widget->setRedrawCallback([rawInstance]() {
    if (rawInstance->surface != nullptr) {
      rawInstance->surface->requestRedraw();
    }
  });
  instance->widget->setFrameTickRequestCallback([rawInstance]() {
    if (rawInstance->surface != nullptr) {
      rawInstance->surface->requestFrameTick();
    }
  });

  attachToSurface(*instance);
  m_instances.push_back(std::move(instance));
  (void)output;
}

void LockscreenWidgetsHost::attachToSurface(WidgetInstance& instance) {
  if (instance.surface == nullptr || instance.widget == nullptr) {
    return;
  }

  Node* layer = instance.surface->widgetLayer();
  if (layer == nullptr) {
    return;
  }

  auto transformNode = std::make_unique<Node>();
  transformNode->setAnimationManager(&instance.animations);
  instance.transformNode = layer->addChild(std::move(transformNode));
  instance.transformNode->addChild(instance.widget->releaseRoot());

  auto* surfacePtr = instance.surface;
  auto* host = this;
  surfacePtr->setFrameTickCallback([host, surfacePtr](float deltaMs) {
    if (host->m_renderContext == nullptr) {
      return;
    }
    host->m_renderContext->makeCurrent(surfacePtr->renderTarget());
    for (auto& inst : host->m_instances) {
      if (inst->surface != surfacePtr || inst->widget == nullptr || !inst->widget->needsFrameTick()) {
        continue;
      }
      inst->widget->onFrameTick(deltaMs, *host->m_renderContext);
    }
  });

  surfacePtr->requestLayout();
}

void LockscreenWidgetsHost::detachFromSurface(WidgetInstance& instance) {
  LockSurface* surface = instance.surface;

  if (instance.transformNode != nullptr && surface != nullptr) {
    if (Node* layer = surface->widgetLayer(); layer != nullptr) {
      (void)layer->removeChild(instance.transformNode);
    }
    instance.transformNode = nullptr;
  }
  instance.surface = nullptr;

  if (surface != nullptr) {
    const bool surfaceInUse = std::any_of(m_instances.begin(), m_instances.end(), [&](const auto& other) {
      return other.get() != &instance && other->surface == surface;
    });
    if (!surfaceInUse) {
      surface->setFrameTickCallback(nullptr);
    }
  }
}

void LockscreenWidgetsHost::updateBuiltinClockVisibility(LockScreen& lockScreen) {
  lockScreen.forEachSurface([&](LockSurface& surface) {
    bool hideBuiltin = false;
    if (m_wayland != nullptr) {
      const WaylandOutput* output = m_wayland->findOutputByWl(surface.output());
      if (output != nullptr) {
        const std::string outputKey = desktop_widgets::outputKey(*output);
        for (const auto& widget : m_snapshot.widgets) {
          if (!widget.enabled || widget.type != "clock") {
            continue;
          }
          if (desktop_widgets::outputKey(*desktop_widgets::resolveStateOutput(*m_wayland, widget)) != outputKey) {
            continue;
          }
          hideBuiltin = true;
          break;
        }
      }
    }
    surface.setBuiltinClockVisible(!hideBuiltin);
  });
}

void LockscreenWidgetsHost::prepareFrame(LockSurface& surface, bool needsUpdate, bool needsLayout) {
  if (!m_visible || m_renderContext == nullptr) {
    return;
  }

  m_renderContext->makeCurrent(surface.renderTarget());

  const float baseUiScale = m_config != nullptr ? m_config->config().shell.uiScale : 1.0f;
  const float surfaceW = static_cast<float>(surface.width());
  const float surfaceH = static_cast<float>(surface.height());

  Node* layer = surface.widgetLayer();
  if (layer != nullptr) {
    layer->setPosition(0.0f, 0.0f);
    layer->setSize(surfaceW, surfaceH);
  }

  for (auto& instance : m_instances) {
    if (instance->surface != &surface || instance->widget == nullptr) {
      continue;
    }

    instance->widget->setContentScale(desktop_widgets::widgetContentScale(baseUiScale, instance->state));

    if (needsUpdate) {
      instance->widget->update(*m_renderContext);
    }
    if (needsLayout) {
      instance->widget->layout(*m_renderContext);
      instance->intrinsicWidth = std::max(1.0f, instance->widget->intrinsicWidth());
      instance->intrinsicHeight = std::max(1.0f, instance->widget->intrinsicHeight());
    }

    if (m_wayland != nullptr) {
      desktop_widgets::clampStateToOutput(
          *m_wayland, instance->state, instance->intrinsicWidth, instance->intrinsicHeight
      );
    }

    if (instance->transformNode == nullptr) {
      continue;
    }

    instance->transformNode->setFrameSize(instance->intrinsicWidth, instance->intrinsicHeight);
    instance->transformNode->setPosition(
        instance->state.cx - instance->intrinsicWidth * 0.5f, instance->state.cy - instance->intrinsicHeight * 0.5f
    );
    instance->transformNode->setRotation(instance->state.rotationRad);
    instance->transformNode->setScale(1.0f);
  }
}
