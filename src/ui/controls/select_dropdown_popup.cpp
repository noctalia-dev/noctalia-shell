#include "ui/controls/select_dropdown_popup.h"

#include "core/deferred_call.h"
#include "core/log.h"
#include "core/ui_phase.h"
#include "cursor-shape-v1-client-protocol.h"
#include "render/core/render_styles.h"
#include "render/render_context.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "render/scene/rect_node.h"
#include "ui/controls/box.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/popup_chrome.h"
#include "ui/style.h"
#include "wayland/popup_surface.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"
#include "xdg-shell-client-protocol.h"

#include <algorithm>
#include <cmath>
#include <linux/input-event-codes.h>
#include <utility>
#include <wayland-client-protocol.h>
#include <xkbcommon/xkbcommon-keysyms.h>

namespace {

  constexpr Logger kLog("select-dropdown-popup");
  constexpr float kMenuPadding = Style::spaceXs;

  Color resolved(ColorRole role, float alpha = 1.0f) { return colorForRole(role, alpha); }

} // namespace

SelectDropdownPopup::SelectDropdownPopup(WaylandConnection& wayland, RenderContext& renderContext)
    : m_wayland(wayland), m_renderContext(renderContext) {}

SelectDropdownPopup::~SelectDropdownPopup() { closeSelectDropdown(); }

void SelectDropdownPopup::setParent(zwlr_layer_surface_v1* layerSurface, wl_output* output) {
  m_parentLayerSurface = layerSurface;
  m_parentXdgSurface = nullptr;
  m_parentOutput = output;
}

void SelectDropdownPopup::setParent(xdg_surface* xdgSurface, wl_output* output) {
  m_parentLayerSurface = nullptr;
  m_parentXdgSurface = xdgSurface;
  m_parentOutput = output;
}

void SelectDropdownPopup::setShadowConfig(const ShellConfig::ShadowConfig& shadow) {
  if (m_shadowConfig == shadow) {
    return;
  }
  m_shadowConfig = shadow;
  if (isSelectDropdownOpen()) {
    closeSelectDropdown();
  }
}

void SelectDropdownPopup::openSelectDropdown(const DropdownRequest& request, DropdownCallbacks callbacks) {
  if (m_openInProgress) {
    m_closeRequestedDuringOpen = true;
    if (callbacks.onDismiss) {
      callbacks.onDismiss();
    }
    return;
  }

  closeSelectDropdown();

  if (m_parentLayerSurface == nullptr && m_parentXdgSurface == nullptr) {
    kLog.warn("no parent surface set");
    return;
  }

  m_closeRequestedDuringOpen = false;
  m_callbacks = std::move(callbacks);
  m_options = request.options;
  m_selectedIndex = request.selectedIndex;
  m_hoveredIndex = m_selectedIndex < m_options.size() ? m_selectedIndex : 0;
  m_optionHeight = request.optionHeight;
  m_menuWidth = request.menuWidth;

  const std::size_t visibleCount = std::min(request.maxVisibleOptions, m_options.size());
  m_viewportHeight = static_cast<float>(visibleCount) * m_optionHeight + kMenuPadding * 2.0f;
  m_totalHeight = static_cast<float>(m_options.size()) * m_optionHeight;
  m_scrollOffset = 0.0f;
  const auto chrome = popup_chrome::computeGeometry(m_menuWidth, m_viewportHeight, m_shadowConfig);

  if (m_selectedIndex < m_options.size()) {
    const float selectedTop = static_cast<float>(m_selectedIndex) * m_optionHeight;
    const float contentViewport = m_viewportHeight - kMenuPadding * 2.0f;
    if (selectedTop + m_optionHeight > contentViewport) {
      m_scrollOffset = selectedTop + m_optionHeight - contentViewport;
    }
    clampScrollOffset();
  }

  PopupSurfaceConfig popupCfg{
      .anchorX = request.anchorX,
      .anchorY = request.anchorY,
      .anchorWidth = std::max(1, request.anchorWidth),
      .anchorHeight = std::max(1, request.anchorHeight),
      .width = chrome.surfaceWidth,
      .height = chrome.surfaceHeight,
      .anchor = XDG_POSITIONER_ANCHOR_BOTTOM,
      .gravity = XDG_POSITIONER_GRAVITY_BOTTOM,
      .constraintAdjustment = XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_X |
                              XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_SLIDE_Y |
                              XDG_POSITIONER_CONSTRAINT_ADJUSTMENT_FLIP_Y,
      .offsetX = 0,
      .offsetY = static_cast<std::int32_t>(std::lround(Style::spaceXs)),
      .serial = m_wayland.lastInputSerial(),
      .grab = true,
  };
  popup_chrome::applyToConfig(popupCfg, chrome,
                              popup_chrome::Attachment{.horizontal = popup_chrome::HorizontalAttachment::Center,
                                                       .vertical = popup_chrome::VerticalAttachment::Top});

  m_surface = std::make_unique<PopupSurface>(m_wayland);
  m_surface->setRenderContext(&m_renderContext);

  auto* self = this;

  m_surface->setConfigureCallback(
      [self](std::uint32_t /*w*/, std::uint32_t /*h*/) { self->m_surface->requestLayout(); });

  m_surface->setPrepareFrameCallback([self, request](bool /*needsUpdate*/, bool needsLayout) {
    if (self->m_surface == nullptr) {
      return;
    }

    const auto width = self->m_surface->width();
    const auto height = self->m_surface->height();
    if (width == 0 || height == 0) {
      return;
    }

    self->m_renderContext.makeCurrent(self->m_surface->renderTarget());

    const bool needsSceneBuild = self->m_sceneDirty || self->m_sceneRoot == nullptr ||
                                 static_cast<std::uint32_t>(std::round(self->m_sceneRoot->width())) != width ||
                                 static_cast<std::uint32_t>(std::round(self->m_sceneRoot->height())) != height;
    if (!needsSceneBuild && !needsLayout) {
      return;
    }

    UiPhaseScope layoutPhase(UiPhase::Layout);

    if (needsSceneBuild) {
      self->m_sceneDirty = false;
      self->buildScene(request);
    }

    const auto fw = static_cast<float>(width);
    const auto fh = static_cast<float>(height);
    self->m_sceneRoot->setSize(fw, fh);
    self->m_sceneRoot->layout(self->m_renderContext);

    self->m_inputDispatcher.setSceneRoot(self->m_sceneRoot.get());
    self->m_inputDispatcher.setCursorShapeCallback(
        [self](std::uint32_t serial, std::uint32_t shape) { self->m_wayland.setCursorShape(serial, shape); });
    self->m_surface->setSceneRoot(self->m_sceneRoot.get());
  });

  m_surface->setDismissedCallback([self]() { DeferredCall::callLater([self]() { self->closeSelectDropdown(); }); });

  m_openInProgress = true;
  const bool initialized = m_parentLayerSurface != nullptr
                               ? m_surface->initialize(m_parentLayerSurface, m_parentOutput, popupCfg)
                               : m_surface->initializeAsChild(m_parentXdgSurface, m_parentOutput, popupCfg);
  m_openInProgress = false;
  if (!initialized) {
    kLog.warn("failed to create select dropdown popup");
    closeSelectDropdown();
    return;
  }
  if (m_closeRequestedDuringOpen) {
    closeSelectDropdown();
    return;
  }

  popup_chrome::setContentInputRegion(*m_surface, chrome);

  m_wlSurface = m_surface->wlSurface();
}

void SelectDropdownPopup::closeSelectDropdown() {
  auto onDismiss = std::move(m_callbacks.onDismiss);
  m_optionViews.clear();
  m_inputDispatcher.setSceneRoot(nullptr);
  m_sceneRoot.reset();
  if (m_openInProgress) {
    m_closeRequestedDuringOpen = true;
  } else {
    m_surface.reset();
    m_closeRequestedDuringOpen = false;
  }
  m_wlSurface = nullptr;
  m_pointerInside = false;
  m_options.clear();
  m_callbacks = {};
  m_sceneDirty = false;
  if (onDismiss) {
    onDismiss();
  }
}

bool SelectDropdownPopup::isSelectDropdownOpen() const { return m_surface != nullptr; }

void SelectDropdownPopup::buildScene(const DropdownRequest& request) {
  m_sceneRoot = std::make_unique<Node>();
  m_optionViews.clear();
  const auto chrome = popup_chrome::computeGeometry(m_menuWidth, m_viewportHeight, m_shadowConfig);
  const float menuX = chrome.contentX();
  const float menuY = chrome.contentY();
  const float radius = Style::scaledRadiusMd();

  (void)popup_chrome::addShadow(*m_sceneRoot, chrome, m_shadowConfig, radius);

  auto bg = std::make_unique<RectNode>();
  bg->setStyle(RoundedRectStyle{
      .fill = resolved(ColorRole::SurfaceVariant),
      .border = resolved(ColorRole::Outline),
      .fillMode = FillMode::Solid,
      .radius = radius,
      .softness = 1.0f,
      .borderWidth = Style::borderWidth,
  });
  auto* bgNode = static_cast<RectNode*>(m_sceneRoot->addChild(std::move(bg)));
  bgNode->setPosition(menuX, menuY);
  bgNode->setFrameSize(m_menuWidth, m_viewportHeight);

  auto viewport = std::make_unique<Node>();
  viewport->setClipChildren(true);
  viewport->setPosition(menuX, menuY + kMenuPadding);
  viewport->setFrameSize(m_menuWidth, m_viewportHeight - kMenuPadding * 2.0f);
  auto* viewportNode = m_sceneRoot->addChild(std::move(viewport));

  const bool hasIndicators = !request.indicatorColors.empty();
  const float indicatorSize = hasIndicators ? std::round(request.fontSize) : 0.0f;
  const float indicatorBorder = hasIndicators ? 1.5f : 0.0f;
  const float indicatorInset = hasIndicators ? (indicatorSize + Style::spaceSm) : 0.0f;

  for (std::size_t i = 0; i < m_options.size(); ++i) {
    const float rowY = static_cast<float>(i) * m_optionHeight - m_scrollOffset;

    auto rowBg = std::make_unique<RectNode>();
    rowBg->setPosition(0.0f, rowY);
    rowBg->setFrameSize(m_menuWidth, m_optionHeight);
    auto* rowBgPtr = static_cast<RectNode*>(viewportNode->addChild(std::move(rowBg)));

    if (hasIndicators && i < request.indicatorColors.size()) {
      auto indicator = std::make_unique<Box>();
      indicator->setFill(request.indicatorColors[i]);
      indicator->setBorder(colorSpecFromRole(ColorRole::Outline), indicatorBorder);
      indicator->setFrameSize(indicatorSize, indicatorSize);
      indicator->setRadius(indicatorSize * 0.5f);
      indicator->setPosition(request.horizontalPadding, rowY + std::round((m_optionHeight - indicatorSize) * 0.5f));
      viewportNode->addChild(std::move(indicator));
    }

    auto label = std::make_unique<Label>();
    label->setText(m_options[i]);
    label->setFontSize(request.fontSize);
    const float labelLeft = request.horizontalPadding + indicatorInset;
    label->setMaxWidth(
        std::max(0.0f, m_menuWidth - labelLeft - request.horizontalPadding - request.glyphSize - Style::spaceXs));
    label->measure(m_renderContext);
    float labelY = std::round((m_optionHeight - label->height()) * 0.5f);
    label->setPosition(labelLeft, rowY + labelY);
    auto* labelPtr = static_cast<Label*>(viewportNode->addChild(std::move(label)));

    Glyph* checkPtr = nullptr;
    if (i == m_selectedIndex) {
      auto checkGlyph = std::make_unique<Glyph>();
      checkGlyph->setGlyph("check");
      checkGlyph->setGlyphSize(request.glyphSize);
      checkGlyph->measure(m_renderContext);
      float glyphY = std::round((m_optionHeight - checkGlyph->height()) * 0.5f);
      checkGlyph->setPosition(m_menuWidth - request.horizontalPadding - checkGlyph->width(), rowY + glyphY);
      checkPtr = static_cast<Glyph*>(viewportNode->addChild(std::move(checkGlyph)));
    }

    m_optionViews.push_back(OptionView{.background = rowBgPtr, .label = labelPtr, .checkGlyph = checkPtr});

    auto area = std::make_unique<InputArea>();
    area->setCursorShape(WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER);
    area->setPosition(0.0f, rowY);
    area->setFrameSize(m_menuWidth, m_optionHeight);
    area->setOnEnter([this, i](const InputArea::PointerData& /*data*/) {
      m_hoveredIndex = i;
      applyHoverVisuals();
      if (m_surface) {
        m_surface->requestRedraw();
      }
    });
    area->setOnClick([this, i](const InputArea::PointerData& data) {
      if (data.button != BTN_LEFT) {
        return;
      }
      selectAndClose(i);
    });
    area->setOnAxisHandler([this](const InputArea::PointerData& data) {
      if (data.axis != WL_POINTER_AXIS_VERTICAL_SCROLL) {
        return false;
      }
      scrollBy(data.scrollDelta(m_optionHeight));
      return true;
    });
    viewportNode->addChild(std::move(area));
  }

  applyHoverVisuals();
}

void SelectDropdownPopup::selectAndClose(std::size_t index) {
  auto onSelect = m_callbacks.onSelect;
  m_callbacks.onDismiss = nullptr;
  DeferredCall::callLater([this, onSelect, index]() {
    closeSelectDropdown();
    if (onSelect) {
      onSelect(index);
    }
  });
}

void SelectDropdownPopup::scrollBy(float delta) {
  m_scrollOffset += delta;
  clampScrollOffset();
  invalidateScene();
}

void SelectDropdownPopup::invalidateScene() {
  m_sceneDirty = true;
  if (m_surface) {
    m_surface->requestLayout();
  }
}

void SelectDropdownPopup::applyHoverVisuals() {
  for (std::size_t i = 0; i < m_optionViews.size(); ++i) {
    auto& view = m_optionViews[i];
    const bool isHovered = (i == m_hoveredIndex);
    const Color bgColor = isHovered ? resolved(ColorRole::Hover) : clearColor();
    const ColorSpec fg = isHovered ? colorSpecFromRole(ColorRole::OnHover) : colorSpecFromRole(ColorRole::OnSurface);

    if (view.background != nullptr) {
      view.background->setStyle(RoundedRectStyle{
          .fill = bgColor,
          .border = bgColor,
          .fillMode = FillMode::Solid,
          .radius = Style::scaledRadiusSm(),
          .softness = 1.0f,
          .borderWidth = 0.0f,
      });
    }
    if (view.label != nullptr) {
      view.label->setColor(fg);
    }
    if (view.checkGlyph != nullptr) {
      view.checkGlyph->setColor(fg);
    }
  }
}

void SelectDropdownPopup::clampScrollOffset() {
  const float contentViewport = m_viewportHeight - kMenuPadding * 2.0f;
  const float maxScroll = std::max(0.0f, m_totalHeight - contentViewport);
  m_scrollOffset = std::clamp(m_scrollOffset, 0.0f, maxScroll);
}

bool SelectDropdownPopup::onPointerEvent(const PointerEvent& event) {
  if (!isSelectDropdownOpen()) {
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
    if (onPopup || m_pointerInside) {
      m_inputDispatcher.pointerAxis(static_cast<float>(event.sx), static_cast<float>(event.sy), event.axis,
                                    event.axisSource, event.axisValue, event.axisDiscrete, event.axisValue120,
                                    event.axisLines);
      return true;
    }
    break;
  }

  if (m_surface != nullptr && m_sceneRoot != nullptr && m_surface->isRunning()) {
    m_surface->requestRedraw();
  }

  return onPopup;
}

void SelectDropdownPopup::onKeyboardEvent(const KeyboardEvent& event) {
  if (!isSelectDropdownOpen()) {
    return;
  }
  handleKey(event.sym, event.utf32, event.pressed);
}

void SelectDropdownPopup::handleKey(std::uint32_t sym, std::uint32_t /*utf32*/, bool pressed) {
  if (!pressed) {
    return;
  }

  if (sym == XKB_KEY_Escape) {
    auto onDismiss = m_callbacks.onDismiss;
    DeferredCall::callLater([this, onDismiss]() {
      closeSelectDropdown();
      if (onDismiss) {
        onDismiss();
      }
    });
  } else if (sym == XKB_KEY_Down) {
    if (!m_options.empty()) {
      m_hoveredIndex = (m_hoveredIndex + 1) % m_options.size();
      applyHoverVisuals();
      if (m_surface) {
        m_surface->requestRedraw();
      }
    }
  } else if (sym == XKB_KEY_Up) {
    if (!m_options.empty()) {
      m_hoveredIndex = (m_hoveredIndex + m_options.size() - 1) % m_options.size();
      applyHoverVisuals();
      if (m_surface) {
        m_surface->requestRedraw();
      }
    }
  } else if (sym == XKB_KEY_Return || sym == XKB_KEY_KP_Enter || sym == XKB_KEY_space) {
    if (m_hoveredIndex < m_options.size()) {
      selectAndClose(m_hoveredIndex);
    }
  } else if (sym == XKB_KEY_Home) {
    m_hoveredIndex = 0;
    applyHoverVisuals();
    if (m_surface) {
      m_surface->requestRedraw();
    }
  } else if (sym == XKB_KEY_End) {
    if (!m_options.empty()) {
      m_hoveredIndex = m_options.size() - 1;
      applyHoverVisuals();
      if (m_surface) {
        m_surface->requestRedraw();
      }
    }
  }
}

wl_surface* SelectDropdownPopup::wlSurface() const noexcept { return m_wlSurface; }
