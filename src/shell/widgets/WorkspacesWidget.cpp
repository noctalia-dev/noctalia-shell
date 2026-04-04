#include "shell/widgets/WorkspacesWidget.hpp"

#include "core/Log.hpp"
#include "render/core/Renderer.hpp"
#include "render/scene/Node.hpp"
#include "ui/controls/Box.hpp"
#include "ui/controls/Chip.hpp"

#include "cursor-shape-v1-client-protocol.h"

#include <linux/input-event-codes.h>

WorkspacesWidget::WorkspacesWidget(WaylandConnection& connection, wl_output* output)
    : m_connection(connection)
    , m_output(output) {}

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
            if (current[i].name != m_cachedState[i].name ||
                current[i].active != m_cachedState[i].active) {
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
            m_cachedState.push_back(Workspace{.id = ws.id, .name = ws.name, .coordinates = ws.coordinates, .active = ws.active});
        }

        rebuild(renderer);
    }
}

void WorkspacesWidget::onPointerEnter(float localX, float localY) {
    m_hoveredPill = pillIndexAt(localX, localY);
}

void WorkspacesWidget::onPointerLeave() {
    m_hoveredPill = -1;
}

void WorkspacesWidget::onPointerMotion(float localX, float localY) {
    m_hoveredPill = pillIndexAt(localX, localY);
}

bool WorkspacesWidget::onPointerButton(std::uint32_t button, bool pressed) {
    if (button == BTN_LEFT && pressed && m_hoveredPill >= 0 &&
        static_cast<std::size_t>(m_hoveredPill) < m_workspaceIds.size()) {
        m_connection.activateWorkspace(m_workspaceIds[static_cast<std::size_t>(m_hoveredPill)]);
        return true;
    }
    return false;
}

std::uint32_t WorkspacesWidget::cursorShape() const {
    return WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER;
}

int WorkspacesWidget::pillIndexAt(float localX, float localY) const {
    const auto& kids = m_container->children();
    // Skip background rect (child 0 if Box has one)
    std::size_t start = 0;
    if (!kids.empty() && kids[0]->type() == NodeType::Rect) {
        start = 1;
    }

    for (std::size_t i = start; i < kids.size(); ++i) {
        const auto* child = kids[i].get();
        float absX = 0.0f, absY = 0.0f;
        Node::absolutePosition(child, absX, absY);

        float containerAbsX = 0.0f, containerAbsY = 0.0f;
        Node::absolutePosition(m_container, containerAbsX, containerAbsY);
        float childLocalX = absX - containerAbsX;
        float childLocalY = absY - containerAbsY;

        if (localX >= childLocalX && localX < childLocalX + child->width() &&
            localY >= childLocalY && localY < childLocalY + child->height()) {
            return static_cast<int>(i - start);
        }
    }

    return -1;
}

void WorkspacesWidget::rebuild(Renderer& renderer) {
    while (!m_container->children().empty()) {
        m_container->removeChild(m_container->children().back().get());
    }

    m_workspaceIds.clear();
    m_hoveredPill = -1;

    auto workspaces = m_connection.workspaces(m_output);

    for (const auto& ws : workspaces) {
        m_workspaceIds.push_back(ws.id);

        auto pill = std::make_unique<Chip>();
        pill->setText(ws.name);
        pill->setWorkspaceActive(ws.active);
        pill->layout(renderer);
        m_container->addChild(std::move(pill));
    }
}
