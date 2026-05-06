#include "shell/bar/widgets/workspaces_widget.h"

#include "core/log.h"
#include "core/ui_phase.h"
#include "render/animation/animation.h"
#include "render/animation/animation_manager.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "ui/controls/box.h"
#include "ui/controls/label.h"
#include "ui/style.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <linux/input-event-codes.h>
#include <utility>
#include <wayland-client-protocol.h>

namespace {
  constexpr Logger kLog("workspace");
  constexpr float kWorkspaceGap = Style::spaceXs;
  constexpr float kWorkspacePillMinWidth = Style::controlHeight + Style::spaceXs;
  constexpr float kWorkspaceLabelPadH = Style::spaceSm;
  constexpr float kWorkspacePillMinHeight = Style::fontSizeMini - Style::spaceXs;
  constexpr float kWorkspaceAnimDurationMs = static_cast<float>(Style::animNormal);
} // namespace

WorkspacesWidget::WorkspacesWidget(WaylandConnection& connection, wl_output* output, DisplayMode displayMode,
                                   ColorSpec focusedColor, ColorSpec occupiedColor, ColorSpec emptyColor)
    : m_connection(connection), m_output(output), m_displayMode(displayMode), m_focusedColor(std::move(focusedColor)),
      m_occupiedColor(std::move(occupiedColor)), m_emptyColor(std::move(emptyColor)) {}

void WorkspacesWidget::create() {
  auto container = std::make_unique<InputArea>();
  container->setOnAxis([this](const InputArea::PointerData& data) {
    if (data.axis != WL_POINTER_AXIS_VERTICAL_SCROLL) {
      return;
    }
    const float delta = data.scrollDelta(1.0f);
    if (delta == 0.0f) {
      return;
    }
    // Wayland reports positive wheel deltas for "scroll down", so treat that
    // as moving to the next workspace and negative as previous.
    activateAdjacentWorkspace(delta > 0.0f ? 1 : -1);
  });
  m_container = container.get();
  setRoot(std::move(container));
}

void WorkspacesWidget::doLayout(Renderer& renderer, float containerWidth, float containerHeight) {
  const bool wasVertical = m_isVertical;
  m_isVertical = containerHeight > containerWidth;
  if (wasVertical != m_isVertical) {
    m_rebuildPending = true;
  }
  if (m_rebuildPending) {
    rebuild(renderer);
    m_rebuildPending = false;
  }
}

void WorkspacesWidget::doUpdate(Renderer& renderer) {
  auto current = m_connection.workspaces(m_output);
  if (m_cachedState.empty() && current.empty()) {
    return;
  }

  bool structuralChange = current.size() != m_cachedState.size();
  bool activeChange = false;
  if (!structuralChange) {
    for (std::size_t i = 0; i < current.size(); ++i) {
      const auto& a = current[i];
      const auto& b = m_cachedState[i];
      if (a.name != b.name || a.coordinates != b.coordinates) {
        structuralChange = true;
        break;
      }
      if (a.active != b.active || a.urgent != b.urgent || a.occupied != b.occupied) {
        activeChange = true;
      }
    }
  }

  if (!structuralChange && !activeChange) {
    return;
  }

  kLog.debug("workspaces widget: state changed (structural={}, {} workspaces)", structuralChange, current.size());
  m_cachedState.clear();
  m_cachedState.reserve(current.size());
  for (const auto& ws : current) {
    m_cachedState.push_back(Workspace{.id = ws.id,
                                      .name = ws.name,
                                      .coordinates = ws.coordinates,
                                      .active = ws.active,
                                      .urgent = ws.urgent,
                                      .occupied = ws.occupied});
  }

  if (structuralChange) {
    m_rebuildPending = true;
    if (root() != nullptr) {
      root()->markLayoutDirty();
    }
  } else {
    retarget(renderer);
  }
}

void WorkspacesWidget::rebuild(Renderer& renderer) {
  uiAssertNotRendering("WorkspacesWidget::rebuild");
  cancelAnimation();
  while (!m_container->children().empty()) {
    m_container->removeChild(m_container->children().back().get());
  }
  m_items.clear();

  const auto& workspaces = m_cachedState;
  const float gap = kWorkspaceGap * m_contentScale;
  const float pillMin = kWorkspacePillMinWidth * m_contentScale;
  const float labelFontSize = Style::fontSizeMini * m_contentScale;
  // Workspace pills are decorative indicators, so keep their body closer to
  // caption text than to the full bar capsule height used by regular widgets.
  const auto labelRefMetrics = renderer.measureFont(labelFontSize, true);
  const float labelRefHeight = labelRefMetrics.bottom - labelRefMetrics.top;
  float indicatorHeight = std::round(std::max(labelRefHeight, kWorkspacePillMinHeight * m_contentScale));

  std::vector<std::string> labels;
  labels.reserve(workspaces.size());
  for (std::size_t i = 0; i < workspaces.size(); ++i) {
    labels.push_back(workspaceLabel(workspaces[i], i));
  }

  // Compute each slot's intrinsic label-padded width (if labelled).
  std::vector<float> labelPadded(workspaces.size(), 0.0f);
  std::vector<float> labelInkCenterX(workspaces.size(), 0.0f);
  bool anyMultiChar = false;
  bool anyLabel = false;
  for (std::size_t i = 0; i < workspaces.size(); ++i) {
    const bool showLabel = (m_displayMode != DisplayMode::None) && !labels[i].empty();
    if (!showLabel) {
      continue;
    }
    anyLabel = true;
    if (labels[i].size() > 1) {
      anyMultiChar = true;
    }
    const TextMetrics tm = renderer.measureText(labels[i], labelFontSize, true);
    const float inkWidth = tm.right - tm.left;
    const float inkHeight = std::max(0.0f, tm.inkBottom - tm.inkTop);
    indicatorHeight = std::max(indicatorHeight, std::round(std::max(labelRefHeight, inkHeight)));
    labelPadded[i] = std::max(pillMin, inkWidth + (kWorkspaceLabelPadH * m_contentScale * 2.0f));
    // Visible-ink horizontal center within the label box. Used to center digits
    // by their visible glyph rather than by their advance width — for fonts where
    // the ink is asymmetric within the advance (e.g. "4"), centering by advance
    // looks visibly off.
    labelInkCenterX[i] = (tm.inkLeft + tm.inkRight) * 0.5f;
  }
  const float minCircleExtent = std::round(indicatorHeight);

  // Pick per-slot active/inactive widths so (active - inactive) is constant across slots,
  // guaranteeing stable total width regardless of which slot is active.
  //
  //   None mode       : inactive = dot,             active = pillMin                 (morph animation)
  //   Single-char Id  : inactive = indicatorHeight, active = max(labelPadded)        (morph animation)
  //   Multi-char Name : inactive = labelPadded[i],  active = labelPadded[i]          (color-only, no morph)
  float uniformActive = pillMin;
  for (float w : labelPadded) {
    uniformActive = std::max(uniformActive, w);
  }

  m_gap = gap;
  m_indicatorHeight = std::round(indicatorHeight);

  for (std::size_t i = 0; i < workspaces.size(); ++i) {
    const auto& ws = workspaces[i];
    const bool showLabel = (m_displayMode != DisplayMode::None) && !labels[i].empty();

    float inactiveWidth = 0.0f;
    float activeWidth = 0.0f;
    if (!anyLabel) {
      inactiveWidth = minCircleExtent;
      activeWidth = uniformActive;
    } else if (anyMultiChar) {
      // Uniform width — inactive must reserve enough room for its own label.
      inactiveWidth = showLabel ? labelPadded[i] : minCircleExtent;
      activeWidth = inactiveWidth;
    } else {
      // All single-char labels: morph from square to uniform pill.
      inactiveWidth = showLabel ? indicatorHeight : minCircleExtent;
      activeWidth = uniformActive;
    }

    auto area = std::make_unique<InputArea>();
    const float w = ws.active ? activeWidth : inactiveWidth;
    area->setFrameSize(w, indicatorHeight);

    Item item{};
    item.active = ws.active;
    item.label = labels[i];
    item.showLabel = showLabel;
    item.inactiveWidth = inactiveWidth;
    item.activeWidth = activeWidth;
    item.textInkCenterX = labelInkCenterX[i];

    auto indicator = std::make_unique<Box>();
    indicator->clearBorder();
    indicator->setRadius(indicatorHeight * 0.5f);
    indicator->setFrameSize(w, indicatorHeight);
    const bool isEmpty = !ws.active && !ws.urgent && !ws.occupied;
    indicator->setFill(colorSpecFromRole(workspaceFillRole(ws), workspaceFillAlpha(ws)));
    indicator->clearBorder();
    item.indicator = static_cast<Box*>(area->addChild(std::move(indicator)));

    if (showLabel) {
      auto text = std::make_unique<Label>();
      text->setText(labels[i]);
      text->setFontSize(labelFontSize);
      text->setBold(true);
      text->setColor(colorSpecFromRole(isEmpty ? emptyWorkspaceTextRole() : workspaceTextRole(ws)));
      text->measure(renderer);
      item.label = labels[i];
      item.text = static_cast<Label*>(area->addChild(std::move(text)));
    }

    auto wsCopy = ws;
    area->setOnClick([this, wsCopy](const InputArea::PointerData& data) {
      if (data.button == BTN_LEFT) {
        m_connection.activateWorkspace(m_output, wsCopy);
      }
    });
    item.area = static_cast<InputArea*>(m_container->addChild(std::move(area)));
    m_items.push_back(item);
  }

  // Size the container now that per-item widths are known.
  float total = 0.0f;
  for (std::size_t i = 0; i < m_items.size(); ++i) {
    const float itemWidth = (m_cachedState[i].active) ? m_items[i].activeWidth : m_items[i].inactiveWidth;
    total += itemWidth;
  }
  if (m_items.size() > 1) {
    total += gap * static_cast<float>(m_items.size() - 1);
  }
  if (m_isVertical) {
    m_container->setFrameSize(m_indicatorHeight, total);
  } else {
    m_container->setFrameSize(total, indicatorHeight);
  }

  // Snap to targets immediately (no animation on structural rebuild).
  computeTargets();
  for (std::size_t i = 0; i < m_items.size(); ++i) {
    auto& it = m_items[i];
    it.currentX = it.targetX;
    it.currentWidth = it.targetWidth;
    applyItemLayout(i);
  }
}

void WorkspacesWidget::computeTargets() {
  float cursor = 0.0f;
  for (std::size_t i = 0; i < m_items.size(); ++i) {
    auto& it = m_items[i];
    const float w = (m_cachedState[i].active) ? it.activeWidth : it.inactiveWidth;
    it.targetX = cursor;
    it.targetWidth = w;
    it.active = m_cachedState[i].active;
    cursor += w + m_gap;
  }
}

void WorkspacesWidget::retarget(Renderer& renderer) {
  (void)renderer;
  // Snapshot current positions as "from" values and compute new targets.
  for (auto& it : m_items) {
    it.fromX = it.currentX;
    it.fromWidth = it.currentWidth;
  }
  computeTargets();

  // Update per-item label text color (no animation on color — instant).
  for (std::size_t i = 0; i < m_items.size(); ++i) {
    auto& it = m_items[i];
    if (it.indicator != nullptr) {
      const auto& ws = m_cachedState[i];
      it.indicator->setFill(colorSpecFromRole(workspaceFillRole(ws), workspaceFillAlpha(ws)));
      it.indicator->clearBorder();
    }
    if (it.text != nullptr) {
      const auto& ws = m_cachedState[i];
      const bool isEmpty = !ws.active && !ws.urgent && !ws.occupied;
      it.text->setColor(colorSpecFromRole(isEmpty ? emptyWorkspaceTextRole() : workspaceTextRole(ws)));
    }
  }

  startAnimation();
}

void WorkspacesWidget::startAnimation() {
  auto* mgr = m_animations;
  if (mgr == nullptr) {
    for (std::size_t i = 0; i < m_items.size(); ++i) {
      auto& it = m_items[i];
      it.currentX = it.targetX;
      it.currentWidth = it.targetWidth;
      applyItemLayout(i);
    }
    return;
  }
  cancelAnimation();
  m_animId = mgr->animate(
      0.0f, 1.0f, kWorkspaceAnimDurationMs, Easing::EaseOutCubic,
      [this](float t) {
        for (std::size_t i = 0; i < m_items.size(); ++i) {
          auto& it = m_items[i];
          it.currentX = it.fromX + (it.targetX - it.fromX) * t;
          it.currentWidth = it.fromWidth + (it.targetWidth - it.fromWidth) * t;
          applyItemLayout(i);
        }
        if (root() != nullptr) {
          root()->markPaintDirty();
        }
      },
      [this]() { m_animId = 0; }, this);
  if (root() != nullptr) {
    root()->markPaintDirty();
  }
}

void WorkspacesWidget::cancelAnimation() {
  if (m_animId != 0 && m_animations != nullptr) {
    m_animations->cancel(m_animId);
  }
  m_animId = 0;
}

void WorkspacesWidget::applyItemLayout(std::size_t i) {
  auto& it = m_items[i];
  if (it.area == nullptr) {
    return;
  }
  if (m_isVertical) {
    it.area->setPosition(0.0f, std::round(it.currentX));
    it.area->setFrameSize(m_indicatorHeight, it.currentWidth);
    if (it.indicator != nullptr) {
      it.indicator->setFrameSize(m_indicatorHeight, it.currentWidth);
    }
  } else {
    it.area->setPosition(std::round(it.currentX), 0.0f);
    it.area->setFrameSize(it.currentWidth, m_indicatorHeight);
    if (it.indicator != nullptr) {
      it.indicator->setFrameSize(it.currentWidth, m_indicatorHeight);
    }
  }
  if (it.text != nullptr) {
    const float itemW = m_isVertical ? m_indicatorHeight : it.currentWidth;
    const float itemH = m_isVertical ? it.currentWidth : m_indicatorHeight;
    // Center on the visible ink center, not the advance box center, so digits
    // with asymmetric ink (e.g. "4") sit optically centered in the slot.
    const float textX = std::round(itemW * 0.5f - it.textInkCenterX);
    it.text->setPosition(std::max(0.0f, textX), std::round((itemH - it.text->height()) * 0.5f));
  }
  if (it.indicator != nullptr) {
    const float itemW = m_isVertical ? m_indicatorHeight : it.currentWidth;
    const float itemH = m_isVertical ? it.currentWidth : m_indicatorHeight;
    it.indicator->setRadius(std::min(itemW, itemH) * 0.5f);
  }
}

WorkspacesWidget::~WorkspacesWidget() { cancelAnimation(); }

std::optional<std::size_t> WorkspacesWidget::activeWorkspaceIndex() const {
  for (std::size_t i = 0; i < m_cachedState.size(); ++i) {
    if (m_cachedState[i].active) {
      return i;
    }
  }
  return std::nullopt;
}

void WorkspacesWidget::activateAdjacentWorkspace(int direction) {
  if (m_cachedState.empty() || direction == 0) {
    return;
  }

  const auto active = activeWorkspaceIndex();
  std::size_t targetIndex = 0;
  if (!active.has_value()) {
    targetIndex = direction > 0 ? 0 : (m_cachedState.size() - 1);
  } else {
    const std::size_t current = *active;
    if (direction > 0) {
      if (current + 1 >= m_cachedState.size()) {
        return;
      }
      targetIndex = current + 1;
    } else {
      if (current == 0) {
        return;
      }
      targetIndex = current - 1;
    }
  }

  m_connection.activateWorkspace(m_output, m_cachedState[targetIndex]);
}

std::string WorkspacesWidget::workspaceLabel(const Workspace& workspace, std::size_t displayIndex) const {
  if (m_displayMode == DisplayMode::Id) {
    if (const auto numericId = numericWorkspaceId(workspace); numericId.has_value()) {
      return std::to_string(*numericId);
    }
    return std::to_string(displayIndex + 1);
  }
  if (m_displayMode == DisplayMode::Name) {
    if (!workspace.id.empty()) {
      return !workspace.name.empty() ? workspace.name : workspace.id;
    }
    return workspace.name;
  }
  return {};
}

std::optional<std::size_t> WorkspacesWidget::numericWorkspaceId(const Workspace& workspace) {
  const auto parseLeadingNumber = [](const std::string& value) -> std::optional<std::size_t> {
    if (value.empty() || !std::isdigit(static_cast<unsigned char>(value.front()))) {
      return std::nullopt;
    }

    std::size_t parsed = 0;
    std::size_t index = 0;
    while (index < value.size() && std::isdigit(static_cast<unsigned char>(value[index]))) {
      parsed = (parsed * 10) + static_cast<std::size_t>(value[index] - '0');
      ++index;
    }
    return parsed > 0 ? std::optional<std::size_t>(parsed) : std::nullopt;
  };

  if (const auto id = parseLeadingNumber(workspace.id); id.has_value()) {
    return id;
  }
  if (const auto name = parseLeadingNumber(workspace.name); name.has_value()) {
    return name;
  }
  return std::nullopt;
}

ColorRole WorkspacesWidget::workspaceFillRole(const Workspace& workspace) const {
  if (workspace.active) {
    return m_focusedColor.role.value_or(ColorRole::Primary);
  }
  if (workspace.urgent) {
    return ColorRole::Error;
  }
  if (workspace.occupied) {
    return m_occupiedColor.role.value_or(ColorRole::Secondary);
  }
  return m_emptyColor.role.value_or(ColorRole::Secondary);
}

ColorRole WorkspacesWidget::workspaceTextRole(const Workspace& workspace) const {
  if (workspace.active) {
    return onRoleForFill(workspaceFillRole(workspace));
  }
  if (workspace.urgent) {
    return ColorRole::OnError;
  }
  if (workspace.occupied) {
    return onRoleForFill(workspaceFillRole(workspace));
  }
  return onRoleForFill(workspaceFillRole(workspace));
}

float WorkspacesWidget::workspaceFillAlpha(const Workspace& workspace) const {
  if (workspace.active) {
    return m_focusedColor.alpha;
  }
  if (workspace.urgent) {
    return 1.0f;
  }
  if (workspace.occupied) {
    return m_occupiedColor.alpha;
  }
  return m_emptyColor.alpha * 0.55f;
}

ColorRole WorkspacesWidget::onRoleForFill(ColorRole fill) {
  switch (fill) {
  case ColorRole::Primary:
    return ColorRole::OnPrimary;
  case ColorRole::Secondary:
    return ColorRole::OnSecondary;
  case ColorRole::Tertiary:
    return ColorRole::OnTertiary;
  case ColorRole::Error:
    return ColorRole::OnError;
  case ColorRole::Surface:
  case ColorRole::SurfaceVariant:
  case ColorRole::Outline:
  case ColorRole::Shadow:
  case ColorRole::Hover:
  case ColorRole::OnPrimary:
  case ColorRole::OnSecondary:
  case ColorRole::OnTertiary:
  case ColorRole::OnError:
  case ColorRole::OnSurface:
  case ColorRole::OnSurfaceVariant:
  case ColorRole::OnHover:
    return ColorRole::OnSurface;
  }
  return ColorRole::OnSurface;
}

ColorRole WorkspacesWidget::emptyWorkspaceTextRole() const {
  return onRoleForFill(m_emptyColor.role.value_or(ColorRole::Secondary));
}
