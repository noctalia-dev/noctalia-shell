#include "shell/widgets/workspaces_widget.h"
#include "ui/palette.h"
#include "ui/style.h"

#include "core/log.h"
#include "render/animation/animation.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "render/scene/text_node.h"
#include "ui/controls/box.h"
#include "ui/controls/flex.h"

#include <algorithm>
#include <cmath>
#include <cctype>
#include <linux/input-event-codes.h>

namespace {
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
  m_root = std::move(container);
}

void WorkspacesWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  update(renderer);
  m_container->layout(renderer);
}

void WorkspacesWidget::update(Renderer& renderer) {
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
    logDebug("workspaces widget: state changed, rebuilding ({} workspaces)", current.size());
    m_cachedState.clear();
    m_cachedState.reserve(current.size());
    for (const auto& ws : current) {
      m_cachedState.push_back(
          Workspace{.id = ws.id, .name = ws.name, .coordinates = ws.coordinates, .active = ws.active});
    }

    rebuild(renderer);
  }
}

void WorkspacesWidget::rebuild(Renderer& renderer) {
  while (!m_container->children().empty()) {
    m_container->removeChild(m_container->children().back().get());
  }

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

    auto indicator = std::make_unique<Box>();
    indicator->setFill(ws.active ? palette.primary : withAlpha(palette.onSurfaceVariant, 0.7f));
    indicator->setBorder(rgba(0.0f, 0.0f, 0.0f, 0.0f), 0.0f);
    indicator->setRadius(indicatorHeight * 0.5f);
    indicator->setSize(indicatorWidth, indicatorHeight);
    area->addChild(std::move(indicator));

    if (showLabel) {
      const float labelFontSize = Style::fontSizeCaption * m_contentScale;
      const TextMetrics textMetrics = renderer.measureText(labelText, labelFontSize, true);
      const float labelX =
          std::round(indicatorWidth * 0.5f - (textMetrics.left + textMetrics.right) * 0.5f);
      const float labelBaselineY = std::round(indicatorHeight * 0.5f - (textMetrics.top + textMetrics.bottom) * 0.5f);

      auto text = std::make_unique<TextNode>();
      text->setText(labelText);
      text->setFontSize(labelFontSize);
      text->setBold(true);
      text->setColor(ws.active ? palette.onPrimary : palette.onSurface);
      text->setPosition(labelX, labelBaselineY);
      text->setSize(textMetrics.width, textMetrics.bottom - textMetrics.top);
      area->addChild(std::move(text));
    }

    auto wsCopy = ws;
    area->setOnClick([this, wsCopy](const InputArea::PointerData& data) {
      if (data.button == BTN_LEFT) {
        m_connection.activateWorkspace(m_output, wsCopy);
      }
    });
    m_container->addChild(std::move(area));
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
