#include "render/scene/Node.hpp"

#include <algorithm>

Node::Node(NodeType type)
    : m_type(type) {}

Node::~Node() = default;

void Node::setPosition(float x, float y) {
    if (m_x == x && m_y == y) {
        return;
    }
    m_x = x;
    m_y = y;
    markDirty();
}

void Node::setSize(float width, float height) {
    if (m_width == width && m_height == height) {
        return;
    }
    m_width = width;
    m_height = height;
    markDirty();
}

void Node::setOpacity(float opacity) {
    if (m_opacity == opacity) {
        return;
    }
    m_opacity = opacity;
    markDirty();
}

void Node::setVisible(bool visible) {
    if (m_visible == visible) {
        return;
    }
    m_visible = visible;
    markDirty();
}

Node* Node::addChild(std::unique_ptr<Node> child) {
    child->m_parent = this;
    auto* raw = child.get();
    m_children.push_back(std::move(child));
    markDirty();
    return raw;
}

Node* Node::insertChildAt(std::size_t index, std::unique_ptr<Node> child) {
    child->m_parent = this;
    auto* raw = child.get();
    if (index >= m_children.size()) {
        m_children.push_back(std::move(child));
    } else {
        m_children.insert(m_children.begin() + static_cast<std::ptrdiff_t>(index), std::move(child));
    }
    markDirty();
    return raw;
}

std::unique_ptr<Node> Node::removeChild(Node* child) {
    auto it = std::find_if(m_children.begin(), m_children.end(),
        [child](const auto& ptr) { return ptr.get() == child; });

    if (it == m_children.end()) {
        return nullptr;
    }

    auto removed = std::move(*it);
    m_children.erase(it);
    removed->m_parent = nullptr;
    markDirty();
    return removed;
}

void Node::markDirty() {
    m_dirty = true;
    if (m_parent != nullptr && !m_parent->m_dirty) {
        m_parent->markDirty();
    }
}

void Node::clearDirty() {
    m_dirty = false;
}
