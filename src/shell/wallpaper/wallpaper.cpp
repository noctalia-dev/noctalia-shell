#include "shell/wallpaper/wallpaper.h"

#include "config/config_service.h"
#include "config/state_service.h"
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

bool Wallpaper::initialize(WaylandConnection& wayland, ConfigService* config, StateService* state) {
  m_wayland = &wayland;
  m_config = config;
  m_state = state;

  if (!m_config->config().wallpaper.enabled) {
    logInfo("wallpaper: disabled in config");
    return true;
  }

  m_state->setWallpaperChangeCallback([this]() { onStateChange(); });
  m_config->addReloadCallback([this]() { reload(); });

  syncInstances();
  return true;
}

void Wallpaper::reload() {
  logInfo("wallpaper: reloading config");

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
  logInfo("wallpaper: state file changed, checking for updates");

  for (auto& inst : m_instances) {
    auto newPath = m_state->getWallpaperPath(inst->connectorName);
    if (newPath.empty() || newPath == inst->currentPath) {
      continue;
    }

    logInfo("wallpaper: changing {} → {}", inst->connectorName, newPath);
    inst->pendingPath = newPath;

    if (inst->surface == nullptr || inst->surface->wallpaperRenderer() == nullptr) {
      continue;
    }

    inst->surface->wallpaperRenderer()->makeCurrent();
    loadWallpaper(*inst, newPath);
  }
}

bool Wallpaper::hasInstances() const noexcept { return !m_instances.empty(); }

void Wallpaper::syncInstances() {
  const auto& outputs = m_wayland->outputs();

  // Remove instances for outputs that no longer exist
  std::erase_if(m_instances, [&](const auto& inst) {
    bool found =
        std::any_of(outputs.begin(), outputs.end(), [&inst](const auto& out) { return out.name == inst->outputName; });
    if (!found) {
      logInfo("wallpaper: removing instance for output {}", inst->outputName);
      releaseInstanceTextures(*inst);
    }
    return !found;
  });

  // Create instances for new outputs
  for (const auto& output : outputs) {
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
      logInfo("wallpaper: skipping {} ({}) — disabled by monitor override", output.connectorName, output.description);
      continue;
    }

    createInstance(output);
  }
}

void Wallpaper::createInstance(const WaylandOutput& output) {
  auto wallpaperPath = m_state->getWallpaperPath(output.connectorName);
  logInfo("wallpaper: creating on {} ({}), path={}", output.connectorName, output.description, wallpaperPath);

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

  if (!instance->surface->initialize(output.output, output.scale)) {
    logWarn("wallpaper: failed to initialize surface for output {}", output.name);
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
  auto it = m_textureCache.find(path);
  if (it != m_textureCache.end()) {
    ++it->second.refCount;
    logInfo("wallpaper: texture cache hit for {} (refCount={})", path, it->second.refCount);
    return it->second.handle;
  }

  // Upload into the shared context — caller is responsible for making a
  // context current before calling acquireTexture.
  auto handle = m_sharedTexManager.loadFromFile(path);
  if (handle.id == 0) {
    return handle;
  }

  m_textureCache[path] = CachedTexture{.handle = handle, .refCount = 1};
  logInfo("wallpaper: texture uploaded and cached for {}", path);
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
    logInfo("wallpaper: texture evicted from cache for {}", path);
  }

  handle = {};
}

void Wallpaper::releaseInstanceTextures(WallpaperInstance& inst) {
  releaseTexture(inst.currentTexture, inst.currentPath);
  releaseTexture(inst.nextTexture, inst.pendingPath);
}

// ── Wallpaper loading & transitions ──────────────────────────────────────────

void Wallpaper::loadWallpaper(WallpaperInstance& instance, const std::string& path) {
  auto newTex = acquireTexture(path);
  if (newTex.id == 0) {
    logWarn("wallpaper: failed to load {}", path);
    return;
  }

  if (instance.currentTexture.id == 0) {
    // First wallpaper — display immediately, no transition
    instance.currentTexture = newTex;
    instance.currentPath = path;
    instance.pendingPath.clear();
    updateRendererState(instance);
    instance.surface->requestRedraw();
  } else {
    // Transition from current to new
    instance.nextTexture = newTex;
    instance.pendingPath = path;
    startTransition(instance);
  }
}

void Wallpaper::startTransition(WallpaperInstance& instance) {
  const auto& wpConfig = m_config->config().wallpaper;

  // Cancel any in-progress transition
  if (instance.transitioning) {
    instance.animations.cancel(0);
    // Commit the pending state — release old current, promote next to current
    if (instance.nextTexture.id != 0) {
      releaseTexture(instance.currentTexture, instance.currentPath);
      instance.currentTexture = instance.nextTexture;
      instance.nextTexture = {};
      instance.currentPath = instance.pendingPath;
    }
    instance.transitionProgress = 0.0f;
    instance.transitioning = false;
  }

  // Re-load pending into nextTexture if we just committed it above
  if (instance.nextTexture.id == 0 && !instance.pendingPath.empty()) {
    makeAnyContextCurrent();
    auto tex = acquireTexture(instance.pendingPath);
    if (tex.id == 0)
      return;
    instance.nextTexture = tex;
  }

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
  instance.animations.animate(
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
