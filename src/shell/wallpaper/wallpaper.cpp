#include "shell/wallpaper/wallpaper.h"

#include "config/config_service.h"
#include "core/log.h"
#include "render/wallpaper_renderer.h"
#include "shell/wallpaper/wallpaper_surface.h"
#include "wayland/wayland_connection.h"

#include "core/random.h"

#include <algorithm>
#include <cmath>

using Random::randomFloat;

namespace {

TransitionParams randomizeParams(WallpaperTransition type, float smoothness, float aspectRatio) {
  TransitionParams params;
  params.smoothness = smoothness;
  params.aspectRatio = aspectRatio;

  switch (type) {
  case WallpaperTransition::Wipe:
    params.direction = std::floor(randomFloat(0.0f, 4.0f));
    break;
  case WallpaperTransition::Disc:
    params.centerX = randomFloat(0.2f, 0.8f);
    params.centerY = randomFloat(0.2f, 0.8f);
    break;
  case WallpaperTransition::Stripes:
    params.stripeCount = std::round(randomFloat(4.0f, 24.0f));
    params.angle = randomFloat(0.0f, 360.0f);
    break;
  case WallpaperTransition::Zoom:
    break;
  case WallpaperTransition::Honeycomb:
    params.cellSize = randomFloat(0.02f, 0.06f);
    params.centerX = randomFloat(0.2f, 0.8f);
    params.centerY = randomFloat(0.2f, 0.8f);
    break;
  case WallpaperTransition::Fade:
  default:
    break;
  }

  return params;
}

constexpr Logger kLog("wallpaper");

} // namespace

Wallpaper::Wallpaper() = default;

Wallpaper::~Wallpaper() {
  // Release all instance textures while contexts are still alive, then clean
  // up the shared TextureManager (also needs a current context).
  for (auto& inst : m_instances) {
    releaseInstanceTextures(*inst);
  }
  makeAnyContextCurrent();
  m_sharedTexManager.cleanup();
  // m_instances and EGL contexts destroyed after this point
}

bool Wallpaper::initialize(WaylandConnection& wayland, ConfigService* config) {
  m_wayland = &wayland;
  m_config = config;

  if (!m_config->config().wallpaper.enabled) {
    kLog.info("disabled in config");
    return true;
  }

  m_config->setWallpaperChangeCallback([this]() { onStateChange(); });
  m_config->addReloadCallback([this]() { reload(); });

  syncInstances();
  return true;
}

void Wallpaper::reload() {
  kLog.info("reloading config");

  const bool nowEnabled = m_config->config().wallpaper.enabled;

  if (!nowEnabled) {
    // Wallpaper disabled — full teardown
    for (auto& inst : m_instances) {
      releaseInstanceTextures(*inst);
    }
    makeAnyContextCurrent();
    m_sharedTexManager.cleanup();
    m_textureCache.clear();
    m_instances.clear();
    m_shareContext = EGL_NO_CONTEXT;
    return;
  }

  // Wallpaper remains (or becomes) enabled — sync instances without teardown
  // to avoid flickering. syncInstances handles monitor override changes
  // (adds/removes instances) without disturbing existing surfaces.
  syncInstances();

  // Refresh renderer state on all instances to pick up fill mode / smoothness
  // changes that take effect immediately without a texture reload.
  for (auto& inst : m_instances) {
    updateRendererState(*inst);
    inst->surface->requestRedraw();
  }
}

void Wallpaper::onOutputChange() {
  if (m_config == nullptr || !m_config->config().wallpaper.enabled) {
    return;
  }
  syncInstances();
}

void Wallpaper::onStateChange() {
  kLog.info("state file changed, checking for updates");

  for (auto& inst : m_instances) {
    auto newPath = m_config->getWallpaperPath(inst->connectorName);
    if (newPath.empty()) {
      continue;
    }

    if (inst->surface == nullptr || inst->surface->wallpaperRenderer() == nullptr) {
      continue;
    }

    if (inst->transitioning) {
      if (newPath == inst->pendingPath) {
        inst->queuedPath.clear();
        continue;
      }

      inst->queuedPath = newPath;
      continue;
    }

    if (newPath == inst->currentPath) {
      continue;
    }

    kLog.info("changing {} → {}", inst->connectorName, newPath);
    inst->surface->wallpaperRenderer()->makeCurrent();
    loadWallpaper(*inst, newPath);
  }
}

bool Wallpaper::hasInstances() const noexcept { return !m_instances.empty(); }

void Wallpaper::syncInstances() {
  const auto& outputs = m_wayland->outputs();

  // Remove instances for outputs that no longer exist or are now disabled by monitor override
  std::erase_if(m_instances, [&](const auto& inst) {
    const auto* output = [&]() -> const WaylandOutput* {
      for (const auto& out : outputs) {
        if (out.name == inst->outputName) return &out;
      }
      return nullptr;
    }();

    if (output == nullptr) {
      kLog.info("removing instance for output {} (disconnected)", inst->outputName);
      releaseInstanceTextures(*inst);
      return true;
    }

    // Check if a monitor override now disables this output
    for (const auto& ovr : m_config->config().wallpaper.monitorOverrides) {
      const auto& match = ovr.match;
      bool hit = (!output->connectorName.empty() && match == output->connectorName) ||
                 (!output->description.empty() && output->description.find(match) != std::string::npos);
      if (hit && ovr.enabled && !*ovr.enabled) {
        kLog.info("removing instance for {} — disabled by monitor override", output->connectorName);
        releaseInstanceTextures(*inst);
        return true;
      }
    }

    return false;
  });

  refreshShareContext();

  // Create instances for new outputs
  for (const auto& output : outputs) {
    if (!output.done || output.connectorName.empty()) {
      continue;
    }

    bool exists = std::any_of(m_instances.begin(), m_instances.end(),
                              [&output](const auto& inst) { return inst->outputName == output.name; });
    if (exists) {
      continue;
    }

    bool enabled = true;
    for (const auto& ovr : m_config->config().wallpaper.monitorOverrides) {
      const auto& match = ovr.match;
      bool hit = (!output.connectorName.empty() && match == output.connectorName) ||
                 (!output.description.empty() && output.description.find(match) != std::string::npos);
      if (hit && ovr.enabled) {
        enabled = *ovr.enabled;
        break;
      }
    }
    if (!enabled) {
      kLog.info("skipping {} ({}) — disabled by monitor override", output.connectorName, output.description);
      continue;
    }

    createInstance(output);
  }
}

void Wallpaper::refreshShareContext() {
  m_shareContext = EGL_NO_CONTEXT;
  for (const auto& inst : m_instances) {
    if (inst->surface == nullptr || inst->surface->wallpaperRenderer() == nullptr) {
      continue;
    }

    const EGLContext context = inst->surface->wallpaperRenderer()->eglContext();
    if (context != EGL_NO_CONTEXT) {
      m_shareContext = context;
      return;
    }
  }
}

void Wallpaper::createInstance(const WaylandOutput& output) {
  auto wallpaperPath = m_config->getWallpaperPath(output.connectorName);
  kLog.info("creating on {} ({}), path={}", output.connectorName, output.description, wallpaperPath);

  auto instance = std::make_unique<WallpaperInstance>();
  instance->outputName = output.name;
  instance->output = output.output;
  instance->scale = output.scale;
  instance->connectorName = output.connectorName;

  auto surfaceConfig = LayerSurfaceConfig{
      .nameSpace = "noctalia-wallpaper",
      .layer = LayerShellLayer::Background,
      .anchor = LayerShellAnchor::Top | LayerShellAnchor::Bottom | LayerShellAnchor::Left | LayerShellAnchor::Right,
      .width = 0,
      .height = 0,
      .exclusiveZone = -1,
  };

  instance->surface = std::make_unique<WallpaperSurface>(*m_wayland, std::move(surfaceConfig));
  instance->surface->setShareContext(m_shareContext);

  auto* inst = instance.get();
  instance->surface->setConfigureCallback(
      [this, inst, wallpaperPath](std::uint32_t /*width*/, std::uint32_t /*height*/) {
        if (inst->currentPath.empty() && !wallpaperPath.empty()) {
          inst->surface->wallpaperRenderer()->makeCurrent();
          loadWallpaper(*inst, wallpaperPath);
        }
      });

  instance->surface->setAnimationManager(&instance->animations);

  instance->surface->setUpdateCallback([this, inst]() { updateRendererState(*inst); });

  if (!instance->surface->initialize(output.output)) {
    kLog.warn("failed to initialize surface for output {}", output.name);
    return;
  }

  // After the first successful init, capture the EGL context as the share root
  // for all subsequent renderers.
  if (m_shareContext == EGL_NO_CONTEXT) {
    m_shareContext = instance->surface->wallpaperRenderer()->eglContext();
  }

  m_instances.push_back(std::move(instance));
}

// ── Shared texture cache ──────────────────────────────────────────────────────

void Wallpaper::makeAnyContextCurrent() {
  for (const auto& inst : m_instances) {
    if (inst->surface != nullptr) {
      auto* renderer = inst->surface->wallpaperRenderer();
      if (renderer != nullptr) {
        renderer->makeCurrent();
        return;
      }
    }
  }
}

TextureHandle Wallpaper::acquireTexture(const std::string& path) {
  makeAnyContextCurrent();
  auto it = m_textureCache.find(path);
  if (it != m_textureCache.end()) {
    ++it->second.refCount;
    kLog.info("texture cache hit for {} (refCount={})", path, it->second.refCount);
    return it->second.handle;
  }

  // Upload into the shared context — caller is responsible for making a
  // context current before calling acquireTexture.
  auto handle = m_sharedTexManager.loadFromFile(path);
  if (handle.id == 0) {
    return handle;
  }

  m_textureCache[path] = CachedTexture{.handle = handle, .refCount = 1};
  kLog.info("texture uploaded and cached for {}", path);
  return handle;
}

void Wallpaper::releaseTexture(TextureHandle& handle, const std::string& path) {
  if (handle.id == 0 || path.empty()) {
    handle = {};
    return;
  }

  auto it = m_textureCache.find(path);
  if (it == m_textureCache.end()) {
    handle = {};
    return;
  }

  --it->second.refCount;
  if (it->second.refCount <= 0) {
    makeAnyContextCurrent();
    m_sharedTexManager.unload(it->second.handle);
    m_textureCache.erase(it);
    kLog.info("texture evicted from cache for {}", path);
  }

  handle = {};
}

void Wallpaper::releaseInstanceTextures(WallpaperInstance& inst) {
  releaseTexture(inst.currentTexture, inst.currentPath);
  releaseTexture(inst.nextTexture, inst.pendingPath);
}

// ── Wallpaper loading & transitions ──────────────────────────────────────────

void Wallpaper::loadWallpaper(WallpaperInstance& instance, const std::string& path) {
  // Nothing to do if we're already at (or heading toward) this wallpaper.
  if (!instance.transitioning && path == instance.currentPath) {
    return;
  }
  if (instance.transitioning && path == instance.pendingPath) {
    return;
  }

  if (instance.transitioning) {
    instance.queuedPath = path;
    return;
  }

  auto newTex = acquireTexture(path);
  if (newTex.id == 0) {
    kLog.warn("failed to load {}", path);
    return;
  }

  if (instance.currentTexture.id == 0) {
    // First wallpaper — display immediately, no transition
    instance.currentTexture = newTex;
    instance.currentPath = path;
    instance.pendingPath.clear();
    instance.queuedPath.clear();
    updateRendererState(instance);
    instance.surface->requestRedraw();
    return;
  }

  instance.nextTexture = newTex;
  instance.pendingPath = path;
  startTransition(instance);
}

void Wallpaper::startTransition(WallpaperInstance& instance) {
  const auto& wpConfig = m_config->config().wallpaper;

  float aspectRatio = 1.777f;
  if (instance.surface->height() > 0) {
    aspectRatio = static_cast<float>(instance.surface->width()) / static_cast<float>(instance.surface->height());
  }

  const auto& transitions = wpConfig.transitions;
  const auto picked = transitions[static_cast<std::size_t>(
      std::floor(randomFloat(0.0f, static_cast<float>(transitions.size()))))];
  instance.activeTransition = picked;
  instance.transitionParams = randomizeParams(picked, wpConfig.edgeSmoothness, aspectRatio);
  instance.transitioning = true;
  instance.transitionProgress = 0.0f;

  auto* inst = &instance;
  instance.transitionAnimId = instance.animations.animate(
      0.0f, 1.0f, wpConfig.transitionDurationMs, Easing::EaseInOutCubic,
      [inst](float v) { inst->transitionProgress = v; },
      [this, inst]() {
        // Transition complete — release old current, promote next to current
        releaseTexture(inst->currentTexture, inst->currentPath);
        inst->currentTexture = inst->nextTexture;
        inst->nextTexture = {};
        inst->currentPath = inst->pendingPath;
        inst->pendingPath.clear();
        inst->transitionProgress = 0.0f;
        inst->transitioning = false;
        updateRendererState(*inst);
        // The frame loop stops once there are no active animations, so the
        // promoted final wallpaper needs one explicit redraw.
        inst->surface->requestRedraw();

        if (!inst->queuedPath.empty() && inst->queuedPath != inst->currentPath) {
          const std::string queuedPath = inst->queuedPath;
          inst->queuedPath.clear();
          inst->surface->wallpaperRenderer()->makeCurrent();
          loadWallpaper(*inst, queuedPath);
        } else {
          inst->queuedPath.clear();
        }
      });

  updateRendererState(instance);
  instance.surface->requestRedraw();
}

void Wallpaper::updateRendererState(WallpaperInstance& instance) {
  auto* renderer = instance.surface->wallpaperRenderer();
  if (renderer == nullptr) {
    return;
  }

  const auto& wpConfig = m_config->config().wallpaper;

  renderer->setTransitionState(
      instance.currentTexture.id, instance.nextTexture.id, static_cast<float>(instance.currentTexture.width),
      static_cast<float>(instance.currentTexture.height), static_cast<float>(instance.nextTexture.width),
      static_cast<float>(instance.nextTexture.height), instance.transitionProgress, instance.activeTransition,
      wpConfig.fillMode, instance.transitionParams);
}
