#include "ui/controls/context_menu_popup.h"

#include "core/deferred_call.h"
#include "core/log.h"
#include "core/ui_phase.h"
#include "render/render_context.h"
#include "render/scene/node.h"
#include "ui/style.h"
#include "wayland/popup_surface.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"
#include "xdg-shell-client-protocol.h"

#include <algorithm>
#include <cmath>
#include <utility>

namespace {

  constexpr Logger kLog("context-menu-popup");

} // namespace

ContextMenuPopup::ContextMenuPopup(WaylandConnection& wayland, RenderContext& renderContext)
    : m_wayland(wayland), m_renderContext(renderContext) {}

ContextMenuPopup::~ContextMenuPopup() { close(); }

void ContextMenuPopup::open(std::vector<ContextMenuControlEntry> entries, float menuWidth, std::size_t maxVisible,
                            std::int32_t anchorX, std::int32_t anchorY, std::int32_t anchorW, std::int32_t anchorH,
                            zwlr_layer_surface_v1* parentLayerSurface, wl_output* output) {
  close();

  const float menuHeight = ContextMenuControl::preferredHeight(entries, maxVisible);

  PopupSurfaceConfig popupCfg{
      .anchorX = anchorX,
      .anchorY = anchorY,
      .anchorWidth = std::max(1, anchorW),
      .anchorHeight = std::max(1, anchorH),
      .width = static_cast<std::uint32_t>(std::max(1.0f, menuWidth)),
      .height = static_cast<std::uint32_t>(std::max(1.0f, menuHeight)),
      .anchor = XDG_POSITIONER_ANCHOR_BOTTOM,
      .gravity = XDG_POSITIONER_GRAVITY_BOTTOM,
      .constraintAdjustment = XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X |
                              XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_Y |
                              XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_X | XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_Y,
      .offsetX = 0,
      .offsetY = static_cast<std::int32_t>(Style::spaceXs),
      .serial = m_wayland.lastInputSerial(),
      .grab = true,
  };

  m_surface = std::make_unique<PopupSurface>(m_wayland);
  m_surface->setRenderContext(&m_renderContext);

  auto* self = this;

  m_surface->setConfigureCallback(
      [self](std::uint32_t /*w*/, std::uint32_t /*h*/) { self->m_surface->requestLayout(); });

  m_surface->setPrepareFrameCallback(
      [self, entries = std::move(entries), maxVisible](bool /*needsUpdate*/, bool needsLayout) {
        if (self->m_surface == nullptr) {
          return;
        }

        const auto width = self->m_surface->width();
        const auto height = self->m_surface->height();
        if (width == 0 || height == 0) {
          return;
        }

        self->m_renderContext.makeCurrent(self->m_surface->renderTarget());

        const bool needsSceneBuild = self->m_sceneRoot == nullptr ||
                                     static_cast<std::uint32_t>(std::round(self->m_sceneRoot->width())) != width ||
                                     static_cast<std::uint32_t>(std::round(self->m_sceneRoot->height())) != height;
        if (!needsSceneBuild && !needsLayout) {
          return;
        }

        UiPhaseScope layoutPhase(UiPhase::Layout);

        const auto fw = static_cast<float>(width);
        const auto fh = static_cast<float>(height);

        self->m_sceneRoot = std::make_unique<Node>();
        self->m_sceneRoot->setSize(fw, fh);

        auto ctrl = std::make_unique<ContextMenuControl>();
        ctrl->setMenuWidth(fw);
        ctrl->setMaxVisible(maxVisible);
        ctrl->setEntries(entries);
        ctrl->setRedrawCallback([self]() {
          if (self->m_surface)
            self->m_surface->requestRedraw();
        });
        ctrl->setOnActivate([self](const ContextMenuControlEntry& e) {
          auto onActivate = self->m_onActivate;
          DeferredCall::callLater([self, onActivate, e]() {
            if (onActivate) {
              onActivate(e);
            }
            self->close();
          });
        });
        ctrl->setPosition(0.0f, 0.0f);
        ctrl->setSize(fw, fh);
        ctrl->layout(self->m_renderContext);

        self->m_sceneRoot->addChild(std::move(ctrl));
        self->m_inputDispatcher.setSceneRoot(self->m_sceneRoot.get());
        self->m_inputDispatcher.setCursorShapeCallback(
            [self](std::uint32_t serial, std::uint32_t shape) { self->m_wayland.setCursorShape(serial, shape); });
        self->m_surface->setSceneRoot(self->m_sceneRoot.get());
      });

  m_surface->setDismissedCallback([self]() { DeferredCall::callLater([self]() { self->close(); }); });

  if (!m_surface->initialize(parentLayerSurface, output, popupCfg)) {
    kLog.warn("failed to create context menu popup");
    m_surface.reset();
    return;
  }

  m_wlSurface = m_surface->wlSurface();
}

void ContextMenuPopup::close() {
  const bool wasOpen = m_surface != nullptr;
  m_sceneRoot.reset();
  m_surface.reset();
  m_wlSurface = nullptr;
  m_pointerInside = false;
  if (wasOpen && m_onDismissed) {
    m_onDismissed();
  }
}

bool ContextMenuPopup::isOpen() const noexcept { return m_surface != nullptr; }

void ContextMenuPopup::setOnActivate(std::function<void(const ContextMenuControlEntry&)> callback) {
  m_onActivate = std::move(callback);
}

void ContextMenuPopup::setOnDismissed(std::function<void()> callback) { m_onDismissed = std::move(callback); }

bool ContextMenuPopup::onPointerEvent(const PointerEvent& event) {
  if (!isOpen()) {
    return false;
  }

  const bool onPopup = (event.surface != nullptr && event.surface == m_wlSurface);

  switch (event.type) {
  case PointerEvent::Type::Enter:
    if (onPopup) {
      m_pointerInside = true;
      m_inputDispatcher.pointerEnter(static_cast<float>(event.sx), static_cast<float>(event.sy), event.serial);
    }
    break;
  case PointerEvent::Type::Leave:
    if (onPopup) {
      m_pointerInside = false;
      m_inputDispatcher.pointerLeave();
    }
    break;
  case PointerEvent::Type::Motion:
    if (onPopup || m_pointerInside) {
      if (onPopup) {
        m_pointerInside = true;
      }
      m_inputDispatcher.pointerMotion(static_cast<float>(event.sx), static_cast<float>(event.sy), 0);
      return true;
    }
    break;
  case PointerEvent::Type::Button:
    if (onPopup || m_pointerInside) {
      if (onPopup) {
        m_pointerInside = true;
      }
      const bool pressed = (event.state == 1);
      m_inputDispatcher.pointerButton(static_cast<float>(event.sx), static_cast<float>(event.sy), event.button,
                                      pressed);
      return true;
    }
    break;
  case PointerEvent::Type::Axis:
    break;
  }

  if (m_surface != nullptr && m_sceneRoot != nullptr && m_surface->isRunning()) {
    m_surface->requestRedraw();
  }

  return onPopup;
}

wl_surface* ContextMenuPopup::wlSurface() const noexcept { return m_wlSurface; }
