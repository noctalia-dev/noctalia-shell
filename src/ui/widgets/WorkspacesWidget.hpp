#pragma once

#include "ui/Widget.hpp"
#include "wayland/WaylandConnection.hpp"

#include <vector>

class Box;

class WorkspacesWidget : public Widget {
public:
    explicit WorkspacesWidget(const WaylandConnection& connection);

    void create(Renderer& renderer) override;
    void layout(Renderer& renderer, float barWidth, float barHeight) override;
    void update(Renderer& renderer) override;

private:
    void rebuild(Renderer& renderer);

    const WaylandConnection& m_connection;
    Box* m_container = nullptr;
    std::vector<WaylandConnection::Workspace> m_cachedState;
};
