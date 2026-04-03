#include "ui/widgets/WorkspacesWidget.hpp"

#include "core/Log.hpp"
#include "render/core/Color.hpp"
#include "render/core/Palette.hpp"
#include "render/core/Renderer.hpp"
#include "render/scene/Node.hpp"
#include "ui/controls/Box.hpp"
#include "ui/controls/Label.hpp"

#include "cursor-shape-v1-client-protocol.h"

#include <linux/input-event-codes.h>

namespace {

constexpr float kPillFontSize = 12.0f;
constexpr float kPillPaddingV = 3.0f;
constexpr float kPillPaddingH = 6.0f;
constexpr float kPillRadius = 10.0f;
constexpr float kGap = 4.0f;

} // namespace

WorkspacesWidget::WorkspacesWidget(WaylandConnection& connection, wl_output* output)
    : m_connection(connection)
    , m_output(output) {}

void WorkspacesWidget::create(Renderer& renderer) {
    auto container = std::make_unique<Box>();
    container->setDirection(BoxDirection::Horizontal);
    container->setGap(kGap);
    container->setAlign(BoxAlign::Center);
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

    // Check if state changed
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
    // Box children: [bg_rect, pill0, pill1, ...]
    // The first child is the background rect added by Box::setBackground
    std::size_t start = 0;
    if (!kids.empty() && kids[0]->type() == NodeType::Rect) {
        start = 1;
    }

    for (std::size_t i = start; i < kids.size(); ++i) {
        const auto* child = kids[i].get();
        float absX = 0.0f, absY = 0.0f;
        Node::absolutePosition(child, absX, absY);

        // Convert to widget-local: our localX/localY is relative to widget root (m_container)
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
    // Remove all children
    while (!m_container->children().empty()) {
        m_container->removeChild(m_container->children().back().get());
    }

    m_workspaceIds.clear();
    m_hoveredPill = -1;

    auto workspaces = m_connection.workspaces(m_output);

    for (const auto& ws : workspaces) {
        m_workspaceIds.push_back(ws.id);

        if (ws.active) {
            auto pill = std::make_unique<Box>();
            pill->setPadding(kPillPaddingV, kPillPaddingH, kPillPaddingV, kPillPaddingH);
            pill->setBackground(kRosePinePalette.love);
            pill->setRadius(kPillRadius);
            pill->setAlign(BoxAlign::Center);

            auto label = std::make_unique<Label>();
            label->setText(ws.name);
            label->setFontSize(kPillFontSize);
            label->setColor(kRosePinePalette.base);
            pill->addChild(std::move(label));
            pill->layout(renderer);

            m_container->addChild(std::move(pill));
        } else {
            auto pill = std::make_unique<Box>();
            pill->setPadding(kPillPaddingV, kPillPaddingH, kPillPaddingV, kPillPaddingH);
            pill->setBackground(rgba(1.0f, 1.0f, 1.0f, 0.08f));
            pill->setRadius(kPillRadius);
            pill->setAlign(BoxAlign::Center);

            auto label = std::make_unique<Label>();
            label->setText(ws.name);
            label->setFontSize(kPillFontSize);
            label->setColor(kRosePinePalette.subtle);
            pill->addChild(std::move(label));
            pill->layout(renderer);

            m_container->addChild(std::move(pill));
        }
    }
}
