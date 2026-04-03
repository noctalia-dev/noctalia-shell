#include "ui/widgets/WorkspacesWidget.hpp"

#include "core/Log.hpp"
#include "render/Color.hpp"
#include "render/Palette.hpp"
#include "render/Renderer.hpp"
#include "ui/controls/Box.hpp"
#include "ui/controls/Label.hpp"

namespace {

constexpr float kPillFontSize = 12.0f;
constexpr float kPillPaddingV = 3.0f;
constexpr float kPillPaddingH = 6.0f;
constexpr float kPillRadius = 10.0f;
constexpr float kGap = 4.0f;

} // namespace

WorkspacesWidget::WorkspacesWidget(const WaylandConnection& connection)
    : m_connection(connection) {}

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
    auto current = m_connection.workspaces();
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
            m_cachedState.push_back(WaylandConnection::Workspace{.name = ws.name, .active = ws.active});
        }

        rebuild(renderer);
    }
}

void WorkspacesWidget::rebuild(Renderer& renderer) {
    // Remove all children except background (if any)
    while (!m_container->children().empty()) {
        // removeChild returns ownership, which we discard
        m_container->removeChild(m_container->children().back().get());
    }

    auto workspaces = m_connection.workspaces();

    for (const auto& ws : workspaces) {
        if (ws.active) {
            // Active workspace: colored pill with label
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
            // Inactive workspace: subtle pill with label
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
