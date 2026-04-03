#include "ui/widgets/WorkspacesWidget.hpp"

#include "core/Log.hpp"
#include "render/core/Renderer.hpp"
#include "ui/controls/Box.hpp"
#include "ui/controls/Chip.hpp"

WorkspacesWidget::WorkspacesWidget(const WaylandConnection& connection, wl_output* output)
    : m_connection(connection)
    , m_output(output) {}

void WorkspacesWidget::create(Renderer& renderer) {
    auto container = std::make_unique<Box>();
    container->applyBarRowLayout();
    m_container = container.get();
    m_root = std::move(container);

    rebuild(renderer);
}

void WorkspacesWidget::layout(Renderer& renderer, float /*barWidth*/, float /*barHeight*/) {
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
            m_cachedState.push_back(WaylandConnection::Workspace{.id = ws.id, .name = ws.name, .coordinates = ws.coordinates, .active = ws.active});
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
        auto pill = std::make_unique<Chip>();
        pill->setText(ws.name);
        pill->setWorkspaceActive(ws.active);
        pill->layout(renderer);
        m_container->addChild(std::move(pill));
    }
}
