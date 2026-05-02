#include "ui/dialogs/color_picker_dialog_popup.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/ui_phase.h"
#include "render/core/renderer.h"
#include "render/render_context.h"
#include "render/scene/node.h"
#include "ui/controls/box.h"
#include "ui/controls/color_picker.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/popup_surface.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"
#include "xdg-shell-client-protocol.h"
#include "xkbcommon/xkbcommon-keysyms.h"

#include <algorithm>
#include <cmath>
#include <memory>

namespace {

  constexpr std::uint32_t kPopupConstraintAdjust =
      XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X | XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_Y |
      XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_X | XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_Y;

} // namespace

void ColorPickerDialogPopup::initialize(WaylandConnection& wayland, ConfigService& config, RenderContext& renderContext,
                                        LayerPopupHostRegistry& popupHosts) {
  m_wayland = &wayland;
  m_config = &config;
  m_renderContext = &renderContext;
  m_popupHosts = &popupHosts;
}

bool ColorPickerDialogPopup::openColorPicker() {
  if (m_wayland == nullptr || m_renderContext == nullptr || m_popupHosts == nullptr) {
    return false;
  }

  closeColorPickerWithoutResult();

  const auto parentContext = resolveParentContext();
  if (!parentContext.has_value()) {
    return false;
  }
  m_parentSurface = parentContext->surface;

  const float scale = uiScale();
  const auto width = static_cast<std::uint32_t>(ColorPickerSheet::preferredDialogWidth(scale));
  const auto height =
      static_cast<std::uint32_t>(ColorPickerSheet::preferredDialogHeight(static_cast<float>(width), scale));

  auto surface = std::make_unique<PopupSurface>(*m_wayland);
  surface->setAnimationManager(&m_animations);
  surface->setRenderContext(m_renderContext);
  surface->setConfigureCallback([this](std::uint32_t /*width*/, std::uint32_t /*height*/) { requestFontLayout(); });
  surface->setPrepareFrameCallback(
      [this](bool needsUpdate, bool needsLayout) { prepareFrame(needsUpdate, needsLayout); });
  surface->setDismissedCallback([this]() { cancel(); });

  const auto [offsetX, offsetY] = parentContext->centeringOffset(*m_wayland);

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
      .offsetX = offsetX,
      .offsetY = offsetY,
      .serial = m_wayland->lastInputSerial(),
      .grab = true,
  };

  m_surface = std::move(surface);
  m_popupHosts->beginAttachedPopup(m_parentSurface);
  m_attachedToHost = true;
  if (!m_surface->initialize(parentContext->layerSurface, parentContext->output, popupConfig)) {
    destroyPopup();
    return false;
  }
  return true;
}

void ColorPickerDialogPopup::closeColorPickerWithoutResult() { destroyPopup(); }

bool ColorPickerDialogPopup::onPointerEvent(const PointerEvent& event) {
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
          requestFontLayout();
        } else {
          requestThemeRedraw();
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
      requestFontLayout();
    } else {
      requestThemeRedraw();
    }
  }
  return true;
}

void ColorPickerDialogPopup::onKeyboardEvent(const KeyboardEvent& event) {
  if (m_surface == nullptr) {
    return;
  }

  if (event.pressed && !event.preedit && event.sym == XKB_KEY_Escape) {
    cancel();
    return;
  }

  m_inputDispatcher.keyEvent(event.sym, event.utf32, event.modifiers, event.pressed, event.preedit);
  if (m_sceneRoot != nullptr && (m_sceneRoot->paintDirty() || m_sceneRoot->layoutDirty())) {
    if (m_sceneRoot->layoutDirty()) {
      requestFontLayout();
    } else {
      requestThemeRedraw();
    }
  }
}

void ColorPickerDialogPopup::requestFontLayout() {
  if (m_surface != nullptr) {
    m_surface->requestLayout();
  }
}

void ColorPickerDialogPopup::requestThemeRedraw() {
  if (m_surface != nullptr) {
    m_surface->requestRedraw();
  }
}

wl_surface* ColorPickerDialogPopup::wlSurface() const noexcept {
  return m_surface != nullptr ? m_surface->wlSurface() : nullptr;
}

void ColorPickerDialogPopup::accept(const Color& result) {
  destroyPopup();
  ColorPickerDialog::complete(result);
}

void ColorPickerDialogPopup::cancel() {
  if (m_surface == nullptr) {
    return;
  }
  destroyPopup();
  ColorPickerDialog::cancelIfPending();
}

void ColorPickerDialogPopup::prepareFrame(bool needsUpdate, bool needsLayout) {
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

  if (needsLayout) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    layoutScene(static_cast<float>(width), static_cast<float>(height));
  }
  if (needsUpdate && m_sceneRoot != nullptr && m_sceneRoot->layoutDirty()) {
    requestFontLayout();
  }
}

void ColorPickerDialogPopup::buildScene(std::uint32_t width, std::uint32_t height) {
  m_sceneRoot = std::make_unique<Node>();
  m_sceneRoot->setAnimationManager(&m_animations);

  auto bg = std::make_unique<Box>();
  bg->setPanelStyle();
  m_bgNode = static_cast<Box*>(m_sceneRoot->addChild(std::move(bg)));

  auto content = std::make_unique<Node>();
  m_contentNode = content.get();

  auto sheet = std::make_unique<ColorPickerSheet>(uiScale());
  sheet->setTitle(ColorPickerDialog::currentOptions().title);
  if (const auto& initialColor = ColorPickerDialog::currentOptions().initialColor; initialColor.has_value()) {
    sheet->colorPicker()->setColor(*initialColor);
  } else {
    sheet->colorPicker()->setColor(colorForRole(ColorRole::Primary));
  }
  sheet->setOnCancel([this]() { DeferredCall::callLater([this]() { cancel(); }); });
  sheet->setOnApply([this](const Color& color) { DeferredCall::callLater([this, color]() { accept(color); }); });
  m_sheet = sheet.get();
  content->addChild(std::move(sheet));
  m_sceneRoot->addChild(std::move(content));

  m_inputDispatcher.setSceneRoot(m_sceneRoot.get());
  m_inputDispatcher.setCursorShapeCallback(
      [this](std::uint32_t serial, std::uint32_t shape) { m_wayland->setCursorShape(serial, shape); });
  m_surface->setSceneRoot(m_sceneRoot.get());

  if (m_sheet != nullptr) {
    if (auto* focusArea = m_sheet->initialFocusArea(); focusArea != nullptr) {
      m_inputDispatcher.setFocus(focusArea);
    }
  }

  layoutScene(static_cast<float>(width), static_cast<float>(height));
  syncPointerStateFromCurrentPosition();
}

void ColorPickerDialogPopup::layoutScene(float width, float height) {
  if (m_sceneRoot == nullptr || m_sheet == nullptr) {
    return;
  }

  m_sceneRoot->setSize(width, height);
  if (m_bgNode != nullptr) {
    m_bgNode->setPosition(0.0f, 0.0f);
    m_bgNode->setSize(width, height);
  }

  const float padding = uiScale() * 12.0f;
  const float contentWidth = width - padding * 2.0f;
  const float contentHeight = height - padding * 2.0f;
  const float sheetPadding = Style::spaceSm * uiScale();

  m_sheet->setPickerColumnWidth(std::max(160.0f, contentWidth - sheetPadding * 2.0f));
  m_sheet->setSize(contentWidth, contentHeight);
  m_sheet->layout(*m_renderContext);

  if (m_contentNode != nullptr) {
    m_contentNode->setPosition(padding, padding);
    m_contentNode->setSize(contentWidth, contentHeight);
  }
}

void ColorPickerDialogPopup::destroyPopup() {
  if (m_attachedToHost && m_popupHosts != nullptr) {
    m_popupHosts->endAttachedPopup(m_parentSurface);
    m_attachedToHost = false;
  }
  m_pointerInside = false;
  m_parentSurface = nullptr;
  m_captureCoordinateSpace = CaptureCoordinateSpace::None;
  m_inputDispatcher.setSceneRoot(nullptr);
  m_sheet = nullptr;
  m_bgNode = nullptr;
  m_contentNode = nullptr;
  m_sceneRoot.reset();
  m_surface.reset();
}

bool ColorPickerDialogPopup::mapPointerEvent(const PointerEvent& event, float& localX, float& localY) const noexcept {
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

void ColorPickerDialogPopup::syncPointerStateFromCurrentPosition() {
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
      requestFontLayout();
    } else {
      requestThemeRedraw();
    }
  }
}

bool ColorPickerDialogPopup::ownsSurface(wl_surface* surface) const noexcept {
  return m_surface != nullptr && surface != nullptr && surface == m_surface->wlSurface();
}

wl_surface* ColorPickerDialogPopup::resolveEventSurface(const PointerEvent& event) const noexcept {
  wl_surface* eventSurface = event.surface;
  if (eventSurface == nullptr && event.type == PointerEvent::Type::Motion && m_wayland != nullptr) {
    eventSurface = m_wayland->lastPointerSurface();
  }
  return eventSurface;
}

std::optional<LayerPopupParentContext> ColorPickerDialogPopup::resolveParentContext() const {
  if (m_wayland == nullptr || m_popupHosts == nullptr) {
    return std::nullopt;
  }
  return m_popupHosts->resolveForInput(*m_wayland);
}

float ColorPickerDialogPopup::uiScale() const {
  if (m_config == nullptr) {
    return 1.0f;
  }
  return std::max(0.1f, m_config->config().shell.uiScale);
}
