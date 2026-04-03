#pragma once

#include <cstdint>
#include <memory>
#include <vector>

enum class NodeType : std::uint8_t {
    Base,
    Rect,
    Text,
    Image,
};

class Node {
public:
    explicit Node(NodeType type = NodeType::Base);
    virtual ~Node();

    Node(const Node&) = delete;
    Node& operator=(const Node&) = delete;

    [[nodiscard]] NodeType type() const noexcept { return m_type; }

    [[nodiscard]] float x() const noexcept { return m_x; }
    [[nodiscard]] float y() const noexcept { return m_y; }
    [[nodiscard]] float width() const noexcept { return m_width; }
    [[nodiscard]] float height() const noexcept { return m_height; }
    [[nodiscard]] float opacity() const noexcept { return m_opacity; }
    [[nodiscard]] bool visible() const noexcept { return m_visible; }
    [[nodiscard]] bool dirty() const noexcept { return m_dirty; }
    [[nodiscard]] Node* parent() const noexcept { return m_parent; }
    [[nodiscard]] const std::vector<std::unique_ptr<Node>>& children() const noexcept { return m_children; }

    void setPosition(float x, float y);
    void setSize(float width, float height);
    void setOpacity(float opacity);
    void setVisible(bool visible);

    Node* addChild(std::unique_ptr<Node> child);
    Node* insertChildAt(std::size_t index, std::unique_ptr<Node> child);
    std::unique_ptr<Node> removeChild(Node* child);

    void markDirty();
    void clearDirty();

private:
    NodeType m_type;
    float m_x = 0.0f;
    float m_y = 0.0f;
    float m_width = 0.0f;
    float m_height = 0.0f;
    float m_opacity = 1.0f;
    bool m_visible = true;
    bool m_dirty = true;
    Node* m_parent = nullptr;
    std::vector<std::unique_ptr<Node>> m_children;
};
