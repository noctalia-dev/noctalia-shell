#include "ui/controls/button.h"

#include "render/animation/animation_manager.h"
#include "render/scene/input_area.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <cmath>
#include <memory>

Button::Button() {
  setAlign(FlexAlign::Center);
  setMinHeight(Style::controlHeight);
  setPadding(Style::spaceSm, Style::spaceMd);
  setRadius(Style::radiusMd);

  auto label = std::make_unique<Label>();
  m_label = static_cast<Label*>(addChild(std::move(label)));
  applyVariant();
}

Button::~Button() {
  if (m_animId != 0 && animationManager() != nullptr) {
    animationManager()->cancel(m_animId);
    m_animId = 0;
  }
}

void Button::setText(std::string_view text) {
  m_label->setText(text);
  m_label->setVisible(!text.empty());
}

void Button::setGlyph(std::string_view name) {
  ensureGlyph();
  m_glyph->setGlyph(name);
}

void Button::setFontSize(float size) {
  m_label->setFontSize(size);
  if (m_glyph != nullptr) {
    m_glyph->setGlyphSize(size);
  }
}

void Button::setGlyphSize(float size) {
  ensureGlyph();
  m_glyph->setGlyphSize(size);
}

void Button::setOnClick(std::function<void()> callback) {
  m_onClick = std::move(callback);

  // Lazily create InputArea on first setOnClick
  if (m_inputArea == nullptr) {
    auto area = std::make_unique<InputArea>();
    area->setOnEnter([this](const InputArea::PointerData& /*data*/) { applyVisualState(); });
    area->setOnLeave([this]() { applyVisualState(); });
    area->setOnPress([this](const InputArea::PointerData& /*data*/) { applyVisualState(); });
    area->setOnClick([this](const InputArea::PointerData& /*data*/) {
      if (m_enabled && m_onClick) {
        m_onClick();
      }
    });
    m_inputArea = static_cast<InputArea*>(addChild(std::move(area)));
    m_inputArea->setPosition(0.0f, 0.0f);
    m_inputArea->setSize(width(), height());
  }
}

void Button::setCursorShape(std::uint32_t shape) {
  if (m_inputArea != nullptr) {
    m_inputArea->setCursorShape(shape);
  }
}

void Button::updateInputArea() {
  if (m_inputArea != nullptr) {
    m_inputArea->setPosition(0.0f, 0.0f);
    m_inputArea->setSize(width(), height());
  }
}

bool Button::hovered() const noexcept { return m_inputArea != nullptr && m_inputArea->hovered(); }

bool Button::pressed() const noexcept { return m_inputArea != nullptr && m_inputArea->pressed(); }

void Button::setEnabled(bool enabled) {
  if (m_enabled == enabled) {
    return;
  }
  m_enabled = enabled;
  applyVisualState();
}

void Button::setContentAlign(ButtonContentAlign align) {
  m_contentAlign = align;
}

void Button::setVariant(ButtonVariant variant) {
  if (m_variant == variant) {
    return;
  }
  m_variant = variant;
  applyVariant();
}

void Button::setMinimalChrome(bool minimalChrome) {
  if (m_minimalChrome == minimalChrome) {
    return;
  }
  m_minimalChrome = minimalChrome;
  applyVariant();
}

void Button::applyVariant() {
  setPadding(Style::spaceSm, Style::spaceMd);
  setRadius(Style::radiusMd);
  setBorderWidth(m_minimalChrome ? 0.0f : Style::borderWidth);

  switch (m_variant) {
  case ButtonVariant::Default:
    // Resting state is neutral; hover/pressed use the primary accent.
    m_bgColorNormal = palette.surfaceVariant;
    m_bgColorHover = palette.primary;
    m_bgColorPressed = palette.primary;
    m_labelColorNormal = palette.onSurface;
    m_labelColorHover = palette.onPrimary;
    m_labelColorPressed = palette.onPrimary;
    m_borderColorNormal = palette.outline;
    m_borderColorHover = palette.primary;
    m_borderColorPressed = palette.primary;
    break;
  case ButtonVariant::Secondary:
    m_bgColorNormal = palette.secondary;
    m_bgColorHover = palette.primary;
    m_bgColorPressed = palette.primary;
    m_labelColorNormal = palette.onSecondary;
    m_labelColorHover = palette.onPrimary;
    m_labelColorPressed = palette.onPrimary;
    m_borderColorNormal = palette.outline;
    m_borderColorHover = palette.primary;
    m_borderColorPressed = palette.primary;
    break;
  case ButtonVariant::Destructive:
    m_bgColorNormal = palette.error;
    m_bgColorHover = palette.primary;
    m_bgColorPressed = palette.error;
    m_labelColorNormal = palette.onError;
    m_labelColorHover = palette.onPrimary;
    m_labelColorPressed = palette.onError;
    m_borderColorNormal = palette.outline;
    m_borderColorHover = palette.primary;
    m_borderColorPressed = palette.error;
    break;
  case ButtonVariant::Outline:
    m_bgColorNormal = palette.surface;
    m_bgColorHover = palette.primary;
    m_bgColorPressed = palette.primary;
    m_labelColorNormal = palette.onSurface;
    m_labelColorHover = palette.onPrimary;
    m_labelColorPressed = palette.onPrimary;
    m_borderColorNormal = palette.outline;
    m_borderColorHover = palette.primary;
    m_borderColorPressed = palette.primary;
    break;
  case ButtonVariant::Ghost:
    m_bgColorNormal = m_minimalChrome ? rgba(0.0f, 0.0f, 0.0f, 0.0f) : palette.surface;
    m_bgColorHover = m_minimalChrome ? palette.surfaceVariant : palette.primary;
    m_bgColorPressed = m_minimalChrome ? palette.surfaceVariant : palette.primary;
    m_labelColorNormal = palette.onSurface;
    m_labelColorHover = m_minimalChrome ? palette.onSurface : palette.onPrimary;
    m_labelColorPressed = m_minimalChrome ? palette.onSurface : palette.onPrimary;
    m_borderColorNormal = m_minimalChrome ? rgba(0.0f, 0.0f, 0.0f, 0.0f) : palette.outline;
    m_borderColorHover = m_minimalChrome ? rgba(0.0f, 0.0f, 0.0f, 0.0f) : palette.primary;
    m_borderColorPressed = m_minimalChrome ? rgba(0.0f, 0.0f, 0.0f, 0.0f) : palette.primary;
    break;
  case ButtonVariant::Accent:
    m_bgColorNormal = palette.primary;
    m_bgColorHover = palette.primary;
    m_bgColorPressed = palette.primary;
    m_labelColorNormal = palette.onPrimary;
    m_labelColorHover = palette.onPrimary;
    m_labelColorPressed = palette.onPrimary;
    m_borderColorNormal = m_minimalChrome ? rgba(0.0f, 0.0f, 0.0f, 0.0f) : palette.primary;
    m_borderColorHover = m_minimalChrome ? rgba(0.0f, 0.0f, 0.0f, 0.0f) : palette.primary;
    m_borderColorPressed = m_minimalChrome ? rgba(0.0f, 0.0f, 0.0f, 0.0f) : palette.primary;
    break;
  case ButtonVariant::Tab:
    m_bgColorNormal = rgba(0.0f, 0.0f, 0.0f, 0.0f);
    m_bgColorHover = palette.primary;
    m_bgColorPressed = palette.primary;
    m_labelColorNormal = palette.onSurface;
    m_labelColorHover = palette.onPrimary;
    m_labelColorPressed = palette.onPrimary;
    m_borderColorNormal = rgba(0.0f, 0.0f, 0.0f, 0.0f);
    m_borderColorHover = rgba(0.0f, 0.0f, 0.0f, 0.0f);
    m_borderColorPressed = rgba(0.0f, 0.0f, 0.0f, 0.0f);
    break;
  case ButtonVariant::TabActive:
    // Active tab is emphasized via primary text/icon, not a filled chip.
    m_bgColorNormal = rgba(0.0f, 0.0f, 0.0f, 0.0f);
    m_bgColorHover = palette.primary;
    m_bgColorPressed = palette.primary;
    m_labelColorNormal = palette.primary;
    m_labelColorHover = palette.onPrimary;
    m_labelColorPressed = palette.onPrimary;
    m_borderColorNormal = rgba(0.0f, 0.0f, 0.0f, 0.0f);
    m_borderColorHover = rgba(0.0f, 0.0f, 0.0f, 0.0f);
    m_borderColorPressed = rgba(0.0f, 0.0f, 0.0f, 0.0f);
    break;
  }

  // Seed animation state so the first transition has valid starting colors.
  m_targetBg = m_bgColorNormal;
  m_targetBorder = m_borderColorNormal;
  m_targetLabel = m_labelColorNormal;
  applyVisualState();
}

void Button::ensureGlyph() {
  if (m_glyph != nullptr) {
    return;
  }
  // insertChildAt so the glyph lands before the label in the children vector,
  // which is what Flex iterates to assign layout positions
  auto& kids = children();
  std::size_t labelIndex = 0;
  for (std::size_t i = 0; i < kids.size(); ++i) {
    if (kids[i].get() == m_label) {
      labelIndex = i;
      break;
    }
  }
  auto glyph = std::make_unique<Glyph>();
  m_glyph = static_cast<Glyph*>(insertChildAt(labelIndex, std::move(glyph)));
  setDirection(FlexDirection::Horizontal);
  setGap(Style::spaceXs);
}

void Button::applyColors(const Color& bg, const Color& border, const Color& label) {
  setBackground(bg);
  setBorderColor(border);
  m_label->setColor(label);
  if (m_glyph != nullptr) {
    m_glyph->setColor(label);
  }
}

void Button::applyVisualState() {
  bool isHovered = m_enabled && hovered();
  bool isPressed = m_enabled && pressed();

  Color targetBg;
  Color targetBorder;
  Color targetLabel;
  if (!m_enabled) {
    targetBg = lerpColor(m_bgColorNormal, palette.surface, 0.35f);
    targetBorder = lerpColor(m_borderColorNormal, palette.outline, 0.35f);
    targetLabel = rgba(m_labelColorNormal.r, m_labelColorNormal.g, m_labelColorNormal.b, 0.45f);
  } else if (isPressed) {
    targetBg = m_bgColorPressed;
    targetBorder = m_borderColorPressed;
    targetLabel = m_labelColorPressed;
  } else if (isHovered) {
    targetBg = m_bgColorHover;
    targetBorder = m_borderColorHover;
    targetLabel = m_labelColorHover;
  } else {
    targetBg = m_bgColorNormal;
    targetBorder = m_borderColorNormal;
    targetLabel = m_labelColorNormal;
  }

  if (animationManager() == nullptr) {
    applyColors(targetBg, targetBorder, targetLabel);
    return;
  }

  // Snapshot current display colors as the animation start point
  m_fromBg = m_targetBg;
  m_fromBorder = m_targetBorder;
  m_fromLabel = m_targetLabel;
  m_targetBg = targetBg;
  m_targetBorder = targetBorder;
  m_targetLabel = targetLabel;

  if (m_animId != 0) {
    animationManager()->cancel(m_animId);
  }

  m_animId = animationManager()->animate(
      0.0f, 1.0f, Style::animFast, Easing::EaseOutCubic,
      [this](float t) {
        applyColors(lerpColor(m_fromBg, m_targetBg, t), lerpColor(m_fromBorder, m_targetBorder, t),
                    lerpColor(m_fromLabel, m_targetLabel, t));
      },
      [this]() { m_animId = 0; });
  markDirty();
}

void Button::layout(Renderer& renderer) {
  if (m_label == nullptr) {
    return;
  }

  const float assignedWidth = width();
  const float assignedHeight = height();

  m_label->measure(renderer);
  if (m_glyph != nullptr) {
    m_glyph->measure(renderer);
  }

  if (m_inputArea != nullptr) {
    m_inputArea->setVisible(false);
  }

  Flex::layout(renderer);

  // Buttons are often sized by a parent stretch pass. Preserve that assigned
  // box instead of collapsing back to intrinsic content width.
  if (assignedWidth > 0.0f || assignedHeight > 0.0f) {
    setSize(std::max(width(), assignedWidth), std::max(height(), assignedHeight));
  }

  // After Flex layout the content row is left-anchored inside the padding.
  // Shift the whole group to honour m_contentAlign (Start leaves it as-is).
  if (m_contentAlign != ButtonContentAlign::Start) {
    auto includeContent = [this](Node* node) {
      return node != nullptr && node->visible() && (node == m_label || node == m_glyph);
    };

    float contentLeft = 0.0f;
    float contentRight = 0.0f;
    bool haveContent = false;

    if (includeContent(m_label)) {
      contentLeft = m_label->x();
      contentRight = m_label->x() + m_label->width();
      haveContent = true;
    }
    if (includeContent(m_glyph)) {
      const float left = m_glyph->x();
      const float right = m_glyph->x() + m_glyph->width();
      if (!haveContent) {
        contentLeft = left;
        contentRight = right;
        haveContent = true;
      } else {
        contentLeft = std::min(contentLeft, left);
        contentRight = std::max(contentRight, right);
      }
    }

    if (haveContent) {
      const float contentWidth = contentRight - contentLeft;
      float targetLeft = 0.0f;
      if (m_contentAlign == ButtonContentAlign::Center) {
        targetLeft = std::round((width() - contentWidth) * 0.5f);
      } else { // End
        targetLeft = std::round(width() - contentWidth - paddingRight());
      }
      const float shiftX = targetLeft - contentLeft;
      if (std::abs(shiftX) > 0.01f) {
        if (includeContent(m_label)) {
          m_label->setPosition(m_label->x() + shiftX, m_label->y());
        }
        if (includeContent(m_glyph)) {
          m_glyph->setPosition(m_glyph->x() + shiftX, m_glyph->y());
        }
      }
    }
  }

  if (m_inputArea != nullptr) {
    m_inputArea->setVisible(true);
    m_inputArea->setPosition(0.0f, 0.0f);
    m_inputArea->setSize(width(), height());
  }

  // Only apply visual state if no animation is in progress — a running
  // animation already owns the color transition and re-calling here would
  // reset its from/to snapshot, collapsing the animation to a no-op.
  if (m_animId == 0) {
    applyVisualState();
  }
}
