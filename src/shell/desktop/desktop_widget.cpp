#include "shell/desktop/desktop_widget.h"

#include "core/ui_phase.h"
#include "ui/controls/box.h"

#include <cmath>
#include <memory>

void DesktopWidget::layout(Renderer& renderer) {
  UiPhaseScope layoutPhase(UiPhase::Layout);
  doLayout(renderer);
  applyBackground();
}

void DesktopWidget::update(Renderer& renderer) {
  UiPhaseScope updatePhase(UiPhase::Update);
  doUpdate(renderer);
}

float DesktopWidget::intrinsicWidth() const noexcept {
  if (m_contentRoot == nullptr) {
    return 0.0f;
  }
  float w = m_contentRoot->width();
  if (m_bgEnabled) {
    w += 2.0f * std::round(m_bgPadding * m_contentScale);
  }
  return w;
}

float DesktopWidget::intrinsicHeight() const noexcept {
  if (m_contentRoot == nullptr) {
    return 0.0f;
  }
  float h = m_contentRoot->height();
  if (m_bgEnabled) {
    h += 2.0f * std::round(m_bgPadding * m_contentScale);
  }
  return h;
}

std::unique_ptr<Node> DesktopWidget::releaseRoot() {
  if (m_outerRoot) {
    m_outerRootPtr = m_outerRoot.get();
    return std::move(m_outerRoot);
  }
  if (m_contentOwned) {
    m_outerRootPtr = m_contentOwned.get();
    return std::move(m_contentOwned);
  }
  return nullptr;
}

void DesktopWidget::setRoot(std::unique_ptr<Node> root) {
  m_contentRoot = root.get();
  if (m_bgEnabled) {
    m_outerRoot = std::make_unique<Node>();
    auto bg = std::make_unique<Box>();
    m_bgBox = bg.get();
    m_outerRoot->addChild(std::move(bg));
    m_outerRoot->addChild(std::move(root));
  } else {
    m_contentOwned = std::move(root);
  }
}

void DesktopWidget::setBackgroundStyle(const ColorSpec& color, float radius, float padding) {
  m_bgEnabled = true;
  m_bgColor = color;
  m_bgRadius = radius;
  m_bgPadding = padding;
}

void DesktopWidget::applyBackground() {
  if (!m_bgEnabled || m_contentRoot == nullptr || m_bgBox == nullptr) {
    return;
  }

  const float pad = std::round(m_bgPadding * m_contentScale);
  const float radius = std::round(m_bgRadius * m_contentScale);
  const float w = m_contentRoot->width() + 2.0f * pad;
  const float h = m_contentRoot->height() + 2.0f * pad;

  m_contentRoot->setPosition(pad, pad);
  m_bgBox->setPosition(0.0f, 0.0f);
  m_bgBox->setSize(w, h);
  m_bgBox->setFill(m_bgColor);
  m_bgBox->setRadius(radius);

  if (m_outerRoot) {
    m_outerRoot->setSize(w, h);
  }
}
