#include "ui/dialogs/dialog_popup_host.h"

#include "config/config_service.h"
#include "core/ui_phase.h"
#include "render/render_context.h"
#include "render/scene/node.h"
#include "ui/controls/box.h"
#include "wayland/popup_surface.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"
#include "xdg-shell-client-protocol.h"
#include "xkbcommon/xkbcommon-keysyms.h"

#include <algorithm>
#include <cassert>
#include <cmath>
#include <utility>

namespace {

  constexpr std::uint32_t kPopupConstraintAdjust =
      XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X | XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_Y |
      XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_X | XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_Y;

} // namespace

DialogPopupHost::DialogPopupHost() = default;

DialogPopupHost::~DialogPopupHost() {
  // Subclass destructors are responsible for calling destroyPopup() before
  // their own members go away — by the time we reach this destructor the
  // subclass vtable has already been replaced and any virtual hook would
  // dispatch to the base no-op, not the subclass override.
  assert(m_surface == nullptr && "subclass must call destroyPopup() in its destructor");
}

void DialogPopupHost::initializeBase(WaylandConnection& wayland, ConfigService& config, RenderContext& renderContext,
                                     LayerPopupHostRegistry& popupHosts) {
  m_wayland = &wayland;
  m_config = &config;
  m_renderContext = &renderContext;
  m_popupHosts = &popupHosts;
}

bool DialogPopupHost::openPopup(std::uint32_t width, std::uint32_t height) {
  if (m_wayland == nullptr || m_renderContext == nullptr || m_popupHosts == nullptr) {
    return false;
  }

  destroyPopup();

  const auto parentContext = resolveParentContext();
  if (!parentContext.has_value()) {
    return false;
  }
  m_parentSurface = parentContext->surface;

  auto surface = std::make_unique<PopupSurface>(*m_wayland);
  surface->setAnimationManager(&m_animations);
  surface->setRenderContext(m_renderContext);
  surface->setConfigureCallback([this](std::uint32_t /*w*/, std::uint32_t /*h*/) { requestLayout(); });
  surface->setPrepareFrameCallback(
      [this](bool needsUpdate, bool needsLayout) { prepareFrame(needsUpdate, needsLayout); });
  surface->setDismissedCallback([this]() { cancel(); });

  PopupSurfaceConfig popupConfig = defaultPopupConfig(*parentContext, width, height);

  m_surface = std::move(surface);
  m_popupHosts->beginAttachedPopup(m_parentSurface);
  m_attachedToHost = true;
  if (!m_surface->initialize(parentContext->layerSurface, parentContext->output, popupConfig)) {
    destroyPopup();
    return false;
  }
  return true;
}

void DialogPopupHost::destroyPopup() {
  if (m_attachedToHost && m_popupHosts != nullptr) {
    m_popupHosts->endAttachedPopup(m_parentSurface);
    m_attachedToHost = false;
  }
  m_pointerInside = false;
  m_parentSurface = nullptr;
  m_inputDispatcher.setSceneRoot(nullptr);
  // onSheetClose hook fires before scene tear-down so subclasses can run
  // any sheet-specific cleanup (e.g. FileDialogView::onClose()) while their
  // sheet pointer is still wired into the scene.
  if (m_sceneRoot != nullptr || m_surface != nullptr) {
    onSheetClose();
  }
  m_bgNode = nullptr;
  m_contentNode = nullptr;
  m_sceneRoot.reset();
  m_surface.reset();
}

void DialogPopupHost::closeAfterAccept() { destroyPopup(); }

float DialogPopupHost::uiScale() const {
  if (m_config == nullptr) {
    return 1.0f;
  }
  return std::max(0.1f, m_config->config().shell.uiScale);
}

PopupSurfaceConfig DialogPopupHost::defaultPopupConfig(const LayerPopupParentContext& parent, std::uint32_t width,
                                                       std::uint32_t height) const {
  const auto [offsetX, offsetY] = parent.centeringOffset(*m_wayland);
  return PopupSurfaceConfig{
      .anchorX = 0,
      .anchorY = 0,
      .anchorWidth = static_cast<std::int32_t>(parent.width),
      .anchorHeight = static_cast<std::int32_t>(parent.height),
      .width = width,
      .height = height,
      .anchor = XDG_POSITIONER_ANCHOR_NONE,
      .gravity = XDG_POSITIONER_GRAVITY_NONE,
      .constraintAdjustment = kPopupConstraintAdjust,
      .offsetX = offsetX,
      .offsetY = offsetY,
      .serial = m_wayland->lastInputSerial(),
      .grab = true,
  };
}

bool DialogPopupHost::onPointerEvent(const PointerEvent& event) {
  if (m_surface == nullptr) {
    return false;
  }

  const bool captured = m_inputDispatcher.pointerCaptured();
  float localX = 0.0f;
  float localY = 0.0f;
  const bool mapped = mapPointerEvent(event, localX, localY);
  if (!mapped) {
    if ((event.type == PointerEvent::Type::Leave && event.surface == m_parentSurface) ||
        (event.type == PointerEvent::Type::Motion && event.surface == m_parentSurface && m_pointerInside)) {
      m_pointerInside = false;
      if (!captured) {
        m_inputDispatcher.pointerLeave();
      }
      markDirtyTail();
    }
    return false;
  }

  switch (event.type) {
  case PointerEvent::Type::Enter:
    m_pointerInside = true;
    m_inputDispatcher.pointerEnter(localX, localY, event.serial);
    break;
  case PointerEvent::Type::Leave:
    m_pointerInside = false;
    if (!captured) {
      m_inputDispatcher.pointerLeave();
    }
    break;
  case PointerEvent::Type::Motion:
    if (captured) {
      m_inputDispatcher.pointerMotion(localX, localY, event.serial);
    } else if (!m_pointerInside) {
      m_pointerInside = true;
      m_inputDispatcher.pointerEnter(localX, localY, event.serial);
    } else {
      m_inputDispatcher.pointerMotion(localX, localY, event.serial);
    }
    break;
  case PointerEvent::Type::Button:
    if (captured) {
      m_inputDispatcher.pointerMotion(localX, localY, event.serial);
    } else if (!m_pointerInside) {
      m_pointerInside = true;
      m_inputDispatcher.pointerEnter(localX, localY, event.serial);
    } else {
      m_inputDispatcher.pointerMotion(localX, localY, event.serial);
    }
    m_inputDispatcher.pointerButton(localX, localY, event.button, event.state == 1);
    break;
  case PointerEvent::Type::Axis:
    if (captured) {
      m_inputDispatcher.pointerMotion(localX, localY, event.serial);
    } else if (!m_pointerInside) {
      m_pointerInside = true;
      m_inputDispatcher.pointerEnter(localX, localY, event.serial);
    } else {
      m_inputDispatcher.pointerMotion(localX, localY, event.serial);
    }
    m_inputDispatcher.pointerAxis(localX, localY, event.axis, event.axisSource, event.axisValue, event.axisDiscrete,
                                  event.axisValue120, event.axisLines);
    break;
  }

  markDirtyTail();
  return true;
}

void DialogPopupHost::onKeyboardEvent(const KeyboardEvent& event) {
  if (m_surface == nullptr) {
    return;
  }

  if (event.pressed && !event.preedit && event.sym == XKB_KEY_Escape) {
    cancel();
    return;
  }

  if (preDispatchKeyboard(event)) {
    markDirtyTail();
    return;
  }

  m_inputDispatcher.keyEvent(event.sym, event.utf32, event.modifiers, event.pressed, event.preedit);
  markDirtyTail();
}

void DialogPopupHost::requestLayout() {
  if (m_surface != nullptr) {
    m_surface->requestLayout();
  }
}

void DialogPopupHost::requestRedraw() {
  if (m_surface != nullptr) {
    m_surface->requestRedraw();
  }
}

void DialogPopupHost::requestUpdateOnly() {
  if (m_surface != nullptr) {
    m_surface->requestUpdateOnly();
  }
}

wl_surface* DialogPopupHost::wlSurface() const noexcept {
  return m_surface != nullptr ? m_surface->wlSurface() : nullptr;
}

void DialogPopupHost::cancel() {
  if (m_surface == nullptr) {
    return;
  }
  destroyPopup();
  cancelToFacade();
}

void DialogPopupHost::prepareFrame(bool needsUpdate, bool needsLayout) {
  if (m_surface == nullptr || m_renderContext == nullptr) {
    return;
  }

  const auto width = m_surface->width();
  const auto height = m_surface->height();
  if (width == 0 || height == 0) {
    return;
  }

  m_renderContext->makeCurrent(m_surface->renderTarget());

  const bool needsSceneBuild = m_sceneRoot == nullptr ||
                               static_cast<std::uint32_t>(std::round(m_sceneRoot->width())) != width ||
                               static_cast<std::uint32_t>(std::round(m_sceneRoot->height())) != height;
  if (needsSceneBuild) {
    buildScene(width, height);
  }

  if (needsUpdate) {
    UiPhaseScope updatePhase(UiPhase::Update);
    runUpdatePhase();
  }
  if (needsLayout) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    layoutScene(static_cast<float>(width), static_cast<float>(height));
  }
  if (needsUpdate && m_sceneRoot != nullptr && m_sceneRoot->layoutDirty()) {
    requestLayout();
  }
}

void DialogPopupHost::buildScene(std::uint32_t width, std::uint32_t height) {
  m_sceneRoot = std::make_unique<Node>();
  m_sceneRoot->setAnimationManager(&m_animations);

  auto bg = std::make_unique<Box>();
  bg->setPanelStyle();
  m_bgNode = static_cast<Box*>(m_sceneRoot->addChild(std::move(bg)));

  auto content = std::make_unique<Node>();
  m_contentNode = content.get();
  populateContent(m_contentNode, width, height);
  m_sceneRoot->addChild(std::move(content));

  m_inputDispatcher.setSceneRoot(m_sceneRoot.get());
  m_inputDispatcher.setCursorShapeCallback(
      [this](std::uint32_t serial, std::uint32_t shape) { m_wayland->setCursorShape(serial, shape); });
  m_surface->setSceneRoot(m_sceneRoot.get());

  if (auto* focusArea = initialFocusArea(); focusArea != nullptr) {
    m_inputDispatcher.setFocus(focusArea);
  }

  layoutScene(static_cast<float>(width), static_cast<float>(height));
  syncPointerStateFromCurrentPosition();
}

void DialogPopupHost::layoutScene(float width, float height) {
  if (m_sceneRoot == nullptr) {
    return;
  }

  m_sceneRoot->setSize(width, height);
  if (m_bgNode != nullptr) {
    m_bgNode->setPosition(0.0f, 0.0f);
    m_bgNode->setSize(width, height);
  }

  const float padding = computePadding(uiScale());
  const float contentWidth = width - padding * 2.0f;
  const float contentHeight = height - padding * 2.0f;

  layoutSheet(contentWidth, contentHeight);

  if (m_contentNode != nullptr) {
    m_contentNode->setPosition(padding, padding);
    m_contentNode->setSize(contentWidth, contentHeight);
  }
}

bool DialogPopupHost::mapPointerEvent(const PointerEvent& event, float& localX, float& localY) const noexcept {
  if (m_surface == nullptr) {
    return false;
  }

  wl_surface* eventSurface = resolveEventSurface(event);
  if (eventSurface == nullptr) {
    return false;
  }

  if (m_inputDispatcher.pointerCaptured() && event.type != PointerEvent::Type::Leave) {
    if (ownsSurface(eventSurface)) {
      localX = static_cast<float>(event.sx);
      localY = static_cast<float>(event.sy);
      return true;
    }
    if (eventSurface == m_parentSurface) {
      localX = static_cast<float>(event.sx) - static_cast<float>(m_surface->configuredX());
      localY = static_cast<float>(event.sy) - static_cast<float>(m_surface->configuredY());
      return true;
    }
  }

  if (ownsSurface(eventSurface)) {
    localX = static_cast<float>(event.sx);
    localY = static_cast<float>(event.sy);
    return true;
  }

  if (eventSurface != m_parentSurface) {
    return false;
  }

  localX = static_cast<float>(event.sx) - static_cast<float>(m_surface->configuredX());
  localY = static_cast<float>(event.sy) - static_cast<float>(m_surface->configuredY());

  if (event.type == PointerEvent::Type::Leave) {
    return m_pointerInside || m_inputDispatcher.pointerCaptured();
  }

  const float width = static_cast<float>(m_surface->width());
  const float height = static_cast<float>(m_surface->height());
  if (m_inputDispatcher.pointerCaptured()) {
    return true;
  }
  if (event.type == PointerEvent::Type::Button && m_pointerInside) {
    return true;
  }
  return localX >= 0.0f && localY >= 0.0f && localX < width && localY < height;
}

void DialogPopupHost::syncPointerStateFromCurrentPosition() {
  if (m_wayland == nullptr || m_surface == nullptr || !m_wayland->hasPointerPosition()) {
    return;
  }

  PointerEvent synthetic;
  synthetic.type = PointerEvent::Type::Motion;
  synthetic.surface = m_wayland->lastPointerSurface();
  synthetic.sx = m_wayland->lastPointerX();
  synthetic.sy = m_wayland->lastPointerY();
  synthetic.serial = m_wayland->lastInputSerial();

  float localX = 0.0f;
  float localY = 0.0f;
  if (!mapPointerEvent(synthetic, localX, localY)) {
    return;
  }

  m_pointerInside = true;
  m_inputDispatcher.pointerEnter(localX, localY, synthetic.serial);
  markDirtyTail();
}

bool DialogPopupHost::ownsSurface(wl_surface* surface) const noexcept {
  return m_surface != nullptr && surface != nullptr && surface == m_surface->wlSurface();
}

wl_surface* DialogPopupHost::resolveEventSurface(const PointerEvent& event) const noexcept {
  wl_surface* eventSurface = event.surface;
  if (eventSurface == nullptr && event.type == PointerEvent::Type::Motion && m_wayland != nullptr) {
    eventSurface = m_wayland->lastPointerSurface();
  }
  return eventSurface;
}

std::optional<LayerPopupParentContext> DialogPopupHost::resolveParentContext() const {
  if (m_wayland == nullptr || m_popupHosts == nullptr) {
    return std::nullopt;
  }
  return m_popupHosts->resolveForInput(*m_wayland);
}

void DialogPopupHost::markDirtyTail() {
  if (m_sceneRoot == nullptr) {
    return;
  }
  if (!m_sceneRoot->paintDirty() && !m_sceneRoot->layoutDirty()) {
    return;
  }
  if (m_sceneRoot->layoutDirty()) {
    requestLayout();
  } else {
    requestRedraw();
  }
}
