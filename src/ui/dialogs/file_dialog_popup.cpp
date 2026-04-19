#include "ui/dialogs/file_dialog_popup.h"

#include "config/config_service.h"
#include "core/ui_phase.h"
#include "render/core/renderer.h"
#include "render/render_context.h"
#include "render/scene/node.h"
#include "ui/controls/box.h"
#include "ui/dialogs/file_dialog.h"
#include "ui/style.h"
#include "wayland/popup_surface.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"
#include "xdg-shell-client-protocol.h"

#include <algorithm>
#include <cmath>
#include <memory>

namespace {

  constexpr std::uint32_t kPopupConstraintAdjust =
      XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X | XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_Y |
      XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_X | XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_Y;

} // namespace

void FileDialogPopup::initialize(WaylandConnection& wayland, ConfigService& config, RenderContext& renderContext,
                                 LayerPopupHostRegistry& popupHosts, ThumbnailService& thumbnails) {
  m_wayland = &wayland;
  m_config = &config;
  m_renderContext = &renderContext;
  m_popupHosts = &popupHosts;
  m_thumbnails = &thumbnails;
}

bool FileDialogPopup::openFileDialog() {
  if (m_wayland == nullptr || m_renderContext == nullptr || m_popupHosts == nullptr || m_thumbnails == nullptr) {
    return false;
  }

  closeFileDialogWithoutResult();

  const auto parentContext = resolveParentContext();
  if (!parentContext.has_value()) {
    return false;
  }
  m_parentSurface = parentContext->surface;

  auto dialog = std::make_unique<FileDialogView>(m_thumbnails);
  dialog->setHost(this);
  dialog->setContentScale(uiScale());

  const auto width = static_cast<std::uint32_t>(dialog->preferredWidth());
  const auto height = static_cast<std::uint32_t>(dialog->preferredHeight());

  auto surface = std::make_unique<PopupSurface>(*m_wayland);
  surface->setAnimationManager(&m_animations);
  surface->setRenderContext(m_renderContext);
  surface->setConfigureCallback([this](std::uint32_t /*width*/, std::uint32_t /*height*/) { requestLayout(); });
  surface->setPrepareFrameCallback(
      [this](bool needsUpdate, bool needsLayout) { prepareFrame(needsUpdate, needsLayout); });
  surface->setDismissedCallback([this]() { cancel(); });

  PopupSurfaceConfig popupConfig{
      .anchorX = 0,
      .anchorY = 0,
      .anchorWidth = static_cast<std::int32_t>(parentContext->width),
      .anchorHeight = static_cast<std::int32_t>(parentContext->height),
      .width = width,
      .height = height,
      .anchor = XDG_POSITIONER_ANCHOR_NONE,
      .gravity = XDG_POSITIONER_GRAVITY_NONE,
      .constraintAdjustment = kPopupConstraintAdjust,
      .offsetX = 0,
      .offsetY = 0,
      .serial = m_wayland->lastInputSerial(),
      .grab = true,
  };

  m_dialog = std::move(dialog);
  m_surface = std::move(surface);
  m_popupHosts->beginAttachedPopup(m_parentSurface);
  m_attachedToHost = true;
  if (!m_surface->initialize(parentContext->layerSurface, parentContext->output, popupConfig)) {
    destroyPopup();
    return false;
  }
  return true;
}

void FileDialogPopup::closeFileDialogWithoutResult() { destroyPopup(); }

bool FileDialogPopup::onPointerEvent(const PointerEvent& event) {
  if (m_surface == nullptr) {
    return false;
  }

  const bool captured = m_inputDispatcher.pointerCaptured();
  wl_surface* const eventSurface = resolveEventSurface(event);
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
      if (m_sceneRoot != nullptr && (m_sceneRoot->paintDirty() || m_sceneRoot->layoutDirty())) {
        if (m_sceneRoot->layoutDirty()) {
          requestLayout();
        } else {
          requestRedraw();
        }
      }
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
    if (event.state == 1 && !captured) {
      if (m_inputDispatcher.pointerCaptured()) {
        m_captureCoordinateSpace =
            ownsSurface(eventSurface) ? CaptureCoordinateSpace::PopupLocal : CaptureCoordinateSpace::ParentMapped;
      }
    } else if (event.state != 1 && !m_inputDispatcher.pointerCaptured()) {
      m_captureCoordinateSpace = CaptureCoordinateSpace::None;
    }
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

  if (m_sceneRoot != nullptr && (m_sceneRoot->paintDirty() || m_sceneRoot->layoutDirty())) {
    if (m_sceneRoot->layoutDirty()) {
      requestLayout();
    } else {
      requestRedraw();
    }
  }
  return true;
}

void FileDialogPopup::onKeyboardEvent(const KeyboardEvent& event) {
  if (m_surface == nullptr || m_dialog == nullptr) {
    return;
  }

  if (m_dialog->handleGlobalKey(event.sym, event.modifiers, event.pressed, event.preedit)) {
    if (m_sceneRoot != nullptr && (m_sceneRoot->paintDirty() || m_sceneRoot->layoutDirty())) {
      if (m_sceneRoot->layoutDirty()) {
        requestLayout();
      } else {
        requestRedraw();
      }
    }
    return;
  }

  m_inputDispatcher.keyEvent(event.sym, event.utf32, event.modifiers, event.pressed, event.preedit);
  if (m_sceneRoot != nullptr && (m_sceneRoot->paintDirty() || m_sceneRoot->layoutDirty())) {
    if (m_sceneRoot->layoutDirty()) {
      requestLayout();
    } else {
      requestRedraw();
    }
  }
}

void FileDialogPopup::requestFontLayout() {
  if (m_surface != nullptr) {
    m_surface->requestLayout();
  }
}

void FileDialogPopup::requestThemeRedraw() {
  if (m_surface != nullptr) {
    m_surface->requestRedraw();
  }
}

wl_surface* FileDialogPopup::wlSurface() const noexcept {
  return m_surface != nullptr ? m_surface->wlSurface() : nullptr;
}

void FileDialogPopup::requestUpdateOnly() {
  if (m_surface != nullptr) {
    m_surface->requestUpdateOnly();
  }
}

void FileDialogPopup::requestLayout() {
  if (m_surface != nullptr) {
    m_surface->requestLayout();
  }
}

void FileDialogPopup::requestRedraw() {
  if (m_surface != nullptr) {
    m_surface->requestRedraw();
  }
}

void FileDialogPopup::focusArea(InputArea* area) { m_inputDispatcher.setFocus(area); }

InputArea* FileDialogPopup::focusedArea() const { return m_inputDispatcher.focusedArea(); }

void FileDialogPopup::accept(std::optional<std::filesystem::path> result) {
  destroyPopup();
  FileDialog::complete(std::move(result));
}

void FileDialogPopup::cancel() {
  if (m_surface == nullptr) {
    return;
  }
  destroyPopup();
  FileDialog::cancelIfPending();
}

void FileDialogPopup::prepareFrame(bool needsUpdate, bool needsLayout) {
  if (m_surface == nullptr || m_renderContext == nullptr || m_dialog == nullptr) {
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
    m_dialog->update(*m_renderContext);
  }
  if (needsLayout) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    layoutScene(static_cast<float>(width), static_cast<float>(height));
  }
}

void FileDialogPopup::buildScene(std::uint32_t width, std::uint32_t height) {
  if (m_dialog == nullptr) {
    return;
  }

  m_sceneRoot = std::make_unique<Node>();
  m_sceneRoot->setAnimationManager(&m_animations);

  auto bg = std::make_unique<Box>();
  bg->setPanelStyle();
  m_bgNode = static_cast<Box*>(m_sceneRoot->addChild(std::move(bg)));

  auto content = std::make_unique<Node>();
  m_contentNode = content.get();
  m_dialog->setAnimationManager(&m_animations);
  m_dialog->create();
  m_dialog->onOpen({});
  if (m_dialog->root() != nullptr) {
    content->addChild(m_dialog->releaseRoot());
  }
  m_sceneRoot->addChild(std::move(content));

  m_inputDispatcher.setSceneRoot(m_sceneRoot.get());
  m_inputDispatcher.setCursorShapeCallback(
      [this](std::uint32_t serial, std::uint32_t shape) { m_wayland->setCursorShape(serial, shape); });
  m_surface->setSceneRoot(m_sceneRoot.get());

  if (auto* focusArea = m_dialog->initialFocusArea(); focusArea != nullptr) {
    m_inputDispatcher.setFocus(focusArea);
  }

  layoutScene(static_cast<float>(width), static_cast<float>(height));
  syncPointerStateFromCurrentPosition();
}

void FileDialogPopup::layoutScene(float width, float height) {
  if (m_sceneRoot == nullptr || m_dialog == nullptr) {
    return;
  }

  m_sceneRoot->setSize(width, height);
  if (m_bgNode != nullptr) {
    m_bgNode->setPosition(0.0f, 0.0f);
    m_bgNode->setSize(width, height);
  }

  const float padding = m_dialog->hasDecoration() ? m_dialog->contentScale() * 12.0f : 0.0f;
  const float contentWidth = width - padding * 2.0f;
  const float contentHeight = height - padding * 2.0f;

  {
    UiPhaseScope updatePhase(UiPhase::Update);
    m_dialog->update(*m_renderContext);
  }
  {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    m_dialog->layout(*m_renderContext, contentWidth, contentHeight);
  }

  if (m_contentNode != nullptr) {
    m_contentNode->setPosition(padding, padding);
    m_contentNode->setSize(contentWidth, contentHeight);
  }
}

void FileDialogPopup::destroyPopup() {
  if (m_attachedToHost && m_popupHosts != nullptr) {
    m_popupHosts->endAttachedPopup(m_parentSurface);
    m_attachedToHost = false;
  }
  m_pointerInside = false;
  m_parentSurface = nullptr;
  m_captureCoordinateSpace = CaptureCoordinateSpace::None;
  m_inputDispatcher.setSceneRoot(nullptr);
  if (m_dialog != nullptr) {
    m_dialog->onClose();
    m_dialog.reset();
  }
  m_bgNode = nullptr;
  m_contentNode = nullptr;
  m_sceneRoot.reset();
  m_surface.reset();
}

bool FileDialogPopup::mapPointerEvent(const PointerEvent& event, float& localX, float& localY) const noexcept {
  if (m_surface == nullptr) {
    return false;
  }

  wl_surface* eventSurface = resolveEventSurface(event);
  if (eventSurface == nullptr) {
    return false;
  }

  if (m_inputDispatcher.pointerCaptured() && event.type != PointerEvent::Type::Leave) {
    switch (m_captureCoordinateSpace) {
    case CaptureCoordinateSpace::PopupLocal:
      localX = static_cast<float>(event.sx);
      localY = static_cast<float>(event.sy);
      return true;
    case CaptureCoordinateSpace::ParentMapped:
      localX = static_cast<float>(event.sx) - static_cast<float>(m_surface->configuredX());
      localY = static_cast<float>(event.sy) - static_cast<float>(m_surface->configuredY());
      return true;
    case CaptureCoordinateSpace::None:
      break;
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

void FileDialogPopup::syncPointerStateFromCurrentPosition() {
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
  if (m_sceneRoot != nullptr && (m_sceneRoot->paintDirty() || m_sceneRoot->layoutDirty())) {
    if (m_sceneRoot->layoutDirty()) {
      requestLayout();
    } else {
      requestRedraw();
    }
  }
}

bool FileDialogPopup::ownsSurface(wl_surface* surface) const noexcept {
  return m_surface != nullptr && surface != nullptr && surface == m_surface->wlSurface();
}

wl_surface* FileDialogPopup::resolveEventSurface(const PointerEvent& event) const noexcept {
  wl_surface* eventSurface = event.surface;
  if (eventSurface == nullptr && event.type == PointerEvent::Type::Motion && m_wayland != nullptr) {
    eventSurface = m_wayland->lastPointerSurface();
  }
  return eventSurface;
}

std::optional<LayerPopupParentContext> FileDialogPopup::resolveParentContext() const {
  if (m_wayland == nullptr || m_popupHosts == nullptr) {
    return std::nullopt;
  }

  const auto trySurface = [this](wl_surface* surface) { return m_popupHosts->contextForSurface(surface); };

  if (m_wayland->lastInputSource() == WaylandSeat::InputSource::Keyboard) {
    if (auto context = trySurface(m_wayland->lastKeyboardSurface()); context.has_value()) {
      return context;
    }
    if (auto context = trySurface(m_wayland->lastPointerSurface()); context.has_value()) {
      return context;
    }
  } else {
    if (auto context = trySurface(m_wayland->lastPointerSurface()); context.has_value()) {
      return context;
    }
    if (auto context = trySurface(m_wayland->lastKeyboardSurface()); context.has_value()) {
      return context;
    }
  }

  return m_popupHosts->fallbackContext();
}

float FileDialogPopup::uiScale() const {
  if (m_config == nullptr) {
    return 1.0f;
  }
  return std::max(0.1f, m_config->config().shell.uiScale);
}
