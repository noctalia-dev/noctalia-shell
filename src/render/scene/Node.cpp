#include "render/scene/Node.h"

#include <algorithm>

Node::Node(NodeType type) : m_type(type) {}

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
  auto it = std::find_if(m_children.begin(), m_children.end(), [child](const auto& ptr) { return ptr.get() == child; });

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
  for (auto& child : m_children) {
    if (child->m_dirty) {
      child->clearDirty();
    }
  }
}

Node* Node::hitTest(Node* root, float x, float y) { return hitTestImpl(root, x, y, 0.0f, 0.0f); }

Node* Node::hitTestImpl(Node* node, float px, float py, float offsetX, float offsetY) {
  if (node == nullptr || !node->m_visible) {
    return nullptr;
  }

  const float nodeX = offsetX + node->m_x;
  const float nodeY = offsetY + node->m_y;

  if (px < nodeX || px >= nodeX + node->m_width || py < nodeY || py >= nodeY + node->m_height) {
    return nullptr;
  }

  // Traverse children in reverse (topmost/last-added first)
  for (auto it = node->m_children.rbegin(); it != node->m_children.rend(); ++it) {
    auto* hit = hitTestImpl(it->get(), px, py, nodeX, nodeY);
    if (hit != nullptr) {
      return hit;
    }
  }

  return node;
}

void Node::absolutePosition(const Node* node, float& outX, float& outY) {
  outX = 0.0f;
  outY = 0.0f;
  for (const Node* n = node; n != nullptr; n = n->m_parent) {
    outX += n->m_x;
    outY += n->m_y;
  }
}
