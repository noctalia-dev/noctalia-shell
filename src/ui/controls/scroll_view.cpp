#include "ui/controls/scroll_view.h"

#include "render/programs/rounded_rect_program.h"
#include "render/scene/input_area.h"
#include "render/scene/rect_node.h"
#include "ui/palette.h"
#include "ui/style.h"

#include "cursor-shape-v1-client-protocol.h"
#include <linux/input-event-codes.h>
#include <wayland-client-protocol.h>

#include <algorithm>
#include <cmath>
#include <memory>

namespace {

constexpr float kDefaultWidth = 260.0f;
constexpr float kDefaultHeight = 180.0f;
constexpr float kScrollbarWidth = 6.0f;
constexpr float kScrollbarPadding = Style::borderWidth;
constexpr float kViewportPaddingH = Style::spaceXs;
constexpr float kScrollbarGap = Style::spaceSm;
constexpr float kMinThumbHeight = 24.0f;

RoundedRectStyle makeSolid(const Color& fill, float radius) {
  return RoundedRectStyle{
      .fill = fill,
      .border = fill,
      .fillMode = FillMode::Solid,
      .radius = radius,
      .softness = 1.0f,
      .borderWidth = 0.0f,
  };
}

} // namespace

ScrollView::ScrollView() {
  m_paletteConn = paletteChanged().connect([this] { applyPalette(); });
  setClipChildren(true);

  auto background = std::make_unique<RectNode>();
  m_background = static_cast<RectNode*>(addChild(std::move(background)));
  m_background->setStyle(RoundedRectStyle{
      .fill = clearColor(),
      .border = clearColor(),
      .fillMode = FillMode::Solid,
      .radius = Style::radiusMd,
      .softness = 1.0f,
      .borderWidth = 0,
  });

  auto viewportArea = std::make_unique<InputArea>();
  viewportArea->setOnPress([this](const InputArea::PointerData& data) {
    if (data.button != BTN_LEFT || !data.pressed || !scrollable()) {
      return;
    }
    // Background drag can be useful when content itself has no interactive children.
    m_dragStartLocalY = data.localY;
    m_dragStartOffset = m_scrollOffset;
  });
  viewportArea->setOnMotion([this](const InputArea::PointerData& data) {
    if (m_viewportArea == nullptr || !m_viewportArea->pressed() || !scrollable()) {
      return;
    }
    const float delta = data.localY - m_dragStartLocalY;
    setScrollOffset(m_dragStartOffset - delta);
  });
  viewportArea->setOnAxis([this](const InputArea::PointerData& data) {
    if (!scrollable()) {
      return;
    }

    if (data.axis != WL_POINTER_AXIS_VERTICAL_SCROLL) {
      return;
    }

    scrollBy(data.scrollDelta(m_scrollWheelStep));
  });
  m_viewportArea = static_cast<InputArea*>(addChild(std::move(viewportArea)));

  auto content = std::make_unique<Flex>();
  content->setDirection(FlexDirection::Vertical);
  content->setAlign(FlexAlign::Start);
  m_content = static_cast<Flex*>(m_viewportArea->addChild(std::move(content)));

  auto scrollbarTrack = std::make_unique<RectNode>();
  m_scrollbarTrack = static_cast<RectNode*>(addChild(std::move(scrollbarTrack)));

  auto scrollbarThumb = std::make_unique<RectNode>();
  m_scrollbarThumb = static_cast<RectNode*>(addChild(std::move(scrollbarThumb)));

  auto scrollbarThumbArea = std::make_unique<InputArea>();
  scrollbarThumbArea->setCursorShape(WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER);
  scrollbarThumbArea->setOnPress([this](const InputArea::PointerData& data) {
    if (data.button != BTN_LEFT || !data.pressed || !scrollable()) {
      return;
    }
    m_dragStartLocalY = data.localY + (m_scrollbarThumbArea != nullptr ? m_scrollbarThumbArea->y() : 0.0f);
    m_dragStartOffset = m_scrollOffset;
  });
  scrollbarThumbArea->setOnMotion([this](const InputArea::PointerData& data) {
    if (m_scrollbarThumbArea == nullptr || !m_scrollbarThumbArea->pressed() || !scrollable() || m_thumbTravel <= 0.0f) {
      return;
    }
    const float pointerY = data.localY + m_scrollbarThumbArea->y();
    const float deltaY = pointerY - m_dragStartLocalY;
    const float offsetPerPx = m_maxScrollOffset / m_thumbTravel;
    setScrollOffset(m_dragStartOffset + deltaY * offsetPerPx);
  });
  m_scrollbarThumbArea = static_cast<InputArea*>(addChild(std::move(scrollbarThumbArea)));

  applyPalette();
}

void ScrollView::setScrollOffset(float offset) {
  const float clamped = clampOffset(offset);
  if (std::abs(clamped - m_scrollOffset) < 0.001f) {
    return;
  }
  m_scrollOffset = clamped;
  applyScrollOffset();
  markPaintDirty();
  if (m_onScrollChanged) {
    m_onScrollChanged(m_scrollOffset);
  }
}

void ScrollView::scrollBy(float delta) { setScrollOffset(m_scrollOffset + delta); }

void ScrollView::setScrollbarVisible(bool visible) {
  if (m_showScrollbar == visible) {
    return;
  }
  m_showScrollbar = visible;
  markLayoutDirty();
}

void ScrollView::setBackgroundStyle(const ThemeColor& fill, const ThemeColor& border, float borderWidth) {
  m_backgroundFill = fill;
  m_backgroundBorder = border;
  m_backgroundBorderWidth = borderWidth;
  applyPalette();
}

void ScrollView::setBackgroundStyle(const Color& fill, const Color& border, float borderWidth) {
  setBackgroundStyle(fixedColor(fill), fixedColor(border), borderWidth);
}

void ScrollView::clearBackgroundStyle() { setBackgroundStyle(clearThemeColor(), clearThemeColor(), 0.0f); }

void ScrollView::setBackgroundRoles(ColorRole fillRole, ColorRole borderRole, float borderWidth) {
  setBackgroundStyle(roleColor(fillRole), roleColor(borderRole), borderWidth);
}

void ScrollView::setOnScrollChanged(std::function<void(float)> callback) { m_onScrollChanged = std::move(callback); }

void ScrollView::setViewportPaddingH(float padding) {
  m_viewportPaddingH = padding;
  markLayoutDirty();
}

void ScrollView::setViewportPaddingV(float padding) {
  m_viewportPaddingV = padding;
  markLayoutDirty();
}

float ScrollView::contentViewportWidth() const noexcept {
  const float gutter = m_scrollbarShown ? (kScrollbarWidth + kScrollbarGap) : 0.0f;
  return std::max(0.0f, width() - m_viewportPaddingH * 2.0f - gutter);
}

void ScrollView::applyPalette() {
  if (m_scrollbarTrack != nullptr) {
    m_scrollbarTrack->setStyle(makeSolid(resolveThemeColor(m_scrollbarTrackColor), kScrollbarWidth * 0.5f));
  }
  if (m_scrollbarThumb != nullptr) {
    m_scrollbarThumb->setStyle(makeSolid(resolveThemeColor(m_scrollbarThumbColor), kScrollbarWidth * 0.5f));
  }
  if (m_background != nullptr) {
    m_background->setStyle(RoundedRectStyle{
        .fill = resolveThemeColor(m_backgroundFill),
        .border = resolveThemeColor(m_backgroundBorder),
        .fillMode = FillMode::Solid,
        .radius = Style::radiusMd,
        .softness = 1.0f,
        .borderWidth = m_backgroundBorderWidth,
    });
  }
}

void ScrollView::doLayout(Renderer& renderer) {
  if (m_background == nullptr || m_viewportArea == nullptr || m_content == nullptr || m_scrollbarTrack == nullptr ||
      m_scrollbarThumb == nullptr || m_scrollbarThumbArea == nullptr) {
    return;
  }

  const float w = width() > 0.0f ? width() : kDefaultWidth;
  const float h = height() > 0.0f ? height() : kDefaultHeight;
  const float viewportX = m_viewportPaddingH;
  const float viewportY = m_viewportPaddingV;
  const float viewportW = std::max(0.0f, w - m_viewportPaddingH * 2.0f);
  const float viewportH = std::max(0.0f, h - m_viewportPaddingV * 2.0f);
  m_viewportHeight = viewportH;
  m_viewportWidth = viewportW;
  setSize(w, h);

  m_background->setPosition(0.0f, 0.0f);
  m_background->setSize(w, h);
  m_viewportArea->setPosition(viewportX, viewportY);
  m_viewportArea->setSize(viewportW, viewportH);

  m_content->setPosition(0.0f, 0.0f);
  m_content->setSize(viewportW, m_content->height());
  m_content->layout(renderer);

  m_scrollbarShown = m_showScrollbar && m_content->height() > viewportH + 0.5f;
  const float gutter = m_scrollbarShown ? (kScrollbarWidth + kScrollbarGap) : 0.0f;
  const float contentWidth = std::max(0.0f, viewportW - gutter);
  if (std::abs(m_content->width() - contentWidth) >= 0.5f) {
    m_content->setSize(contentWidth, m_content->height());
    m_content->layout(renderer);
  }

  const float contentHeight = m_content->height();
  m_maxScrollOffset = std::max(0.0f, contentHeight - viewportH);
  m_scrollOffset = clampOffset(m_scrollOffset);

  updateScrollbarGeometry(viewportH, contentHeight);
  applyScrollOffset();
}

void ScrollView::applyScrollOffset() {
  if (m_content != nullptr) {
    m_content->setPosition(0.0f, -m_scrollOffset);
  }

  if (m_scrollbarThumb == nullptr || m_scrollbarTrack == nullptr || m_scrollbarThumbArea == nullptr ||
      m_maxScrollOffset <= 0.0f) {
    return;
  }

  const float trackY = m_scrollbarTrack->y();
  const float thumbH = m_scrollbarThumb->height();
  const float t = std::clamp(m_scrollOffset / m_maxScrollOffset, 0.0f, 1.0f);
  const float thumbY = trackY + t * m_thumbTravel;

  m_scrollbarThumb->setPosition(m_scrollbarTrack->x(), thumbY);
  m_scrollbarThumbArea->setPosition(m_scrollbarTrack->x(), thumbY);
  m_scrollbarThumbArea->setSize(kScrollbarWidth, thumbH);
}

void ScrollView::updateScrollbarGeometry(float viewportHeight, float contentHeight) {
  const bool show = m_showScrollbar && contentHeight > viewportHeight + 0.5f;
  m_scrollbarShown = show;
  m_scrollbarTrack->setVisible(show);
  m_scrollbarThumb->setVisible(show);
  m_scrollbarThumbArea->setVisible(show);
  if (!show) {
    m_thumbTravel = 0.0f;
    return;
  }

  const float trackX = m_viewportPaddingH + m_viewportWidth - kScrollbarWidth;
  const float trackY = m_viewportPaddingV;
  const float trackH = std::max(0.0f, viewportHeight);
  m_scrollbarTrack->setPosition(trackX, trackY);
  m_scrollbarTrack->setSize(kScrollbarWidth, trackH);

  const float thumbH =
      std::clamp((viewportHeight * viewportHeight) / std::max(viewportHeight, contentHeight), kMinThumbHeight, trackH);
  m_thumbTravel = std::max(0.0f, trackH - thumbH);
  m_scrollbarThumb->setSize(kScrollbarWidth, thumbH);
}

float ScrollView::clampOffset(float offset) const noexcept { return std::clamp(offset, 0.0f, m_maxScrollOffset); }
