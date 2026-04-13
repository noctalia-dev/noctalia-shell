#include "core/ui_phase.h"
#include "shell/widgets/workspaces_widget.h"
#include "ui/style.h"

#include "core/log.h"
#include "render/animation/animation.h"
#include "render/animation/animation_manager.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "ui/controls/box.h"
#include "ui/controls/label.h"

#include <algorithm>
#include <cmath>
#include <cctype>
#include <linux/input-event-codes.h>

namespace {
constexpr Logger kLog("workspace");
constexpr float kWorkspaceGap = Style::spaceSm;
constexpr float kWorkspaceDotSize = Style::controlHeightSm * 0.62f;
constexpr float kWorkspacePillMinWidth = Style::controlHeightLg + Style::spaceXs;
constexpr float kWorkspaceIndicatorHeight = Style::controlHeightSm * 0.62f;
constexpr float kWorkspaceLabelPadH = Style::spaceSm;
constexpr float kWorkspaceAnimDurationMs = static_cast<float>(Style::animNormal);
} // namespace

WorkspacesWidget::WorkspacesWidget(WaylandConnection& connection, wl_output* output, DisplayMode displayMode)
    : m_connection(connection), m_output(output), m_displayMode(displayMode) {}

void WorkspacesWidget::create() {
  auto container = std::make_unique<Node>();
  m_container = container.get();
  setRoot(std::move(container));
}

void WorkspacesWidget::doLayout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  update(renderer);
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
  const float indicatorHeight = kWorkspaceIndicatorHeight * m_contentScale;
  const float dotWidth = kWorkspaceDotSize * m_contentScale;
  const float gap = kWorkspaceGap * m_contentScale;
  const float pillMin = kWorkspacePillMinWidth * m_contentScale;
  const float labelFontSize = Style::fontSizeCaption * m_contentScale;

  std::vector<std::string> labels;
  labels.reserve(workspaces.size());
  for (std::size_t i = 0; i < workspaces.size(); ++i) {
    labels.push_back(workspaceLabel(workspaces[i], i));
  }

  // Compute each slot's intrinsic label-padded width (if labelled).
  std::vector<float> labelPadded(workspaces.size(), 0.0f);
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
    labelPadded[i] = std::max(pillMin, inkWidth + (kWorkspaceLabelPadH * m_contentScale * 2.0f));
  }

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
  m_indicatorHeight = indicatorHeight;

  for (std::size_t i = 0; i < workspaces.size(); ++i) {
    const auto& ws = workspaces[i];
    const bool showLabel = (m_displayMode != DisplayMode::None) && !labels[i].empty();

    float inactiveWidth = 0.0f;
    float activeWidth = 0.0f;
    if (!anyLabel) {
      inactiveWidth = dotWidth;
      activeWidth = uniformActive;
    } else if (anyMultiChar) {
      // Uniform width — inactive must reserve enough room for its own label.
      inactiveWidth = showLabel ? labelPadded[i] : dotWidth;
      activeWidth = inactiveWidth;
    } else {
      // All single-char labels: morph from square to uniform pill.
      inactiveWidth = showLabel ? indicatorHeight : dotWidth;
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

    auto indicator = std::make_unique<Box>();
    indicator->clearBorder();
    indicator->setRadius(indicatorHeight * 0.5f);
    indicator->setFrameSize(w, indicatorHeight);
    indicator->setFill(roleColor(workspaceFillRole(ws)));
    item.indicator = static_cast<Box*>(area->addChild(std::move(indicator)));

    if (showLabel) {
      auto text = std::make_unique<Label>();
      text->setText(labels[i]);
      text->setFontSize(labelFontSize);
      text->setBold(true);
      text->setColor(roleColor(workspaceTextRole(ws)));
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
    total += (m_cachedState[i].active) ? m_items[i].activeWidth : m_items[i].inactiveWidth;
  }
  if (m_items.size() > 1) {
    total += gap * static_cast<float>(m_items.size() - 1);
  }
  m_container->setFrameSize(total, indicatorHeight);

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
      it.indicator->setFill(roleColor(workspaceFillRole(m_cachedState[i])));
    }
    if (it.text != nullptr) {
      it.text->setColor(roleColor(workspaceTextRole(m_cachedState[i])));
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
  it.area->setPosition(std::round(it.currentX), 0.0f);
  it.area->setFrameSize(it.currentWidth, m_indicatorHeight);
  if (it.indicator != nullptr) {
    it.indicator->setFrameSize(it.currentWidth, m_indicatorHeight);
  }
  if (it.text != nullptr) {
    it.text->setPosition(std::round((it.currentWidth - it.text->width()) * 0.5f),
                         std::round((m_indicatorHeight - it.text->height()) * 0.5f));
  }
}

WorkspacesWidget::~WorkspacesWidget() { cancelAnimation(); }

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

ColorRole WorkspacesWidget::workspaceFillRole(const Workspace& workspace) {
  if (workspace.active) {
    return ColorRole::Primary;
  }
  if (workspace.urgent) {
    return ColorRole::Error;
  }
  if (workspace.occupied) {
    return ColorRole::Secondary;
  }
  return ColorRole::SurfaceVariant;
}

ColorRole WorkspacesWidget::workspaceTextRole(const Workspace& workspace) {
  if (workspace.active) {
    return ColorRole::OnPrimary;
  }
  if (workspace.urgent) {
    return ColorRole::OnError;
  }
  if (workspace.occupied) {
    return ColorRole::OnSecondary;
  }
  return ColorRole::OnSurfaceVariant;
}
