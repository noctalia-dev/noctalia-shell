#include "ui/controls/button.h"

#include "render/animation/animation_manager.h"
#include "render/scene/input_area.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <cmath>
#include <memory>

namespace {

Button::ButtonStateColors makeState(ThemeColor bg, ThemeColor border, ThemeColor label) {
  return Button::ButtonStateColors{
      .bg = std::move(bg),
      .border = std::move(border),
      .label = std::move(label),
  };
}

Button::ButtonPalette paletteForVariant(ButtonVariant variant) {
  switch (variant) {
  case ButtonVariant::Default:
    return Button::ButtonPalette{
        .borderWidth = Style::borderWidth,
        .normal = makeState(roleColor(ColorRole::SurfaceVariant), roleColor(ColorRole::Outline),
                            roleColor(ColorRole::OnSurface)),
        .hover = makeState(roleColor(ColorRole::Primary), roleColor(ColorRole::Primary),
                           roleColor(ColorRole::OnPrimary)),
        .pressed = makeState(roleColor(ColorRole::Primary), roleColor(ColorRole::Primary),
                             roleColor(ColorRole::OnPrimary)),
    };
  case ButtonVariant::Secondary:
    return Button::ButtonPalette{
        .borderWidth = Style::borderWidth,
        .normal = makeState(roleColor(ColorRole::Secondary), roleColor(ColorRole::Outline),
                            roleColor(ColorRole::OnSecondary)),
        .hover = makeState(roleColor(ColorRole::Primary), roleColor(ColorRole::Primary),
                           roleColor(ColorRole::OnPrimary)),
        .pressed = makeState(roleColor(ColorRole::Primary), roleColor(ColorRole::Primary),
                             roleColor(ColorRole::OnPrimary)),
    };
  case ButtonVariant::Destructive:
    return Button::ButtonPalette{
        .borderWidth = Style::borderWidth,
        .normal = makeState(roleColor(ColorRole::Error), roleColor(ColorRole::Outline),
                            roleColor(ColorRole::OnError)),
        .hover = makeState(roleColor(ColorRole::Primary), roleColor(ColorRole::Primary),
                           roleColor(ColorRole::OnPrimary)),
        .pressed = makeState(roleColor(ColorRole::Error), roleColor(ColorRole::Error),
                             roleColor(ColorRole::OnError)),
    };
  case ButtonVariant::Outline:
    return Button::ButtonPalette{
        .borderWidth = Style::borderWidth,
        .normal = makeState(roleColor(ColorRole::Surface), roleColor(ColorRole::Outline),
                            roleColor(ColorRole::OnSurface)),
        .hover = makeState(roleColor(ColorRole::Primary), roleColor(ColorRole::Primary),
                           roleColor(ColorRole::OnPrimary)),
        .pressed = makeState(roleColor(ColorRole::Primary), roleColor(ColorRole::Primary),
                             roleColor(ColorRole::OnPrimary)),
    };
  case ButtonVariant::Ghost:
    return Button::ButtonPalette{
        .borderWidth = 0.0f,
        .normal = makeState(clearThemeColor(), clearThemeColor(), roleColor(ColorRole::OnSurface)),
        .hover = makeState(roleColor(ColorRole::SurfaceVariant), clearThemeColor(), roleColor(ColorRole::OnSurface)),
        .pressed = makeState(roleColor(ColorRole::SurfaceVariant), clearThemeColor(), roleColor(ColorRole::OnSurface)),
    };
  case ButtonVariant::Accent:
    return Button::ButtonPalette{
        .borderWidth = 0.0f,
        .normal = makeState(roleColor(ColorRole::Primary), clearThemeColor(), roleColor(ColorRole::OnPrimary)),
        .hover = makeState(roleColor(ColorRole::Primary), clearThemeColor(), roleColor(ColorRole::OnPrimary)),
        .pressed = makeState(roleColor(ColorRole::Primary), clearThemeColor(), roleColor(ColorRole::OnPrimary)),
    };
  case ButtonVariant::Tab:
    return Button::ButtonPalette{
        .borderWidth = 0.0f,
        .normal = makeState(clearThemeColor(), clearThemeColor(), roleColor(ColorRole::OnSurface)),
        .hover = makeState(roleColor(ColorRole::Primary), clearThemeColor(), roleColor(ColorRole::OnPrimary)),
        .pressed = makeState(roleColor(ColorRole::Primary), clearThemeColor(), roleColor(ColorRole::OnPrimary)),
    };
  case ButtonVariant::TabActive:
    return Button::ButtonPalette{
        .borderWidth = 0.0f,
        .normal = makeState(clearThemeColor(), clearThemeColor(), roleColor(ColorRole::Primary)),
        .hover = makeState(roleColor(ColorRole::Primary), clearThemeColor(), roleColor(ColorRole::OnPrimary)),
        .pressed = makeState(roleColor(ColorRole::Primary), clearThemeColor(), roleColor(ColorRole::OnPrimary)),
    };
  }

  return {};
}

} // namespace

Button::Button() {
  setAlign(FlexAlign::Center);
  setMinHeight(Style::controlHeight);
  setPadding(Style::spaceSm, Style::spaceMd);
  setRadius(Style::radiusMd);

  auto area = std::make_unique<InputArea>();
  area->setOnEnter([this](const InputArea::PointerData& /*data*/) { applyVisualState(); });
  area->setOnLeave([this]() { applyVisualState(); });
  area->setOnPress([this](const InputArea::PointerData& /*data*/) { applyVisualState(); });
  area->setOnMotion([this](const InputArea::PointerData& /*data*/) {
    if (m_onMotion) {
      m_onMotion();
    }
  });
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    if (m_enabled && m_onClick) {
      m_onClick();
    }
  });
  area->setEnabled(false);
  m_inputArea = static_cast<InputArea*>(addChild(std::move(area)));
  m_inputArea->setParticipatesInLayout(false);
  m_inputArea->setZIndex(1);
  m_inputArea->setPosition(0.0f, 0.0f);
  m_inputArea->setSize(width(), height());

  applyVariant();
  m_paletteConn = paletteChanged().connect([this] {
    // Re-derive color slots from the (possibly updated) palette and push
    // them immediately if no hover/press animation is in flight. Otherwise
    // the running animation keeps its old snapshot for one more tick and
    // the next applyVisualState() will resync.
    applyVariant();
  });
}

Button::~Button() {
  if (m_animId != 0 && animationManager() != nullptr) {
    animationManager()->cancel(m_animId);
    m_animId = 0;
  }
}

void Button::setText(std::string_view text) {
  ensureLabel();
  m_label->setText(text);
  m_label->setVisible(!text.empty());
}

void Button::setGlyph(std::string_view name) {
  ensureGlyph();
  m_glyph->setGlyph(name);
}

void Button::setFontSize(float size) {
  ensureLabel();
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
  refreshInputAreaEnabled();
}

void Button::setOnMotion(std::function<void()> callback) {
  m_onMotion = std::move(callback);
  refreshInputAreaEnabled();
}

void Button::setHoverSuppressed(bool suppressed) {
  if (m_hoverSuppressed == suppressed) {
    return;
  }
  m_hoverSuppressed = suppressed;
  applyVisualState();
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
  refreshInputAreaEnabled();
  applyVisualState();
}

void Button::setSelected(bool selected) {
  if (m_selected == selected) {
    return;
  }
  m_selected = selected;
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

void Button::applyVariant() {
  setPadding(Style::spaceSm, Style::spaceMd);
  setRadius(Style::radiusMd);

  m_palette = paletteForVariant(m_variant);
  setBorderWidth(m_palette.borderWidth);

  // Seed animation state so the first transition has valid starting colors.
  m_targetBg = resolveThemeColor(m_palette.normal.bg);
  m_targetBorder = resolveThemeColor(m_palette.normal.border);
  m_targetLabel = resolveThemeColor(m_palette.normal.label);
  applyVisualState();
}

void Button::refreshInputAreaEnabled() {
  if (m_inputArea != nullptr) {
    m_inputArea->setEnabled(m_enabled && (static_cast<bool>(m_onClick) || static_cast<bool>(m_onMotion)));
  }
}

void Button::ensureLabel() {
  if (m_label != nullptr) {
    return;
  }
  auto label = std::make_unique<Label>();
  m_label = static_cast<Label*>(addChild(std::move(label)));
  if (m_glyph != nullptr) {
    setDirection(FlexDirection::Horizontal);
    setGap(Style::spaceXs);
  }
}

void Button::ensureGlyph() {
  if (m_glyph != nullptr) {
    return;
  }
  // insertChildAt so the glyph lands before the label in the children vector,
  // which is what Flex iterates to assign layout positions
  if (m_label != nullptr) {
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
  } else {
    auto glyph = std::make_unique<Glyph>();
    m_glyph = static_cast<Glyph*>(addChild(std::move(glyph)));
  }
  if (m_label != nullptr) {
    setDirection(FlexDirection::Horizontal);
    setGap(Style::spaceXs);
  }
}

void Button::applyColors(const Color& bg, const Color& border, const Color& label) {
  setBackground(bg);
  setBorderColor(border);
  if (m_label != nullptr) {
    m_label->setColor(label);
  }
  if (m_glyph != nullptr) {
    m_glyph->setColor(label);
  }
}

void Button::applyVisualState() {
  bool isHovered = m_enabled && ((!m_hoverSuppressed && hovered()) || m_selected);
  bool isPressed = m_enabled && pressed();

  Color targetBg;
  Color targetBorder;
  Color targetLabel;
  if (!m_enabled) {
    targetBg = lerpColor(resolveThemeColor(m_palette.normal.bg), resolveColorRole(ColorRole::Surface), 0.35f);
    targetBorder = lerpColor(resolveThemeColor(m_palette.normal.border), resolveColorRole(ColorRole::Outline), 0.35f);
    targetLabel = resolveThemeColor(roleColor(ColorRole::OnSurface, 0.45f));
  } else if (isPressed) {
    targetBg = resolveThemeColor(m_palette.pressed.bg);
    targetBorder = resolveThemeColor(m_palette.pressed.border);
    targetLabel = resolveThemeColor(m_palette.pressed.label);
  } else if (isHovered) {
    targetBg = resolveThemeColor(m_palette.hover.bg);
    targetBorder = resolveThemeColor(m_palette.hover.border);
    targetLabel = resolveThemeColor(m_palette.hover.label);
  } else {
    targetBg = resolveThemeColor(m_palette.normal.bg);
    targetBorder = resolveThemeColor(m_palette.normal.border);
    targetLabel = resolveThemeColor(m_palette.normal.label);
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
  const float assignedWidth = width();
  const float assignedHeight = height();

  if (m_label != nullptr) {
    m_label->measure(renderer);
  }
  if (m_glyph != nullptr) {
    m_glyph->measure(renderer);
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
