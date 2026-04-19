#include "shell/color_picker/panel_color_picker_modal.h"

#include "config/config_service.h"
#include "core/log.h"
#include "core/ui_phase.h"
#include "render/core/renderer.h"
#include "render/render_context.h"
#include "render/scene/node.h"
#include "shell/panel/panel.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/box.h"
#include "wayland/layer_surface.h"

#include <algorithm>
#include <cmath>

namespace {

  constexpr Logger kLog("panel");

  float resolvePanelContentScale(ConfigService* configService) {
    if (configService == nullptr) {
      return 1.0f;
    }
    return std::max(0.1f, configService->config().shell.uiScale);
  }

} // namespace

std::unique_ptr<PanelColorPickerModal> PanelColorPickerModal::openOverHost(PanelManager& pm, wl_output* output,
                                                                           float anchorX, float anchorY,
                                                                           std::string_view context) {
  (void)output;
  (void)anchorX;
  (void)anchorY;

  auto cpIt = pm.m_panels.find("color-picker");
  if (cpIt == pm.m_panels.end()) {
    kLog.warn("panel manager: unknown panel \"color-picker\"");
    return nullptr;
  }

  auto modal = std::unique_ptr<PanelColorPickerModal>(new PanelColorPickerModal());
  modal->m_hostPanelId = pm.m_activePanelId;
  modal->m_hostPanel = pm.m_activePanel;
  pm.m_activePanel = cpIt->second.get();
  pm.m_activePanelId = "color-picker";
  pm.m_activePanel->setContentScale(resolvePanelContentScale(pm.m_config));
  pm.m_pendingOpenContext = std::string(context);

  const std::uint32_t hostW = static_cast<std::uint32_t>(modal->m_hostPanel->preferredWidth());
  const std::uint32_t hostH = static_cast<std::uint32_t>(modal->m_hostPanel->preferredHeight());
  const std::uint32_t pickW = static_cast<std::uint32_t>(pm.m_activePanel->preferredWidth());
  const std::uint32_t pickH = static_cast<std::uint32_t>(pm.m_activePanel->preferredHeight());
  const std::uint32_t nw = std::max(hostW, pickW);
  const std::uint32_t nh = std::max(hostH, pickH);
  if (pm.m_surface != nullptr && (nw != pm.m_surface->width() || nh != pm.m_surface->height())) {
    pm.m_surface->requestSize(nw, nh);
  }

  // Attach immediately when a host scene already exists so we do not depend solely
  // on a later prepare-frame callback to materialize the modal subtree.
  if (pm.m_sceneRoot != nullptr) {
    modal->attach(pm);
  }

  if (pm.m_surface != nullptr) {
    pm.m_surface->requestLayout();
    pm.m_surface->requestRedraw();
  }

  return modal;
}

void PanelColorPickerModal::attach(PanelManager& pm) {
  if (pm.m_sceneRoot == nullptr || m_hostPanel == nullptr || pm.m_activePanel == nullptr || m_modalRoot != nullptr) {
    return;
  }

  pm.m_activePanel->setAnimationManager(&pm.m_animations);
  pm.m_activePanel->create();
  pm.m_activePanel->onOpen(pm.m_pendingOpenContext);
  pm.m_pendingOpenContext.clear();

  auto wrap = std::make_unique<Node>();
  wrap->setParticipatesInLayout(false);
  wrap->setZIndex(1000);
  m_modalRoot = pm.m_sceneRoot->addChild(std::move(wrap));

  if (pm.m_activePanel->hasDecoration()) {
    auto modalBg = std::make_unique<Box>();
    modalBg->setPanelStyle();
    modalBg->setParticipatesInLayout(false);
    modalBg->setZIndex(0);
    m_modalBg = static_cast<Box*>(m_modalRoot->addChild(std::move(modalBg)));
  } else {
    m_modalBg = nullptr;
  }

  if (pm.m_activePanel->root() != nullptr) {
    pm.m_activePanel->root()->setZIndex(1);
    m_modalRoot->addChild(pm.m_activePanel->releaseRoot());
  }

  if (auto* focusArea = pm.m_activePanel->initialFocusArea(); focusArea != nullptr) {
    pm.m_inputDispatcher.setFocus(focusArea);
  }
}

void PanelColorPickerModal::layoutScene(PanelManager& pm, float w, float h, Renderer& renderer) {
  uiAssertNotRendering("PanelColorPickerModal::layoutScene");
  if (pm.m_sceneRoot == nullptr || m_hostPanel == nullptr || pm.m_activePanel == nullptr) {
    return;
  }

  pm.m_sceneRoot->setSize(w, h);

  if (pm.m_bgNode != nullptr) {
    pm.m_bgNode->setPosition(0.0f, 0.0f);
    pm.m_bgNode->setSize(w, h);
  }

  const bool hostDec = m_hostPanel->hasDecoration();
  const float hostPad = hostDec ? m_hostPanel->contentScale() * 12.0f : 0.0f;
  pm.m_contentWidth = w - hostPad * 2.0f;
  pm.m_contentHeight = h - hostPad * 2.0f;

  if (pm.m_contentNode != nullptr) {
    pm.m_contentNode->setPosition(hostPad, hostPad);
    pm.m_contentNode->setSize(w - hostPad * 2.0f, h - hostPad * 2.0f);
  }

  {
    UiPhaseScope updatePhase(UiPhase::Update);
    m_hostPanel->update(renderer);
    pm.m_activePanel->update(renderer);
  }
  {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    m_hostPanel->layout(renderer, pm.m_contentWidth, pm.m_contentHeight);
    const float pw = pm.m_activePanel->preferredWidth();
    const float ph = pm.m_activePanel->preferredHeight();
    pm.m_activePanel->layout(renderer, pw, ph);
    if (m_modalRoot != nullptr) {
      m_modalRoot->setSize(pw, ph);
      m_modalRoot->setPosition(std::round((w - pw) * 0.5f), std::round((h - ph) * 0.5f));
      if (m_modalBg != nullptr) {
        m_modalBg->setPosition(0.0f, 0.0f);
        m_modalBg->setSize(pw, ph);
      }
    }
  }
}

void PanelColorPickerModal::shrinkSurfaceToHost(PanelManager& pm) const {
  if (pm.m_surface == nullptr || pm.m_activePanel == nullptr) {
    return;
  }
  const std::uint32_t w = static_cast<std::uint32_t>(pm.m_activePanel->preferredWidth());
  const std::uint32_t h = static_cast<std::uint32_t>(pm.m_activePanel->preferredHeight());
  if (w != pm.m_surface->width() || h != pm.m_surface->height()) {
    pm.m_surface->requestSize(w, h);
  }
}

void PanelColorPickerModal::prepareFrame(PanelManager& pm, bool needsUpdate, bool needsLayout) {
  if (m_hostPanel == nullptr || pm.m_sceneRoot == nullptr) {
    return;
  }
  const bool wasMissingModal = m_modalRoot == nullptr;
  if (wasMissingModal) {
    attach(pm);
  }
  const auto width = pm.m_surface->width();
  const auto height = pm.m_surface->height();
  const bool dimSync = static_cast<std::uint32_t>(std::lround(pm.m_sceneRoot->width())) != width ||
                       static_cast<std::uint32_t>(std::lround(pm.m_sceneRoot->height())) != height;
  if (needsUpdate) {
    UiPhaseScope updatePhase(UiPhase::Update);
    m_hostPanel->update(*pm.m_renderContext);
    pm.m_activePanel->update(*pm.m_renderContext);
  }
  if (wasMissingModal || needsLayout || dimSync) {
    layoutScene(pm, static_cast<float>(width), static_cast<float>(height), *pm.m_renderContext);
  }
}

void PanelColorPickerModal::close(PanelManager& pm) {
  if (pm.m_sceneRoot != nullptr && m_modalRoot != nullptr) {
    (void)pm.m_sceneRoot->removeChild(m_modalRoot);
    m_modalRoot = nullptr;
    m_modalBg = nullptr;
  }
  if (pm.m_activePanel != nullptr) {
    pm.m_activePanel->onClose();
  }
  pm.m_activePanel = m_hostPanel;
  pm.m_activePanelId = m_hostPanelId;
  m_hostPanel = nullptr;
  m_hostPanelId.clear();

  // Force input recapture against the host tree after removing the modal subtree.
  pm.m_inputDispatcher.setSceneRoot(nullptr);
  if (pm.m_sceneRoot != nullptr) {
    pm.m_inputDispatcher.setSceneRoot(pm.m_sceneRoot.get());
  }
  shrinkSurfaceToHost(pm);
  if (pm.m_surface != nullptr) {
    pm.m_surface->requestLayout();
  }
}

void PanelColorPickerModal::prepareForDestroyPanel(PanelManager& pm) {
  m_modalRoot = nullptr;
  m_modalBg = nullptr;
  if (m_hostPanel != nullptr) {
    m_hostPanel->onClose();
  }
  if (pm.m_activePanel != nullptr) {
    pm.m_activePanel->onClose();
  }
  m_hostPanel = nullptr;
  m_hostPanelId.clear();
  pm.m_activePanel = nullptr;
  pm.m_activePanelId.clear();
}

void PanelColorPickerModal::frameTickHostIfPresent(PanelManager& /*pm*/, float deltaMs) const {
  if (m_hostPanel != nullptr) {
    m_hostPanel->onFrameTick(deltaMs);
  }
}
