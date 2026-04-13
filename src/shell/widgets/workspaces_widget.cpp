#include "core/ui_phase.h"
#include "shell/widgets/workspaces_widget.h"
#include "ui/style.h"

#include "core/log.h"
#include "render/animation/animation.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "ui/controls/box.h"
#include "ui/controls/flex.h"
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
} // namespace

WorkspacesWidget::WorkspacesWidget(WaylandConnection& connection, wl_output* output, DisplayMode displayMode)
    : m_connection(connection), m_output(output), m_displayMode(displayMode) {}

void WorkspacesWidget::create() {
  auto container = std::make_unique<Flex>();
  container->setRowLayout();
  container->setGap(kWorkspaceGap * m_contentScale);
  m_container = container.get();
  setRoot(std::move(container));
}

void WorkspacesWidget::doLayout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  update(renderer);
  if (m_rebuildPending) {
    rebuild(renderer);
    m_rebuildPending = false;
  }
  m_container->layout(renderer);
}

void WorkspacesWidget::doUpdate(Renderer& renderer) {
  (void)renderer;
  auto current = m_connection.workspaces(m_output);
  if (m_cachedState.empty() && current.empty()) {
    return;
  }

  bool changed = current.size() != m_cachedState.size();
  if (!changed) {
    for (std::size_t i = 0; i < current.size(); ++i) {
      if (current[i].name != m_cachedState[i].name || current[i].active != m_cachedState[i].active ||
          current[i].coordinates != m_cachedState[i].coordinates) {
        changed = true;
        break;
      }
    }
  }

  if (changed) {
    kLog.debug("workspaces widget: state changed, rebuilding ({} workspaces)", current.size());
    m_cachedState.clear();
    m_cachedState.reserve(current.size());
    for (const auto& ws : current) {
      m_cachedState.push_back(
          Workspace{.id = ws.id, .name = ws.name, .coordinates = ws.coordinates, .active = ws.active});
    }
    m_rebuildPending = true;
    if (root() != nullptr) {
      root()->markLayoutDirty();
    }
  }
}

void WorkspacesWidget::rebuild(Renderer& renderer) {
  uiAssertNotRendering("WorkspacesWidget::rebuild");
  while (!m_container->children().empty()) {
    m_container->removeChild(m_container->children().back().get());
  }
  m_items.clear();

  auto workspaces = m_connection.workspaces(m_output);

  for (std::size_t i = 0; i < workspaces.size(); ++i) {
    const auto& ws = workspaces[i];
    const std::string labelText = workspaceLabel(ws, i);
    const bool showLabel = (m_displayMode != DisplayMode::None) && !labelText.empty();
    const bool singleCharLabel = showLabel && labelText.size() == 1;

    const float indicatorHeight = kWorkspaceIndicatorHeight * m_contentScale;
    float indicatorWidth = (ws.active ? kWorkspacePillMinWidth : kWorkspaceDotSize) * m_contentScale;
    if (singleCharLabel && !ws.active) {
      indicatorWidth = indicatorHeight;
    } else if (showLabel) {
      const float labelFontSize = Style::fontSizeCaption * m_contentScale;
      const TextMetrics labelMetrics = renderer.measureText(labelText, labelFontSize, true);
      const float inkWidth = labelMetrics.right - labelMetrics.left;
      const float paddedWidth = inkWidth + (kWorkspaceLabelPadH * m_contentScale * 2.0f);
      indicatorWidth = std::max(kWorkspacePillMinWidth * m_contentScale, paddedWidth);
    }

    // Single clickable badge with optional centered text.
    auto area = std::make_unique<InputArea>();
    area->setSize(indicatorWidth, indicatorHeight);

    Item item{.active = ws.active};

    auto indicator = std::make_unique<Box>();
    indicator->clearBorder();
    indicator->setRadius(indicatorHeight * 0.5f);
    indicator->setSize(indicatorWidth, indicatorHeight);
    indicator->setFill(roleColor(ws.active ? ColorRole::Primary : ColorRole::Secondary));
    item.indicator = static_cast<Box*>(area->addChild(std::move(indicator)));

    if (showLabel) {
      const float labelFontSize = Style::fontSizeCaption * m_contentScale;
      auto text = std::make_unique<Label>();
      text->setText(labelText);
      text->setFontSize(labelFontSize);
      text->setBold(true);
      text->setColor(roleColor(ws.active ? ColorRole::OnPrimary : ColorRole::OnSecondary));
      text->measure(renderer);
      text->setPosition(std::round((indicatorWidth - text->width()) * 0.5f),
                        std::round((indicatorHeight - text->height()) * 0.5f));
      item.text = static_cast<Label*>(area->addChild(std::move(text)));
    }

    auto wsCopy = ws;
    area->setOnClick([this, wsCopy](const InputArea::PointerData& data) {
      if (data.button == BTN_LEFT) {
        m_connection.activateWorkspace(m_output, wsCopy);
      }
    });
    m_container->addChild(std::move(area));
    m_items.push_back(item);
  }
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
