#include "ui/controls/select.h"

#include "render/programs/rounded_rect_program.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "render/scene/rect_node.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include "cursor-shape-v1-client-protocol.h"
#include <linux/input-event-codes.h>

#include <algorithm>
#include <cmath>
#include <memory>

namespace {

constexpr float kDefaultWidth = 220.0f;
constexpr float kMinWidth = 160.0f;
constexpr float kTriggerHeight = Style::controlHeight;
constexpr float kOptionHeight = Style::controlHeight;
constexpr float kMenuTopGap = Style::spaceXs;
constexpr float kHorizontalPadding = Style::spaceMd;
constexpr float kGlyphSize = 14.0f;
constexpr std::int32_t kOpenSelectZIndex = 100;
constexpr std::size_t kMaxVisibleOptions = 6;

Color resolved(ColorRole role, float alpha = 1.0f) { return resolveThemeColor(roleColor(role, alpha)); }

} // namespace

Select* Select::s_openSelect = nullptr;

Select::Select() {
  auto triggerBackground = std::make_unique<RectNode>();
  m_triggerBackground = static_cast<RectNode*>(addChild(std::move(triggerBackground)));

  auto triggerLabel = std::make_unique<Label>();
  m_triggerLabel = static_cast<Label*>(addChild(std::move(triggerLabel)));

  auto triggerGlyph = std::make_unique<Glyph>();
  m_triggerGlyph = static_cast<Glyph*>(addChild(std::move(triggerGlyph)));
  m_triggerGlyph->setGlyph("chevron-down");
  m_triggerGlyph->setGlyphSize(m_glyphSize);

  auto triggerArea = std::make_unique<InputArea>();
  triggerArea->setCursorShape(WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER);
  triggerArea->setOnEnter([this](const InputArea::PointerData& /*data*/) {
    applyVisualState();
    markPaintDirty();
  });
  triggerArea->setOnLeave([this]() {
    applyVisualState();
    markPaintDirty();
  });
  triggerArea->setOnPress([this](const InputArea::PointerData& /*data*/) {
    applyVisualState();
    markPaintDirty();
  });
  triggerArea->setOnClick([this](const InputArea::PointerData& data) {
    if (!m_enabled || data.button != BTN_LEFT) {
      return;
    }
    toggleOpen();
  });
  m_triggerArea = static_cast<InputArea*>(addChild(std::move(triggerArea)));

  auto menuViewport = std::make_unique<Node>();
  menuViewport->setClipChildren(true);
  menuViewport->setZIndex(1);
  m_menuViewport = addChild(std::move(menuViewport));

  auto menuBackground = std::make_unique<RectNode>();
  m_menuBackground = static_cast<RectNode*>(m_menuViewport->addChild(std::move(menuBackground)));

  auto menuArea = std::make_unique<InputArea>();
  menuArea->setCursorShape(WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER);
  menuArea->setOnAxis([this](const InputArea::PointerData& data) {
    if (!m_open) {
      return;
    }
    scrollBy(data.scrollDelta(kOptionHeight));
  });
  m_menuArea = static_cast<InputArea*>(m_menuViewport->addChild(std::move(menuArea)));

  applyVisualState();
  m_paletteConn = paletteChanged().connect([this] { applyVisualState(); });
}

Select::~Select() {
  restoreAncestorChain();
  if (s_openSelect == this) {
    s_openSelect = nullptr;
  }
}

void Select::setOptions(std::vector<std::string> options) {
  m_options = std::move(options);
  if (m_options.empty()) {
    m_selectedIndex = npos;
    m_hoveredOptionIndex = npos;
    m_open = false;
    m_scrollOffset = 0.0f;
  } else if (m_selectedIndex == npos || m_selectedIndex >= m_options.size()) {
    m_selectedIndex = 0;
  }
  syncTriggerText();
  m_needsOptionRebuild = true;
  applyVisualState();
  markLayoutDirty();
}

void Select::setSelectedIndex(std::size_t index) {
  if (index >= m_options.size()) {
    return;
  }
  if (m_selectedIndex == index) {
    return;
  }
  m_selectedIndex = index;
  syncTriggerText();
  applyVisualState();
  markLayoutDirty();
  if (m_onSelectionChanged) {
    m_onSelectionChanged(m_selectedIndex, selectedText());
  }
}

void Select::setEnabled(bool enabled) {
  if (m_enabled == enabled) {
    return;
  }
  m_enabled = enabled;
  if (!m_enabled) {
    m_open = false;
    m_hoveredOptionIndex = npos;
    if (s_openSelect == this) {
      s_openSelect = nullptr;
    }
    restoreAncestorChain();
    setZIndex(0);
  }
  applyVisualState();
  markPaintDirty();
}

void Select::setPlaceholder(std::string_view placeholder) {
  m_placeholder = std::string(placeholder);
  syncTriggerText();
  applyVisualState();
  markLayoutDirty();
}

void Select::setFontSize(float size) {
  m_fontSize = std::max(1.0f, size);
  syncTriggerText();
  m_needsOptionRebuild = true;
  markLayoutDirty();
}

void Select::setControlHeight(float height) {
  m_controlHeight = std::max(1.0f, height);
  markLayoutDirty();
}

void Select::setHorizontalPadding(float padding) {
  m_horizontalPadding = std::max(0.0f, padding);
  markLayoutDirty();
}

void Select::setGlyphSize(float size) {
  m_glyphSize = std::max(1.0f, size);
  if (m_triggerGlyph != nullptr) {
    m_triggerGlyph->setGlyphSize(m_glyphSize);
  }
  for (auto& option : m_optionViews) {
    if (option.checkGlyph != nullptr) {
      option.checkGlyph->setGlyphSize(m_glyphSize);
    }
  }
  markLayoutDirty();
}

void Select::setOnSelectionChanged(std::function<void(std::size_t, std::string_view)> callback) {
  m_onSelectionChanged = std::move(callback);
}

std::string_view Select::selectedText() const noexcept {
  if (m_selectedIndex >= m_options.size()) {
    return {};
  }
  return m_options[m_selectedIndex];
}

void Select::doLayout(Renderer& renderer) {
  if (m_triggerBackground == nullptr || m_triggerLabel == nullptr || m_triggerGlyph == nullptr || m_triggerArea == nullptr ||
      m_menuBackground == nullptr) {
    return;
  }

  if (m_needsOptionRebuild) {
    rebuildOptionViews();
    m_needsOptionRebuild = false;
  }

  if (width() > 0.0f) {
    m_fixedWidth = width();
  }

  syncTriggerText();
  m_triggerLabel->measure(renderer);
  m_triggerGlyph->measure(renderer);

  float widestLabel = m_triggerLabel->width();
  for (auto& option : m_optionViews) {
    option.label->measure(renderer);
    widestLabel = std::max(widestLabel, option.label->width());
  }

  float contentWidth = widestLabel + m_horizontalPadding * 2.0f + m_glyphSize + Style::spaceXs;
  float dropdownWidth = m_fixedWidth > 0.0f ? m_fixedWidth : std::max({kDefaultWidth, kMinWidth, contentWidth});

  const float viewportHeight = menuViewportHeight();
  setSize(dropdownWidth, m_controlHeight);

  m_triggerBackground->setPosition(0.0f, 0.0f);
  m_triggerBackground->setFrameSize(dropdownWidth, m_controlHeight);

  const float triggerLabelMax =
      std::max(0.0f, dropdownWidth - (m_horizontalPadding * 2.0f + m_glyphSize + Style::spaceXs));
  m_triggerLabel->setMaxWidth(triggerLabelMax);
  m_triggerLabel->measure(renderer);
  float triggerLabelY = std::round((m_controlHeight - m_triggerLabel->height()) * 0.5f);
  m_triggerLabel->setPosition(m_horizontalPadding, triggerLabelY);
  m_triggerGlyph->setPosition(dropdownWidth - m_horizontalPadding - m_triggerGlyph->width(), triggerLabelY);
  m_triggerArea->setPosition(0.0f, 0.0f);
  m_triggerArea->setFrameSize(dropdownWidth, m_controlHeight);

  float absLeft = 0.0f;
  float absTop = 0.0f;
  float absRight = 0.0f;
  float absBottom = 0.0f;
  Node::transformedBounds(this, absLeft, absTop, absRight, absBottom);
  Node* root = this;
  while (root->parent() != nullptr) {
    root = root->parent();
  }
  const float rootHeight = root->height();
  const float belowSpace = std::max(0.0f, rootHeight - absBottom);
  const float aboveSpace = std::max(0.0f, absTop);
  const float neededSpace = viewportHeight + kMenuTopGap;
  m_openUpward = neededSpace > belowSpace && aboveSpace > belowSpace;
  const float menuY = m_openUpward ? -(viewportHeight + kMenuTopGap) : (m_controlHeight + kMenuTopGap);
  clampScrollOffset();

  m_menuViewport->setVisible(m_open && !m_optionViews.empty());
  m_menuViewport->setPosition(0.0f, menuY);
  m_menuViewport->setFrameSize(dropdownWidth, viewportHeight);
  m_menuViewport->setZIndex(1);

  m_menuBackground->setPosition(0.0f, 0.0f);
  m_menuBackground->setFrameSize(dropdownWidth, viewportHeight);
  m_menuBackground->setZIndex(1);

  m_menuArea->setVisible(m_open && !m_optionViews.empty());
  m_menuArea->setPosition(0.0f, 0.0f);
  m_menuArea->setFrameSize(dropdownWidth, viewportHeight);
  m_menuArea->setZIndex(2);

  for (std::size_t i = 0; i < m_optionViews.size(); ++i) {
    auto& option = m_optionViews[i];
    const bool showMenu = m_open && !m_optionViews.empty();
    option.background->setVisible(showMenu);
    option.label->setVisible(showMenu);
    option.checkGlyph->setVisible(showMenu && i == m_selectedIndex);
    option.area->setVisible(showMenu);

    const float rowY = static_cast<float>(i) * m_controlHeight - m_scrollOffset;
    option.background->setPosition(0.0f, rowY);
    option.background->setFrameSize(dropdownWidth, m_controlHeight);
    option.background->setZIndex(3);

    option.label->setMaxWidth(
        std::max(0.0f, dropdownWidth - m_horizontalPadding * 2.0f - m_glyphSize - Style::spaceXs));
    option.label->measure(renderer);
    float optLabelY = std::round((m_controlHeight - option.label->height()) * 0.5f);
    option.label->setPosition(m_horizontalPadding, rowY + optLabelY);
    option.label->setZIndex(4);

    option.checkGlyph->measure(renderer);
    option.checkGlyph->setPosition(dropdownWidth - m_horizontalPadding - option.checkGlyph->width(),
                                   rowY + optLabelY);
    option.checkGlyph->setZIndex(4);

    option.area->setPosition(0.0f, rowY);
    option.area->setFrameSize(dropdownWidth, m_controlHeight);
    option.area->setZIndex(5);
  }

  applyVisualState();
}

void Select::clearOptionViews() {
  for (auto& option : m_optionViews) {
    if (option.area != nullptr) {
      (void)m_menuViewport->removeChild(option.area);
    }
    if (option.checkGlyph != nullptr) {
      (void)m_menuViewport->removeChild(option.checkGlyph);
    }
    if (option.label != nullptr) {
      (void)m_menuViewport->removeChild(option.label);
    }
    if (option.background != nullptr) {
      (void)m_menuViewport->removeChild(option.background);
    }
  }
  m_optionViews.clear();
}

void Select::rebuildOptionViews() {
  clearOptionViews();

  for (std::size_t i = 0; i < m_options.size(); ++i) {
    auto background = std::make_unique<RectNode>();
    auto* bgPtr = static_cast<RectNode*>(m_menuViewport->addChild(std::move(background)));

    auto label = std::make_unique<Label>();
    label->setText(m_options[i]);
    label->setFontSize(m_fontSize);
    auto* labelPtr = static_cast<Label*>(m_menuViewport->addChild(std::move(label)));

    auto checkGlyph = std::make_unique<Glyph>();
    checkGlyph->setGlyph("check");
    checkGlyph->setGlyphSize(m_glyphSize);
    auto* checkIconPtr = static_cast<Glyph*>(m_menuViewport->addChild(std::move(checkGlyph)));

    auto area = std::make_unique<InputArea>();
    area->setCursorShape(WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER);
    area->setOnEnter([this, i](const InputArea::PointerData& /*data*/) {
      if (!m_enabled) {
        return;
      }
      m_hoveredOptionIndex = i;
      applyVisualState();
      markPaintDirty();
    });
    area->setOnLeave([this, i]() {
      if (m_hoveredOptionIndex == i) {
        m_hoveredOptionIndex = npos;
        applyVisualState();
        markPaintDirty();
      }
    });
    area->setOnClick([this, i](const InputArea::PointerData& data) {
      if (!m_enabled || data.button != BTN_LEFT) {
        return;
      }
      setSelectedIndex(i);
      closeMenu();
    });
  area->setOnAxis([this](const InputArea::PointerData& data) {
    if (!m_open) {
      return;
    }
    scrollBy(data.scrollDelta(m_controlHeight));
  });
    auto* areaPtr = static_cast<InputArea*>(m_menuViewport->addChild(std::move(area)));

    m_optionViews.push_back(OptionView{
        .background = bgPtr,
        .label = labelPtr,
        .checkGlyph = checkIconPtr,
        .area = areaPtr,
    });
  }
}

void Select::applyVisualState() {
  if (m_triggerLabel == nullptr || m_triggerGlyph == nullptr || m_triggerBackground == nullptr || m_menuBackground == nullptr) {
    return;
  }

  const bool triggerHovered = m_triggerArea != nullptr && m_triggerArea->hovered();
  const bool triggerPressed = m_triggerArea != nullptr && m_triggerArea->pressed();

  Color triggerBg = resolved(ColorRole::SurfaceVariant);
  Color triggerBorder = resolved(ColorRole::Outline);
  ThemeColor triggerText = selectedText().empty() ? roleColor(ColorRole::OnSurfaceVariant) : roleColor(ColorRole::OnSurface);

  if (!m_enabled) {
    triggerBg = resolved(ColorRole::SurfaceVariant, 0.75f);
    triggerBorder = resolved(ColorRole::Outline, 0.6f);
    triggerText = roleColor(ColorRole::OnSurface, 0.55f);
  } else if (triggerHovered || triggerPressed) {
    triggerBg = brighten(resolved(ColorRole::SurfaceVariant), 1.14f);
    triggerBorder = brighten(resolved(ColorRole::Outline), 1.14f);
  }

  m_triggerLabel->setColor(triggerText);
  m_triggerGlyph->setColor(triggerText);
  m_triggerGlyph->setGlyph(m_openUpward ? "chevron-up" : "chevron-down");

  m_triggerBackground->setStyle(RoundedRectStyle{
      .fill = triggerBg,
      .border = triggerBorder,
      .fillMode = FillMode::Solid,
      .radius = Style::radiusMd,
      .softness = 1.0f,
      .borderWidth = Style::borderWidth,
  });

  const bool showMenu = m_open && !m_optionViews.empty();
  m_menuBackground->setVisible(showMenu);
  m_menuBackground->setStyle(RoundedRectStyle{
      .fill = resolved(ColorRole::SurfaceVariant),
      .border = resolved(ColorRole::Outline),
      .fillMode = FillMode::Solid,
      .radius = Style::radiusMd,
      .softness = 1.0f,
      .borderWidth = Style::borderWidth,
  });

  for (std::size_t i = 0; i < m_optionViews.size(); ++i) {
    auto& option = m_optionViews[i];
    option.background->setVisible(showMenu);
    option.label->setVisible(showMenu);
    option.checkGlyph->setVisible(showMenu && i == m_selectedIndex);
    option.area->setVisible(showMenu);

    Color bg = clearColor();
    ThemeColor fg = roleColor(ColorRole::OnSurface);

    if (!m_enabled) {
      fg = roleColor(ColorRole::OnSurface, 0.55f);
    } else if (i == m_hoveredOptionIndex) {
      bg = resolved(ColorRole::Primary);
      fg = roleColor(ColorRole::OnPrimary);
    }

    option.label->setColor(fg);
    option.checkGlyph->setColor(fg);
    option.background->setStyle(RoundedRectStyle{
        .fill = bg,
        .border = bg,
        .fillMode = FillMode::Solid,
        .radius = Style::radiusSm,
        .softness = 1.0f,
        .borderWidth = 0.0f,
    });
  }
}

void Select::syncTriggerText() {
  if (m_triggerLabel == nullptr) {
    return;
  }
  m_triggerLabel->setText(selectedText().empty() ? m_placeholder : std::string(selectedText()));
  m_triggerLabel->setFontSize(m_fontSize);
}

void Select::toggleOpen() {
  if (!m_enabled || m_options.empty()) {
    return;
  }
  const bool opening = !m_open;
  if (opening && s_openSelect != nullptr && s_openSelect != this) {
    s_openSelect->closeMenu();
  }
  m_open = opening;
  if (m_open) {
    const float selectedTop =
        m_selectedIndex < m_optionViews.size() ? static_cast<float>(m_selectedIndex) * m_controlHeight : 0.0f;
    const float selectedBottom = selectedTop + m_controlHeight;
    const float viewportHeight = menuViewportHeight();
    if (selectedTop < m_scrollOffset) {
      m_scrollOffset = selectedTop;
    } else if (selectedBottom > m_scrollOffset + viewportHeight) {
      m_scrollOffset = selectedBottom - viewportHeight;
    }
    clampScrollOffset();
    s_openSelect = this;
    liftAncestorChain();
    setZIndex(kOpenSelectZIndex);
  } else {
    m_hoveredOptionIndex = npos;
    if (s_openSelect == this) {
      s_openSelect = nullptr;
    }
    restoreAncestorChain();
    setZIndex(0);
  }
  applyVisualState();
  markLayoutDirty();
}

void Select::closeMenu() {
  if (!m_open) {
    return;
  }
  m_open = false;
  m_hoveredOptionIndex = npos;
  if (s_openSelect == this) {
    s_openSelect = nullptr;
  }
  restoreAncestorChain();
  setZIndex(0);
  applyVisualState();
  markLayoutDirty();
}

bool Select::containsNode(const Node* node) const noexcept {
  for (auto* current = node; current != nullptr; current = current->parent()) {
    if (current == this) {
      return true;
    }
  }
  return false;
}

void Select::scrollBy(float delta) {
  if (!m_open || m_optionViews.empty()) {
    return;
  }
  m_scrollOffset += delta;
  clampScrollOffset();
  markPaintDirty();
}

void Select::clampScrollOffset() {
  const float totalHeight = static_cast<float>(m_optionViews.size()) * m_controlHeight;
  const float maxScroll = std::max(0.0f, totalHeight - menuViewportHeight());
  m_scrollOffset = std::clamp(m_scrollOffset, 0.0f, maxScroll);
}

float Select::menuViewportHeight() const noexcept {
  const float totalHeight = static_cast<float>(m_optionViews.size()) * m_controlHeight;
  const float maxHeight = static_cast<float>(kMaxVisibleOptions) * m_controlHeight;
  return std::min(totalHeight, maxHeight);
}

void Select::liftAncestorChain() {
  restoreAncestorChain();

  std::int32_t z = kOpenSelectZIndex;
  for (Node* current = this; current != nullptr; current = current->parent()) {
    m_liftedNodes.emplace_back(current, current->zIndex());
    current->setZIndex(z);
    ++z;
  }
}

void Select::restoreAncestorChain() {
  for (auto it = m_liftedNodes.rbegin(); it != m_liftedNodes.rend(); ++it) {
    if (it->first != nullptr) {
      it->first->setZIndex(it->second);
    }
  }
  m_liftedNodes.clear();
}

void Select::handleGlobalPointerPress(InputArea* target) {
  if (s_openSelect == nullptr) {
    return;
  }
  if (target != nullptr && s_openSelect->containsNode(target)) {
    return;
  }
  s_openSelect->closeMenu();
}

void Select::closeAnyOpen() {
  if (s_openSelect != nullptr) {
    s_openSelect->closeMenu();
  }
}
