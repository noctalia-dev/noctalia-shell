#include "shell/widgets/WorkspacesWidget.h"
#include "ui/style/Style.h"

#include "core/Log.h"
#include "render/core/Renderer.h"
#include "render/scene/InputArea.h"
#include "render/scene/Node.h"
#include "ui/controls/Box.h"
#include "ui/controls/Chip.h"

#include <linux/input-event-codes.h>

WorkspacesWidget::WorkspacesWidget(WaylandConnection& connection, wl_output* output)
    : m_connection(connection), m_output(output) {}

void WorkspacesWidget::create(Renderer& renderer) {
  auto container = std::make_unique<Box>();
  container->setRowLayout();
  m_container = container.get();
  m_root = std::move(container);

  rebuild(renderer);
}

void WorkspacesWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
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
      if (current[i].name != m_cachedState[i].name || current[i].active != m_cachedState[i].active) {
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

  for (const auto& ws : workspaces) {
    auto chip = std::make_unique<Chip>();
    chip->setText(ws.name);
    chip->setActive(ws.active);
    chip->setPadding(Style::paddingV * 0.5, Style::paddingH * 0.5, Style::paddingV * 0.5, Style::paddingH * 0.5);
    chip->layout(renderer);

    // Wrap chip in an InputArea for click handling
    auto area = std::make_unique<InputArea>();
    area->setSize(chip->width(), chip->height());
    auto wsCopy = ws;
    area->setOnClick([this, wsCopy](const InputArea::PointerData& data) {
      if (data.button == BTN_LEFT) {
        m_connection.activateWorkspace(m_output, wsCopy);
      }
    });
    area->addChild(std::move(chip));
    m_container->addChild(std::move(area));
  }
}
