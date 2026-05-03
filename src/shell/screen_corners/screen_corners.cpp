#include "shell/screen_corners/screen_corners.h"

#include "config/config_service.h"
#include "core/ui_phase.h"
#include "render/render_context.h"
#include "ui/controls/box.h"
#include "wayland/wayland_connection.h"

#include <algorithm>

namespace {

  constexpr std::uint32_t kCornerAnchors[4] = {
      LayerShellAnchor::Top | LayerShellAnchor::Left,
      LayerShellAnchor::Top | LayerShellAnchor::Right,
      LayerShellAnchor::Bottom | LayerShellAnchor::Right,
      LayerShellAnchor::Bottom | LayerShellAnchor::Left,
  };

  Radii cornerRadii(int cornerIndex, float size) {
    switch (cornerIndex) {
    case 0:
      return Radii{size, 0.0f, 0.0f, 0.0f};
    case 1:
      return Radii{0.0f, size, 0.0f, 0.0f};
    case 2:
      return Radii{0.0f, 0.0f, size, 0.0f};
    case 3:
      return Radii{0.0f, 0.0f, 0.0f, size};
    default:
      return Radii{};
    }
  }

} // namespace

void ScreenCorners::initialize(WaylandConnection& wayland, ConfigService* config, RenderContext* renderContext) {
  m_wayland = &wayland;
  m_config = config;
  m_renderContext = renderContext;
}

void ScreenCorners::onConfigReload() {
  if (m_config == nullptr) {
    return;
  }

  const auto& cfg = m_config->config().shell.screenCorners;
  if (!cfg.enabled) {
    if (m_lastEnabled) {
      destroySurfaces();
      m_lastEnabled = false;
    }
    return;
  }

  if (cfg.enabled != m_lastEnabled || cfg.size != m_lastSize || m_instances.size() != m_wayland->outputs().size()) {
    destroySurfaces();
    m_lastEnabled = cfg.enabled;
    m_lastSize = cfg.size;
    ensureSurfaces();
  }
}

void ScreenCorners::onOutputChange() {
  if (m_config == nullptr || !m_config->config().shell.screenCorners.enabled) {
    return;
  }
  destroySurfaces();
  ensureSurfaces();
}

void ScreenCorners::ensureSurfaces() {
  if (m_wayland == nullptr || m_renderContext == nullptr || m_config == nullptr) {
    return;
  }

  const auto& cfg = m_config->config().shell.screenCorners;
  if (!cfg.enabled || !m_instances.empty()) {
    return;
  }

  const auto size = static_cast<std::uint32_t>(std::clamp(cfg.size, 1, 100));

  for (const auto& output : m_wayland->outputs()) {
    auto inst = std::make_unique<OutputInstance>();
    inst->output = output.output;

    bool ok = true;
    for (int i = 0; i < 4; ++i) {
      auto surfaceConfig = LayerSurfaceConfig{
          .nameSpace = "noctalia-screen-corner",
          .layer = LayerShellLayer::Top,
          .anchor = kCornerAnchors[i],
          .width = size,
          .height = size,
          .exclusiveZone = -1,
          .keyboard = LayerShellKeyboard::None,
          .defaultWidth = size,
          .defaultHeight = size,
      };

      auto& corner = inst->corners[i];
      corner.surface = std::make_unique<LayerSurface>(*m_wayland, std::move(surfaceConfig));

      auto* cornerPtr = &corner;
      const int cornerIndex = i;
      const float cornerSize = static_cast<float>(size);

      corner.surface->setConfigureCallback(
          [cornerPtr](std::uint32_t, std::uint32_t) { cornerPtr->surface->requestLayout(); });
      corner.surface->setPrepareFrameCallback([this, cornerPtr, cornerSize, cornerIndex](bool, bool) {
        if (cornerPtr->sceneRoot == nullptr) {
          UiPhaseScope layoutPhase(UiPhase::Layout);
          buildCornerScene(*cornerPtr, cornerSize, cornerIndex);
        }
      });
      corner.surface->setRenderContext(m_renderContext);

      if (!corner.surface->initialize(output.output)) {
        ok = false;
        break;
      }
      corner.surface->setInputRegion({});
    }

    if (ok) {
      m_instances.push_back(std::move(inst));
    }
  }
}

void ScreenCorners::destroySurfaces() { m_instances.clear(); }

void ScreenCorners::buildCornerScene(Corner& corner, float size, int cornerIndex) {
  auto root = std::make_unique<Box>();
  root->setSize(size, size);
  root->setStyle(RoundedRectStyle{
      .fill = Color{0.0f, 0.0f, 0.0f, 1.0f},
      .fillMode = FillMode::Solid,
      .radius = cornerRadii(cornerIndex, size),
      .softness = 0.5f,
      .invertFill = true,
  });

  corner.sceneRoot = std::move(root);
  corner.surface->setSceneRoot(corner.sceneRoot.get());
}
