#include "ui/controls/collapsible.h"

#include "render/animation/animation_manager.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "ui/controls/glyph.h"
#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <memory>

Collapsible::Collapsible() {
  setDirection(FlexDirection::Vertical);
  setAlign(FlexAlign::Stretch);

  auto headerRow = std::make_unique<Flex>();
  headerRow->setDirection(FlexDirection::Horizontal);
  headerRow->setAlign(FlexAlign::Center);
  headerRow->setGap(Style::spaceXs);
  headerRow->setPadding(0.0f, Style::spaceMd);
  m_headerRow = static_cast<Flex*>(addChild(std::move(headerRow)));

  auto chevron = std::make_unique<Glyph>();
  chevron->setGlyph("chevron-down");
  chevron->setGlyphSize(Style::fontSizeBody);
  chevron->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  m_chevron = static_cast<Glyph*>(m_headerRow->addChild(std::move(chevron)));

  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData&) { setExpanded(!m_expanded); });
  m_headerInput = static_cast<InputArea*>(addChild(std::move(area)));
  m_headerInput->setParticipatesInLayout(false);
  m_headerInput->setZIndex(1);

  auto clip = std::make_unique<Node>();
  clip->setClipChildren(true);
  m_clipContainer = addChild(std::move(clip));
  m_clipContainer->setParticipatesInLayout(false);
}

void Collapsible::setHeader(std::unique_ptr<Node> header) {
  if (m_userHeader != nullptr) {
    m_headerRow->removeChild(m_userHeader);
    m_userHeader = nullptr;
  }
  if (header != nullptr) {
    header->setFlexGrow(1.0f);
    m_userHeader = m_headerRow->insertChildAt(0, std::move(header));
  }
  markLayoutDirty();
}

void Collapsible::setBody(std::unique_ptr<Node> body) {
  if (m_bodyNode != nullptr) {
    m_clipContainer->removeChild(m_bodyNode);
    m_bodyNode = nullptr;
  }
  if (body != nullptr) {
    m_bodyNode = m_clipContainer->addChild(std::move(body));
    m_bodyNode->setPosition(0.0f, 0.0f);
  }
  m_bodyNaturalHeight = 0.0f;
  markLayoutDirty();
}

void Collapsible::setExpanded(bool expanded) {
  if (m_expanded == expanded) {
    return;
  }
  m_expanded = expanded;

  if (animationManager() != nullptr) {
    if (m_animId != 0) {
      animationManager()->cancel(m_animId);
    }
    float from = m_expandProgress;
    float to = m_expanded ? 1.0f : 0.0f;
    m_animId = animationManager()->animate(
        from, to, Style::animNormal, Easing::EaseOutCubic, [this](float t) { applyExpandedProgress(t); },
        [this]() { m_animId = 0; }, this);
    markPaintDirty();
  } else {
    applyExpandedProgress(m_expanded ? 1.0f : 0.0f);
  }
}

void Collapsible::setExpandedImmediate(bool expanded) {
  if (m_expanded == expanded) {
    return;
  }
  m_expanded = expanded;
  if (m_animId != 0 && animationManager() != nullptr) {
    animationManager()->cancel(m_animId);
    m_animId = 0;
  }
  applyExpandedProgress(m_expanded ? 1.0f : 0.0f);
}

void Collapsible::setScale(float scale) {
  m_scale = std::max(0.1f, scale);
  if (m_chevron != nullptr) {
    m_chevron->setGlyphSize(Style::fontSizeBody * m_scale);
  }
  if (m_headerRow != nullptr) {
    m_headerRow->setGap(Style::spaceXs * m_scale);
    m_headerRow->setPadding(0.0f, Style::spaceMd * m_scale);
  }
  markLayoutDirty();
}

void Collapsible::applyExpandedProgress(float t) {
  m_expandProgress = t;

  if (m_chevron != nullptr) {
    m_chevron->setRotation(t * static_cast<float>(M_PI));
  }

  m_clipHeight = t * m_bodyNaturalHeight;
  if (m_clipContainer != nullptr) {
    m_clipContainer->setFrameSize(m_clipContainer->width(), m_clipHeight);
  }

  markLayoutDirty();
}

void Collapsible::doLayout(Renderer& renderer) {
  Flex::doLayout(renderer);

  if (m_bodyNode != nullptr) {
    LayoutConstraints bodyConstraints;
    if (width() > 0.0f) {
      bodyConstraints.setExactWidth(width());
    }
    LayoutSize bodySz = m_bodyNode->measure(renderer, bodyConstraints);
    if (std::abs(bodySz.height - m_bodyNaturalHeight) > 0.5f) {
      m_bodyNaturalHeight = bodySz.height;
      if (m_animId == 0) {
        m_clipHeight = m_expanded ? m_bodyNaturalHeight : 0.0f;
      }
    }
  }

  if (m_clipContainer != nullptr) {
    m_clipContainer->setFrameSize(width(), m_clipHeight);
    const float headerBottom = (m_headerRow != nullptr) ? (m_headerRow->y() + m_headerRow->height()) : 0.0f;
    m_clipContainer->setPosition(0.0f, headerBottom);
    if (m_bodyNode != nullptr && m_bodyNaturalHeight > 0.0f) {
      m_bodyNode->arrange(renderer, LayoutRect{0.0f, 0.0f, width(), m_bodyNaturalHeight});
    }
  }

  if (m_headerInput != nullptr && m_headerRow != nullptr) {
    m_headerInput->setPosition(0.0f, 0.0f);
    m_headerInput->setFrameSize(width(), m_headerRow->height());
  }

  const float headerH = (m_headerRow != nullptr) ? m_headerRow->height() : 0.0f;
  setFrameSize(width(), headerH + m_clipHeight);
}

LayoutSize Collapsible::doMeasure(Renderer& renderer, const LayoutConstraints& constraints) {
  LayoutSize headerSize;
  if (m_headerRow != nullptr) {
    headerSize = m_headerRow->measure(renderer, constraints);
  }

  if (m_bodyNode != nullptr) {
    LayoutConstraints bodyConstraints;
    if (constraints.hasMaxWidth) {
      bodyConstraints.setExactWidth(constraints.maxWidth);
    }
    LayoutSize bodySz = m_bodyNode->measure(renderer, bodyConstraints);
    m_bodyNaturalHeight = bodySz.height;
    m_clipHeight = m_expandProgress * m_bodyNaturalHeight;
  }

  return constraints.constrain(LayoutSize{headerSize.width, headerSize.height + m_clipHeight});
}

void Collapsible::doArrange(Renderer& renderer, const LayoutRect& rect) {
  setPosition(rect.x, rect.y);
  setFrameSize(rect.width, rect.height);
  doLayout(renderer);
}
