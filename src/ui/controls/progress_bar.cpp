#include "ui/controls/progress_bar.h"

#include "render/programs/rounded_rect_program.h"
#include "render/scene/rect_node.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <memory>

ProgressBar::ProgressBar() {
  auto track = std::make_unique<RectNode>();
  m_track = static_cast<RectNode*>(addChild(std::move(track)));

  auto fill = std::make_unique<RectNode>();
  m_fill = static_cast<RectNode*>(addChild(std::move(fill)));

  setTrackColor(palette.surfaceVariant);
  setFillColor(palette.primary);
  setRadius(Style::radiusSm);
  setSoftness(0.5f);
}

void ProgressBar::setFillColor(const Color& color) {
  auto style = m_fill->style();
  style.fill = color;
  style.fillMode = FillMode::Solid;
  m_fill->setStyle(style);
}

void ProgressBar::setTrackColor(const Color& color) {
  auto style = m_track->style();
  style.fill = color;
  style.fillMode = FillMode::Solid;
  m_track->setStyle(style);
}

void ProgressBar::setRadius(float radius) {
  auto style = m_track->style();
  style.radius = radius;
  m_track->setStyle(style);
  auto fillStyle = m_fill->style();
  fillStyle.radius = radius;
  m_fill->setStyle(fillStyle);
}

void ProgressBar::setSoftness(float softness) {
  auto style = m_track->style();
  style.softness = softness;
  m_track->setStyle(style);
  auto fillStyle = m_fill->style();
  fillStyle.softness = softness;
  m_fill->setStyle(fillStyle);
}

void ProgressBar::setProgress(float progress) {
  m_progress = std::clamp(progress, 0.0f, 1.0f);
  updateGeometry();
}

void ProgressBar::setSize(float w, float h) {
  Node::setSize(w, h);
  updateGeometry();
}

void ProgressBar::setOrientation(ProgressBarOrientation orientation) {
  m_orientation = orientation;
  updateGeometry();
}

void ProgressBar::updateGeometry() {
  m_track->setSize(width(), height());
  if (m_orientation == ProgressBarOrientation::Vertical) {
    const float fillH = height() * m_progress;
    m_fill->setPosition(0.0f, height() - fillH);
    m_fill->setSize(width(), fillH);
  } else {
    m_fill->setSize(width() * m_progress, height());
  }
}
