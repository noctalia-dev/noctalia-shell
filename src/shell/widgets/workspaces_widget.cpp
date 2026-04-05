#include "shell/widgets/workspaces_widget.h"
#include "ui/style.h"

#include "core/log.h"
#include "render/animation/animation.h"
#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "ui/controls/box.h"
#include "ui/controls/chip.h"

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

  const auto previousActiveX = activeCoordinateX(m_cachedState);
  const auto currentActiveX = activeCoordinateX(current);

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

    int direction = 0;
    if (previousActiveX.has_value() && currentActiveX.has_value()) {
      if (*currentActiveX > *previousActiveX) {
        direction = 1;
      } else if (*currentActiveX < *previousActiveX) {
        direction = -1;
      }
    }
    playSwitchAnimation(direction);
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

void WorkspacesWidget::playSwitchAnimation(int direction) {
  if (m_container == nullptr || m_animations == nullptr) {
    return;
  }

  if (m_slideAnimId != 0) {
    m_animations->cancel(m_slideAnimId);
    m_slideAnimId = 0;
  }
  if (m_fadeAnimId != 0) {
    m_animations->cancel(m_fadeAnimId);
    m_fadeAnimId = 0;
  }

  const float startX = static_cast<float>(direction) * 14.0f;
  const float targetY = m_container->y();
  m_container->setPosition(startX, targetY);
  m_container->setOpacity(0.78f);

  m_slideAnimId = m_animations->animate(
      startX, 0.0f, Style::animNormal, Easing::EaseOutCubic,
      [this, targetY](float x) {
        if (m_container != nullptr) {
          m_container->setPosition(x, targetY);
        }
      },
      [this]() { m_slideAnimId = 0; });

  m_fadeAnimId = m_animations->animate(
      0.78f, 1.0f, Style::animNormal, Easing::EaseOutCubic,
      [this](float a) {
        if (m_container != nullptr) {
          m_container->setOpacity(a);
        }
      },
      [this]() { m_fadeAnimId = 0; });

  requestRedraw();
}

std::optional<int> WorkspacesWidget::activeCoordinateX(const std::vector<Workspace>& workspaces) {
  for (const auto& ws : workspaces) {
    if (!ws.active) {
      continue;
    }
    if (!ws.coordinates.empty()) {
      return static_cast<int>(ws.coordinates[0]);
    }
  }
  return std::nullopt;
}
