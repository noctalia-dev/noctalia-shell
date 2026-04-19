#include "shell/overview/overview.h"

#include "config/config_service.h"
#include "core/log.h"
#include "render/core/shared_texture_cache.h"
#include "shell/overview/overview_surface.h"
#include "ui/palette.h"
#include "wayland/wayland_connection.h"

#include <algorithm>

namespace {

  constexpr Logger kLog("overview");

} // namespace

Overview::Overview() = default;
Overview::~Overview() = default;

bool Overview::initialize(WaylandConnection& wayland, ConfigService* config, SharedTextureCache* textureCache,
                          GlSharedContext* sharedGl) {
  m_wayland = &wayland;
  m_config = config;
  m_textureCache = textureCache;
  m_sharedGl = sharedGl;

  // Register reload callback unconditionally so toggling enabled in config works.
  m_config->addReloadCallback([this]() { reload(); });

  if (!m_config->config().overview.enabled) {
    kLog.info("disabled in config");
    return true;
  }

  syncInstances();
  return true;
}

void Overview::reload() {
  kLog.info("reloading config");

  // Always tear down existing instances. This is necessary because a
  // wallpaper enable/disable cycle resets the wallpaper share context, and any
  // overview instances created against the old context cannot access the new
  // textures. Full teardown + recreate is safe since overview surfaces are
  // hidden by the compositor outside of overview mode (no visible flash).
  for (auto& inst : m_instances) {
    releaseInstanceTexture(*inst);
  }
  m_instances.clear();

  if (!m_config->config().overview.enabled) {
    return;
  }

  syncInstances();
}

void Overview::onOutputChange() {
  if (m_config == nullptr || !m_config->config().overview.enabled) {
    return;
  }
  syncInstances();
}

void Overview::onStateChange() {
  kLog.info("state changed, checking wallpaper updates");

  for (auto& inst : m_instances) {
    auto newPath = m_config->getWallpaperPath(inst->connectorName);
    if (newPath.empty() || newPath == inst->currentPath) {
      continue;
    }

    kLog.info("updating {} → {}", inst->connectorName, newPath);
    releaseInstanceTexture(*inst);
    loadWallpaper(*inst, newPath);
  }
}

void Overview::onThemeChanged() {
  for (auto& inst : m_instances) {
    updateRendererState(*inst);
    if (inst->surface != nullptr) {
      inst->surface->requestRedraw();
    }
  }
}

void Overview::onFontChanged() { requestLayout(); }

void Overview::requestLayout() {
  for (auto& inst : m_instances) {
    if (inst->surface != nullptr) {
      inst->surface->requestLayout();
    }
  }
}

void Overview::syncInstances() {
  const auto& outputs = m_wayland->outputs();

  // Remove instances for outputs that no longer exist
  std::erase_if(m_instances, [&](const auto& inst) {
    bool found =
        std::any_of(outputs.begin(), outputs.end(), [&inst](const auto& out) { return out.name == inst->outputName; });
    if (!found) {
      kLog.info("removing instance for output {}", inst->outputName);
      releaseInstanceTexture(*inst);
    }
    return !found;
  });

  // Create instances for new outputs
  for (const auto& output : outputs) {
    if (!output.done || output.connectorName.empty()) {
      continue;
    }

    bool exists = std::any_of(m_instances.begin(), m_instances.end(),
                              [&output](const auto& inst) { return inst->outputName == output.name; });
    if (!exists) {
      createInstance(output);
    }
  }
}

void Overview::createInstance(const WaylandOutput& output) {
  auto wallpaperPath = m_config->getWallpaperPath(output.connectorName);
  kLog.info("creating on {} ({}), path={}", output.connectorName, output.description, wallpaperPath);

  auto inst = std::make_unique<OverviewInstance>();
  inst->outputName = output.name;
  inst->output = output.output;
  inst->scale = output.scale;
  inst->connectorName = output.connectorName;

  auto surfaceConfig = LayerSurfaceConfig{
      .nameSpace = "noctalia-overview",
      .layer = LayerShellLayer::Background,
      .anchor = LayerShellAnchor::Top | LayerShellAnchor::Bottom | LayerShellAnchor::Left | LayerShellAnchor::Right,
      .width = 0,
      .height = 0,
      .exclusiveZone = -1,
  };

  inst->surface = std::make_unique<OverviewSurface>(*m_wayland, std::move(surfaceConfig));
  inst->surface->setSharedGl(m_sharedGl);

  updateRendererState(*inst);

  auto* instPtr = inst.get();
  inst->surface->setConfigureCallback(
      [this, instPtr, wallpaperPath](std::uint32_t /*width*/, std::uint32_t /*height*/) {
        if (instPtr->currentPath.empty() && !wallpaperPath.empty()) {
          loadWallpaper(*instPtr, wallpaperPath);
        }
      });

  if (!inst->surface->initialize(output.output)) {
    kLog.warn("failed to initialize overview surface for output {}", output.name);
    return;
  }

  m_instances.push_back(std::move(inst));
}

void Overview::loadWallpaper(OverviewInstance& inst, const std::string& path) {
  auto tex = m_textureCache->acquire(path);
  if (tex.id == 0) {
    kLog.warn("failed to load {}", path);
    return;
  }

  inst.currentTexture = tex;
  inst.currentPath = path;
  updateRendererState(inst);
  if (inst.surface != nullptr) {
    inst.surface->requestRedraw();
  }
}

void Overview::updateRendererState(OverviewInstance& inst) {
  if (inst.surface == nullptr) {
    return;
  }

  const auto& ov = m_config->config().overview;
  inst.surface->setBlurIntensity(ov.blurIntensity);
  inst.surface->setTintIntensity(ov.tintIntensity);

  // Tint color from the current surface role.
  const Color surface = resolveThemeColor(roleColor(ColorRole::Surface));
  inst.surface->setTintColor(surface.r, surface.g, surface.b);

  if (inst.currentTexture.id != 0) {
    inst.surface->setWallpaperState(inst.currentTexture.id, static_cast<float>(inst.currentTexture.width),
                                    static_cast<float>(inst.currentTexture.height),
                                    m_config->config().wallpaper.fillMode);
  }
}

void Overview::releaseInstanceTexture(OverviewInstance& inst) {
  if (inst.currentTexture.id != 0) {
    m_textureCache->release(inst.currentTexture, inst.currentPath);
    inst.currentPath.clear();
  }
}
