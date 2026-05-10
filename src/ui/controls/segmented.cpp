#include "ui/controls/segmented.h"

#include "render/core/render_styles.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/separator.h"
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
  if (index > 0) {
    auto sep = makeSegmentSeparator();
    m_separators.push_back(sep.get());
    addChild(std::move(sep));
  }
  auto btn = makeSegmentButton(label, glyph, index);
  Button* raw = btn.get();
  m_buttons.push_back(raw);
  addChild(std::move(btn));
  refreshVariants();
  return index;
}

void Segmented::clearOptions() {
  for (Button* button : m_buttons) {
    if (button != nullptr) {
      (void)removeChild(button);
    }
  }
  for (Separator* separator : m_separators) {
    if (separator != nullptr) {
      (void)removeChild(separator);
    }
  }
  m_separators.clear();
  m_buttons.clear();
  m_hoveredIndex.reset();
  m_selected = 0;
  markLayoutDirty();
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
      btn->setMinHeight(segmentHeight());
      btn->setPadding(Style::spaceXs * m_scale, horizontalPadding());
      btn->setFontSize(fs);
      btn->setGlyphSize(fs);
    }
  }
  const float ruleW = std::max(1.0f, Style::borderWidth * m_scale);
  for (Separator* sep : m_separators) {
    if (sep != nullptr) {
      sep->setThickness(ruleW);
    }
  }
  refreshVariants();
  markLayoutDirty();
}

void Segmented::setOnChange(std::function<void(std::size_t)> callback) { m_onChange = std::move(callback); }

void Segmented::setEnabled(bool enabled) {
  if (m_enabled == enabled) {
    return;
  }
  m_enabled = enabled;
  for (Button* btn : m_buttons) {
    if (btn != nullptr) {
      btn->setEnabled(enabled);
    }
  }
  setOpacity(enabled ? 1.0f : 0.55f);
}

std::unique_ptr<Separator> Segmented::makeSegmentSeparator() {
  auto sep = std::make_unique<Separator>();
  sep->setOrientation(SeparatorOrientation::VerticalRule);
  sep->setThickness(std::max(1.0f, Style::borderWidth * m_scale));
  sep->setColor(colorSpecFromRole(ColorRole::Outline, 0.5f));
  sep->setFlexGrow(0.0f);
  return sep;
}

std::unique_ptr<Button> Segmented::makeSegmentButton(std::string_view label, std::string_view glyph,
                                                     std::size_t index) {
  auto btn = std::make_unique<Button>();
  if (!glyph.empty()) {
    btn->setGlyph(glyph);
    btn->setGlyphSize(effectiveFontSize());
  }
  btn->setText(label);
  btn->setFontSize(effectiveFontSize());
  btn->setMinHeight(segmentHeight());
  btn->setPadding(Style::spaceXs * m_scale, horizontalPadding());
  if (m_iconOnlyHoverLabelsEnabled) {
    btn->setText("");
    btn->setGlyphOnlySquare(false);
    auto storedLabel = std::make_shared<std::string>(label);
    btn->setOnEnter([this, index, storedLabel]() { emitHoverLabel(index, *storedLabel); });
    btn->setOnLeave([this, index]() { clearHoverLabel(index); });
  }
  btn->setOnPress([this, index](float /*localX*/, float /*localY*/, bool pressed) {
    if (m_selectOnPress && pressed) {
      setSelectedIndex(index);
    }
  });
  btn->setOnClick([this, index]() { setSelectedIndex(index); });
  btn->setFlexGrow(m_equalSegmentWidths ? 1.0f : 0.0f);
  btn->setContentAlign(ButtonContentAlign::Center);
  btn->setEnabled(m_enabled);
  return btn;
}

void Segmented::setEqualSegmentWidths(bool equalWidths) {
  if (m_equalSegmentWidths == equalWidths) {
    return;
  }
  m_equalSegmentWidths = equalWidths;
  for (Button* b : m_buttons) {
    if (b != nullptr) {
      b->setFlexGrow(m_equalSegmentWidths ? 1.0f : 0.0f);
    }
  }
  markLayoutDirty();
}

void Segmented::setIconOnlyHoverLabelsEnabled(bool enabled) {
  if (m_iconOnlyHoverLabelsEnabled == enabled) {
    return;
  }
  m_iconOnlyHoverLabelsEnabled = enabled;
  for (Button* btn : m_buttons) {
    if (btn != nullptr) {
      btn->setMinHeight(segmentHeight());
      btn->setPadding(Style::spaceXs * m_scale, horizontalPadding());
    }
  }
  if (!enabled && m_onHoverLabelChange) {
    m_hoveredIndex.reset();
    m_onHoverLabelChange(std::nullopt, {}, 0.0f);
  }
  markLayoutDirty();
}

void Segmented::setOnHoverLabelChange(
    std::function<void(std::optional<std::size_t>, std::string_view, float)> callback) {
  m_onHoverLabelChange = std::move(callback);
}

void Segmented::setToolbarStyle(bool toolbarStyle) {
  if (m_toolbarStyle == toolbarStyle) {
    return;
  }
  m_toolbarStyle = toolbarStyle;
  applyOuterStyle();
  refreshVariants();
}

void Segmented::setSelectOnPress(bool selectOnPress) { m_selectOnPress = selectOnPress; }

void Segmented::refreshVariants() {
  const std::size_t n = m_buttons.size();
  const float r = Style::radiusMd * m_scale;
  for (std::size_t i = 0; i < n; ++i) {
    if (m_buttons[i] == nullptr) {
      continue;
    }
    m_buttons[i]->setVariant(i == m_selected
                                 ? (m_toolbarStyle ? ButtonVariant::ToolbarTabActive : ButtonVariant::TabActive)
                                 : (m_toolbarStyle ? ButtonVariant::ToolbarTab : ButtonVariant::Tab));
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
  setFill(m_toolbarStyle ? colorSpecFromRole(ColorRole::Surface) : colorSpecFromRole(ColorRole::SurfaceVariant));
  clearBorder();
  setRadius(Style::radiusMd * m_scale);
}

void Segmented::emitHoverLabel(std::size_t index, std::string_view label) {
  if (!m_iconOnlyHoverLabelsEnabled || index >= m_buttons.size()) {
    return;
  }

  Button* button = m_buttons[index];
  if (button == nullptr) {
    return;
  }

  m_hoveredIndex = index;
  if (m_onHoverLabelChange) {
    m_onHoverLabelChange(index, label, button->x() + button->width() * 0.5f);
  }
}

void Segmented::clearHoverLabel(std::size_t index) {
  if (!m_hoveredIndex.has_value() || *m_hoveredIndex != index) {
    return;
  }
  m_hoveredIndex.reset();
  if (m_onHoverLabelChange) {
    m_onHoverLabelChange(std::nullopt, {}, 0.0f);
  }
}

float Segmented::segmentHeight() const noexcept {
  return (m_iconOnlyHoverLabelsEnabled ? Style::controlHeightSm : Style::controlHeight) * m_scale;
}

float Segmented::horizontalPadding() const noexcept {
  return (m_iconOnlyHoverLabelsEnabled ? Style::spaceXs : Style::spaceMd) * m_scale;
}

float Segmented::effectiveFontSize() const noexcept {
  return (m_fontSize > 0.0f ? m_fontSize : Style::fontSizeBody) * m_scale;
}
