#include "ui/controls/segmented.h"

#include "render/core/render_styles.h"
#include "ui/controls/button.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <memory>
#include <utility>

Segmented::Segmented() {
  setDirection(FlexDirection::Horizontal);
  setAlign(FlexAlign::Stretch);
  setGap(0.0f);
  applyOuterStyle();
}

std::size_t Segmented::addOption(std::string_view label) { return addOption(label, std::string_view{}); }

std::size_t Segmented::addOption(std::string_view label, std::string_view glyph) {
  const std::size_t index = m_buttons.size();
  Button* btn = makeSegmentButton(label, glyph, index);
  m_buttons.push_back(btn);
  refreshVariants();
  return index;
}

void Segmented::setSelectedIndex(std::size_t index) {
  if (index >= m_buttons.size() || index == m_selected) {
    return;
  }
  m_selected = index;
  refreshVariants();
  if (m_onChange) {
    m_onChange(index);
  }
}

void Segmented::setFontSize(float size) {
  m_fontSize = size;
  const float fs = effectiveFontSize();
  for (Button* btn : m_buttons) {
    if (btn != nullptr) {
      btn->setFontSize(fs);
      btn->setGlyphSize(fs);
    }
  }
}

void Segmented::setScale(float scale) {
  m_scale = std::max(0.1f, scale);
  applyOuterStyle();
  const float fs = effectiveFontSize();
  for (Button* btn : m_buttons) {
    if (btn != nullptr) {
      btn->setMinHeight(Style::controlHeight * m_scale);
      btn->setPadding(Style::spaceXs * m_scale, Style::spaceMd * m_scale);
      btn->setFontSize(fs);
      btn->setGlyphSize(fs);
    }
  }
  refreshVariants();
  markLayoutDirty();
}

void Segmented::setOnChange(std::function<void(std::size_t)> callback) { m_onChange = std::move(callback); }

Button* Segmented::makeSegmentButton(std::string_view label, std::string_view glyph, std::size_t index) {
  auto btn = std::make_unique<Button>();
  if (!glyph.empty()) {
    btn->setGlyph(glyph);
    btn->setGlyphSize(effectiveFontSize());
  }
  btn->setText(label);
  btn->setFontSize(effectiveFontSize());
  btn->setMinHeight(Style::controlHeight * m_scale);
  btn->setPadding(Style::spaceXs * m_scale, Style::spaceMd * m_scale);
  btn->setOnClick([this, index]() { setSelectedIndex(index); });
  Button* raw = btn.get();
  addChild(std::move(btn));
  return raw;
}

void Segmented::refreshVariants() {
  const std::size_t n = m_buttons.size();
  const float r = Style::radiusMd * m_scale;
  for (std::size_t i = 0; i < n; ++i) {
    if (m_buttons[i] == nullptr) {
      continue;
    }
    m_buttons[i]->setVariant(i == m_selected ? ButtonVariant::TabActive : ButtonVariant::Tab);
    Radii radii;
    if (n == 1) {
      radii = Radii{r, r, r, r};
    } else if (i == 0) {
      radii = Radii{r, 0.0f, 0.0f, r};
    } else if (i == n - 1) {
      radii = Radii{0.0f, r, r, 0.0f};
    } else {
      radii = Radii{0.0f};
    }
    m_buttons[i]->setRadii(radii);
  }
}

void Segmented::applyOuterStyle() {
  setPadding(0.0f);
  setFill(colorSpecFromRole(ColorRole::SurfaceVariant));
  clearBorder();
  setRadius(Style::radiusMd * m_scale);
}

float Segmented::effectiveFontSize() const noexcept {
  return (m_fontSize > 0.0f ? m_fontSize : Style::fontSizeBody) * m_scale;
}
