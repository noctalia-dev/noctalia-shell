#include "ui/controls/Select.h"

#include "render/programs/RoundedRectProgram.h"
#include "render/scene/InputArea.h"
#include "render/scene/RectNode.h"
#include "ui/controls/Icon.h"
#include "ui/controls/Label.h"
#include "ui/style/Palette.h"
#include "ui/style/Style.h"

#include "cursor-shape-v1-client-protocol.h"

#include <algorithm>
#include <memory>

namespace {

constexpr float kDefaultWidth = 220.0f;
constexpr float kMinWidth = 160.0f;
constexpr float kTriggerHeight = Style::controlHeight;
constexpr float kOptionHeight = Style::controlHeightSm;
constexpr float kMenuTopGap = 4.0f;
constexpr float kHorizontalPadding = Style::paddingH;
constexpr float kIconSize = 14.0f;

} // namespace

Select::Select() {
  auto triggerBackground = std::make_unique<RectNode>();
  m_triggerBackground = static_cast<RectNode*>(addChild(std::move(triggerBackground)));

  auto triggerLabel = std::make_unique<Label>();
  m_triggerLabel = static_cast<Label*>(addChild(std::move(triggerLabel)));

  auto triggerIcon = std::make_unique<Icon>();
  m_triggerIcon = static_cast<Icon*>(addChild(std::move(triggerIcon)));
  m_triggerIcon->setIcon("chevron-down");
  m_triggerIcon->setSize(kIconSize);

  auto triggerArea = std::make_unique<InputArea>();
  triggerArea->setCursorShape(WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER);
  triggerArea->setOnEnter([this](const InputArea::PointerData& /*data*/) {
    applyVisualState();
    markDirty();
  });
  triggerArea->setOnLeave([this]() {
    applyVisualState();
    markDirty();
  });
  triggerArea->setOnPress([this](const InputArea::PointerData& /*data*/) {
    applyVisualState();
    markDirty();
  });
  triggerArea->setOnClick([this](const InputArea::PointerData& data) {
    if (!m_enabled || data.button != 0x110) {
      return;
    }
    toggleOpen();
  });
  m_triggerArea = static_cast<InputArea*>(addChild(std::move(triggerArea)));

  auto menuBackground = std::make_unique<RectNode>();
  m_menuBackground = static_cast<RectNode*>(addChild(std::move(menuBackground)));

  applyVisualState();
}

void Select::setOptions(std::vector<std::string> options) {
  m_options = std::move(options);
  if (m_options.empty()) {
    m_selectedIndex = npos;
    m_hoveredOptionIndex = npos;
    m_open = false;
  } else if (m_selectedIndex == npos || m_selectedIndex >= m_options.size()) {
    m_selectedIndex = 0;
  }
  syncTriggerText();
  rebuildOptionViews();
  applyVisualState();
  markDirty();
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
  markDirty();
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
  }
  applyVisualState();
  markDirty();
}

void Select::setPlaceholder(std::string_view placeholder) {
  m_placeholder = std::string(placeholder);
  syncTriggerText();
  applyVisualState();
  markDirty();
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

void Select::layout(Renderer& renderer) {
  if (m_triggerBackground == nullptr || m_triggerLabel == nullptr || m_triggerIcon == nullptr || m_triggerArea == nullptr ||
      m_menuBackground == nullptr) {
    return;
  }

  if (m_fixedWidth <= 0.0f && width() > 0.0f) {
    m_fixedWidth = width();
  }

  syncTriggerText();
  m_triggerLabel->measure(renderer);
  m_triggerIcon->measure(renderer);

  float widestLabel = m_triggerLabel->width();
  for (auto& option : m_optionViews) {
    option.label->measure(renderer);
    widestLabel = std::max(widestLabel, option.label->width());
  }

  float contentWidth = widestLabel + kHorizontalPadding * 2.0f + kIconSize + Style::spaceXs;
  float dropdownWidth = m_fixedWidth > 0.0f ? m_fixedWidth : std::max({kDefaultWidth, kMinWidth, contentWidth});

  const float menuHeight = static_cast<float>(m_optionViews.size()) * kOptionHeight;
  setSize(dropdownWidth, kTriggerHeight);

  m_triggerBackground->setPosition(0.0f, 0.0f);
  m_triggerBackground->setSize(dropdownWidth, kTriggerHeight);

  const float triggerLabelMax = std::max(0.0f, dropdownWidth - (kHorizontalPadding * 2.0f + kIconSize + Style::spaceXs));
  m_triggerLabel->setMaxWidth(triggerLabelMax);
  m_triggerLabel->measure(renderer);
  m_triggerLabel->setPosition(kHorizontalPadding, (kTriggerHeight - m_triggerLabel->height()) * 0.5f);

  m_triggerIcon->setPosition(dropdownWidth - kHorizontalPadding - m_triggerIcon->width(),
                             (kTriggerHeight - m_triggerIcon->height()) * 0.5f);
  m_triggerArea->setPosition(0.0f, 0.0f);
  m_triggerArea->setSize(dropdownWidth, kTriggerHeight);

  // Position menu so the selected item overlaps the trigger
  const float selectedRow = m_selectedIndex < m_optionViews.size() ? static_cast<float>(m_selectedIndex) : 0.0f;
  const float menuY = -selectedRow * kOptionHeight;

  m_menuBackground->setPosition(0.0f, menuY);
  m_menuBackground->setSize(dropdownWidth, menuHeight);

  for (std::size_t i = 0; i < m_optionViews.size(); ++i) {
    auto& option = m_optionViews[i];
    const bool showMenu = m_open && !m_optionViews.empty();
    option.background->setVisible(showMenu);
    option.label->setVisible(showMenu);
    option.checkIcon->setVisible(showMenu && i == m_selectedIndex);
    option.area->setVisible(showMenu);

    const float rowY = menuY + static_cast<float>(i) * kOptionHeight;
    option.background->setPosition(0.0f, rowY);
    option.background->setSize(dropdownWidth, kOptionHeight);

    option.label->setMaxWidth(std::max(0.0f, dropdownWidth - kHorizontalPadding * 2.0f - kIconSize - Style::spaceXs));
    option.label->measure(renderer);
    option.label->setPosition(kHorizontalPadding, rowY + (kOptionHeight - option.label->height()) * 0.5f);

    option.checkIcon->measure(renderer);
    option.checkIcon->setPosition(dropdownWidth - kHorizontalPadding - option.checkIcon->width(),
                                  rowY + (kOptionHeight - option.checkIcon->height()) * 0.5f);

    option.area->setPosition(0.0f, rowY);
    option.area->setSize(dropdownWidth, kOptionHeight);
  }

  applyVisualState();
}

void Select::clearOptionViews() {
  for (auto& option : m_optionViews) {
    if (option.area != nullptr) {
      (void)removeChild(option.area);
    }
    if (option.checkIcon != nullptr) {
      (void)removeChild(option.checkIcon);
    }
    if (option.label != nullptr) {
      (void)removeChild(option.label);
    }
    if (option.background != nullptr) {
      (void)removeChild(option.background);
    }
  }
  m_optionViews.clear();
}

void Select::rebuildOptionViews() {
  clearOptionViews();

  for (std::size_t i = 0; i < m_options.size(); ++i) {
    auto background = std::make_unique<RectNode>();
    auto* bgPtr = static_cast<RectNode*>(addChild(std::move(background)));

    auto label = std::make_unique<Label>();
    label->setText(m_options[i]);
    auto* labelPtr = static_cast<Label*>(addChild(std::move(label)));

    auto checkIcon = std::make_unique<Icon>();
    checkIcon->setIcon("check");
    checkIcon->setSize(kIconSize);
    auto* checkIconPtr = static_cast<Icon*>(addChild(std::move(checkIcon)));

    auto area = std::make_unique<InputArea>();
    area->setCursorShape(WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER);
    area->setOnEnter([this, i](const InputArea::PointerData& /*data*/) {
      if (!m_enabled) {
        return;
      }
      m_hoveredOptionIndex = i;
      applyVisualState();
      markDirty();
    });
    area->setOnLeave([this, i]() {
      if (m_hoveredOptionIndex == i) {
        m_hoveredOptionIndex = npos;
        applyVisualState();
        markDirty();
      }
    });
    area->setOnClick([this, i](const InputArea::PointerData& data) {
      if (!m_enabled || data.button != 0x110) {
        return;
      }
      setSelectedIndex(i);
      closeMenu();
    });
    auto* areaPtr = static_cast<InputArea*>(addChild(std::move(area)));

    m_optionViews.push_back(OptionView{
        .background = bgPtr,
        .label = labelPtr,
        .checkIcon = checkIconPtr,
        .area = areaPtr,
    });
  }
}

void Select::applyVisualState() {
  if (m_triggerLabel == nullptr || m_triggerIcon == nullptr || m_triggerBackground == nullptr || m_menuBackground == nullptr) {
    return;
  }

  const bool triggerHovered = m_triggerArea != nullptr && m_triggerArea->hovered();
  const bool triggerPressed = m_triggerArea != nullptr && m_triggerArea->pressed();

  Color triggerBg = palette.surfaceVariant;
  Color triggerBorder = palette.outline;
  Color triggerText = selectedText().empty() ? palette.onSurfaceVariant : palette.onSurface;

  if (!m_enabled) {
    triggerBg = rgba(palette.surfaceVariant.r, palette.surfaceVariant.g, palette.surfaceVariant.b, 0.75f);
    triggerBorder = rgba(palette.outline.r, palette.outline.g, palette.outline.b, 0.6f);
    triggerText = rgba(palette.onSurface.r, palette.onSurface.g, palette.onSurface.b, 0.55f);
  } else if (triggerHovered || triggerPressed) {
    triggerBg = brighten(palette.surfaceVariant, 1.14f);
    triggerBorder = brighten(palette.outline, 1.14f);
  }

  m_triggerLabel->setColor(triggerText);
  m_triggerIcon->setColor(triggerText);
  m_triggerIcon->setIcon(m_open ? "chevron-up" : "chevron-down");

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
      .fill = palette.surfaceVariant,
      .border = palette.outline,
      .fillMode = FillMode::Solid,
      .radius = Style::radiusMd,
      .softness = 1.0f,
      .borderWidth = Style::borderWidth,
  });

  for (std::size_t i = 0; i < m_optionViews.size(); ++i) {
    auto& option = m_optionViews[i];
    option.background->setVisible(showMenu);
    option.label->setVisible(showMenu);
    option.checkIcon->setVisible(showMenu && i == m_selectedIndex);
    option.area->setVisible(showMenu);

    Color bg = rgba(0.0f, 0.0f, 0.0f, 0.0f);
    Color fg = palette.onSurface;

    if (!m_enabled) {
      fg = rgba(palette.onSurface.r, palette.onSurface.g, palette.onSurface.b, 0.55f);
    } else if (i == m_hoveredOptionIndex) {
      bg = palette.primary;
      fg = palette.onPrimary;
    }

    option.label->setColor(fg);
    option.checkIcon->setColor(fg);
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
}

void Select::toggleOpen() {
  if (!m_enabled || m_options.empty()) {
    return;
  }
  m_open = !m_open;
  if (!m_open) {
    m_hoveredOptionIndex = npos;
  }
  applyVisualState();
  markDirty();
}

void Select::closeMenu() {
  if (!m_open) {
    return;
  }
  m_open = false;
  m_hoveredOptionIndex = npos;
  applyVisualState();
  markDirty();
}
